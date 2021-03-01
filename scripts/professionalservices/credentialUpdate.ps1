#import credentials
. ./lmAPICreds.ps1
$company = 'rfa'
$csvfile = "../../orgCreds.csv"

# Functionize the reusable code that builds and executes the query
function Send-Request() {
    Param(
        [Parameter(position = 0, Mandatory = $true)]
        [string]$path,
        [Parameter(position = 1, Mandatory = $false)]
        [string]$httpVerb = 'GET',
        [Parameter(position = 2, Mandatory = $false)]
        [string]$queryParams,
        [Parameter(position = 3, Mandatory = $false)]
        $data = $null,
        [Parameter(position = 4, Mandatory = $false)]
        $version = 3

    )

    if ($data -and $data -isnot [string]) { $data = $data | ConvertTo-Json -Depth 10 }
    # Use TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    <# Construct URL #>
    $url = "https://$company.logicmonitor.com/santaba/rest$path$queryParams"
    
    <# Get current time in milliseconds #>
    $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)

    <# Concatenate Request Details #>
    $requestVars = $httpVerb + $epoch + $data + $path

    <# Construct Signature #>
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [Text.Encoding]::UTF8.GetBytes($accessKey)
    $signatureBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestVars))
    $signatureHex = [System.BitConverter]::ToString($signatureBytes) -replace '-'
    $signature = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($signatureHex.ToLower()))

    <# Construct Headers #>
    $auth = 'LMv1 ' + $accessId + ':' + $signature + ':' + $epoch
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", $auth)
    $headers.Add("Content-Type", 'application/json')
    $headers.Add("X-version", $version)

    <# Make request & retry if failed due to rate limiting #>
    $Stoploop = $false
    do {
        try {
            <# Make Request #>
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Body $data -Header $headers
            $Stoploop = $true
        }
        catch {
            switch ($_) {
                { $_.Exception.Response.StatusCode.value__ -eq 429 } {
                    Write-Host "Request exceeded rate limit, retrying in 60 seconds..."
                    Start-Sleep -Seconds 60
                    $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Body $data -Header $headers
                }
                default {
                    write-host $_
                    $Stoploop = $true
                }
            }
        }
    } While ($Stoploop -eq $false)
    Return $response
}
function Iterate() {
    Param(
        [Parameter(position = 0, Mandatory = $true)]
        [string]$Path
    )
    $response = @()
    $remaining = $true
    $offset = 0
    $size = 50
    while ($remaining) {
        $result = (Send-Request -Path $path -httpverb 'GET' -queryParams "?size=$size&offset=$offset").items
        $response += $result
        if ($result.Count -lt $size) {
            $remaining = $false
        }
        else {
            $offset += $size
        }
    }
    return $response
}

$devicegroups = iterate -path '/device/groups'

$csvobject = import-csv $csvfile

foreach ($line in $csvobject) {
    $companyid = $line.companyID
    $properties = $line.companyCredentials.split(';')
    foreach ($devicegroup in $devicegroups) {
        $devicegroupcompanyid = $devicegroup.customproperties | where {$_.name -match "company.id"}
        if ($devicegroupcompanyid.value -match $companyid) {
            foreach ($property in $properties) {
                $propertyname = $property.split('=')[0]
                $propertyvalue = $property.split('=')[1]
                $propertymatched = $devicegroup.customproperties | where {$_.name -match $propertyname}
                if (!$propertymatched) {
                    $body = @{
                        name = $propertyname
                        value = $propertyvalue
                    }
                    $result = send-request -path "/device/groups/$($devicegroup.id)/properties" -httpVerb 'POST' -data $body
                    if ($result) {
                        Write-Host "Updated property $propertyname for device group $($devicegroup.name)"
                    } else {
                        write-host "failed to update property $propertyname for device group $($devicegroup.name)"
                    }
                }
            }
        }
    }
}