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
Import-Module WebAdministration -ErrorAction Stop

$DefaultSite  = Get-ChildItem "IIS:\Sites" | Select-Object -First 1
$SiteName     = $DefaultSite.Name
$PhysicalPath = [Environment]::ExpandEnvironmentVariables($DefaultSite.physicalPath)

if ([string]::IsNullOrWhiteSpace($PhysicalPath) -or (-not (Test-Path -Path $PhysicalPath))) {
    throw "Invalid IIS physical path: $PhysicalPath"
}

$JSONRoot = Join-Path -Path $PhysicalPath -ChildPath "\Deployment\ConfigFiles"
if (-NOT (Test-Path -Path "$JSONRoot\JSON")) {
    throw "JSON Path not found"
    Start-Sleep -Seconds 9999
}


# Import the functions.
# ------------------------------------------------------------
Import-Module -Name "$RootPath\Functions\IP2Mac.ps1"


# Import master config
# ------------------------------------------------------------
if (-NOT (Test-Path -Path "$JSONRoot\MasterServerConfig.json")) {

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
    $MasterConfig  = Get-Content "$JSONRoot\MasterServerConfig.json" | ConvertFrom-Json
}


# Define servers in each Domain
# ------------------------------------------------------------
$Domains = @{
    "Corp.SecInfra.Dk" = [PSCustomObject]@{
        "Servers" = $MasterConfig.Name | Where {
            $_ -NotLike "*NODE*"
        }
        "Defaults" = [PSCustomObject]@{
                DomainName="Corp.SecInfra.Dk";
                IPv4Subnet="10.36.100.0/24";
                Password=(-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 25 | ForEach-Object {[char]$_}));
        }
    };

    "Dev.SecInfra.Dk" = [PSCustomObject]@{
        "Servers" = $MasterConfig.name | Where {
            $_ -eq "ADDS-01" -or
            $_ -eq "ADDS-02" -or
            $_ -eq "MGMT-01" -or
            $_ -eq "RDGW-01" -or
            $_ -eq "MGMT-11"
        }
        "Defaults" = [PSCustomObject]@{
                DomainName="Dev.SecInfra.Dk";
                IPv4Subnet="10.36.150.0/24";
                Password=(-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 25 | ForEach-Object {[char]$_}));
        }
    };

    "Fabric.SecInfra.Dk" = [PSCustomObject]@{
        "Servers" = $MasterConfig.name | Where {
            $_ -eq "ADDS-01" -or
            $_ -eq "ADDS-02" -or
            $_ -eq "MGMT-01" -or
            $_ -eq "MGMT-02" -or
            $_ -eq "RDGW-01" -or
            $_ -eq "RDGW-02" -or
            $_ -eq "NPAS-01" -or
            $_ -eq "NPAS-02" -or
            $_ -eq "AMFA-01" -or
            $_ -eq "AMFA-02" -or
            $_ -eq "MGMT-11" -or
            $_ -eq "MGMT-12" -or
            $_ -eq "FILE-01"
        }
        "Defaults" = [PSCustomObject]@{
                DomainName="Fabric.SecInfra.Dk";
                IPv4Subnet="10.36.200.0/24";
                Password=(-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 25 | ForEach-Object {[char]$_}));
        }
    };
}


# Select Domain to create
# ------------------------------------------------------------
$Selected = $Domains.Keys | Out-GridView -Title "Select what domain to create" -OutputMode Single

$SelectedServers  = $Domains[$Selected].Servers
$SelectedDefaults = $Domains[$Selected].Defaults


# Extract server config into single files
# ------------------------------------------------------------
Foreach ($Server in $SelectedServers) {
    $ServerData = $MasterConfig | Where {$_.Name -eq $Server}

    # Get IP addr from server master data, and replace with default network definition
    $NewNetworkAddress = (($SelectedDefaults.IPv4Subnet -Split("\."))[0..2]) -join(".")
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
        $ServerData.DomainName = $SelectedDefaults.DomainName
    }

    # Update Domain Join values
    $ServerData.JoinOptions.UserDNSDomain = $SelectedDefaults.DomainName
    $ServerData.JoinOptions.UserDomain    = ($SelectedDefaults.DomainName -split("\."))[0]
    $ServerData.JoinOptions.Password      = $SelectedDefaults.Password

    if (-NOT (Test-Path -Path "$JSONRoot\JSON\$($ServerData.Network.PhysicalAddress).json")) {
        $ServerData | ConvertTo-Json -Depth 5 | Out-File -FilePath "$JSONRoot\JSON\$($ServerData.Network.PhysicalAddress).json" -Encoding utf8
    } else {
        Write-Warning "The server $($ServerData.Name).$($ServerData.JoinOptions.UserDNSDomain) already exist"
    }
}
