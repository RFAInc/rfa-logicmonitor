<#
.NOTES
    Version:        1.0
    Author:         Andy Escolastico
    Creation Date:  8/17/2020
#>
#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#----------------------------------------------------------[Declarations]----------------------------------------------------------
$BackupDir = "./backups/$(Get-Date -Format 'MM-dd-yyyy')"
#-----------------------------------------------------------[Functions]------------------------------------------------------------
. ./creds/lm-api-creds.ps1
. ./modules/rfa-logicmonitor.ps1
#-----------------------------------------------------------[Execution]------------------------------------------------------------
$DSRequest = @{
    tenantName = $tenantName 
    accessId = $accessId 
    accessKey = $accessKey 
    httpVerb = "GET" 
    resourcePath = "/setting/datasources" 
    queryParams = '?size=1000' 
    Version = 3
}

$DSs = Invoke-LMAPI @DSRequest

foreach ($DS in $DSs) {
    $DSID = $DS.id
    $DSGroup = $DS.group
    $DSName = $DS.name
    if (-not $DSGroup) {
        $DSGroup = "_Ungrouped"
    }
    $BURequest = @{
        tenantName = $tenantName 
        accessId = $accessId 
        accessKey = $accessKey 
        httpVerb = "GET" 
        resourcePath = "/setting/datasources/$($DSID)" 
        queryParams = '?format=xml' 
    }
    $BU = Invoke-LMAPI @BURequest
    if (-not (Test-Path "$BackupDir/datasources/$DSGroup")) {
        New-Item -ItemType "Directory" -Path "$BackupDir/datasources/$DSGroup" -Force
    }
    $BU | Out-File "$BackupDir/datasources/$DSGroup/$DSName.xml" -Force
}

$PSRequest = @{
    tenantName = $tenantName 
    accessId = $accessId 
    accessKey = $accessKey 
    httpVerb = "GET" 
    resourcePath = "/setting/propertyrules" 
    queryParams = '?size=1000' 
    Version = 3
}

$PSs = Invoke-LMAPI @PSRequest

foreach ($PS in $PSs) {
    $PSID = $PS.id
    $PSGroup = $PS.group
    $PSName = $PS.name
    if (-not $PSGroup) {
        $PSGroup = "_Ungrouped"
    }
    $BURequest = @{
        tenantName = $tenantName 
        accessId = $accessId 
        accessKey = $accessKey 
        httpVerb = "GET" 
        resourcePath = "/setting/propertyrules/$($PSID)" 
        queryParams = '?format=file&v=3' 
    }
    $BU = Invoke-LMAPI @BURequest
    if (-not (Test-Path "$BackupDir/propertysources/$PSGroup")) {
        New-Item -ItemType "Directory" -Path "$BackupDir/propertysources/$PSGroup" -Force
    }
    $BU | Out-File "$BackupDir/propertysources/$PSGroup/$PSName.json" -Force
}


$ATRequest = @{
    tenantName = $tenantName 
    accessId = $accessId 
    accessKey = $accessKey 
    httpVerb = "GET" 
    resourcePath = "/setting/functions" 
    queryParams = '?size=1000' 
    Version = 3
}

$ATs = Invoke-LMAPI @ATRequest
