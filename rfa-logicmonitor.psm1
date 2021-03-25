# All below copied from PSExcel module, with the DLL part removed. 

# Get public and private function definition files.
$PrivateFilePaths = @()
$Private = $PrivateFilePaths | %{Get-Item $_ -ErrorAction SilentlyContinue}
$PublicFilePaths = @(
    '.\api-functions.ps1'
    '.\modules\rfa-logicmonitor.ps1'
)
$Public = $PublicFilePaths | %{Get-Item $_ -ErrorAction SilentlyContinue}
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
#Export-ModuleMember -Function $($Public | Select -ExpandProperty BaseName) -Alias *
Export-ModuleMember -Function $PublicFunctions -Alias *

