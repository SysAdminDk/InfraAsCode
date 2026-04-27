<#

    Move VM between Nodes and storage on Nodes.

    # Examples.

    # Move All VM Disks to other Storage on same node.
    Move-PVEVM -ProxmoxAPI $($PVEConnect.PVEAPI) -Headers $($PVEConnect.Headers) -VMID 100 -SourceNode NODE1 -TargetNode NODE01 -Targetstorage local-lvm

    # Move Node, require same storage name
    Move-PVEVM -ProxmoxAPI $($PVEConnect.PVEAPI) -Headers $($PVEConnect.Headers) -VMID 100 -SourceNode NODE1 -TargetNode NODE02

    # Move Node, other storage location.
    Move-PVEVM -ProxmoxAPI $($PVEConnect.PVEAPI) -Headers $($PVEConnect.Headers) -VMID 100 -SourceNode NODE1 -TargetNode NODE02 -Targetstorage local-lvm
    

#>
Function Move-PVEVM {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)][string]$ProxmoxAPI,
        [Parameter(Mandatory)][object]$Headers,
        [Parameter(Mandatory)][string]$VMID,
        [Parameter(Mandatory)][string]$SourceNode,
        [Parameter(Mandatory)][string]$TargetNode,
        [string]$Targetstorage,
        [switch]$Wait
    )


    if ($SourceNode -eq $TargetNode) {
        $VMStatus = (Invoke-RestMethod -Uri "$ProxmoxAPI/nodes/$SourceNode/qemu/$VMID/config" -Headers $Headers -Verbose:$false).data
        $VMDisks = $VMStatus.PSObject.Properties | Where-Object { $_.Name -match "scsi|sata|virtio|tpmstate|efidisk" -and $_.Value -like "*$VMID*"}
        $VMDisks | ForEach-Object {
            $DiskId = $_.value
            $SourceStorage = $($DiskId -split(":"))[0]
            $Controller = $_.name
            
            if ($SourceStorage -ne $Targetstorage) {

                $Body = "vmid=$VMID"
                $Body += "&disk=$Controller"
                $Body += "&storage=$Targetstorage"
                $Body += "&delete=1"
                $MoveDisk = Invoke-RestMethod -Uri "$ProxmoxAPI/nodes/$SourceNode/qemu/$VMID/move_disk" -Body $Body -Method Post -Headers $Headers -Verbose:$false
                
                # We have to wait, multiple locks on configuration is not posible.
                Start-PVEWait -ProxmoxAPI $ProxmoxAPI -Headers $Headers -node $SourceNode -taskid $MoveDisk.data

            }
        }

    } else {

        $Body = "vmid=$VMID"
        $Body += "&target=$TargetNode"
        if ($Targetstorage) {
            $Body += "&targetstorage=$Targetstorage"
        }
        $MoveStatus = Invoke-RestMethod -Uri "$ProxmoxAPI/nodes/$SourceNode/qemu/$VMID/migrate" -Body $body -Method Post -Headers $Headers -Verbose:$false

    }

    if ($Wait) {
        Start-PVEWait -ProxmoxAPI $ProxmoxAPI -Headers $Headers -node $SourceNode -taskid $MoveStatus.data
    } else {
        return
    }
}
