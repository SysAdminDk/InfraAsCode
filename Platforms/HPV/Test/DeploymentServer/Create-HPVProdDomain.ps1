<#

    Requires
    - PVE Node(s) with Disk, CPU and memory to handle the amount of VMs
    - Create Master Deployment server using, Create-DeploymentServer.ps1
    - VM Template(s) have been created using New-PVEVMTemplate.ps1



    Create required servers for the PROD Domain.

    Tier 0 (10 Servers)
    3 x Active Directory Domain Controllers
    1 x Active Directory Certificate Authority
    2 x Entra Connect Sync
    2 x Entra Password Protection Proxy

    2 x Management server

    Tier 1 (24 Servers)
    2 x Remote Desktop Gateways
    2 x Radius Servers (MFA)
    2 x Entra Application Proxy / App Gateway

    2 x DHCP Servers
    2 x RRAS Servers (Always On VPN)
    2 x NPAS Servers (Always On VPN)

    2 x File Servers
    1 x DFS Server

    2 x Management server
    1 x Limited Management server

    2 x Remote Desktop Connection Broker Database Servers
    2 x Remote Desktop Connection Broker Servers
    2 x Remote Desktop Licensing Servers

    Optional Tier 2 (3 Servers)
    2 x Management server
    1 x Limited Management server


    Optional Tier Endpoint (9) (3 Servers)
    2 x Management server
    1 x Limited Management server

#>

# Do Not Just Execute.
# ------------------------------------------------------------
break


# Path to PVE scripts and Functions.
# ------------------------------------------------------------
$RootPath = "D:\PVE Scripts"


# Defaults.
# ------------------------------------------------------------
$DefaultUser = "Administrator"
$DefaultPass = "P@ssword2025.!!"
$DefaultDomain = "Prod.SecInfra.Dk"


