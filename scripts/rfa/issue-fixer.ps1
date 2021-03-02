<#
.NOTES
    Version:        1.0
    Author:         Andy Escolastico
    Creation Date:  8/17/2020
#>
#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#----------------------------------------------------------[Declarations]----------------------------------------------------------
$LogPath = "./reports/device-imports_$(Get-Date -format "MM-dd-yy_HH-mm").log"
$CsvPath = "./reports/device-imports__$(Get-Date -format "MM-dd-yy_HH-mm").csv"
#-----------------------------------------------------------[Functions]------------------------------------------------------------
. ./creds/lm-api-creds.ps1
. ./modules/rfa-logicmonitor.ps1
#-----------------------------------------------------------[Execution]------------------------------------------------------------
#get collectors
$CGRequest = @{
    tenantName = $tenantName 
    accessId = $accessId 
    accessKey = $accessKey 
    httpverb = "GET" 
    resourcePath = "/setting/collectors/groups" 
    queryParams = '?size=10000' 
    Version = 1
}
$CollectorGroups = Invoke-LMAPI @CGRequest
$CollectorGroups | ForEach-Object { 
    $CollectorGroupCompanyID = $_.customProperties | ForEach-Object { 
        ($_ | Where-Object {$_.name -eq "company.id"}).value
    } 
    $_ | Add-Member -MemberType "NoteProperty" -Name "companyID" -Value $CollectorGroupCompanyID
}


#-----------#-----------#-----------#-----------#-----------#
## set device to use ABCG
$DevicesRequest = @{
    tenantName = $tenantName 
    accessId = $accessId 
    accessKey = $accessKey 
    httpVerb = "GET" 
    resourcePath = "/device/devices" 
    queryParams = '?filter=autoBalancedCollectorGroupId:0&size=1000' 
    Version = 3
}

$Devices = Invoke-LMAPI @DevicesRequest
$TroubleDevices = $Devices | Where-Object {($_.preferredCollectorGroupName -notlike "RFA*") -and ($_.preferredCollectorGroupName -notlike "*default*") -and ($_.preferredCollectorGroupName -notlike "Generation*") -and ($_.preferredCollectorGroupName -notlike "Sunlight*") } 
$TroubleDevices | ForEach-Object { 
    $DevCompanyID = ($_.inheritedProperties | Where-Object {$_.name -eq "company.id"}).value
    $_ | Add-Member -MemberType "NoteProperty" -Name "companyID" -Value $DevCompanyID
    $Group = ($_.systemProperties | Where-Object {$_.name -eq "system.staticgroups"}).value
    $_ | Add-Member -MemberType "NoteProperty" -Name "Group" -Value $Group

}

foreach ($Device in $TroubleDevices) {
    $CompanyID = $Device.CompanyID
    $CollectorGroup = $CollectorGroups | Where-Object {$_.companyID -eq $CompanyID}
    $CollectorGroupID = $CollectorGroup.id
    $DeviceID  = $Device.id
    $CCGBody = @{
        preferredCollectorId = 0
        autoBalancedCollectorGroupId = $CollectorGroupID
    }
    $CCGRequest = @{
        tenantName = $tenantName 
        accessId = $accessId 
        accessKey = $accessKey 
        httpVerb = "PATCH" 
        resourcePath = "/device/devices/$DeviceID" 
        queryParams = "?patchFields=preferredCollectorId,autoBalancedCollectorGroupId"
        httpBody = $CCGBody | ConvertTo-Json
        Version = 3
    }
    $ChangedDevice = Invoke-LMAPI @CCGRequest
    Write-Output "$($ChangedDevice.displayName) : $($ChangedDevice.autoBalancedCollectorGroupId)"

}
#-----------#-----------#-----------#-----------#-----------#

# Change CG in bulk
$DevicesRequest = @{
    tenantName = $tenantName 
    accessId = $accessId 
    accessKey = $accessKey 
    httpVerb = "GET" 
    resourcePath = "/device/devices" 
    queryParams = '?size=1000' 
    Version = 3
}

$Devices = Invoke-LMAPI @DevicesRequest
$TroubleDevices = $Devices | Where-Object {($_.preferredCollectorGroupName -notlike "*default*") } 
$TroubleDevices | ForEach-Object { 
    $DevCompanyID = ($_.inheritedProperties | Where-Object {$_.name -eq "company.id"}).value
    $_ | Add-Member -MemberType "NoteProperty" -Name "companyID" -Value $DevCompanyID
    $Group = ($_.systemProperties | Where-Object {$_.name -eq "system.staticgroups"}).value
    $_ | Add-Member -MemberType "NoteProperty" -Name "Group" -Value $Group
}
$TroubleDevices = $TroubleDevices | Where-Object {($_.Group -like "*ClearBridge*New De*") } 


foreach ($Device in $TroubleDevices) {
    $CompanyID = $Device.CompanyID
    $CollectorGroup = $CollectorGroups | Where-Object {$_.companyID -eq $CompanyID}
    $CollectorGroupID = $CollectorGroup.id
    $DeviceID  = $Device.id
    $CCGBody = @{
        preferredCollectorId = 0
        autoBalancedCollectorGroupId = $CollectorGroupID
    }
    $CCGRequest = @{
        tenantName = $tenantName 
        accessId = $accessId 
        accessKey = $accessKey 
        httpVerb = "PATCH" 
        resourcePath = "/device/devices/$DeviceID" 
        queryParams = "?patchFields=preferredCollectorId,autoBalancedCollectorGroupId"
        httpBody = $CCGBody | ConvertTo-Json
        Version = 3
    }
    $ChangedDevice = Invoke-LMAPI @CCGRequest
    Write-Output "$($ChangedDevice.displayName) : $($ChangedDevice.autoBalancedCollectorGroupId)"

}


