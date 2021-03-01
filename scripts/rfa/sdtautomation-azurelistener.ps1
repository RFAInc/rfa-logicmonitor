using namespace System.Net

<# Input bindings are passed in via param block #>
param($Request, $TriggerMetadata)

<# Import logicmonitor helper function from github #>
(new-object Net.WebClient).DownloadString("https://raw.githubusercontent.com/RFAInc/rfa-logicmonitor/main/api-functions.ps1") | Invoke-Expression

<# Access credentials from environment variables #>
$accessId = $env:accessId
$accessKey = $env:accessKey
$tenantName = $env:tenantName

<# logicmonitor lookup body details #>
$lmLookupBody = @{
    type = "testAppliesTo"
    currentAppliesTo = 'system.sysname == "' + $($Request.Body.deviceSysName) + '" && company.id == "' + $($Request.Body.companyID) + '"'
} | ConvertTo-Json

<# logicmonitor lookup request details #>
$lmLookupRequest = @{
    httpVerb = "POST"
    resourcePath = "/functions"
    httpBody = $lmLookupBody
    accessId = $accessId
    accessKey = $accessKey
    tenantName = $tenantName
    version = 2
}

<# Lookup Device in logicmonitor based on a matching system.sysname & company.id #>
$lmLookupResponse = Invoke-LomoApi @lmLookupRequest

<# Write logicmonitor response to the Azure Functions log stream #>
Write-Host "LM Device Lookup Response: $lmLookupResponse"

if (-not $lmLookupResponse.currentMatches) {
    <# Store result message for logicmonitor operation #>
    $azfuncResponse = "Device Not Found"

    <# Write az func response to the Azure Functions log stream #>
    Write-Host "Az Function response: $azfuncResponse"
} else {
    <# logicmonitor SDT body details #>
    $lmSdtBody = @{
        sdtType = "oneTime"
        type = "DeviceSDT"
        deviceId = $lmLookupResponse.currentMatches.id
        startDateTime = $Request.Body.sdtStartTime
        endDateTime = $Request.Body.sdtEndTime
        comment = $Request.Body.sdtNote
    } | ConvertTo-Json

    <# logicmonitor SDT request details #>
    $lmSdtRequest = @{
        httpVerb = "POST"
        resourcePath = "/sdt/sdts"
        httpBody = $lmSdtBody
        accessId = $accessId
        accessKey = $accessKey
        tenantName = $tenantName
        version = 2
    } 

    <# Set SDT in logicmonitor #>
    $lmSdtResponse = Invoke-LomoApi @lmSdtRequest

    <# Store result message for logicmonitor operation #>
    if ($lmSdtResponse.id) {
        $azfuncResponse = "LogicMonitor device ID " + $lmLookupResponse.currentMatches.id + " found for values " + $Request.Body.deviceSysName + "@" + $Request.Body.deviceLocalIPAddress + "@"+$Request.Body.companyID + ". SDT set succeeded." 
    } else {
        $azfuncResponse = "LogicMonitor device ID " + $lmLookupResponse.currentMatches.id + " found for values " + $Request.Body.deviceSysName + "@" + $Request.Body.deviceLocalIPAddress + "@"+$Request.Body.companyID + ". SDT set failed. Please check the az func logs for any exceptions from the logicmontior api." 
    } 

    <# Write logicmonitor response to the Azure Functions log stream #>
    Write-Host "LM SDT setting Response: $lmSdtResponse"
    
    <# Write az func response to the Azure Functions log stream #>
    Write-Host "Az Function response: $azfuncResponse"
}

<# Respond to az func request with logicmonitor result #>
Push-OutputBinding -Name "Response" -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $azfuncResponse
})