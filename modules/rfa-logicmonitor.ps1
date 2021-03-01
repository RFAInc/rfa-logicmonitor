function Invoke-LMAPI {
    Param(
        [Parameter(Mandatory=$true)] 
        [String] $tenantName,
        [Parameter(Mandatory=$true)] 
        [String] $accessId,
        [Parameter(Mandatory=$true)] 
        [String] $accessKey,
        [Parameter(Mandatory = $true)]
        [string]$resourcePath,
        [Parameter(Mandatory = $false)]
        [string]$httpVerb = 'GET',
        [Parameter(Mandatory = $false)]
        [string]$queryParams,
        [Parameter(Mandatory = $false)]
        [string]$httpBody = $null,
        [Parameter(Mandatory = $false)]
        [int]$version = 3
    )
    if ($httpBody -and $httpBody -isnot [string]) { $httpBody = $httpBody | ConvertTo-Json -Depth 10 }
    # Use TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    <# Construct URL #>
    $url = "https://$tenantName.logicmonitor.com/santaba/rest$resourcePath$queryParams"
    <# Get current time in milliseconds #>
    $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)
    <# Concatenate Request Details #>
    $requestVars = $httpVerb + $epoch + $httpBody + $resourcePath
    <# Construct Signature #>
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [Text.Encoding]::UTF8.GetBytes($accessKey)
    $signature = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(([System.BitConverter]::ToString($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestVars))) -replace '-').ToLower()))
    <# Construct Headers #>
    $auth = 'LMv1 ' + $accessId + ':' + $signature + ':' + $epoch
    $httpHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $httpHeaders.Add("Authorization", $auth)
    $httpHeaders.Add("Content-Type", 'application/json')
    $httpHeaders.Add("X-version", $version)
    <# Construct Request #>
    $request = @{  
        Uri = $url
        Method = $httpVerb
        Headers = $httpHeaders
    }
    if ($httpVerb -ne "GET"){$request.Body = $httpBody}
    <# Make request & retry if failed due to rate limiting #>
    $finalDataSet = @()
    try {
        if ($request.uri -like "*?format=*") {
            $response = Invoke-WebRequest @request
        } else {
            $response = Invoke-RestMethod @request
        }  
    } catch {
        switch ($_) {
            { $_.Exception.Response.StatusCode.value__ -eq 429 } {
                Write-Warning "Request exceeded rate limit, retrying in 60 seconds..."
                Start-Sleep -Seconds 60
                if ($request.uri -like "*?format=*") {
                    $response = Invoke-WebRequest @request
                } else {
                    $response = Invoke-RestMethod @request
                }  
            }
            default {   
                Write-Host $_            
            }
        }
    }
    <# Collect data from response #>
    if ($version -eq 1) {
        $data = $response.data.items
        $total = $response.data.total
    } else {
        $data = $response.items
        $total = $response.total
    }
    if ($response.id){
        $data = $response
    }
    if ($request.uri -like "*?format=*") {
        $data = $response.Content
    }
    $finalDataSet += $data 
    <# Determine if more requests are needed to return full dataset #>
    $offset = $finalDataSet.count
    while ($finalDataSet.count -lt [int]$total) {
        $ogURI = $request.Uri
        $request.Uri += "&offset=$($offset)"
        try {
            $response = Invoke-RestMethod @request
        } catch {
            switch ($_) {
                { $_.Exception.Response.StatusCode.value__ -eq 429 } {
                    Write-Warning "Request exceeded rate limit, retrying in 60 seconds..."
                    Start-Sleep -Seconds 60
                    $response = Invoke-RestMethod @request
                }
                default {   
                    Write-Host $_            
                }
            }
        }
        if ($version -eq 1) {
            $data = $response.data.items
            $total = $response.data.total
        } else {
            $data = $response.items
            $total = $response.total 
        }
        $finalDataSet += $data 
        $offset = $finalDataSet.count
        $request.Uri = $ogURI
    }
    return $finalDataSet
}
function New-RFALogicMonitorSDT {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$jobRunnerUri,
        [Parameter(Mandatory=$true)]
        [string]$companyID,
        [Parameter(Mandatory=$true)]
        [string]$deviceHostName,
        [Parameter(Mandatory=$false)]
        [string]$deviceIPAddress,
        [Parameter(Mandatory=$false)]
        [string]$deviceMacAddress,
        [Parameter(Mandatory=$false)]
        [string]$deviceSerialNumber,
        [Parameter(Mandatory=$true)]
        [string]$sdtStartTime,
        [Parameter(Mandatory=$true)]
        [string]$sdtEndTime,
        [Parameter(Mandatory=$false)]
        [string]$sdtNote
    )
    # TODO: add conditional to check if date is in epoch time before converting. catch exceptions when attempting to convert
    $sdtStartTime = (New-TimeSpan -Start (Get-Date "01/01/1970") -End (Get-Date $sdtStartTime)).TotalMilliseconds
    $sdtEndTime = (New-TimeSpan -Start (Get-Date "01/01/1970") -End (Get-Date $sdtEndTime)).TotalMilliseconds
    $body = @{
        deviceSysName = $deviceHostName 
        companyID = $companyID
        sdtStartTime = $sdtStartTime
        sdtEndTime = $sdtEndTime
        sdtNote = $sdtNote
        deviceMacAddress = $deviceMacAddress
        deviceSerialNumber = $deviceSerialNumber
        deviceLocalIPAddress = $deviceIPAddress
    } | ConvertTo-Json
    $Result = Invoke-WebRequest -Uri $jobRunnerUri -Method "POST" -Body $body -ContentType 'application/json'
    Write-Output $Result
}

