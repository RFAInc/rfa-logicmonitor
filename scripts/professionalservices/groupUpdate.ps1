#import credentials
. ./creds/lm-api-creds.ps1
$company = 'rfa'
$csvfile = "./csvs/companies.csv"
$desiredCloneGroup = "Categories"

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

function getResourcePath($type) {
    if ($type -eq "devicegroup") {
        $resourcePath = "/device/groups"
    }
    elseif ($type -eq "websitegroup") {
        $resourcePath = "/website/groups"
    }
    elseif ($type -eq "reportgroup") {
        $resourcePath = "/report/groups"
    }
    elseif ($type -eq "topologygroup") {
        $resourcePath = "/topology/groups"
    }
    elseif ($type -eq 'dashboardgroup') {
        $resourcePath = "/dashboard/groups"
    }
    elseif ($type -eq "collectorgroup") {
        $resourcePath = "/setting/collector/groups"
    }
    elseif ($type -eq "rolegroup") {
        $resourcePath = "/setting/role/groups"
    }
    if ($resourcePath) {
        return $resourcePath
    }
    else {
        return $null
    }
}

function createGroup($name, $type, $properties) {

    $data = @{}
    $resourcePath = getResourcePath $type
    foreach ($key in $properties.Keys) {
        $data.$key = $properties[$key]
    }

    $data.name = $name
    $queryParams = ""
    $httpVerb = 'POST'

    $response = Send-Request $resourcePath $httpVerb $queryParams $data
    return $response
}

function updateGroup($group, $type, $properties) {
    $data = @{}
    $resourcePath = getResourcePath $type
    $resourcePath = $resourcePath + "/$($group.id)"
    foreach ($key in $properties.Keys) {
        $data.$key = $properties[$key]
    }

    $queryParams = ''
    $httpVerb = 'PATCH'

    $response = Send-Request $resourcePath $httpVerb $queryParams $data
}

function checkIfExists() {
    Param(
        [Parameter(position = 0, Mandatory = $true)]
        [PSObject]$groups,
        [Parameter(position = 1, Mandatory = $false)]
        [string]$groupFullPath,
        [Parameter(position = 2, Mandatory = $true)]
        [string]$name,
        [Parameter(position = 3, Mandatory = $false)]
        [string]$type = "devicegroup",
        [Parameter(position = 4, Mandatory = $false)]
        $properties = @{}
    )

    $listOfExistingIds = ($groups.customProperties | WHere { $_.name -eq "company.id" }).value
    if (!$listOfExistingIds) {
        $listOfExistingIds = ($groups.properties | Where { $_.name -eq "company.id" }).value
    }
    if (!$listOfExistingIds) {
        $listOfExistingIds = ($groups.widgetTokens | Where { $_.name -eq "company.id" }).value
    }
    $companyId = ($properties.customProperties | Where { $_.name -eq "company.id" }).value
    if (!$companyId) {
        $companyId = ($properties.properties | Where { $_.name -eq "company.id" }).value
    }
    if (!$companyId) {
        $companyId = ($properties.widgetTokens | Where { $_.name -eq "company.id" -and $_.type -eq "owned" }).id
    }

    if ($companyId -and $listOfExistingIds -contains $companyId) {
        $group = $groups | where { $_.customProperties.value -contains $companyId -or $_.properties.value -contains $companyId -or $_.widgetTokens.value -contains $companyId }
        Write-host "$($type): $name already exists with companyId: $companyId"
    }
    else {
        if (($type -eq "devicegroup" -or $type -eq "websitegroup" -or $type -eq "dashboardgroup") -and $groups.fullPath -contains $groupFullPath) {
            #if (($type -eq "devicegroup" -or $type -eq "websitegroup" -or $type -eq "dashboardgroup") -and ($listOfExistingIds -contains $companyId -or $groups.fullPath -contains $groupFullPath)) {
            Write-host "$($type): $name already exists"
            $group = $groups | where { $_.fullPath -eq $groupFullPath }

            $propertiesMatch = checkIfPropertiesMatch $group $properties
            if (!$propertiesMatch) {
                write-host "Updating $($type): $name due to mismatched properties"
                updateGroup $group $type $properties
            }
        }
        elseif (($type -eq "reportgroup" -or $type -eq "topologygroup" -or $type -eq "collectorgroup" -or $type -eq "rolegroup") -and $groups.name -contains $name ) {

            Write-host "$($type): $name already exists"
            $group = $groups | where { $_.name -eq $name }

            $propertiesMatch = checkIfPropertiesMatch $group $properties
            if (!$propertiesMatch) {
                write-host "Updating $($type): $name due to mismatched properties"
                updateGroup $group $type $properties
            }
        }
        else {

            $group = createGroup $name $type $properties

            if ($group) {
                Write-Host "$($type): $name has been created"
            }
            else {
                Write-Host "Oh No! $($type): $name failed to be created."
            }

        }
    }
    return $group

}

