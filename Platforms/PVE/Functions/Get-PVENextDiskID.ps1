<#

    Get drives attached to a VM, and get next avalible drive ID, used when adding disk(s)

#>
Function Get-PVENextDiskID {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)][string]$ProxmoxAPI,
        [Parameter(Mandatory)][object]$Headers,
        [Parameter(Mandatory)][string]$Node=$SourceNode,
        [Parameter(Mandatory)][int]$VMID=$TargetVM,
	[string][ValidateSet("scsi","sata","virtio")]$DiskType=""
    )

    # Get VM Status
    # ------------------------------------------------------------
    $VMStatus = (Invoke-RestMethod -Uri "$ProxmoxAPI/nodes/$Node/qemu/$VMID/config" -Headers $Headers -Verbose:$false).data


    if ($DiskType -eq "") {

        # Get first boot device from list.
        # ------------------------------------------------------------
        $BootDrive = ((($VMStatus.boot -split("="))[-1] -split(";"))[0])


        # Exclude IDE and NET
        # ------------------------------------------------------------
        if ( ($BootDrive -like "IDE*") -or ($BootDrive -like "NET*") ) { $BootDrive = "scsi" }


       # Get name of storage controller
       # ------------------------------------------------------------
       $StorageController = $bootdrive -replace("\d+$","")
       
    } else {

        $StorageController = $DiskType

    }
    
    # Find LAST drive attached to the selected Storage Controller
    # ------------------------------------------------------------
    $LastVMDisk = $VMStatus.PSObject.Properties | Where-Object { $_.Name -match "^$StorageController\d+$" } | Sort-Object Name | Select-Object -Last 1


    # Controller ID ++
    # ------------------------------------------------------------
    if ($LastVMDisk) {
        if ($LastVMDisk.Name -match '\d+$') {
            $VMDiskCount = [int]$matches[0] + 1
        }
    } else {
        $VMDiskCount = 0
    }
    
    
    # Verify drive counter.
    # ------------------------------------------------------------
    if ( ($StorageController -eq "sata") -and ($VMDiskCount -gt 5) ) {            Throw "Sata max disk count is 0 to 5"    
    } elseif (( ($StorageController -eq "scsi") -and ($VMDiskCount -gt 30) )) {   Throw "Sata max disk count is 0 to 30"
    } elseif (( ($StorageController -eq "virtio") -and ($VMDiskCount -gt 15) )) { Throw "Sata max disk count is 0 to 15"
    } else {
        return "$StorageController$VMDiskCount"
    }
}
