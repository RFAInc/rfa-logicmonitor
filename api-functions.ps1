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
                # { $_.Exception.Response.StatusCode.value__ } {
                #     Write-Host "Request failed, not as a result of rate limiting"
                #     # Dig into the exception to get the Response details.
                #     # Note that value__ is not a typo.
                #     Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
                #     Write-Host "StatusDescription:" $_.Exception.Response.StatusCode
                #     $response = $null
                #     $Stoploop = $true
                # }
                default {
                    # Write-Host "An Unknown Exception occured:"
                    # Write-Host $_.Exception
                    # $response = $null        
                    Write-Host $_            
                    $Stoploop = $true
                }
            }
        }
    } while ($Stoploop -eq $false)
    return $response
}