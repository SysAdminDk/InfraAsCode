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


# Import TS Tiering Module
# ------------------------------------------------------------
Import-Module (Get-ChildItem -Path $RootPath -Recurse -Filter "TSxTieringModule.psm1").FullName -Verbose -Force


If (-NOT (Get-Command -Name New-TSxAdminAccount)) {
    Throw "TSx modules not found"
}


# Create Users.
# --------------------------------------------------------------------------------------------------
$UserList = @(
    [PSCustomObject]@{ FirstName = "Jan";              LastName = "Kristensen" }
    [PSCustomObject]@{ FirstName = "Homer";            LastName = "Simpson"    }
    [PSCustomObject]@{ FirstName = "Marjorie Bouvier"; LastName = "Simpson"    }
)


$CreatedUsers = @()
$UserList | ForEach-Object {
    $CreatedUsers += New-TSxAdminAccount -FirstName $_.FirstName -LastName $_.LastName -AccountType T0  -Prefix "Adm" -Suffix "FTE" -AddToSilo $false
    $CreatedUsers += New-TSxAdminAccount -FirstName $_.FirstName -LastName $_.LastName -AccountType T1  -Prefix "Adm" -Suffix "FTE" -AddToSilo $false
    $CreatedUsers += New-TSxAdminAccount -FirstName $_.FirstName -LastName $_.LastName -AccountType CON -Prefix "Adm" -Suffix "FTE" -AddToSilo $false
}


# Create Groups.
# --------------------------------------------------------------------------------------------------
$GroupList = @(
    [PSCustomObject]@{ Name = "Access - PingCastle Readers";  Tier = "Tier1"; Description = "Read access to PingCastle Rapports" }
    [PSCustomObject]@{ Name = "Access - Admin File Share RW"; Tier = "Tier1"; Description = "Read/Write access to IT Admin Share" }
    [PSCustomObject]@{ Name = "Access - Admin File Share RO"; Tier = "Tier1"; Description = "Read only access to IT Admin Share" }
)


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


# UPDATE !!


# Get Data from Json Config
# ------------------------------------------------------------
If (Test-Path -Path "$PSScriptRoot\ServerConfig.json") {
    $ServerConfig = Get-Content -Path "$PSScriptRoot\ServerConfig.json" | ConvertFrom-Json
}


# Change Task to Completed
# ------------------------------------------------------------
if ($ServerConfig) {
    ($ServerConfig.Tasks | Where-Object { $_.Name -eq "ADDS-01.ps1" }).status = "Completed"
    $ServerConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath "$RootPath\ServerConfig.json" -Encoding utf8 -Force
}
