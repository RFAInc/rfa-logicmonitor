<#
.NOTES
    Author:     Andy Escolastico
#>
#----------------------------------------------------------[Initializations]----------------------------------------------------------#

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Ssl3, [Net.SecurityProtocolType]::Tls, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls12; 
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Ssl3, [Net.SecurityProtocolType]::Tls, [Net.SecurityProtocolType]::Tls12

#----------------------------------------------------------[Declarations]----------------------------------------------------------#

# lm variables
. ./creds/lm-api-creds.ps1
$Category = "BackupExec"

#-----------------------------------------------------------[Functions]------------------------------------------------------------#
. ./modules/rfa-logicmonitor.ps1
#-----------------------------------------------------------[Execution]------------------------------------------------------------#

$lmRequest = @{
    accessId = $accessId
    accessKey = $accessKey
    tenantName = $tenantName
    resourcePath = "/device/devices"
    queryParams = '?fields=id,customProperties&size=1000'
    httpVerb = "GET"
}

$lmResponse = Invoke-LomoApi @lmRequest
$devices = $lmResponse.items
$devices | ForEach-Object {
    $Categories = ($_.customProperties | Where-Object {$_.name -eq "system.categories"}).value
    $_ | Add-Member -MemberType "NoteProperty" -Name "Categories" -Value $Categories
}

foreach ($i in $devices){
    $OldCategories = $i.Categories
    $DeviceID = $i.id
    $Array = [System.Collections.ArrayList]($OldCategories -split ",")
    $Array.Remove($Category)
    $NewCategories = $Array -join ","
    # lm request
    $lmBody = @{
        value = $NewCategories
    }
    $lmRequest = @{
        accessId = $accessId
        accessKey = $accessKey
        tenantName = $tenantName
        resourcePath = "/device/devices/$DeviceID/properties/system.categories/"
        httpVerb = "PUT"
        httpBody = $lmBody | ConvertTo-Json
    }
    $lmResponse = Invoke-LomoApi @lmRequest
}
