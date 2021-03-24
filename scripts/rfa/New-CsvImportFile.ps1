#Requires -Modules PsGuiTools, PsCwAutomateDB

$CompanyRecords = @()

# Get data from DB
$Companies = Invoke-RfaLtSqlCommand "Select Company,ExternalID FROM clients" |
    Where-Object {$_.Company} | Sort-Object Company

# Loop until cancel
$strCompany = 'not null'
for ($i=1; $strCompany; $i++) {

    # Prompt for list of companies
    $strCompany = $Companies.Company |
        Show-GuiSelectItemFromList -Title 'Select a company (cancel to exit loop)'

    if ($strCompany) {

        # Filter by chosen item
        $thisCompany = $Companies |
            Where-Object {$_.Company -eq $strCompany}

        # Get Locations (Not New Computers)
        $Locations = Invoke-RfaLtSqlCommand "SELECT Name FROM locations WHERE clientid = (
            SELECT clientid FROM clients WHERE ExternalID=$($thisCompany.ExternalID)
        ) AND Name != 'New Computers'" | Select-Object -ExpandProperty Name
        
        # Add to array
        $CompanyRecords += [PSCustomObject]@{
            companyID = $thisCompany.ExternalID
            companyName = $thisCompany.Company
            companyLocations = ($Locations -join ';')
        }
    }

}

# Export array as file
$InitialDirectory = Join-Path $env:USERPROFILE 'Downloads'
$Save = 'Save file as...'
$Path = Show-GuiFilePicker -InitialDirectory $InitialDirectory -Extension 'csv' -Single -OutString -Title $Save
$CompanyRecords | Export-Csv $Path -NoTypeInfo
Get-Item $Path
