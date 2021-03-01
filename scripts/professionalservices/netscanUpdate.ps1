#import credentials
. ./lmAPICreds.ps1
$company = 'rfa'
$csvfile = "./netscans.csv"

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

    if ($data -and $data -isnot [string]) { $data = $data | ConvertTo-Json -Depth 4}

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
        } catch {
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


function checkIfExists() {
    Param(
        [Parameter(position = 0, Mandatory = $true)]
        [PSObject]$groups,
        [Parameter(position = 1, Mandatory = $false)]
        [string]$groupFullPath,
        [Parameter(position = 2, Mandatory = $false)]
        [string]$companyId,
        [Parameter(position = 3, Mandatory = $false)]
        [string]$type = "devicegroup",
        [Parameter(position = 4, Mandatory = $false)]
        $properties = @{}
    )

    $listOfExistingIds = ($groups.customProperties | WHere {$_.name -eq "company.id"}).value
    if (!$listOfExistingIds) {
        $listOfExistingIds = ($groups.properties | Where {$_.name -eq "company.id"}).value
    }

    if ($companyId -and $listOfExistingIds -contains $companyId) {
        $group = $groups | where {$_.customProperties.value -contains $companyId -or $_.properties.value -contains $companyId}
        Write-host "$($type): $name already exists with companyId: $companyId"
    } else {
        if (($type -eq "devicegroup" -or $type -eq "websitegroup" -or $type -eq "dashboardgroup") -and $groups.fullPath -contains $groupFullPath) {
        #if (($type -eq "devicegroup" -or $type -eq "websitegroup" -or $type -eq "dashboardgroup") -and ($listOfExistingIds -contains $companyId -or $groups.fullPath -contains $groupFullPath)) {
            Write-host "$($type): $name already exists"
            $group = $groups | where { $_.fullPath -eq $groupFullPath }



        } elseif (($type -eq "reportgroup" -or $type -eq "topologygroup" -or $type -eq "collectorgroup" -or $type -eq "rolegroup") -and $groups.name -contains $name ) {

            Write-host "$($type): $name already exists"
            $group = $groups | where { $_.name -eq $name }


        } else {


	}
    }
    return $group

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
        } else {
            $offset += $size
        }
    }
    return $response
}

$data = Import-Csv $csvfile

$deviceGroups = Iterate -Path '/device/groups'
$listOfExistingIds = ($deviceGroups.customProperties | Where {$_.name -eq "company.id"}).value
    if (!$listOfExistingIds) {
        $listOfExistingIds = ($deviceGroups.properties | Where {$_.name -eq "company.id"}).value
    }

$groupFullPath='Devices by Organization'
$ParentId=($deviceGroups | where { $_.fullPath -eq $groupFullPath }).id

$collectorGroups = Iterate -Path '/setting/collector/groups'
$listOfCollectorIds = ($collectorGroups.customProperties | Where {$_.name -eq "company.id"}).value
    if (!$listOfCollectorIds) {
        $listOfCollectorIds = ($collectorGroups.properties | Where {$_.name -eq "company.id"}).value
}

$netscansGroups = Iterate -Path '/setting/netscans/'
$existingNetscans=$netscansGroups.name

$collectors = Iterate -Path '/setting/collector/collectors'

foreach ($line in $data) {


	$companyID = $line.'companyID'
	$subnets= $line.'companySubnets'

    Write-Host "######################################################"
	Write-Host "Working on NetScan Automation for $companyID"
	Write-Host "For Subnets $subnets"
	Write-Host "--------------------------------------------------------"


#check if device group exists

 if ($listOfExistingIds -contains $companyID) {
		#device group exists so create Netscan
		Write-Host "device group exists proceeding...."

	$dgroupFullpath=($deviceGroups | where { $_.parentId -eq $ParentId -and $_.customProperties.value -eq $companyID}).fullpath
	$dgroupName=($deviceGroups | where { $_.parentId -eq $ParentId -and $_.customProperties.value -eq $companyID}).name
	$dgroupId=($deviceGroups | where { $_.parentId -eq $ParentId -and $_.customProperties.value -eq $companyID}).id


	if ($listOfCollectorIds -contains $companyID) {
		# collector group exists so proceed with netscan creating
		Write-Host "collector group exists for cutomer:$dgroupName, proceeding with creating Netscan...."
		$numOfCollectors=($collectorGroups | where { $_.customProperties.value -eq $companyID}).numOfCollectors

			if ($numOfCollectors -ge 1) {
				Write-Host "has $numOfCollectors collector(s), proceeding...."

				# use the first collector if more than one collectors
				$collectorTouse=($collectors | where { $_.customProperties.value -eq "$companyID (inherited from Group)"}).id

				if ($existingNetscans -contains $dgroupName)
				{
					Write-Host "netscan already exists for $dgroupName, aborting...."
				}
				else
				{
					Write-Host "creating netscan for $dgroupName...."

						$netscanBody= @{
							version            = 2
							name               = $dgroupName
							description        = "$dgroupName Netscan"
							method             = "nmap"
							group              = "Clients"
							nsgId              = 3
							schedule = @{
								notify   = $false
								type     = "manual"
								recipients   = @()
								cron    = ""
								timezone = "Europe/London"
							}
							collector          = $collectorTouse[0]
							nextStart          = "manual"
							nextStartEpoch     = 0
							duplicate= @{
					  			type = 1
							  	groups= @()
							  	collectors= @()
				 			 }
							ignoreSystemIPsDuplicates  = $false
							subnet = $subnets
							exclude  = ""
							ports= @{
								isGlobalDefault   = $true
								value     		  = "21,22,23,25,53,69,80,81,110,123,135,143,389,443,445,631,993,1433,1521,3306,3389,5432,5672,6081,7199,8000,8080,8081,9100,10000,11211,27017"
				  			}
							credentials= @{
					  		deviceGroupId = 0
					  		deviceGroupName = ""
					  		custom = @()
				 			 }
							ddr = @{
								changeName = "##REVERSEDNS##"
								assignment = @(
									@{
										group = $dgroupId
										groupName = $dgroupFullpath
										disableAlerting = $false
										action = "Include"
										type = 1
										query = ""
									}
							    )
						}
				  	}
				Send-Request -Path '/setting/netscans/' -httpVerb 'POST' -data $netscanBody | Out-Null
				Write-host "netscan created for $dgroupName"
				}

			}
			else
			{
				Write-Host "has $numOfCollectors collector(s), will not create netscan...."

			}

	}
	else
	{
		Write-Host "No collector group exists for cutomer:$dgroupName compnayID:$companyID"
	}
}
else
{
	#Group does not Exists so do nothing
	Write-Host "No device group exists for compnayID $companyID, will not create netscan."

}
Write-Host "######################################################"
}