function checkIfPropertiesMatch($group, $properties) {
    $returnValue = $false
    if ($properties.Count -gt 0) {
        foreach ($key in $properties.Keys) {
            $value = $properties.$key
            $groupvalue = $group.$key
            if (!$groupvalue) {
                return $false
            }
            foreach ($item in $value) {
                if ($item.Keys) {
                    foreach ($k in $item.Keys) {
                        $v = $item.$k
                        if ($groupvalue.$k -match $v -or $groupvalue.$k -contains $v) {
                            $returnValue = $true
                        }
                        else {
                            return $false
                        }
                    }
                }
                else {
                    if ($groupvalue -match $item -or $groupvalue -contains $item) {
                        $returnValue = $true
                    }
                    else {
                        return $false
                    }
                }
            }
        }
        return $returnValue
    }
    else {
        return $true
    }
}

function getSortedGroups($groups) {
    $groupsObject = @{}
    $lengthList = @()
    $groups.fullPath | % {
        $lengthlist += ($_.split('/').Length - 1)
    }
    $maxdepth = ($lengthlist | Measure-Object -Maximum).Maximum
    for ($i = 1; $i -le $maxdepth; $i ++) {
        New-Variable -Name "var$i" -Value @()
    }
    foreach ($group in $groups) {
        $fullPathArray = $group.fullPath.split('/')
        $depth = ($fullPathArray.count - 1)
        (Get-Variable -Name "var$depth").Value += $group
    }
    for ($i = 1; $i -le $maxdepth; $i ++) {
        $groupsObject["$i"] = (Get-Variable -Name "var$i").Value
    }
    return $groupsObject
} 

function createSortedGroups($groups, $sortedgroups, $parentFolderPath, $parentId, $additionalAppliesTo) {
    foreach ($item in $sortedgroups.getEnumerator() | Sort-Object -Property Name) {
        $depth = $item.name
        $newgroups = $item.value
        foreach ($group in $newgroups) {
            if ($depth -eq "1") {
                $properties = @{
                    parentId = $parentId
                }
                if ($group.appliesTo) {
                    $properties.appliesTo = ($group.appliesTo + $additionalAppliesTo)
                }
                $createdgroupID = (checkIfExists -groups $groups -groupFullPath ($parentFolderPath + "/" + $group.fullPath) -name $group.name -type "devicegroup" -properties $properties).id
                New-Variable -Name "$($group.fullPath)" -Value $createdGroupID
            }
            else {
                $newparentId = (Get-Variable -Name $($group.fullPath.split('/')[0..($depth - 1)] -join ('/'))).Value
                $properties = @{
                    parentId = $newparentId
                }
                if ($group.appliesTo) {
                    $properties.appliesTo = ($group.appliesTo + $additionalAppliesTo)
                }
                $createdGroupID = (checkIfExists -groups $groups -groupFullPath ($parentFolderPath + "/" + $group.fullPath) -name $group.name -type "devicegroup" -properties $properties).id
                New-Variable -Name "$($group.fullPath)" -Value $createdGroupID
            }
        }
    }
}