function New-LMDevice {
    Param(
        [Parameter(Mandatory=$true)]  
        [String] $PollingAddress,
        [Parameter(Mandatory=$true)] 
        [String] $DisplayName,
        [Parameter(Mandatory=$true)] 
        [String] $CollectorGroupID,
        [Parameter(Mandatory=$false)] 
        [String] $HostGroupIds,
        [Parameter(Mandatory=$false)] 
        [String] $Description,
        [Parameter(Mandatory = $false)]
        [bool]$DisableAlerting,
        [Parameter(Mandatory = $false)]
        [string]$Link,
        [Parameter(Mandatory = $false)]
        [string] $CustomProperties,
        [Parameter(Mandatory=$true)] 
        [String] $tenantName,
        [Parameter(Mandatory=$true)] 
        [String] $accessId,
        [Parameter(Mandatory=$true)] 
        [String] $accessKey
    )
    $Body = @{
        name = $PollingAddress
        displayName = $DisplayName
        preferredCollectorId = 0
        autoBalancedCollectorGroupId = $CollectorGroupID
    }
    if ($HostGroupIds){
        $Body.hostGroupIds = $HostGroupIDs
    }
    if ($Description){
        $Body.description = $Description
    }
    $Request = @{
        tenantName = $tenantName 
        accessId = $accessId 
        accessKey = $accessKey 
        resourcePath = "/device/devices"
        httpVerb = 'POST'
        httpBody = $Body | ConvertTo-Json
        version = 3
    }
    Invoke-LMAPI @Request
}

function Invoke-LomoApi() {
    Param(
        [Parameter(Mandatory=$true)] 
        [String] $tenantName,
        [Parameter(Mandatory=$true)] 
        [String] $accessId,
        [Parameter(Mandatory=$true)] 
        [String] $accessKey,
        [Parameter(Mandatory = $true)]
        [string]$resourcePath,
        [Parameter(Mandatory = $false)]
        [string]$httpVerb = 'GET',
        [Parameter(Mandatory = $false)]
        [string]$queryParams,
        [Parameter(Mandatory = $false)]
        [string]$httpBody = $null,
        [Parameter(Mandatory = $false)]
        [int]$version = 3
    )
    if ($httpBody -and $httpBody -isnot [string]) { $httpBody = $httpBody | ConvertTo-Json -Depth 10 }
    # Use TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    <# Construct URL #>
    $url = "https://$tenantName.logicmonitor.com/santaba/rest$resourcePath$queryParams"
    <# Get current time in milliseconds #>
    $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)
    <# Concatenate Request Details #>
    $requestVars = $httpVerb + $epoch + $httpBody + $resourcePath
    <# Construct Signature #>
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [Text.Encoding]::UTF8.GetBytes($accessKey)
    $signature = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(([System.BitConverter]::ToString($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestVars))) -replace '-').ToLower()))
    <# Construct Headers #>
    $auth = 'LMv1 ' + $accessId + ':' + $signature + ':' + $epoch
    $httpHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $httpHeaders.Add("Authorization", $auth)
    $httpHeaders.Add("Content-Type", 'application/json')
    $httpHeaders.Add("X-version", $version)

    <# Construct Request #>
    $request = @{
        Uri = $url
        Method = $httpVerb
        Headers = $httpHeaders
    }
    if ($httpVerb -ne "GET"){$request.Body = $httpBody}

    <# Make request & retry if failed due to rate limiting #>
    $Stoploop = $false
    do {
        try {
            <# Make Request #>
            $response = Invoke-RestMethod @request
            $Stoploop = $true
        }
        catch {
            switch ($_) {
                { $_.Exception.Response.StatusCode.value__ -eq 429 } {
                    Write-Host "Request exceeded rate limit, retrying in 60 seconds..."
                    Start-Sleep -Seconds 60
                    $response = Invoke-RestMethod @request
                }
                default {
                    Write-Host $_            
                    $Stoploop = $true
                }
            }
        }
    } while ($Stoploop -eq $false)
    return $response
}


