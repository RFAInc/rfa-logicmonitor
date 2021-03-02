<#
.NOTES
    Version:        1.0
    Author:         Andy Escolastico
    Creation Date:  8/17/2020
#>
#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#----------------------------------------------------------[Declarations]----------------------------------------------------------
$LogPath = "./reports/device-imports_$(Get-Date -format "MM-dd-yy_HH-mm").log"
$RejectedPath =  "./reports/device-rejects_$(Get-Date -format "MM-dd-yy_HH-mm").csv"
$DeviceSourcePath = "./csvs/devices.csv"
$NATSourcePath = "./csvs/nats.csv"
#-----------------------------------------------------------[Functions]------------------------------------------------------------
. ./creds/lm-api-creds.ps1
. ./modules/rfa-logicmonitor.ps1
#-----------------------------------------------------------[Execution]------------------------------------------------------------
Write-Host "Gathering Collector and Resource Group information..."
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
$RGRequest = @{
    tenantName = $tenantName 
    accessId = $accessId 
    accessKey = $accessKey 
    httpVerb = "GET" 
    resourcePath = "/device/groups" 
    queryParams = '?size=1000&filter=fullPath~Devices by Organization/' 
    Version = 1
}
$ResourceGroups = Invoke-LMAPI @RGRequest
$ParentRGs = $ResourceGroups | Where-Object {$_.fullPath -notmatch "Devices by Organization\/.*\/.*"}
$ParentRGs | ForEach-Object { 
    $ResourceGroupCompanyID = ($_.customProperties | Where-Object {$_.name -eq "company.id"}).value
    $_ | Add-Member -MemberType "NoteProperty" -Name "companyID" -Value $ResourceGroupCompanyID
}
$Devices = Import-Csv -Path $DeviceSourcePath
$NATs = Import-Csv -Path $NATSourcePath
$RejectedDevices = @()
foreach ($Device in $Devices){
    $CompanyID = $Device.CompanyID
    $IPAddress = $Device.IP
    $NetworkAddress = ((($IPAddress).Split("."))[0..2] -join ".") + ".0"
    $DisplayName = $Device.Name
    $CollectorGroup = @($CollectorGroups | Where-Object {$_.companyID -eq $CompanyID})[0]
    $CollectorGroupID = $CollectorGroup.id
    $ParentRG = $ParentRGs | Where-Object {$_.companyID -eq $CompanyID}
    $LocationRG = $ParentRG.subgroups | Where-Object {$_.name -eq "Locations"}
    $NewDevicesRG = $ResourceGroups | Where-Object {$_.fullPath -eq "$($LocationRG.fullPath)/New Devices"}
    #------------------#------------------#------------------#
    if (-not $ParentRG){ 
        Write-Warning "$($CompanyID):$DisplayName has no Resource Group, creating group"
        Add-Content -Path $LogPath -Value "[EXCEPTION] $CompanyID, $IPAddress, $DisplayName | Reason: Device has no Resource Group"
        $RejectedDevices += $Device   
        continue 
    }
    if ($NetworkAddress -in $NATs.'RFA NAT') {
        Write-Warning "$($CompanyID):$DisplayName is part of a NAT, attempting conversion"
        $ClientNat = ($NATs | Where-Object {$_.'RFA NAT' -eq $NetworkAddress}).'CLIENT NAT'
        if ($ClientNat -like "*.*.*.*") {
            $NewIPAddress = ( (($ClientNat).Split("."))[0..2] -join "." ) + "." + ( (($IPAddress).Split("."))[-1] )
            $OldIPAddress = $IPAddress
            $IPAddress = $NewIPAddress
        } else {
            Write-Warning "$($CompanyID):$DisplayName's remote NAT is unknown"
            Add-Content -Path $LogPath -Value "[EXCEPTION] $CompanyID, $IPAddress, $DisplayName | Reason: Device is part of an unknown NAT"
            $RejectedDevices += $Device   
            continue  
        }
    }
    #------------------#------------------#------------------#
    if (($CollectorGroup.numOfCollectors -eq 0) -or (-not $CollectorGroup)){
        Write-Host "$($CompanyID):$DisplayName has no collectors of their own available" -ForegroundColor "Blue"
        Add-Content -Path $LogPath -Value "[INFO] $CompanyID, $IPAddress, $DisplayName | Reason: Device has no collectors of their own available"
        $CollectorGroupID = 260
        # $IPAddress = 
    }
    if (-not $NewDevicesRG) {
        Write-Host "$($CompanyID):$DisplayName doesnt have a 'New Devices' group" -ForegroundColor "Blue"
        Add-Content -Path $LogPath -Value "[INFO] $CompanyID, $IPAddress, $DisplayName | Reason: Device doesnt have a 'New Devices' group"
        $NDRGBody = @{
            name = "New Devices"
            parentId = $LocationRG.id 
            description = "Location is used to stage devices added using automated deployment routines. Devices in this group should be moved to the correct group under 'Devices by Organization/{{CLIENT}}/Locations/{{LOCATION}}'"
        }
        $NDRGRequest = @{
            tenantName = $tenantName 
            accessId = $accessId 
            accessKey = $accessKey 
            httpVerb = "POST" 
            resourcePath = "/device/groups" 
            httpBody = $NDRGBody | ConvertTo-Json
            Version = 3
        }
        $NewDevicesRG = Invoke-LMAPI @NDRGRequest
        $ResourceGroups = Invoke-LMAPI @RGRequest
    }
    #------------------#------------------#------------------#
    $NewDevicesRGID = $NewDevicesRG.id
    $DeviceRequest = @{
        PollingAddress = $IPAddress 
        DisplayName = $DisplayName 
        CollectorGroupID = $CollectorGroupID 
        HostGroupIds = $NewDevicesRGID
        tenantName = $tenantName 
        accessId = $accessId 
        accessKey = $accessKey
    }
    $Device = New-LMDevice @DeviceRequest
    #------------------#------------------#------------------#
    if ($Device.id) {
        Write-Host "$($CompanyID):$DisplayName added" -ForegroundColor "Green"
        Add-Content -Path $LogPath -Value "[SUCCESS] $CompanyID, $IPAddress, $DisplayName | Reason: Device added with ID $($Device.id)"
    } else {
        $ErrorMessage = $error[0].ErrorDetails.Message
        Add-Content -Path $LogPath -Value "[FAILURE] $CompanyID, $IPAddress, $DisplayName | Reason: $ErrorMessage"
    }   
}
if ($RejectedPath -ne $null) {
    $RejectedDevices | Export-Csv -Path $RejectedPath -NoTypeInformation
}