# List of VMs to create.
# ------------------------------------------------------------
$VMConfig = @(
    [PSCustomObject]@{ VMName = "ADDS-01";  IPAddress = "10.36.100.11"; VMCores=2;  VMMemory=4; OSDisk=50; } # Active Directory
    [PSCustomObject]@{ VMName = "ADDS-02";  IPAddress = "10.36.100.12"; VMCores=2;  VMMemory=4; OSDisk=50; } # Active Directory
    [PSCustomObject]@{ VMName = "ADDS-03";  IPAddress = "10.36.100.13"; VMCores=2;  VMMemory=4; OSDisk=50; } # Active Directory
    [PSCustomObject]@{ VMName = "ADCA-01";  IPAddress = "10.36.100.16"; VMCores=2;  VMMemory=4; OSDisk=50; } # Certificate Auth
    [PSCustomObject]@{ VMName = "AADC-01";  IPAddress = "10.36.100.18"; VMCores=2;  VMMemory=4; OSDisk=50; } # Entra Connect Sync
    [PSCustomObject]@{ VMName = "AADC-02";  IPAddress = "10.36.100.19"; VMCores=2;  VMMemory=4; OSDisk=50; } # Entra Connect Sync
    [PSCustomObject]@{ VMName = "AAPP-01";  IPAddress = "10.36.100.21"; VMCores=2;  VMMemory=4; OSDisk=50; } # Entra / Azure Password Protection Proxy
    [PSCustomObject]@{ VMName = "AAPP-02";  IPAddress = "10.36.100.22"; VMCores=2;  VMMemory=4; OSDisk=50; } # Entra / Azure Password Protection Proxy
    [PSCustomObject]@{ VMName = "MGMT-01";  IPAddress = "10.36.100.23"; VMCores=4;  VMMemory=8; OSDisk=50; } # T0 Management server / Jumpstation
    [PSCustomObject]@{ VMName = "MGMT-02";  IPAddress = "10.36.100.24"; VMCores=4;  VMMemory=8; OSDisk=50; } # T0 Management server / Jumpstation
    [PSCustomObject]@{ VMName = "RDGW-01";  IPAddress = "10.36.100.31"; VMCores=2;  VMMemory=4; OSDisk=50; } # Remote Desktop Gateway
    [PSCustomObject]@{ VMName = "RDGW-02";  IPAddress = "10.36.100.32"; VMCores=2;  VMMemory=4; OSDisk=50; } # Remote Desktop Gateway
    [PSCustomObject]@{ VMName = "AMFA-01";  IPAddress = "10.36.100.33"; VMCores=2;  VMMemory=4; OSDisk=50; } # Remote Desktop NPS MFA.
    [PSCustomObject]@{ VMName = "AMFA-02";  IPAddress = "10.36.100.34"; VMCores=2;  VMMemory=4; OSDisk=50; } # Remote Desktop NPS MFA.
    [PSCustomObject]@{ VMName = "MEAP-01";  IPAddress = "10.36.100.35"; VMCores=2;  VMMemory=4; OSDisk=50; } # Entra Application Proxy
    [PSCustomObject]@{ VMName = "MEAP-02";  IPAddress = "10.36.100.36"; VMCores=2;  VMMemory=4; OSDisk=50; } # Entra Application Proxy
    [PSCustomObject]@{ VMName = "RDDB-01";  IPAddress = "10.36.100.37"; VMCores=2;  VMMemory=8; OSDisk=50; } # Remote Desktop Connection Broker Database
    [PSCustomObject]@{ VMName = "RDDB-02";  IPAddress = "10.36.100.38"; VMCores=2;  VMMemory=8; OSDisk=50; } # Remote Desktop Connection Broker Database
    [PSCustomObject]@{ VMName = "RDCB-01";  IPAddress = "10.36.100.39"; VMCores=2;  VMMemory=4; OSDisk=50; } # Remote Desktop Connection Broker
    [PSCustomObject]@{ VMName = "RDCB-02";  IPAddress = "10.36.100.40"; VMCores=2;  VMMemory=4; OSDisk=50; } # Remote Desktop Connection Broker
    [PSCustomObject]@{ VMName = "RDLI-01";  IPAddress = "10.36.100.41"; VMCores=2;  VMMemory=4; OSDisk=50; } # Remote Desktop Licensing
    [PSCustomObject]@{ VMName = "RDLI-02";  IPAddress = "10.36.100.42"; VMCores=2;  VMMemory=4; OSDisk=50; } # Remote Desktop Licensing
#   [PSCustomObject]@{ VMName = "DHCP-01";  IPAddress = "10.36.100.44"; VMCores=2;  VMMemory=4; OSDisk=50; } # DHCP
#   [PSCustomObject]@{ VMName = "DHCP-02";  IPAddress = "10.36.100.45"; VMCores=2;  VMMemory=4; OSDisk=50; } # DHCP
#   [PSCustomObject]@{ VMName = "NPAS-01";  IPAddress = "10.36.100.46"; VMCores=2;  VMMemory=4; OSDisk=50; } # Always On VPN NPS
#   [PSCustomObject]@{ VMName = "NPAS-02";  IPAddress = "10.36.100.47"; VMCores=2;  VMMemory=4; OSDisk=50; } # Always On VPN NPS
#   [PSCustomObject]@{ VMName = "RRAS-01";  IPAddress = "10.36.100.48"; VMCores=2;  VMMemory=4; OSDisk=50; } # Always On VPN Remote Access
#   [PSCustomObject]@{ VMName = "RRAS-02";  IPAddress = "10.36.100.49"; VMCores=2;  VMMemory=4; OSDisk=50; } # Always On VPN Remote Access
    [PSCustomObject]@{ VMName = "DFSR-01";  IPAddress = "10.36.100.51"; VMCores=2;  VMMemory=4; OSDisk=50; } # Distributed File services (DFS-R)
    [PSCustomObject]@{ VMName = "FILE-01";  IPAddress = "10.36.100.52"; VMCores=2;  VMMemory=4; OSDisk=50; } # File Service node
    [PSCustomObject]@{ VMName = "FILE-02";  IPAddress = "10.36.100.53"; VMCores=2;  VMMemory=4; OSDisk=50; } # File Service node
    [PSCustomObject]@{ VMName = "MGMT-11";  IPAddress = "10.36.100.55"; VMCores=4;  VMMemory=8; OSDisk=50; } # T1 Management server / Jumpstation
    [PSCustomObject]@{ VMName = "MGMT-12";  IPAddress = "10.36.100.56"; VMCores=4;  VMMemory=8; OSDisk=50; } # T1 Management server / Jumpstation
    [PSCustomObject]@{ VMName = "MGMT-13L"; IPAddress = "10.36.100.57"; VMCores=4;  VMMemory=8; OSDisk=50; } # T1 Limited Management server / Jumpstation
    [PSCustomObject]@{ VMName = "MGMT-14L"; IPAddress = "10.36.100.58"; VMCores=4;  VMMemory=8; OSDisk=50; } # T1 Limited Management server / Jumpstation
#   [PSCustomObject]@{ VMName = "MGMT-21";  IPAddress = "10.36.100.59"; VMCores=2;  VMMemory=4; OSDisk=50; } # T2 Management server / Jumpstation
#   [PSCustomObject]@{ VMName = "MGMT-22";  IPAddress = "10.36.100.60"; VMCores=2;  VMMemory=4; OSDisk=50; } # T2 Management server / Jumpstation
#   [PSCustomObject]@{ VMName = "MGMT-23L"; IPAddress = "10.36.100.61"; VMCores=2;  VMMemory=4; OSDisk=50; } # T2 Limited Management server / Jumpstation
#   [PSCustomObject]@{ VMName = "MGMT-24L"; IPAddress = "10.36.100.62"; VMCores=2;  VMMemory=4; OSDisk=50; } # T2 Limited Management server / Jumpstation
#   [PSCustomObject]@{ VMName = "MGMT-91";  IPAddress = "10.36.100.63"; VMCores=2;  VMMemory=4; OSDisk=50; } # T9 Endpoint Management server / Jumpstation
#   [PSCustomObject]@{ VMName = "MGMT-92";  IPAddress = "10.36.100.64"; VMCores=2;  VMMemory=4; OSDisk=50; } # T9 Endpoint Management server / Jumpstation
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
$MasterServer = Get-PVEServerID -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers -ServerName "Deploy"


# Get information required to create the template (VM)
# ------------------------------------------------------------
$PVELocation = Get-PVELocation -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers -IncludeNode $MasterServer.Node


# Create the servers listed.
# ------------------------------------------------------------
$VMConfig | ForEach-Object {
    Write-Host "Create Server : $($_.VMName).$DefaultDomain"
    & "$RootPath\New-PVEServer.ps1" -NewVMFQDN "$($_.VMName).$DefaultDomain" `
                                    -NewVmIp $_.IPAddress `
                                    -LocalUsername $DefaultUser `
                                    -LocalPassword $DefaultPass `
                                    -VMMemory $_.VMMemory `
                                    -VMCores $_.VMCores `
                                    -OSDisk $_.OSDisk `
                                    -DefaultConnection $PVEConnect `
                                    -DefaultLocation $PVELocation
}
