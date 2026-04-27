<#

    Command script to create New PVE VM.
    1. Clone selected PVETemplate (Show selection if multiple)
    2. Create Custom Cloud Init media


#>
<#

    This script creates new VM from selected Template, see CreateProdDomain or CreateFabricDomain.



    1. User/script picks target node, storage, and network.

    3. Clone Template → new VM.

    4. If required, migrate the VM to the requested node/storage.

    5. Boot....

#>
Function New-PVEServer {
    param (
        [cmdletbinding()]
        [Parameter(Mandatory)][string]$FQDN,
        [Parameter(Mandatory)][string]$NetAdapterMac,
        [Parameter(Mandatory)][object]$PVEConnection,
        [Parameter(Mandatory)][object]$PVELocation,
        [Parameter(Mandatory)][object]$PVETemplate,
        [object]$Disks,
        [Nullable[int]]$Vlan,
        [int]$VMMemory,
        [int]$VMCores
    )


    # Extract Info of the VM created.
    # ------------------------------------------------------------
    $FQDNParts = $FQDN -split("\.")
    $VMName = $FQDNParts | Select-Object -First 1
    $VmDomain = ($FQDNParts | Select-Object -Skip 1) -Join (".")

    $IpAddress = MAC2IP -MACAddress $NetAdapterMac
    $IPParts = $IpAddress -Split("\.")
    $VMID = "{0}{1:D3}{2:D3}" -f [int]$IPParts[1], [int]$IPParts[2], [int]$IPParts[3]

    if ($null -eq $Vlan) {
        $Vlan = $IPParts[2]
    }

    <#

        Verify Deployment and PVETemplate is on same NODE

    #>


    # If NO PVETemplate, FAIL
    # ------------------------------------------------------------
    if (!($PVETemplate)) {
        Throw "No VM PVETemplate found or selected"
    }


    <#

        Create VM

    #>

    $AllVMIDs = (Invoke-RestMethod -Uri "$($PVEConnection.PVEAPI)/cluster/resources?type=vm" -Headers $PVEConnection.Headers -Verbose:$false).data | Select-Object vmid, name
    if ($AllVMIDs.vmid -contains $VMID) {
        throw "VMID already in use."

    }

    # Configure and create VM
    # ------------------------------------------------------------
    Write-Verbose "Proxmox: Create new VM: $VMName"


    # Clone PVETemplate
    # ------------------------------------------------------------
    If ($PVELocation.Name -ne $PVETemplate.Node) {
        $VMCreate = Invoke-RestMethod -Uri "$($PVEConnection.PVEAPI)/nodes/$($PVETemplate.Node)/qemu/$($PVETemplate.VmID)/clone" -Body "newid=$VMID&name=$FQDN&full=1" -Method Post -Headers $PVEConnection.Headers -Verbose:$false
        Start-PVEWait -ProxmoxAPI $PVEConnection.PVEAPI -Headers $PVEConnection.Headers -Node $($PVETemplate.Node) -Taskid $VMCreate.data

        Move-PVEVM -ProxmoxAPI $PVEConnection.PVEAPI -Headers $PVEConnection.Headers -SourceNode $PVETemplate.Node -TargetNode $PVELocation.Name -VMID $VMID -Targetstorage $PVELocation.storage -Wait

    } else {
        $VMCreate = Invoke-RestMethod -Uri "$($PVEConnection.PVEAPI)/nodes/$($PVELocation.name)/qemu/$($PVETemplate.VmID)/clone" -Body "newid=$VMID&name=$FQDN&full=1&storage=$($PVELocation.storage)" -Method Post -Headers $PVEConnection.Headers -Verbose:$false

        # Wait for clone...
        # ------------------------------------------------------------
        Start-PVEWait -ProxmoxAPI $PVEConnection.PVEAPI -Headers $PVEConnection.Headers -node $($PVELocation.name) -taskid $VMCreate.data
    }


    <# 

        Modify New VM depending on selections..

    #>

    
    # Get VM Configuration prior to updates / changes
    # ------------------------------------------------------------
    Write-Verbose "Proxmox: Change VM configuration"
    $VMStatus = (Invoke-RestMethod -Uri "$($PVEConnection.PVEAPI)/nodes/$($PVELocation.name)/qemu/$VMID/config" -Headers $PVEConnection.Headers -Verbose:$false).data


    # Modify Boot sequence.
    if ($VMStatus.boot -eq " ") {

        $VMDisks = $VMStatus.PSObject.Properties | Where {$_.Value -like "*Size*" -and $_.Name -notlike "*efi*" -and $_.Name -notlike "*tpm*"}
        $BootDisk = $VMDisks | Sort-Object -Property Name | Select-Object -First 1

        $VMStatus.boot = "order=$($BootDisk.name)"
        $Body = "boot=$([uri]::EscapeDataString($VMStatus.boot))"
        $null = Invoke-RestMethod -Uri "$($PVEConnection.PVEAPI)/nodes/$($PVELocation.name)/qemu/$VMID/config" -Body $Body -Method POST -Headers $PVEConnection.Headers -Verbose:$false
    }


    # Set VLan and Mac Address
    # ------------------------------------------------------------
    $NetAdapter = $VMStatus.PSObject.Properties | Where {$_.name -like "net0*"}
    $AdapterData = $NetAdapter.Value -split(",")

    $VirtIO   = ($AdapterData | Where {$_ -like "virtio=*"}) -replace '(?<=^[^=]+=)(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}', "$($NetAdapterMac.replace("-",":"))"
    $Bridge   = $AdapterData | Where {$_ -like "bridge=*"}
    $Firewall = $AdapterData | Where {$_ -like "firewall=*"}
    $Tag      = ($AdapterData | Where {$_ -like "tag=*"}) -replace "tag=\d+", "tag=$Vlan"
    if (!($Tag)) { $Tag = "tag=$Vlan" }

    $NewAdapterData = @($VirtIO, $Bridge, $Firewall, $Tag) -join(",")
    $Body = "$($NetAdapter.name)=$([uri]::EscapeDataString($NewAdapterData))"
    $null = Invoke-RestMethod -Uri "$($PVEConnection.PVEAPI)/nodes/$($PVELocation.name)/qemu/$VMID/config" -Body $Body -Method Put -Headers $PVEConnection.Headers -Verbose:$false


    # Change CPU Count if needed
    # ------------------------------------------------------------
    if ($VMStatus.cores -ne $VMCores) {
        Write-Verbose "Proxmox: Update CPU Cores"

        $body = "cores=$VMCores"
        $null = Invoke-RestMethod -Uri "$($PVEConnection.PVEAPI)/nodes/$($PVELocation.name)/qemu/$VMID/config" -Body $body -Method Post -Headers $PVEConnection.Headers -Verbose:$false

    }
    

    # Change Memory Size if needed
    # ------------------------------------------------------------
    if ([math]::Round($($VMMemory * 1KB)) -ne $VMStatus.memory) {
        Write-Verbose "Proxmox: Update Memory size"

        $body = "memory=$($VMMemory*1KB)"
        $null = Invoke-RestMethod -Uri "$($PVEConnection.PVEAPI)/nodes/$($PVELocation.name)/qemu/$VMID/config" -Body $body -Method Post -Headers $PVEConnection.Headers -Verbose:$false

    }
    

    # Expand OS disk if needed.
    # ------------------------------------------------------------
    $BootDisk = ($VMStatus.boot -replace("order="))
    $OSDiskSize = [int](($VMStatus.$BootDisk -split "=")[-1] -replace '\D')

    if ($OSDiskSize -lt [int]($Disks[0])) {

        Write-Verbose "Proxmox: Update Disk size ($BootDisk - $([int]($Disks[0]))G)"

        $body = "disk=$($BootDisk)&size=$([int]($Disks[0]))G"
        $null = Invoke-RestMethod -Uri "$($PVEConnection.PVEAPI)/nodes/$($PVELocation.name)/qemu/$VMID/resize" -Body $body -Method Put -Headers $PVEConnection.Headers -Verbose:$false

    }


    # Add Data disks, if any
    # ------------------------------------------------------------
    foreach ($Disk in $Disks[1..10]) {

        $DiskId = Get-PVENextDiskID -ProxmoxAPI $PVEConnection.PVEAPI -Headers $PVEConnection.Headers -Node $PVELocation.name -VMID $VMID

        $Null = Invoke-RestMethod -Uri "$($PVEConnection.PVEAPI)/nodes/$($PVELocation.name)/qemu/$VMID/config" -Body "$DiskId=$([uri]::EscapeDataString("$($PVELocation.Storage):$Disk"))" -Method Post -Headers $PVEConnection.Headers -Verbose:$false

    }
}

# Start new server
# ------------------------------------------------------------
if ($Start) {
    $null = Invoke-RestMethod -Uri "$($PVEConnection.PVEAPI)/nodes/$($PVELocation.name)/qemu/$VMID/status/start" -Headers $PVEConnection.Headers -Method POST -Verbose:$false
}

Write-Verbose "Script end: $(Get-Date)"