function Get-ClientResourceGroups {
    $RGRequest = @{
        tenantName = $tenantName 
        accessId = $accessId 
        accessKey = $accessKey 
        httpverb = "GET" 
        resourcePath = "/device/groups" 
        queryParams = '?size=1000&filter=name:Devices by Organization' 
        Version = 1
    }
    $ResourceGroups = (Invoke-LMAPI @RGRequest).subGroups
    $ResourceGroups | ForEach-Object {
        $RGPropRequest = @{
            tenantName = $tenantName 
            accessId = $accessId 
            accessKey = $accessKey 
            httpverb = "GET" 
            resourcePath = "/device/groups/$($_.id)" 
            queryParams = '?fields=customProperties,defaultCollectorId,defaultCollectorGroupId,defaultAutoBalancedCollectorGroupId'
            Version = 1
        }
        # Old function is being used here. Need to update New function to handle format returned by this endpoint. 
        $RGProps = (Invoke-LOMOAPI @RGPropRequest).data
        $_ | Add-Member -MemberType "NoteProperty" -Name "companyID" -Value (($RGProps.customProperties | Where-Object {$_.name -eq "company.id"}).value)
        $_ | Add-Member -MemberType "NoteProperty" -Name "defaultCollectorId" -Value $RGProps.defaultCollectorId
        $_ | Add-Member -MemberType "NoteProperty" -Name "defaultCollectorGroupId" -Value $RGProps.defaultCollectorGroupId
        $_ | Add-Member -MemberType "NoteProperty" -Name "defaultAutoBalancedCollectorGroupId" -Value $RGProps.defaultAutoBalancedCollectorGroupId
    }
    $ResourceGroups
}
function Get-ClientCollectorGroups {
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
    $CollectorGroups
}
function Get-ClientResources {
    $ResourceRequest = @{
        tenantName = $tenantName 
        accessId = $accessId 
        accessKey = $accessKey 
        httpVerb = "GET" 
        resourcePath = "/device/devices" 
        queryParams = '?size=1000' 
        Version = 3
    }
    $Resources = Invoke-LMAPI @ResourceRequest
    $Resources | ForEach-Object { 
        $ResourceCompanyID = ($_.inheritedProperties | Where-Object {$_.name -eq "company.id"}).value
        $_ | Add-Member -MemberType "NoteProperty" -Name "companyID" -Value $ResourceCompanyID
        $StaticGroups = ($_.systemProperties | Where-Object {$_.name -eq "system.staticgroups"}).value
        $_ | Add-Member -MemberType "NoteProperty" -Name "staticGroups" -Value $StaticGroups
        $Groups = ($_.systemProperties | Where-Object {$_.name -eq "system.groups"}).value
        $_ | Add-Member -MemberType "NoteProperty" -Name "groups" -Value $Groups
        $Sysname = ($_.systemProperties | Where-Object {$_.name -eq "system.sysname"}).value
        $_ | Add-Member -MemberType "NoteProperty" -Name "sysname" -Value $Sysname
        $CompanyName = (@($_.staticGroups)[0] -split ("/"))[1] 
        $_ | Add-Member -MemberType "NoteProperty" -Name "companyName" -Value $CompanyName    
        if ($_.groups -match ".*/Type/Server.*") { $isServer = $true } else { $isServer = $false }
        $_ | Add-Member -MemberType "NoteProperty" -Name "isServer" -Value $isServer
        if ($_.groups -match ".*/Type/Network.*") { $isNetwork = $true } else { $isNetwork = $false }
        $_ | Add-Member -MemberType "NoteProperty" -Name "isNetwork" -Value $isNetwork
        if ($_.groups -match ".*/Type/Environmental.*") { $isEnvironmental = $true } else { $isEnvironmental = $false }
        $_ | Add-Member -MemberType "NoteProperty" -Name "isEnvironmental" -Value $isEnvironmental
        if ($_.groups -match ".*/Type/Cloud.*") { $isCloud = $true } else { $isCloud = $false }
        $_ | Add-Member -MemberType "NoteProperty" -Name "isCloud" -Value $isCloud
        if ($_.groups -match ".*/Type/Storage.*") { $isStorage = $true } else { $isStorage = $false }
        $_ | Add-Member -MemberType "NoteProperty" -Name "isStorage" -Value $isStorage
        if ($_.groups -match ".*/Locations/New Devices.*") { $isNewDevice = $true } else { $isNewDevice = $false }
        $_ | Add-Member -MemberType "NoteProperty" -Name "isNewDevice" -Value $isNewDevice
        $DataSourceRequest = @{
            tenantName = $tenantName 
            accessId = $accessId 
            accessKey = $accessKey 
            httpVerb = "GET" 
            resourcePath = "/device/devices/$($_.id)/devicedatasources" 
            queryParams = '?size=1000&filter=instanceNumber!:0' 
            Version = 1
        }
        $DataSources = (Invoke-LMAPI @DataSourceRequest | Select-Object -ExpandProperty dataSourceName) -join "; "
        $_ | Add-Member -MemberType "NoteProperty" -Name "dataSources" -Value $DataSources
        if ($DataSources -match ".*Troubleshooter.*") { $TroubleshooterActive = $true } else { $TroubleshooterActive = $false } 
        $_ | Add-Member -MemberType "NoteProperty" -Name "troubleshooterActive" -Value $TroubleshooterActive
        Start-Sleep -Milliseconds 100
    }
    $Result = @()
    foreach ($Resource in $Resources){
        if ($Resource.Datasources -like "*Troubleshooter*") {
            $Resource.troubleshooterActive = $true
        } else {
            $Resource.troubleshooterActive = $false
        }
        $Result += $Resource
    }
    $Result    
}
function Get-ClientCollectors {
    $LMAuth = @{
        tenantName = $tenantName 
        accessId = $accessId 
        accessKey = $accessKey 
    }
    $CollectorRequest = @{
        tenantName = $tenantName 
        accessId = $accessId 
        accessKey = $accessKey 
        httpVerb = "GET" 
        resourcePath = "/setting/collectors" 
        queryParams = '?size=1000' 
        Version = 1
    }
    $Collectors = Invoke-LMAPI @CollectorRequest
    $Collectors | ForEach-Object {
        $CollectorCompanyID = ($_.customproperties | Where-Object {$_.name -eq "company.id"}).value
        $_ | Add-Member -MemberType "NoteProperty" -Name "companyID" -Value $CollectorCompanyID
    }
    $Collectors
}
function Get-EmptyClientCollectorGroups {
    $CollectorGroups = Get-ClientCollectorGroups
    $CollectorGroups | Where-Object {$_.numOfCollectors -eq 0} 
}
function Get-EmptyClientResourceGroups {
    $ResourceGroups = Get-ClientResourceGroups
    $ResourceGroups | Where-Object {$_.numOfHosts -eq 0} 
}
function Get-DeadResources {
    $Resources = Get-ClientResources
    $Resources | Where-Object {($_.hostStatus -eq "dead") } 
}
function Get-ResourcesWiIPAsDN {
    $Resources = Get-ClientResources
    $Resources | Where-Object { ($_.displayName -match '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}') -and ($_.collectorDescription -ne "Cloud Collector")} 
}
function Get-ResourcesWiDNforPolling {
    $Resources = Get-ClientResources
    $Resources | Where-Object { ($_.name -notmatch '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}') -and ($_.collectorDescription -ne "Cloud Collector") -and ($_.StaticGroups -notmatch ".*Portals.*")} 
}
function Get-ResourcesWoSysname {
    $Resources = Get-ClientResources
    $Resources | Where-Object { ($_.sysname -eq $null) -and ($_.collectorDescription -ne "Cloud Collector")} 
}
function Get-CloudResources {
    $Resources = Get-ClientResources
    $Resources | Where-Object { $_.collectorDescription -eq "Cloud Collector"} 
}
function Get-ResourcesWoLocationGroup {
    $Resources = Get-ClientResources
    $Resources | Where-Object { (($_.staticGroups -match ".*New Devices.*") -or ($_.StaticGroups -notmatch ".*Locations.*")) -and ($_.collectorDescription -ne "Cloud Collector") -and (($_.StaticGroups -notmatch ".*Portals.*"))} 
}
function Get-ResourcesWiTroubleshooterActive {
    $Resources = Get-ClientResources
    $Resources | Where-Object { $_.activeDataSources -match ".*Troubleshooter.*" }
}
function Get-ResourcesWiSharedCollector {
    $Resources = Get-ClientResources
    $Resources | Where-Object { $_.preferredCollectorGroupName -like "*Shared*" } 
}
function Get-ResourcesWoABCG {
    $Resources = Get-ClientResources
    $Resources | Where-Object { $_.autoBalancedCollectorGroupId -eq "0" } 
}
function Get-CollectorsWoEC {
    $Collectors = Get-ClientCollectors
    $Collectors | Where-Object {$_.escalatingChainId -eq "0"} 
}
function Get-DownCollectors {
    $Collectors = Get-ClientCollectors
    $Collectors | Where-Object {$_.isDown -eq "True"} 
}
function Get-CollectorIPs {
    $Collectors = Get-ClientCollectors | Where-Object {$_.isDown -eq $false}
    $Result = @()
    foreach ($i in $Collectors) {
        $DGSessionBody = @{
            cmdline = "!ipaddress"
        }
        $DGSessionRequest = @{
            tenantName = $tenantName 
            accessId = $accessId 
            accessKey = $accessKey 
            httpVerb = "POST" 
            resourcePath = "/debug/" 
            queryParams = "?collectorId=$($i.id)"
            httpBody = $DGSessionBody | ConvertTo-Json
            Version = 3
        }
        $DebugCommandSession = Invoke-LomoAPI @DGSessionRequest
        $DGOutputRequest = @{
            tenantName = $tenantName 
            accessId = $accessId 
            accessKey = $accessKey 
            httpVerb = "GET" 
            resourcePath = "/debug/$($DebugCommandSession.sessionId)" 
            queryParams = "?collectorId=$($i.id)"
            Version = 3
        }
        $DebugCommandOutput = Invoke-LomoAPI @DGOutputRequest
        $Capture = $DebugCommandOutput.Output | Select-String -Pattern “IPV4.*:\s(.*)” 
        try {
            $CollectorIP = $Capture.Matches.Groups[1].Value
            $i| Add-Member -MemberType "NoteProperty" -Name "collectorIPAddress" -Value $CollectorIP
        } catch {
            Write-Warning "$($i.hostname) has no IPConfig Output"
        }
        $Result += $i
    }
    $Result
}
function Get-CollectorGroupsWoCompanyID {
    $CollectorGroups = Get-ClientCollectorGroups
    $CollectorGroups | Where-Object {$_.companyID -eq $null -and $_.name -ne "@default"}
}
function Get-ResourceGroupsWoCompanyID {
    $ResourceGroups = Get-ClientResourceGroups
    $ResourceGroups | Where-Object {$_.companyID -eq $null}
}
function Get-DashboardGroupsWoCRG {

}
function Get-CollectorGroupsWoCRG {

}
function Get-MapGroupsWoCRG {

}
function Get-ReportGroupsWoCRG {

}
function Get-RolesWoCRG {

}
function Get-ResourcesWiPubIP {

}