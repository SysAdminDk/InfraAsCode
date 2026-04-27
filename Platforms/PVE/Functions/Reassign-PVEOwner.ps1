<#

    Move VM Disk from VM to VM.

#>
function Reassign-PVEOwner {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)][string]$ProxmoxAPI,
        [Parameter(Mandatory)][object]$Headers,
        [Parameter(Mandatory)][string]$SourceNode,
        [Parameter(Mandatory)][string]$SourceVM,
        [Parameter(Mandatory)][string]$TargetVM,
        $SourceDisk,
        $TargetDisk,
        [string][ValidateSet("scsi","sata","virtio")]$DiskType="scsi|sata|virtio",
        [switch]$Wait
    )

    
    # Get Drive to move..
    # ------------------------------------------------------------
    if ( ($null -eq $SourceDisk) -or ($SourceDisk -eq "First") ) {
        $SourceVmData = (Invoke-RestMethod -Uri "$ProxmoxAPI/nodes/$SourceNode/qemu/$SourceVM/config" -Headers $Headers -Verbose:$false).data
        $SourceVMDisk = $SourceVmData.PSObject.Properties | Where-Object { $_.Name -match $DiskType -and $_.Value -like "*$SourceVM*"} | Sort-Object -Property Name | Select-Object -First 1

    } else {
        $SourceVmData = (Invoke-RestMethod -Uri "$ProxmoxAPI/nodes/$SourceNode/qemu/$SourceVM/config" -Headers $Headers -Verbose:$false).data
        $SourceVMDisk = $SourceVmData.PSObject.Properties | Where-Object { $_.Name -eq $SourceDisk -and $_.Value -like "*$SourceVM*"}
    }
    

    # Detach disk from VM
    # ------------------------------------------------------------
    $Body = "delete=$($SourceVMDisk.name)"
    $UnMount = Invoke-RestMethod -Uri "$ProxmoxAPI/nodes/$SourceNode/qemu/$SourceVM/config" -Body $Body -Method Post -Headers $Headers -Verbose:$false

    Start-PVEWait -ProxmoxAPI $ProxmoxAPI -Headers $Headers -node $($MasterID.Node) -taskid $UnMount.data
    

    # Get Target data.
    # ------------------------------------------------------------
    $TargetVMData = (Invoke-RestMethod -Uri "$ProxmoxAPI/nodes/$SourceNode/qemu/$TargetVM/config" -Method Get -Headers $Headers -Verbose:$false).data


    # Find Target Disk Number to use
    # ------------------------------------------------------------
    if ( ($TargetDisk -eq "Next") -or ($null -eq $TargetDisk) ) {

        $NextVMDisk = Get-PVENextDiskID -ProxmoxAPI $ProxmoxAPI -Headers $Headers -Node $SourceNode -VMID $TargetVM
                
        # Add to VM
        $Body = "vmid=$SourceVM"
        $Body += "&target-vmid=$TargetVM"
        $Body += "&disk=unused0"
        $Body += "&target-disk=$NextVMDisk"
        $MoveDisk = Invoke-RestMethod -Uri "$ProxmoxAPI/nodes/$SourceNode/qemu/$SourceVM/move_disk" -Body $Body -Method Post -Headers $Headers -Verbose:$false


    } else {

        $AllVMDisks = ($TargetVMData.PSObject.Properties | Where-Object { $_.Name -match $DiskType -and $_.value -like "*$TargetVM*"}).name
        if ($AllVMDisks -contains $TargetDisk) {
            throw "Selected Controller ID is already in use"
            break
        }

        # Add to VM
        $Body = "vmid=$VMID"
        $Body += "&target-vmid=$TargetVM"
        $Body += "&disk=unused0"
        $Body += "&target-disk=$TargetDisk"
        $MoveDisk = Invoke-RestMethod -Uri "$ProxmoxAPI/nodes/$SourceNode/qemu/$SourceVM/move_disk" -Body $Body -Method Post -Headers $Headers -Verbose:$false

    }

    if ($Wait) {
        Start-PVEWait -ProxmoxAPI $ProxmoxAPI -Headers $Headers -node $SourceNode -taskid $MoveDisk.data
    }

    return $NextVMDisk
}
