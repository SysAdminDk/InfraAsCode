<#

    Generate random VM ID.

#>
function Get-PVENextID {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)][string]$ProxmoxAPI,
        [Parameter(Mandatory)][object]$Headers,
        [int]$StartID = 99999900,
        [int]$EndID   = 99999999
    )

    # Get all cluster VMs
    # ------------------------------------------------------------
    $allVMs = (Invoke-RestMethod -Uri "$ProxmoxAPI/cluster/resources?type=vm" -Headers $Headers -Verbose:$false).data | Select-Object vmid, name

    # Extract used IDs
    # ------------------------------------------------------------
    $usedIDs = $allVMs.vmid | Sort-Object -Unique

    # Find first free ID in range
    # ------------------------------------------------------------
    for ($id = $StartID; $id -le $EndID; $id++) {
        if ($id -notin $usedIDs) {
            return $id
        }
    }

    Throw "No available VMID found in range $StartID - $EndID"
}