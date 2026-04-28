<#

    Requires
    - PVE Node(s) with Disk, CPU and memory to handle the amount of VMs
    - Create Master Deployment server using, Create-DeploymentServer.ps1
    - VM Template(s) have been created using New-PVEVMTemplate.ps1


    Create required servers for the FABRIC Domain.
    - Server list found in ./ConfigFiles/FabricDomain.json

#>

# Do Not Just Execute.
# ------------------------------------------------------------
#break


# Path to PVE scripts and Functions.
# ------------------------------------------------------------
$RootPath        = "C:\Scripts"
$DefaultNode     = "NUC01"
$DefaultSwitch   = "vmbr0"
$DefaultStorage  = "VMdata"
$DefaultTemplate = "2025-Standard"
$GitConnection   = Get-Content -Path "$RootPath\GitHub-Connection.json" | Convertfrom-Json
$PVEConnection   = Get-Content -Path "$RootPath\Proxmox-Connection.json" | Convertfrom-Json


# Download required files
# ------------------------------------------------------------






# Configure or extract the Vendor Max, will be used for all VMs created.
# ------------------------------------------------------------
#$MacPrefix         = "BC:24"
$VendorMac         = (((Get-NetAdapter).MacAddress -split("-"))[0..1]) -join("-")


# List of VMs to create.
# ------------------------------------------------------------
$RepoUrl  = "https://api.github.com/repos/SysAdminDk"

$URL = "$RepoUrl/LAB-Deployment/contents/ConfigFiles/JSON"

$Response = Invoke-RestMethod -Uri $URL -Headers @{ Authorization = "token $gitToken" }
$GitJsonFiles = $Response.Name | % { ($_ -split("\."))[0] }



# Import PVE modules
# ------------------------------------------------------------
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -Confirm:$false
Get-ChildItem -Path "$RootPath\Functions" | ForEach-Object { Import-Module -Name $_.FullName -Force }


# Connect to PVE Cluster
# ------------------------------------------------------------
$PVEConnect = PVE-Connect -Authkey "$($PVESecret.User)!$($PVESecret.TokenID)=$($PVESecret.Token)" -Hostaddr $($PVESecret.Host)


# Get information required to create the template (VM)
# ------------------------------------------------------------
#$PVELocation = Get-PVELocation -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers -IncludeNode NUC01
$PVELocation = [PSCustomObject]@{
    "Name"      = $DefaultNode;
    "Storage"   = $DefaultStorage;
    "Interface" = $DefaultSwitch
}


# Find all templates
# ------------------------------------------------------------
$Template = Get-PVETemplates -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers | Where {$_.name -eq $DefaultTemplate}
$Template = [PSCustomObject]@{
    "VmID" = "99999901";
    "Name" = "2025-Standard";
    "Node" = "NUC01"
}


# Get VM list from PVE.
# ------------------------------------------------------------
$AllVMIDs = (Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/cluster/resources?type=vm" -Headers $PVEConnect.Headers -Verbose:$false).data | Where {$_.template -eq 0} | Select-Object vmid, name, node
$VMMacAddresses = $AllVMIDs | Foreach {
    $VMNet = (Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($_.Node)/qemu/$($_.VMID)/config" -Headers $PVEConnect.Headers -Verbose:$false).data.net0
    $VMMac = ((($VMNet -split(","))[0]) -split("="))[-1]
    @("00","00") + ($VMMac -split(":"))[2..5] -Join("-")
}

$VMsToCreate = (Compare-Object -ReferenceObject $VMMacAddresses -DifferenceObject $GitJsonFiles | Where-Object SideIndicator -eq "=>").InputObject
$VMsToCreate.Count

Foreach ($MACAddress in $VMsToCreate | Where {$_ -like "00-00-0A-24-96*"}) {
    $URL = ($Response | Where {$_.name -eq "$($MACAddress).json"}).download_url

    $ServerRawData = Invoke-WebRequest -Uri $URL -UseBasicParsing -Headers @{ Authorization = "token $gitToken" }

    $JsonBytes = [System.Text.Encoding]::UTF8.GetBytes($ServerRawData.Content)
    $JsonText  = [System.Text.Encoding]::UTF8.GetString($JsonBytes).Trim([char]0xFEFF)
    $ServerData = $JsonText | ConvertFrom-Json

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


<#
# Start them In the right ORDER.
# ------------------------------------------------------------
$PDCMac = $VMsToCreate | Where {$_ -like "*96-0B"}
$IPParts = (MAC2IP -MACAddress $PDCMac) -split("\.")
$VMID = "{0}{1:D3}{2:D3}" -f [int]$IPParts[1], [int]$IPParts[2], [int]$IPParts[3]

$null = Invoke-RestMethod -Uri "$($PVEConnection.PVEAPI)/nodes/$($PVELocation.name)/qemu/$VMID/status/start" -Headers $PVEConnection.Headers -Method POST -Verbose:$false

# Wait for DOMAIN to be ready.
# ------------------------------------------------------------
Start-Sleep -Seconds 300

# Start the rest
# ------------------------------------------------------------
foreach ($PDCMac in $VMsToCreate | Where {$_ -like "*96*" -and $_ -ne $PDCMac}) {
    $IPParts = (MAC2IP -MACAddress $PDCMac) -split("\.")
    $VMID = "{0}{1:D3}{2:D3}" -f [int]$IPParts[1], [int]$IPParts[2], [int]$IPParts[3]

    $null = Invoke-RestMethod -Uri "$($PVEConnection.PVEAPI)/nodes/$($PVELocation.name)/qemu/$VMID/status/start" -Headers $PVEConnection.Headers -Method POST -Verbose:$false

    Start-Sleep -Seconds 60
}
#>


<#
$CleanupVMs = (Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/cluster/resources?type=vm" -Headers $PVEConnect.Headers -Verbose:$false).data | Where {$_.vmid -like "36150*"}

$CleanupVMs | Sort-Object -Descending -Property vmid | % { Remove-PVEServer -PVEConnection $PVEConnect -VMID $_.vmid }

#>

