<#

    Requires
    - PVE Node(s) with Disk, CPU and memory to handle the amount of VMs
    - Create Master Deployment server using, Create-DeploymentServer.ps1
    - VM Template(s) have been created using New-PVEVMTemplate.ps1



    Create required servers for the FABRIC Domain.

    2 x Domain Controllers
    2 x Radius Servers (MFA)
    2 x Remote Desktop Gateways
    2 x Entra Application Proxy / App Gateway
    2 x T0 Management server

    Optional
    2 x Radius Servers (NPS)

#>

# Do Not Just Execute.
# ------------------------------------------------------------
break


# Path to PVE scripts and Functions.
# ------------------------------------------------------------
$RootPath = "D:\Deployment\Scripts\Proxmox"


# Defaults.
# ------------------------------------------------------------
$DefaultUser = "Administrator"
$DefaultPass = "P@ssword2025.!!"
$DefaultDomain = "Fabric.SecInfra.Dk"
$VLanId = 200


# List of VMs to create.
# ------------------------------------------------------------
$VMConfig = @(
    [PSCustomObject]@{ VMName = "ADDS-01";  IPAddress = "10.36.200.11"; Subnet="255.255.255.0"; Gateway="10.36.200.1"; DNSServers=@("1.1.1.1","1.0.0.1");           VMCores=2;  VMMemory=4; OSDisk=50; } # Active Directory
    [PSCustomObject]@{ VMName = "ADDS-02";  IPAddress = "10.36.200.12"; Subnet="255.255.255.0"; Gateway="10.36.200.1"; DNSServers=@("1.1.1.1","1.0.0.1");           VMCores=2;  VMMemory=4; OSDisk=50; } # Active Directory
    [PSCustomObject]@{ VMName = "MGMT-01";  IPAddress = "10.36.200.23"; Subnet="255.255.255.0"; Gateway="10.36.200.1"; DNSServers=@("10.36.200.11","10.36.200.12"); VMCores=4;  VMMemory=8; OSDisk=50; } # T0 Management server / Jumpstation
    [PSCustomObject]@{ VMName = "MGMT-02";  IPAddress = "10.36.200.24"; Subnet="255.255.255.0"; Gateway="10.36.200.1"; DNSServers=@("10.36.200.11","10.36.200.12"); VMCores=4;  VMMemory=8; OSDisk=50; } # T0 Management server / Jumpstation
    [PSCustomObject]@{ VMName = "RDGW-01";  IPAddress = "10.36.200.31"; Subnet="255.255.255.0"; Gateway="10.36.200.1"; DNSServers=@("10.36.200.11","10.36.200.12"); VMCores=2;  VMMemory=4; OSDisk=50; } # Remote Desktop Gateway
    [PSCustomObject]@{ VMName = "RDGW-02";  IPAddress = "10.36.200.32"; Subnet="255.255.255.0"; Gateway="10.36.200.1"; DNSServers=@("10.36.200.11","10.36.200.12"); VMCores=2;  VMMemory=4; OSDisk=50; } # Remote Desktop Gateway
    [PSCustomObject]@{ VMName = "AMFA-01";  IPAddress = "10.36.200.33"; Subnet="255.255.255.0"; Gateway="10.36.200.1"; DNSServers=@("10.36.200.11","10.36.200.12"); VMCores=2;  VMMemory=4; OSDisk=50; } # Remote Desktop NPS MFA.
    [PSCustomObject]@{ VMName = "AMFA-02";  IPAddress = "10.36.200.34"; Subnet="255.255.255.0"; Gateway="10.36.200.1"; DNSServers=@("10.36.200.11","10.36.200.12"); VMCores=2;  VMMemory=4; OSDisk=50; } # Remote Desktop NPS MFA.
    [PSCustomObject]@{ VMName = "NPAS-01";  IPAddress = "10.36.200.46"; Subnet="255.255.255.0"; Gateway="10.36.200.1"; DNSServers=@("10.36.200.11","10.36.200.12"); VMCores=2;  VMMemory=4; OSDisk=50; } # Radius auth
    [PSCustomObject]@{ VMName = "NPAS-02";  IPAddress = "10.36.200.47"; Subnet="255.255.255.0"; Gateway="10.36.200.1"; DNSServers=@("10.36.200.11","10.36.200.12"); VMCores=2;  VMMemory=4; OSDisk=50; } # Radius auth
    [PSCustomObject]@{ VMName = "FILE-01";  IPAddress = "10.36.200.52"; Subnet="255.255.255.0"; Gateway="10.36.200.1"; DNSServers=@("10.36.200.11","10.36.200.12"); VMCores=2;  VMMemory=4; OSDisk=50; } # File Service
)


# Import PVE modules
# ------------------------------------------------------------
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -Confirm:$false
Get-ChildItem -Path "$RootPath\Functions" | ForEach-Object { Import-Module -Name $_.FullName -Force }


# Connect to PVE Cluster
# ------------------------------------------------------------
$PVESecret = Get-Content "$RootPath\PVE-Secret.json" | Convertfrom-Json
$PVEConnect = PVE-Connect -Authkey "$($PVESecret.User)!$($PVESecret.TokenID)=$($PVESecret.Token)" -Hostaddr $($PVESecret.Host)


# Get the Deployment server info
# ------------------------------------------------------------
$MasterServer = Get-PVEServerID -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers -ServerName "LAB-Deploy"


# Get information required to create the template (VM)
# ------------------------------------------------------------
$PVELocation = Get-PVELocation -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers -IncludeNode $MasterServer.Node


# Create the servers listed.
# ------------------------------------------------------------
$VMConfig[4] | ForEach-Object {
    Write-Host "Create Server : $($_.VMName).$DefaultDomain"
    & "$RootPath\New-PVEServer.ps1" -NewVMFQDN "$($_.VMName).$DefaultDomain" `
                                    -NewVmIp $_.IPAddress `
                                    -vlan $VLanId `
                                    -LocalUsername $DefaultUser `
                                    -LocalPassword $DefaultPass `
                                    -VMMemory $_.VMMemory `
                                    -VMCores $_.VMCores `
                                    -OSDisk $_.OSDisk `
                                    -DefaultConnection $PVEConnect `
                                    -DefaultLocation $PVELocation
}
