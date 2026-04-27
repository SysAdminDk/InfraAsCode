# Required for unsigned scripts & modules.
# ------------------------------------------------------------
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -Confirm:$false


# Path to PVE scripts and Functions.
# ------------------------------------------------------------
if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $RootPath = Split-Path -Path $PSScriptRoot -Parent
} else {
    $RootPath  = "C:\Scripts"
}


# JSON directory Path
# ------------------------------------------------------------
$IISDefault   = Get-IISSite
$JSONRoot = [Environment]::ExpandEnvironmentVariables($(($IISDefault).Applications.VirtualDirectories[0].PhysicalPath)) + "\Deployment\ConfigFiles"
if (-NOT (Test-Path -Path "$JSONRoot\JSON")) {
    New-Item -Path "$JSONRoot\JSON" -ItemType Directory | Out-Null
}


# Import the functions.
# ------------------------------------------------------------
#Import-Module -Name "$RootPath\Functions\IP2Mac.ps1"


# Import master config
# ------------------------------------------------------------
if (-NOT (Test-Path -Path "$RootPath\MasterServerConfig.json")) {

    Add-Type -AssemblyName System.Windows.Forms

    $FileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $FileDialog.InitialDirectory = $RootPath
    $FileDialog.Filter = "JSON files (*.json)|*.json"
    $FileDialog.Title  = "Select file"

    if ($FileDialog.ShowDialog() -eq "OK") {
        $MasterConfig = Get-Content -Path $FileDialog.FileName | ConvertFrom-Json
    }
    else {
        Throw "No file selected"
    }
} else {
    $MasterConfig  = Get-Content "$RootPath\MasterServerConfig.json" | ConvertFrom-Json
}


# ..
# ------------------------------------------------------------
$NewDomainName   = Read-Host -Prompt "Active Directory Doamin Name (test.domain.tld)"
$NewDomainSubNet = Read-Host -Prompt "IP Subnet (10.10.10.0/24)"
$NewJoinPassword = (-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 25 | ForEach-Object {[char]$_}))


# Select server type to add
# ------------------------------------------------------------
$SelectedServers  = @()
$SelectedServers += ($MasterConfig | Where {$_.Name -eq "ADDS-01"}).Name
$SelectedServers += $MasterConfig.name | Where {$_ -notlike "*NODE*" -and $_ -NotIn $PDCData.Name} | Out-GridView -Title "Select server type to add to selected domain" -OutputMode Multiple


Foreach ($Server in $SelectedServers) {

    $ServerData = $MasterConfig | Where {$_.Name -eq $Server}

    # Get IP addr from server master data, and replace with default network definition
    $NewNetworkAddress = (($NewDomainSubNet -Split("\."))[0..2]) -join(".")
    $NetworkData       = $ServerData.Network.IPv4Address -split("\.")
    $ServerAddress     = ($NetworkData)[-1]
    $OldNetworkAddress = ($NetworkData[0..2]) -join(".")

    # Update the Server Values
    $ServerData.Network.IPv4Address     = ($NewNetworkAddress, $ServerAddress) -join(".")
    $ServerData.Network.PhysicalAddress = ("00","00") + (((IP2Mac -IpAddress $ServerData.Network.IPv4Address) -Split("-"))[2..5]) -Join("-")
    $ServerData.Network.DefaultGateway  = ($NewNetworkAddress, "1") -join(".")

    # Update DNS servers
    $ServerData.Network.DNSServers = $ServerData.Network.DNSServers -replace "^$([regex]::Escape($OldNetworkAddress))\.(\d+)$", "$NewNetworkAddress.`$1"

    # Update Domain Value
    if ($ServerData.DomainName -ne $null) {
        $ServerData.DomainName = $NewDomainName
    }

    # Update Domain Join values
    $ServerData.JoinOptions.UserDNSDomain = $NewDomainName
    $ServerData.JoinOptions.UserDomain    = ($NewDomainName -split("\."))[0]
    $ServerData.JoinOptions.Password      = $NewJoinPassword

    $ServerData | ConvertTo-Json -Depth 5 | Out-File -FilePath "$JSONRoot\JSON\$($ServerData.Network.PhysicalAddress).json" -Encoding utf8
}