function createOrUpdateDashboard() {
    param(
        [Parameter(position = 0, Mandatory = $true)]
        $dashboard,
        [Parameter(position = 1, Mandatory = $true)]
        $dashboards,
        [Parameter(position = 2, Mandatory = $true)]
        $groupId,
        [Parameter(position = 3, Mandatory = $true)]
        $customer
    )
    $defaultresourcegroup = ($dashboard.widgetTokens | Where { $_.name -eq "defaultResourceGroup" })
    if ($defaultresourcegroup) {
        $defaultresourcegroupValue = $defaultresourcegroup.value
        $newResourceGroup = "Devices by Organization/$customer/$($defaultResourceGroupValue.replace('Devices By Category', 'Categories'))"
        ($dashboard.widgetTokens | Where { $_.name -eq "defaultResourceGroup" }).value = $newResourceGroup
    }
   

    $body = @{
        name         = $dashboard.name
        description  = $dashboard.description
        sharable     = $true
        groupId      = $groupId
        widgetTokens = $dashboard.widgetTokens
        widgetsConfig = $dashboard.widgetsConfig
    }
    $oldDashboard = $dashboards | Where { $_.name -eq $dashboard.name -and $_.groupId -eq $groupId }
    if ($oldDashboard) {
        Send-Request -path "/dashboard/dashboards/$($oldDashboard.id)" -httpVerb 'DELETE' | Out-Null
        $newDashboard = Send-Request -path "/dashboard/dashboards/$($dashboard.id)/clone" -httpVerb 'POST' -data $body
        $status = "updated"
    }
    else {
        $newDashboard = Send-Request -path "/dashboard/dashboards/$($dashboard.id)/clone" -httpVerb 'POST' -data $body
        $status = "created"
    }
    if ($newDashboard) {
        Write-Host "Dashboard: $($dashboard.name) has been $status for Customer $customer"
    }
    else {
        Write-Host "ERROR: Something went wrong when attempting update/create $($dashboard.name) for Customer $customer"
    }

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

$data = Import-Csv $csvfile

$groups = Iterate -Path '/device/groups'
$rootId = (checkIfExists -groups $groups -groupFullPath 'Devices by Organization' -name 'Devices by Organization' -properties @{parentId = 1 }).id
$DBCgroups = $groups | Where { $_.fullPath -like "$desiredCloneGroup/*" }
$DBCSorted = getSortedGroups $DBCgroups

$websitegroups = Iterate -Path '/website/groups'
$websitesRootId = (checkIfExists -groups $websitegroups -groupFullPath 'Websites by Organization' -name 'Websites by Organization' -type "websitegroup" -properties @{parentId = 1 }).id
$websitesSubgroups = @("Applications", "Circuits")

$dashboardgroups = Iterate -Path '/dashboard/groups'
$dashboardRootId = (checkIfExists -groups $dashboardgroups -groupfullPath 'Dashboards by Organization' -name 'Dashboards by Organization' -type 'dashboardgroup' -properties @{parentId = 1 }).id
$dashboardsByCategoryId = (checkIfExists -groups $dashboardGroups -groupFullPath "Dashboards By Category" -name "Dashboards By Category" -type "dashboardgroup" -properties @{parentId = 1 }).id
$dashboards = Iterate -Path "/dashboard/dashboards"
$dashboardsByCategoryDashboards = $dashboards | Where { $_.groupId -eq $dashboardsByCategoryId }

$reportgroups = Iterate -Path '/report/groups'

$topologygroups = Iterate -Path '/topology/groups'

$collectorGroups = Iterate -Path "/setting/collector/groups"

$roles = Iterate -Path '/setting/roles'
$rolegroups = Iterate -Path "/setting/role/groups"
$RoleGroupId = (checkIfExists -groups $rolegroups -name "Clients" -type "rolegroup").id

foreach ($line in $data) {
    
    $customer = $line.'companyName'
    $companyID = $line.'companyID'
    $locations = $line.'companyLocations'.split(";")

    Write-Host "------------------------------------"
    Write-Host "Working on Automation for $customer"
    Write-Host "Company ID for $customer is $companyId"
    Write-Host "------------------------------------"
    
    #DO DEVICE GROUP PORTION
    $properties = @{
        parentId         = $rootId
        customProperties = @(
            @{
                name  = "company.id"
                value = $companyID
            }
        )
    }
    $grouproot = "Devices by Organization/$($customer)"
    $customerFolder = checkIfExists -groups $groups -groupFullPath $grouproot -name $customer -properties $properties
    $customerId = $customerFolder.id
    $grouproot = $customerFolder.fullPath
    $customer = $customerFolder.name
    if (!$customer) {
        Write-Host "Failed to get customer name!!! stopping everything :O"
        return
    }
    $LocationsId = (checkIfExists -groups $groups -groupFullPath "$($grouproot)/Locations" -name "Locations" -properties @{parentId = $customerId }).id

    foreach ($location in $locations) {
        checkIfExists -groups $groups -groupFullPath "$($grouproot)/Locations/$($location)" -name $location -properties @{parentId = $LocationsId } | Out-Null
    }
    
    checkIfExists -groups $groups -groupFullPath "$($grouproot)/Portals" -name "Portals" -properties @{parentId = $customerId } | Out-Null

    $DBCId = (checkIfExists -groups $groups -groupFullPath "$($grouproot)/$desiredCloneGroup" -name "$desiredCloneGroup" -properties @{parentId = $customerId }).id
    createSortedGroups $groups $DBCSorted "$($grouproot)" $DBCId " && auto.company.id == `"$companyID`"" | Out-Null

    #DO WEBSITE GROUP PORTION
    $websiteProperties = @{
        parentId   = $websitesRootId
        properties = @(
            @{
                name  = "company.id"
                value = $companyID
            }
        )
    }
    $websitesGroupRoot = "Websites by Organization/$($customer)"
    $website = checkIfExists -groups $websitegroups -groupFullPath $websitesGroupRoot -name $customer -type "websitegroup" -properties $websiteProperties
    $websiteId = $website.id
    $websitesGroupRoot = $website.fullPath
    foreach ($websitegroup in $websitesSubgroups) {
        checkIfExists -groups $websitegroups -groupFullPath "$websitesGroupRoot/$websitegroup" -name $websitegroup -type "websitegroup" -properties @{parentId = $websiteId } | Out-Null
    }

    #DO DASHBOARD GROUP PORTION
    $dashboardProperties = @{
        parentId     = $dashboardRootId
        widgetTokens = @(
            @{
                name  = "company.id"
                value = $companyID
            }
        )
    }

    $dashboardGroupRoot = "Dashboards by Organization/$customer"
    $dashboardId = (checkIfExists -Groups $dashboardgroups -groupFullPath $dashboardGroupRoot -name $customer -type "dashboardgroup" -properties $dashboardProperties).id
    $dashboardCategoriesId = (checkIfExists -groups $dashboardgroups -groupFullPath "$dashboardGroupRoot/Categories" -name "Categories" -type "dashboardgroup" -properties @{parentId = $dashboardId }).id

    foreach ($dashboard in $dashboardsByCategoryDashboards) {
        createOrUpdateDashboard -dashboard $dashboard -dashboards $dashboards -groupId $dashboardCategoriesId -customer $customer
    }
    #DO REPORT GROUP PORTION
    $reportId = (checkIfExists -groups $reportgroups -name $customer -type "reportgroup").id

    #DO TOPOLOGY GROUP PORTION
    $topologyId = (checkIfExists -groups $topologygroups -name $customer -type "topologygroup").id
    
    $collectorProperties = @{
        autoBalanced     = $true
        customProperties = @(
            @{
                name  = "company.id"
                value = $companyID
            }
        )
    }
    #DO COLLECTOR GROUP PORTION
    checkIfExists -groups $collectorGroups -name $customer -type "collectorgroup" -properties $collectorProperties | Out-Null
    
    #DO ROLE PORTION
    $roleBody = @{
        name             = "Client - $customer"
        requireEULA      = $false
        twoFARequired    = $true
        acctRequireTwoFA = $false
        roleGroupId      = $RoleGroupId
        privileges       = @(
            @{
                objectType   = "dashboard_group"
                objectId     = $dashboardRootId
                objectName   = "Dashboards by Organization"
                operation    = "none"
                subOperation = "read"
            }
            @{
                objectType   = "deviceDashboard"
                objectId     = ""
                objectName   = "deviceDashboard"
                operation    = "read"
                subOperation = ""
            }
            @{
                objectType   = "website_group"
                objectId     = $websitesRootId
                objectName   = "Websites by Organization"
                operation    = "none"
                subOperation = "read"
            }
            @{
                objectType   = "report_group"
                objectId     = $reportId
                objectName   = $customer
                operation    = "read"
                subOperation = ""
            }
            @{
                objectType   = "configNeedDeviceManagePermission"
                objectId     = ""
                objectName   = "configNeedDeviceManagePermission"
                operation    = "write"
                subOperation = ""
            }
            @{
                objectType   = "website_group"
                objectId     = $websiteId
                objectName   = $customer
                operation    = "read"
                subOperation = ""
            }
            @{
                objectType   = "host_group"
                objectId     = $rootId
                objectName   = "Devices by Organization"
                operation    = "none"
                subOperation = "read"
            }
            @{
                objectType   = "dashboard_group"
                objectId     = $dashboardId
                objectName   = $customer
                operation    = "read"
                subOperation = ""
            }
            @{
                objectType   = "map"
                objectId     = $topologyId
                objectName   = $customer
                operation    = "read"
                subOperation = ""
            }
            @{
                objectType   = "help"
                objectId     = "document"
                objectName   = "help"
                operation    = "read"
                subOperation = ""
            }
            @{
                objectType   = "host_group"
                objectId     = $customerId
                objectName   = $customer
                operation    = "read"
                subOperation = ""
            }
            @{
                objectType   = "help"
                objectId     = "chat"
                objectName   = "help"
                operation    = "read"
                subOperation = ""
            }
        )
    }
    $customerRole = $roles | Where { $_.name -match "Client - $customer" }
    if (!$customerRole) {
        Send-Request -Path '/setting/roles' -httpVerb 'POST' -data $roleBody | Out-Null
        Write-host "Created role for $customer"
    }
    else {
        write-host "Role for $customer already exists."
    }

}

# # Functionize the reusable code that builds and executes the query
# function Send-Request() {
#     Param(
#         [Parameter(position = 0, Mandatory = $true)]
#         [string]$path,
#         [Parameter(position = 1, Mandatory = $false)]
#         [string]$httpVerb = 'GET',
#         [Parameter(position = 2, Mandatory = $false)]
#         [string]$queryParams,
#         [Parameter(position = 3, Mandatory = $false)]
#         $data = $null,
#         [Parameter(position = 4, Mandatory = $false)]
#         $version = 3

#     )

#     if ($data -and $data -isnot [string]) { $data = $data | ConvertTo-Json -Depth 50 }

#     # Use TLS 1.2
#     [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#     <# Construct URL #>
#     $url = "https://$company.logicmonitor.com/santaba/rest$path$queryParams"
    
#     <# Get current time in milliseconds #>
#     $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)

#     <# Concatenate Request Details #>
#     $requestVars = $httpVerb + $epoch + $data + $path

#     <# Construct Signature #>
#     $hmac = New-Object System.Security.Cryptography.HMACSHA256
#     $hmac.Key = [Text.Encoding]::UTF8.GetBytes($accessKey)
#     $signatureBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestVars))
#     $signatureHex = [System.BitConverter]::ToString($signatureBytes) -replace '-'
#     $signature = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($signatureHex.ToLower()))

#     <# Construct Headers #>
#     $auth = 'LMv1 ' + $accessId + ':' + $signature + ':' + $epoch
#     $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
#     $headers.Add("Authorization", $auth)
#     $headers.Add("Content-Type", 'application/json')
#     $headers.Add("X-version", $version)

#     <# Make request & retry if failed due to rate limiting #>
#     $Stoploop = $false
#     do {
#         try {
#             <# Make Request #>
#             $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Body $data -Header $headers
#             $Stoploop = $true
#         }
#         catch {
#             switch ($_) {
#                 { $_.Exception.Response.StatusCode.value__ -eq 429 } {
#                     Write-Host "Request exceeded rate limit, retrying in 60 seconds..."
#                     Start-Sleep -Seconds 60
#                     $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Body $data -Header $headers
#                 }
#                 default {
#                     write-host $_
#                     $Stoploop = $true
#                 }
#             }
#         }
#     } While ($Stoploop -eq $false)
#     Return $response
# }

# function getResourcePath($type) {
#     if ($type -eq "devicegroup") {
#         $resourcePath = "/device/groups"
#     }
#     elseif ($type -eq "websitegroup") {
#         $resourcePath = "/website/groups"
#     }
#     elseif ($type -eq "reportgroup") {
#         $resourcePath = "/report/groups"
#     }
#     elseif ($type -eq "topologygroup") {
#         $resourcePath = "/topology/groups"
#     }
#     elseif ($type -eq 'dashboardgroup') {
#         $resourcePath = "/dashboard/groups"
#     }
#     elseif ($type -eq "collectorgroup") {
#         $resourcePath = "/setting/collector/groups"
#     }
#     elseif ($type -eq "rolegroup") {
#         $resourcePath = "/setting/role/groups"
#     }
#     if ($resourcePath) {
#         return $resourcePath
#     }
#     else {
#         return $null
#     }
# }

# function createGroup($name, $type, $properties) {

#     $data = @{}
#     $resourcePath = getResourcePath $type
#     foreach ($key in $properties.Keys) {
#         $data.$key = $properties[$key]
#     }

#     $data.name = $name
#     $queryParams = ""
#     $httpVerb = 'POST'

#     $response = Send-Request $resourcePath $httpVerb $queryParams $data
#     return $response
# }

# function updateGroup($group, $type, $properties) {
#     $data = @{}
#     $resourcePath = getResourcePath $type
#     $resourcePath = $resourcePath + "/$($group.id)"
#     foreach ($key in $properties.Keys) {
#         $data.$key = $properties[$key]
#     }

#     $queryParams = ''
#     $httpVerb = 'PATCH'

#     $response = Send-Request $resourcePath $httpVerb $queryParams $data
# }

# function checkIfExists() {
#     Param(
#         [Parameter(position = 0, Mandatory = $true)]
#         [PSObject]$groups,
#         [Parameter(position = 1, Mandatory = $false)]
#         [string]$groupFullPath,
#         [Parameter(position = 2, Mandatory = $true)]
#         [string]$name,
#         [Parameter(position = 3, Mandatory = $false)]
#         [string]$type = "devicegroup",
#         [Parameter(position = 4, Mandatory = $false)]
#         $properties = @{}
#     )

#     $listOfExistingIds = ($groups.customProperties | WHere { $_.name -eq "company.id" }).value
#     if (!$listOfExistingIds) {
#         $listOfExistingIds = ($groups.properties | Where { $_.name -eq "company.id" }).value
#     }
#     if (!$listOfExistingIds) {
#         $listOfExistingIds = ($groups.widgetTokens | Where { $_.name -eq "company.id" }).value
#     }
#     $companyId = ($properties.customProperties | Where { $_.name -eq "company.id" }).value
#     if (!$companyId) {
#         $companyId = ($properties.properties | Where { $_.name -eq "company.id" }).value
#     }
#     if (!$companyId) {
#         $companyId = ($properties.widgetTokens | Where { $_.name -eq "company.id" -and $_.type -eq "owned" }).id
#     }

#     if ($companyId -and $listOfExistingIds -contains $companyId) {
#         $group = $groups | where { $_.customProperties.value -contains $companyId -or $_.properties.value -contains $companyId -or $_.widgetTokens.value -contains $companyId }
#         Write-host "$($type): $name already exists with companyId: $companyId"
#     }
#     else {
#         if (($type -eq "devicegroup" -or $type -eq "websitegroup" -or $type -eq "dashboardgroup") -and $groups.fullPath -contains $groupFullPath) {
#             #if (($type -eq "devicegroup" -or $type -eq "websitegroup" -or $type -eq "dashboardgroup") -and ($listOfExistingIds -contains $companyId -or $groups.fullPath -contains $groupFullPath)) {
#             Write-host "$($type): $name already exists"
#             $group = $groups | where { $_.fullPath -eq $groupFullPath }

#             $propertiesMatch = checkIfPropertiesMatch $group $properties
#             if (!$propertiesMatch) {
#                 write-host "Updating $($type): $name due to mismatched properties"
#                 updateGroup $group $type $properties
#             }
#         }
#         elseif (($type -eq "reportgroup" -or $type -eq "topologygroup" -or $type -eq "collectorgroup" -or $type -eq "rolegroup") -and $groups.name -contains $name ) {

#             Write-host "$($type): $name already exists"
#             $group = $groups | where { $_.name -eq $name }

#             $propertiesMatch = checkIfPropertiesMatch $group $properties
#             if (!$propertiesMatch) {
#                 write-host "Updating $($type): $name due to mismatched properties"
#                 updateGroup $group $type $properties
#             }
#         }
#         else {

#             $group = createGroup $name $type $properties

#             if ($group) {
#                 Write-Host "$($type): $name has been created"
#             }
#             else {
#                 Write-Host "Oh No! $($type): $name failed to be created."
#             }

#         }
#     }
#     return $group

# }

# function checkIfPropertiesMatch($group, $properties) {
#     $returnValue = $false
#     if ($properties.Count -gt 0) {
#         foreach ($key in $properties.Keys) {
#             $value = $properties.$key
#             $groupvalue = $group.$key
#             if (!$groupvalue) {
#                 return $false
#             }
#             foreach ($item in $value) {
#                 if ($item.Keys) {
#                     foreach ($k in $item.Keys) {
#                         $v = $item.$k
#                         if ($groupvalue.$k -match $v -or $groupvalue.$k -contains $v) {
#                             $returnValue = $true
#                         }
#                         else {
#                             return $false
#                         }
#                     }
#                 }
#                 else {
#                     if ($groupvalue -match $item -or $groupvalue -contains $item) {
#                         $returnValue = $true
#                     }
#                     else {
#                         return $false
#                     }
#                 }
#             }
#         }
#         return $returnValue
#     }
#     else {
#         return $true
#     }
# }

# function getSortedGroups($groups) {
#     $groupsObject = @{}
#     $lengthList = @()
#     $groups.fullPath | % {
#         $lengthlist += ($_.split('/').Length - 1)
#     }
#     $maxdepth = ($lengthlist | Measure-Object -Maximum).Maximum
#     for ($i = 1; $i -le $maxdepth; $i ++) {
#         New-Variable -Name "var$i" -Value @()
#     }
#     foreach ($group in $groups) {
#         $fullPathArray = $group.fullPath.split('/')
#         $depth = ($fullPathArray.count - 1)
#         (Get-Variable -Name "var$depth").Value += $group
#     }
#     for ($i = 1; $i -le $maxdepth; $i ++) {
#         $groupsObject["$i"] = (Get-Variable -Name "var$i").Value
#     }
#     return $groupsObject
# } 

# function createSortedGroups($groups, $sortedgroups, $parentFolderPath, $parentId, $additionalAppliesTo) {
#     foreach ($item in $sortedgroups.getEnumerator() | Sort-Object -Property Name) {
#         $depth = $item.name
#         $newgroups = $item.value
#         foreach ($group in $newgroups) {
#             if ($depth -eq "1") {
#                 $properties = @{
#                     parentId = $parentId
#                 }
#                 if ($group.appliesTo) {
#                     $properties.appliesTo = ($group.appliesTo + $additionalAppliesTo)
#                 }
#                 $createdgroupID = (checkIfExists -groups $groups -groupFullPath ($parentFolderPath + "/" + $group.fullPath) -name $group.name -type "devicegroup" -properties $properties).id
#                 New-Variable -Name "$($group.fullPath)" -Value $createdGroupID
#             }
#             else {
#                 $newparentId = (Get-Variable -Name $($group.fullPath.split('/')[0..($depth - 1)] -join ('/'))).Value
#                 $properties = @{
#                     parentId = $newparentId
#                 }
#                 if ($group.appliesTo) {
#                     $properties.appliesTo = ($group.appliesTo + $additionalAppliesTo)
#                 }
#                 $createdGroupID = (checkIfExists -groups $groups -groupFullPath ($parentFolderPath + "/" + $group.fullPath) -name $group.name -type "devicegroup" -properties $properties).id
#                 New-Variable -Name "$($group.fullPath)" -Value $createdGroupID
#             }
#         }
#     }
# }

# function createOrUpdateDashboard() {
#     param(
#         [Parameter(position = 0, Mandatory = $true)]
#         $dashboard,
#         [Parameter(position = 1, Mandatory = $true)]
#         $dashboards,
#         [Parameter(position = 2, Mandatory = $true)]
#         $groupId,
#         [Parameter(position = 3, Mandatory = $true)]
#         $customer
#     )
#     $template = Send-Request -path "/dashboard/dashboards/$($dashboard.id)" -queryParams '?template=true&format=json'
#     $defaultResourceGroup = ($template.widgetTokens | Where { $_.name -eq "defaultResourceGroup" }).value

#     if ($defaultResourceGroup) {
#         $newResourceGroup = "Devices by Organization/$customer/$($defaultResourceGroup.replace('Devices By Category', 'Categories'))"
#         ($template.widgetTokens | Where { $_.name -eq "defaultResourceGroup" }).value = $newResourceGroup
#     }

#     $body = @{
#         name         = $dashboard.name
#         template     = $template
#         description  = $dashboard.description
#         sharable     = $true
#         groupId      = $groupId
#         widgetTokens = $template.widgetTokens
#     }
#     $oldDashboard = $dashboards | Where { $_.name -eq $dashboard.name -and $_.groupId -eq $groupId }
#     if ($oldDashboard) {
#         Send-Request -path "/dashboard/dashboards/$($oldDashboard.id)" -httpVerb 'DELETE' | Out-Null
#         $newDashboard = Send-Request -path "/dashboard/dashboards" -httpVerb 'POST' -data $body
#         $status = "updated"
#     }
#     else {
#         $newDashboard = Send-Request -path "/dashboard/dashboards" -httpVerb 'POST' -data $body
#         $status = "created"
#     }
#     if ($newDashboard) {
#         Write-Host "Dashboard: $($dashboard.name) has been $status for Customer $customer"
#     }
#     else {
#         Write-Host "ERROR: Something went wrong when attempting update/create $($dashboard.name) for Customer $customer"
#     }

# }
# function Iterate() {
#     Param(
#         [Parameter(position = 0, Mandatory = $true)]
#         [string]$Path
#     )
#     $response = @()
#     $remaining = $true
#     $offset = 0
#     $size = 1000
#     while ($remaining) {
#         $result = (Send-Request -Path $path -httpverb 'GET' -queryParams "?size=$size&offset=$offset").items
#         $response += $result
#         if ($result.Count -lt $size) {
#             $remaining = $false
#         }
#         else {
#             $offset += $size
#         }
#     }
#     return $response
# }

# $data = Import-Csv $csvfile

# $groups = Iterate -Path '/device/groups'
# $rootId = (checkIfExists -groups $groups -groupFullPath 'Devices by Organization' -name 'Devices by Organization' -properties @{parentId = 1 }).id
# $DBCgroups = $groups | Where { $_.fullPath -like "$desiredCloneGroup/*" }
# $DBCSorted = getSortedGroups $DBCgroups

# $websitegroups = Iterate -Path '/website/groups'
# $websitesRootId = (checkIfExists -groups $websitegroups -groupFullPath 'Websites by Organization' -name 'Websites by Organization' -type "websitegroup" -properties @{parentId = 1 }).id
# $websitesSubgroups = @("Applications", "Circuits")

# $dashboardgroups = Iterate -Path '/dashboard/groups'
# $dashboardRootId = (checkIfExists -groups $dashboardgroups -groupfullPath 'Dashboards by Organization' -name 'Dashboards by Organization' -type 'dashboardgroup' -properties @{parentId = 1 }).id
# $dashboardsByCategoryId = (checkIfExists -groups $dashboardGroups -groupFullPath "Dashboards By Category" -name "Dashboards By Category" -type "dashboardgroup" -properties @{parentId = 1 }).id
# $dashboards = Iterate -Path "/dashboard/dashboards"
# $dashboardsByCategoryDashboards = $dashboards | Where { $_.groupId -eq $dashboardsByCategoryId }

# $reportgroups = Iterate -Path '/report/groups'

# $topologygroups = Iterate -Path '/topology/groups'

# $collectorGroups = Iterate -Path "/setting/collector/groups"

# $roles = Iterate -Path '/setting/roles'
# $rolegroups = Iterate -Path "/setting/role/groups"
# $RoleGroupId = (checkIfExists -groups $rolegroups -name "Clients" -type "rolegroup").id

# foreach ($line in $data) {
    
#     $customer = $line.companyName
#     $companyID = $line.companyID
#     if ($line.companyLocations -ne $null) {
#         $locations = $line.companyLocations.split(";")
#     }else{
#         $locations = ""
#     }

#     Write-Host "------------------------------------"
#     Write-Host "Working on Automation for $customer"
#     Write-Host "Company ID for $customer is $companyId"
#     Write-Host "------------------------------------"
    
#     #DO DEVICE GROUP PORTION
#     $properties = @{
#         parentId         = $rootId
#         customProperties = @(
#             @{
#                 name  = "company.id"
#                 value = $companyID
#             }
#         )
#     }
#     $grouproot = "Devices by Organization/$($customer)"
#     $customerFolder = checkIfExists -groups $groups -groupFullPath $grouproot -name $customer -properties $properties
#     $customerId = $customerFolder.id
#     $grouproot = $customerFolder.fullPath
#     $customer = $customerFolder.name

#     $LocationsId = (checkIfExists -groups $groups -groupFullPath "$($grouproot)/Locations" -name "Locations" -properties @{parentId = $customerId }).id
    
#     if ($locations){
#         foreach ($location in $locations) {
#             checkIfExists -groups $groups -groupFullPath "$($grouproot)/Locations/$($location)" -name $location -properties @{parentId = $LocationsId } | Out-Null
#         }
#     }
    
#     checkIfExists -groups $groups -groupFullPath "$($grouproot)/Portals" -name "Portals" -properties @{parentId = $customerId } | Out-Null

#     $DBCId = (checkIfExists -groups $groups -groupFullPath "$($grouproot)/$desiredCloneGroup" -name "$desiredCloneGroup" -properties @{parentId = $customerId }).id
#     createSortedGroups $groups $DBCSorted "$($grouproot)" $DBCId " && auto.company.id == `"$companyID`"" | Out-Null

#     #DO WEBSITE GROUP PORTION
#     $websiteProperties = @{
#         parentId   = $websitesRootId
#         properties = @(
#             @{
#                 name  = "company.id"
#                 value = $companyID
#             }
#         )
#     }
#     $websitesGroupRoot = "Websites by Organization/$($customer)"
#     $website = checkIfExists -groups $websitegroups -groupFullPath $websitesGroupRoot -name $customer -type "websitegroup" -properties $websiteProperties
#     $websiteId = $website.id
#     $websitesGroupRoot = $website.fullPath
#     foreach ($websitegroup in $websitesSubgroups) {
#         checkIfExists -groups $websitegroups -groupFullPath "$websitesGroupRoot/$websitegroup" -name $websitegroup -type "websitegroup" -properties @{parentId = $websiteId } | Out-Null
#     }

#     #DO DASHBOARD GROUP PORTION
#     $dashboardProperties = @{
#         parentId     = $dashboardRootId
#         widgetTokens = @(
#             @{
#                 name  = "company.id"
#                 value = $companyID
#             }
#         )
#     }

#     $dashboardGroupRoot = "Dashboards by Organization/$customer"
#     $dashboardId = (checkIfExists -Groups $dashboardgroups -groupFullPath $dashboardGroupRoot -name $customer -type "dashboardgroup" -properties $dashboardProperties).id
#     $dashboardCategoriesId = (checkIfExists -groups $dashboardgroups -groupFullPath "$dashboardGroupRoot/Categories" -name "Categories" -type "dashboardgroup" -properties @{parentId = $dashboardId }).id

#     # foreach ($dashboard in $dashboardsByCategoryDashboards) {
#     #     createOrUpdateDashboard -dashboard $dashboard -dashboards $dashboards -groupId $dashboardCategoriesId -customer $customer
#     # }
#     #DO REPORT GROUP PORTION
#     $reportId = (checkIfExists -groups $reportgroups -name $customer -type "reportgroup").id

#     #DO TOPOLOGY GROUP PORTION
#     $topologyId = (checkIfExists -groups $topologygroups -name $customer -type "topologygroup").id
    
#     $collectorProperties = @{
#         autoBalance     = $true
#         customProperties = @(
#             @{
#                 name  = "company.id"
#                 value = $companyID
#             }
#         )
#     }
#     #DO COLLECTOR GROUP PORTION
#     checkIfExists -groups $collectorGroups -name $customer -type "collectorgroup" -properties $collectorProperties | Out-Null
    
#     #DO ROLE PORTION
#     $roleBody = @{
#         name             = "Client - $customer"
#         requireEULA      = $false
#         twoFARequired    = $true
#         acctRequireTwoFA = $false
#         roleGroupId      = $RoleGroupId
#         privileges       = @(
#             @{
#                 objectType   = "dashboard_group"
#                 objectId     = $dashboardRootId
#                 objectName   = "Dashboards by Organization"
#                 operation    = "none"
#                 subOperation = "read"
#             }
#             @{
#                 objectType   = "deviceDashboard"
#                 objectId     = ""
#                 objectName   = "deviceDashboard"
#                 operation    = "read"
#                 subOperation = ""
#             }
#             @{
#                 objectType   = "website_group"
#                 objectId     = $websitesRootId
#                 objectName   = "Websites by Organization"
#                 operation    = "none"
#                 subOperation = "read"
#             }
#             @{
#                 objectType   = "report_group"
#                 objectId     = $reportId
#                 objectName   = $customer
#                 operation    = "read"
#                 subOperation = ""
#             }
#             @{
#                 objectType   = "configNeedDeviceManagePermission"
#                 objectId     = ""
#                 objectName   = "configNeedDeviceManagePermission"
#                 operation    = "write"
#                 subOperation = ""
#             }
#             @{
#                 objectType   = "website_group"
#                 objectId     = $websiteId
#                 objectName   = $customer
#                 operation    = "read"
#                 subOperation = ""
#             }
#             @{
#                 objectType   = "host_group"
#                 objectId     = $rootId
#                 objectName   = "Devices by Organization"
#                 operation    = "none"
#                 subOperation = "read"
#             }
#             @{
#                 objectType   = "dashboard_group"
#                 objectId     = $dashboardId
#                 objectName   = $customer
#                 operation    = "read"
#                 subOperation = ""
#             }
#             @{
#                 objectType   = "map"
#                 objectId     = $topologyId
#                 objectName   = $customer
#                 operation    = "read"
#                 subOperation = ""
#             }
#             @{
#                 objectType   = "help"
#                 objectId     = "document"
#                 objectName   = "help"
#                 operation    = "read"
#                 subOperation = ""
#             }
#             @{
#                 objectType   = "host_group"
#                 objectId     = $customerId
#                 objectName   = $customer
#                 operation    = "read"
#                 subOperation = ""
#             }
#             @{
#                 objectType   = "help"
#                 objectId     = "chat"
#                 objectName   = "help"
#                 operation    = "read"
#                 subOperation = ""
#             }
#         )
#     }
#     $customerRole = $roles | Where { $_.name -match "Client - $customer" }
#     if (!$customerRole) {
#         Send-Request -Path '/setting/roles' -httpVerb 'POST' -data $roleBody | Out-Null
#         Write-host "Created role for $customer"
#     }
#     else {
#         write-host "Role for $customer already exists."
#     }

# }
