<#

    Requires
    - PVE Node(s) with Disk, CPU and memory to handle the amount of VMs
    - Create Master Deployment server using, Create-DeploymentServer.ps1
    - VM Template(s) have been created using New-PVEVMTemplate.ps1


    Create required servers for the FABRIC Domain.
    - Server list found in ./ConfigFiles/FabricDomain.json

#>

# Path to PVE scripts and Functions.
# ------------------------------------------------------------
if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $RootPath = $PSScriptRoot
} else {
    $RootPath  = "C:\Scripts"
}


# Default Variables
# ------------------------------------------------------------
$DefaultTemplate = "2025-Standard"
$PVESecret   = Get-Content -Path "$RootPath\Proxmox-Connection.json" | Convertfrom-Json


# Configure or extract the Vendor Max, will be used for all VMs created.
# ------------------------------------------------------------
#$MacPrefix         = "BC:24"
$VendorMac         = (((Get-NetAdapter).MacAddress -split("-"))[0..1]) -join("-")


# List of VMs to create.
# ------------------------------------------------------------
$Response = Invoke-WebRequest -Uri "http://localhost/deployment/ConfigFiles/JSON" -UseBasicParsing
$JsonFiles = (Split-Path -path ($Response.links.href | Where {$_ -like "*.json"}) -Leaf) -replace(".json","")


# Import PVE modules
# ------------------------------------------------------------
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -Confirm:$false
Get-ChildItem -Path "$RootPath\Functions" | ForEach-Object { Import-Module -Name $_.FullName -Force }


# Connect to PVE Cluster
# ------------------------------------------------------------
$PVEConnect = PVE-Connect -Authkey "$($PVESecret.User)!$($PVESecret.TokenID)=$($PVESecret.Token)" -Hostaddr $($PVESecret.Host)


# Get Id of Deployment server....
# ------------------------------------------------------------
$MasterID = Get-PVEServerID -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers -ServerName $ENV:Computername


# Get information required to create the template (VM)
# ------------------------------------------------------------
$PVELocation = Get-PVELocation -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers -IncludeNode $MasterID.Node | Select-Object Name,Storage,Interface
<#
# Defaults.
$PVELocation = [PSCustomObject]@{
    "Name"      = "NUC01"
    "Storage"   = "VMdata"
    "Interface" = "vmbr0"
}
#>

# Find all templates
# ------------------------------------------------------------
$Template = Get-PVETemplates -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers | Where {$_.name -eq $DefaultTemplate}
<#
$Template = [PSCustomObject]@{
    "VmID" = "99999901";
    "Name" = "2025-Standard";
    "Node" = "NUC01"
}
#>


# Get VM list from PVE.
# ------------------------------------------------------------
$AllVMIDs = (Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/cluster/resources?type=vm" -Headers $PVEConnect.Headers -Verbose:$false).data | Where {$_.template -eq 0} | Select-Object vmid, name, node
$VMMacAddresses = $AllVMIDs | Foreach {
    $VMNet = (Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($_.Node)/qemu/$($_.VMID)/config" -Headers $PVEConnect.Headers -Verbose:$false).data.net0
    $VMMac = ((($VMNet -split(","))[0]) -split("="))[-1]
    @("00","00") + ($VMMac -split(":"))[2..5] -Join("-")
}

$VMsToCreate = (Compare-Object -ReferenceObject $VMMacAddresses -DifferenceObject $JsonFiles | Where-Object SideIndicator -eq "=>").InputObject


Foreach ($MACAddress in $VMsToCreate) {
    $URL = ($Response.links.href | Where {$_ -like "*$($MACAddress)*"})

    $ServerRawData = Invoke-RestMethod -Uri "http://localhost/$URL" -UseBasicParsing -OutFile "$($ENV:Temp)\$MACAddress.json"
    $ServerData = Get-Content -Path "$($ENV:Temp)\$MACAddress.json" | ConvertFrom-Json
    Remove-Item -Path "$($ENV:Temp)\$MACAddress.json"

    $FQDN = (@($ServerData.Name,$ServerData.JoinOptions.UserDNSDomain) -join("."))
    $VLAN = ($ServerData.Network.IPv4Address -split("\."))[-2]
    $MacAddress = $ServerData.Network.PhysicalAddress -replace("00-00",$VendorMac)

    $ServerDisks = @([int]$ServerData.Hardware.Disks.System)
    if ($ServerData.Hardware.Disks.Data.count -gt 0) {
        $ServerDisks += $ServerData.Hardware.Disks.Data | ForEach-Object { [int]$_ }
    }

    New-PVEServer -FQDN $FQDN -NetAdapterMac $ServerData.Network.PhysicalAddress -vlan $VLAN `
        -Disks $ServerDisks -VMMemory $ServerData.Hardware.MaxMemory -VMCores $ServerData.Hardware.CPUCores `
        -PVEConnection $PVEConnect -PVELocation $PVELocation -PVETemplate $Template -Verbose

}
