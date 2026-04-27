
Function Remove-PVEServer {
    param (
        [cmdletbinding()]
        [Parameter(Mandatory)][object]$PVEConnection,
        [Parameter(Mandatory)][object]$VMID
    )

    # Ensure the VMID is found
    # ------------------------------------------------------------
    $AllVMIDs = (Invoke-RestMethod -Uri "$($PVEConnection.PVEAPI)/cluster/resources?type=vm" -Headers $PVEConnection.Headers -Verbose:$false).data
    $Index = $AllVMIDs.vmid.IndexOf($VMID)

    If ($Index -ge 0) {

        If ($AllVMIDs[$Index].status -ne "stopped") {
        
        

            # STOP VM
            # ------------------------------------------------------------
            $VMStop = Invoke-RestMethod -Uri "$($PVEConnection.PVEAPI)/nodes/$($AllVMIDs[$Index].node)/qemu/$VMID/status/stop" -Headers $PVEConnection.Headers -Method POST -Verbose:$false
            Start-PVEWait -ProxmoxAPI $PVEConnection.PVEAPI -Headers $PVEConnection.Headers -node $($AllVMIDs[$Index].node) -taskid $VMStop.data

        }
        
        # Remove VM
        # ------------------------------------------------------------
        $VMDestroy = Invoke-RestMethod -Uri "$($PVEConnection.PVEAPI)/nodes/$($AllVMIDs[$Index].node)/qemu/$VMID" -Method DELETE -Headers $PVEConnection.Headers -Verbose:$false
        Start-PVEWait -ProxmoxAPI $PVEConnection.PVEAPI -Headers $PVEConnection.Headers -node $($AllVMIDs[$Index].node) -taskid $VMDestroy.data


    } else {
        Throw "Selected VMID do not exist"
    }
}