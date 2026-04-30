<#

    Balance the WMs across the two nodes

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
$PVESecret   = Get-Content -Path "$RootPath\Proxmox-Connection.json" | Convertfrom-Json


# Import PVE modules
# ------------------------------------------------------------
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -Confirm:$false
Get-ChildItem -Path "$RootPath\Functions" | ForEach-Object { Import-Module -Name $_.FullName -Force }


# Connect to PVE Cluster
# ------------------------------------------------------------
$PVEConnect = PVE-Connect -Authkey "$($PVESecret.User)!$($PVESecret.TokenID)=$($PVESecret.Token)" -Hostaddr $($PVESecret.Host)


# Get all Cluster nodes.
# ------------------------------------------------------------
$NodesQuery = ((Invoke-WebRequest -Uri "$($PVEConnect.PVEAPI)/cluster/status" -Headers $PVEConnect.Headers -Verbose:$false -UseBasicParsing | ConvertFrom-Json)[0]).data | Where {$_.type -eq "node"} | Sort-Object -Property Name
$OddNode = $NodesQuery.name[0]
$EvenNode = $NodesQuery.name[1]


# Get VM list from PVE.
# ------------------------------------------------------------
$AllVMIDs = (Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/cluster/resources?type=vm" -Headers $PVEConnect.Headers -Verbose:$false).data | Where {$_.template -eq 0} | Select-Object vmid, name, node
$MigrateVMs = $AllVMIDs | Where {$_.vmid -match "^36(0[1-9]\d|1\d{2}|2[0-4]\d)\d{3}$"}


foreach ($VMID in $MigrateVMs) {
    Write-host "$($VMID.name) - $($VMID.vmid)" -NoNewline
    if ( ($VMID.vmid -Match "^\d{7}[13579]$") -and ($VMID.node -ne $OddNode) ) {
        Write-host " Odd ($OddNode)"
        Move-PVEVM -ProxmoxAPI $($PVEConnect.PVEAPI) -Headers $PVEConnect.Headers -VMID $VMID.VMID -SourceNode $VMID.node -TargetNode $OddNode -Wait
    } elseif ( ($VMID.vmid -Match "^\d{7}[02468]$") -and ($VMID.node -ne $EvenNode) ) {
        Write-host " Even ($EvenNode)"
        Move-PVEVM -ProxmoxAPI $($PVEConnect.PVEAPI) -Headers $PVEConnect.Headers -VMID $VMID.VMID -SourceNode $VMID.node -TargetNode $EvenNode -Wait
    } else {
        Write-Host " Stay $($VMID.node)"
    }
}
