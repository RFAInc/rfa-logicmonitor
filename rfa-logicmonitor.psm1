# Get public and private function definition files.
$PrivateFilePaths = @()
$Private = $PrivateFilePaths | %{Join-Path $PSScriptRoot $_} | %{Get-Item $_ }
#write-debug "private" -debug

#$RelativeCredPath = (Join-Path 'creds' 'lm-api-creds.ps1')
#$FullCredPath = (Join-Path $PSScriptRoot $CredPath)


$PublicFilePaths = @(
    'api-functions.ps1'
    (Join-Path 'modules' 'rfa-logicmonitor.ps1')
)
$Public = $PublicFilePaths | %{Join-Path $PSScriptRoot $_} | %{Get-Item $_ }
#write-debug "public" -debug

$PublicFunctions = @(
    'Invoke-LomoApi'
    'Invoke-LMAPI'
    'New-RFALogicMonitorSDT'
    'New-LMDevice'
    'Invoke-LomoApi'
    'Get-ClientResourceGroups'
    'Get-ClientCollectorGroups'
    'Get-ClientResources'
    'Get-ClientCollectors'
    'Get-EmptyClientCollectorGroups'
    'Get-EmptyClientResourceGroups'
    'Get-DeadResources'
    'Get-ResourcesWiIPAsDN'
    'Get-ResourcesWiDNforPolling'
    'Get-ResourcesWoSysname'
    'Get-CloudResources'
    'Get-ResourcesWoLocationGroup'
    'Get-ResourcesWiTroubleshooterActive'
    'Get-ResourcesWiSharedCollector'
    'Get-ResourcesWoABCG'
    'Get-CollectorsWoEC'
    'Get-DownCollectors'
    'Get-CollectorIPs'
    'Get-CollectorGroupsWoCompanyID'
    'Get-ResourceGroupsWoCompanyID'
    'Get-DashboardGroupsWoCRG'
    'Get-CollectorGroupsWoCRG'
    'Get-MapGroupsWoCRG'
    'Get-ReportGroupsWoCRG'
    'Get-RolesWoCRG'
    'Get-ResourcesWiPubIP'   
)#>

#Dot source the files
Foreach ($import in @($Public + $Private)) {
    Try {
        #PS2 compatibility
        if ($import.fullname) {
            . $import.fullname
        }
    }
    Catch {
        Write-Error "Failed to import function $($import.fullname): $_"
    }
}


#Create some aliases, export public functions
#Export-ModuleMember -Function ($PublicFunctions) -Alias *
#$PublicFunctions | %{ Export-ModuleMember -Function $_ -Alias * }


#Load Creds
$RelativeCredPath = Join-Path 'creds' 'lm-api-creds.ps1'
$FullCredPath = Join-Path $PSScriptRoot $RelativeCredPath
#write-host $FullCredPath
#Test-Path $FullCredPath
#write-debug "cred" -debug

