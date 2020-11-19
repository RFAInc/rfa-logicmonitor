(new-object Net.WebClient).DownloadString('https://raw.githubusercontent.com/RFAInc/rfa-backups/main/general-functions.ps1') | Invoke-Expression
function Get-ClientCredentials {
    [CmdletBinding()]
    param (    
        [Parameter(Mandatory=$true)]
        [string]$User,        
        [Parameter(Mandatory=$true)]
        [string]$Pass
    )
    $ClientIDQuery = '
        SELECT clientid 
        FROM clients
        WHERE externalid != 0'
    $ClientIDs = (Invoke-MySqlMethod -Server "RFALABTECHDB" -User $User -Pass $Pass -DataBase "labtech" -Query $ClientIDQuery).clientid
    $Credentials = New-Object -TypeName System.Collections.ArrayList
    foreach ($i in $ClientIDs){
        $ClientID = $i
        $Key = $ClientID + 1
        $CredsQuery = '
            SELECT cli.name AS ClientName, cli.externalid AS ExternalId, pwd.Username, CONVERT(AES_DECRYPT(pwd.PASSWORD,SHA(" ' + $Key + '")) USING utf8) AS Password
            FROM Passwords AS pwd
            LEFT JOIN clients AS cli ON cli.clientid = pwd.clientid
            WHERE pwd.clientid = ' + $ClientID
        $result = Invoke-MySqlMethod -Server "RFALABTECHDB" -User $User -Pass $Pass -DataBase "labtech" -Query $CredsQuery
        if ($result.Password -ne $null){   
            $result | ForEach-Object{
                $null = ($Credentials).Add($_)
            }
        }
    }
    Write-Output $Credentials
}