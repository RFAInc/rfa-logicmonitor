function New-RFALogicMonitorSDT {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$jobRunnerUri,
        [Parameter(Mandatory=$true)]
        [string]$companyID,
        [Parameter(Mandatory=$true)]
        [string]$deviceHostName,
        [Parameter(Mandatory=$false)]
        [string]$deviceIPAddress,
        [Parameter(Mandatory=$false)]
        [string]$deviceMacAddress,
        [Parameter(Mandatory=$false)]
        [string]$deviceSerialNumber,
        [Parameter(Mandatory=$true)]
        [string]$sdtStartTime,
        [Parameter(Mandatory=$true)]
        [string]$sdtEndTime,
        [Parameter(Mandatory=$false)]
        [string]$sdtNote
    )
    # TODO: add conditional to check if date is in epoch time before converting. catch exceptions when attempting to convert
    $sdtStartTime = (New-TimeSpan -Start (Get-Date "01/01/1970") -End (Get-Date $sdtStartTime)).TotalMilliseconds
    $sdtEndTime = (New-TimeSpan -Start (Get-Date "01/01/1970") -End (Get-Date $sdtEndTime)).TotalMilliseconds
    $body = @{
        deviceSysName = $deviceHostName 
        companyID = $companyID
        sdtStartTime = $sdtStartTime
        sdtEndTime = $sdtEndTime
        sdtNote = $sdtNote
        deviceMacAddress = $deviceMacAddress
        deviceSerialNumber = $deviceSerialNumber
        deviceLocalIPAddress = $deviceIPAddress
    } | ConvertTo-Json
    $Result = Invoke-WebRequest -Uri $jobRunnerUri -Method "POST" -Body $body -ContentType 'application/json'
    Write-Output $Result
}
