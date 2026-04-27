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
Import-Module -Name "$RootPath\Functions\IP2Mac.ps1"


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


# Find Existing Domains.
# ------------------------------------------------------------
#$MacFilter = ((IP2Mac -IpAddress "0.0.0.11") -split("-"))[-1]
$ExistingServers = (Get-ChildItem -Path "$JSONRoot\JSON" -Filter "*.json" | % { Get-Content $_.FullName | ConvertFrom-Json })

$SelectedDomain = $ExistingServers.JoinOptions.UserDNSDomain | Select-Object -Unique | Out-GridView -Title "Select AD domain where to join the server" -OutputMode Single
$DomainServers = $ExistingServers | where {$_.JoinOptions.UserDNSDomain -eq $SelectedDomain}


# Select server type to add
# ------------------------------------------------------------
$SelectedServers = $MasterConfig.name | Where {$_ -notlike "*NODE*" -and $_ -NotIn $DomainServers.Name} | Out-GridView -Title "Select server type to add to selected domain" -OutputMode Multiple


Foreach ($Server in $SelectedServers) {

    $ServerData = $MasterConfig | Where {$_.Name -eq $Server}

    # Get IP addr from server master data, and replace with default network definition
    $NewNetworkAddress = (($DomainServers[0].Network.IPv4Address -Split("\."))[0..2]) -join(".")
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
        $ServerData.DomainName = $SelectedDomain
    }

    # Update Domain Join values
    $ServerData.JoinOptions.UserDNSDomain = $DomainServers[0].JoinOptions.UserDNSDomain
    $ServerData.JoinOptions.UserDomain    = $DomainServers[0].JoinOptions.UserDomain
    $ServerData.JoinOptions.Password      = $DomainServers[0].JoinOptions.Password

    $ServerData | ConvertTo-Json -Depth 5 | Out-File -FilePath "$JSONRoot\JSON\$($ServerData.Network.PhysicalAddress).json" -Encoding utf8
}
