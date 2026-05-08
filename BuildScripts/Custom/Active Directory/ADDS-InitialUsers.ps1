<#
     _   _                              _____
    | | | |                     ___    |  __ \
    | | | |___  ___ _ __ ___   ( _ )   | |  \/_ __ ___  _   _ _ __  ___ 
    | | | / __|/ _ \ '__/ __|  / _ \/\ | | __| '__/ _ \| | | | '_ \/ __|
    | |_| \__ \  __/ |  \__ \ | (_>  < | |_\ \ | | (_) | |_| | |_) \__ \
     \___/|___/\___|_|  |___/  \___/\/  \____/_|  \___/ \__,_| .__/|___/
                                                             | |
                                                             |_|
#>

# Path to PVE scripts and Functions.
# ------------------------------------------------------------
if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $RootPath = $PSScriptRoot
} else {
    $RootPath  = "C:\Scripts"
}


# Deployment server Name and Address
# ------------------------------------------------------------
if (-NOT (Test-Path -Path "$RootPath\DeploymentServer.json")) {
    Write-Warning "Missing Deployment server connection information"
    Start-Sleep -Seconds 600
}

$Deployment = Get-Content -Path "$RootPath\DeploymentServer.json" | Convertfrom-Json
try {
    Resolve-DnsName $Deployment.ServerName -QuickTimeout -ErrorAction Stop | Out-Null
    $DeploymentServer = $Deployment.ServerName
}
catch {
    $DeploymentServer = $Deployment.IpAddress
}


if (-not (Test-NetConnection $DeploymentServer -CommonTCPPort HTTP -InformationLevel Quiet)) {
    throw "Unable to connect to Deployment Website"
} else {
    $RepoUrl  = "http://$DeploymentServer/$($Deployment.VirtualPath)"
}


# Import TS Tiering Module
# ------------------------------------------------------------
Import-Module (Get-ChildItem -Path $RootPath -Recurse -Filter "TSxTieringModule.psm1").FullName -Verbose -Force


If (-NOT (Get-Command -Name New-TSxAdminAccount)) {
    Throw "TSx modules not found"
}


# Create Users.
# --------------------------------------------------------------------------------------------------
#$UserList = @(
#    [PSCustomObject]@{ FirstName = "Jan";              LastName = "Kristensen"; Type = "FTE"; Access = @("T0","T1","T2","Te") }
#    [PSCustomObject]@{ FirstName = "Homer";            LastName = "Simpson";    Type = "EXT"; Access = @("T1L","T2L")         }
#    [PSCustomObject]@{ FirstName = "Marjorie Bouvier"; LastName = "Simpson";    Type = "EXT"; Access = @("T1L","T2L")         }
#)
#$UserList | ConvertTo-Json

Invoke-WebRequest -Uri "$RepoUrl/ConfigFiles/Initial-Users.json" -UseBasicParsing -OutFile "$($ENV:TEMP)\Initial-Users.json"
$UserList = Get-Content -Path "$($ENV:TEMP)\Initial-Users.json" | ConvertFrom-Json

$CreatedUsers = @()
ForEach ($User in $UserList) {

    $User.Access | ForEach-Object {
        if ($_ -eq "TE") { $Silo = $false } else { $Silo = $true }
        $CreatedUsers += New-TSxAdminAccount -FirstName $User.FirstName -LastName $User.LastName -AccountType $($_) -AddToSilo $Silo -ErrorAction SilentlyContinue
    }
    if ($User.type -eq "EXT") {
        $CreatedUsers += New-TSxAdminAccount -FirstName $User.FirstName -LastName $User.LastName -AccountType CON -AddToSilo $false
    }
}


# Create Groups.
# --------------------------------------------------------------------------------------------------
#$GroupList = @(
#    [PSCustomObject]@{ Name = "Access - PingCastle Readers";  Tier = "Tier1"; Description = "Read access to PingCastle Rapports" }
#    [PSCustomObject]@{ Name = "Access - Admin File Share RW"; Tier = "Tier1"; Description = "Read/Write access to IT Admin Share" }
#    [PSCustomObject]@{ Name = "Access - Admin File Share RO"; Tier = "Tier1"; Description = "Read only access to IT Admin Share" }
#)
#$GroupList | ConvertTo-Json

Invoke-WebRequest -Uri "$RepoUrl/ConfigFiles/Initial-Groups.json" -UseBasicParsing -OutFile "$($ENV:TEMP)\Initial-Groups.json"
$GroupList = Get-Content -Path "$($ENV:TEMP)\Initial-Groups.json" | ConvertFrom-Json

$GroupList | ForEach-Object {
    $GroupPath = (((Get-ADGroup -Identity "Domain $($_.Tier) Service accounts") -Split(","))[1..99]) -Join(",")
    New-TSxADGroup -Name $($_.Name) -Path $GroupPath -GroupCategory Security -GroupScope Global -Description $($_.Description) | Out-Null
}


# Show the created users, if any.
# --------------------------------------------------------------------------------------------------
$TempFile = [System.IO.Path]::Combine($env:TEMP, "CreatedUsers_$([guid]::NewGuid()).txt")
$CreatedUsers | Format-Table -AutoSize | Out-String | Set-Content -LiteralPath $TempFile -Encoding UTF8


# Change Administrator password and show on screen.
# ------------------------------------------------------------
if (!((Get-WmiObject -Class win32_computersystem).partofdomain)) {
    $NewPassword = $(-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 15 | ForEach-Object {[char]$_}))
    $SecurePassword = ConvertTo-SecureString -string $NewPassword -AsPlainText -Force
    Set-LocalUser -Name Administrator -Password $SecurePassword
}


# Get Data from Json Config
# ------------------------------------------------------------
If (Test-Path -Path "$RootPath\ServerConfig.json") {
    $ServerConfig = Get-Content -Path "$RootPath\ServerConfig.json" | ConvertFrom-Json
}


# Change Task to Completed
# ------------------------------------------------------------
if ($ServerConfig) {
    ($ServerConfig.Tasks | Where-Object { $_.Name -like "*$(Split-Path $PSCommandPath -Leaf)" }).status = "Completed"
    $ServerConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath "$RootPath\ServerConfig.json" -Encoding utf8 -Force
}
