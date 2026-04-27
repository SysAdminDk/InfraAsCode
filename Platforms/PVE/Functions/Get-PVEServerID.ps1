<#

    Get VMID From ServerName

#>
Function Get-PVEServerID {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)][string]$ProxmoxAPI,
        [Parameter(Mandatory)][object]$Headers,
        [string]$ServerName
    )

    $NodesQuery = ((Invoke-WebRequest -Uri "$ProxmoxAPI/cluster/status" -Headers $Headers -Verbose:$false -UseBasicParsing | ConvertFrom-Json)[0]).data | Where {$_.type -eq "node"}
    $AllVMs = @()
    foreach ($Node in $NodesQuery) {

        $VMData = (((Invoke-WebRequest -Uri "$ProxmoxAPI/nodes/$($Node.name)/qemu/" -Headers $headers -Verbose:$false -UseBasicParsing | ConvertFrom-Json)[0]).data | Where {$_.template -ne 1 -and $_.name -like "*$ServerName*"})

        $VMData | foreach {
            $NodeDataArray = @(
                [PSCustomObject]@{
                                  VmID = "$($_.vmid)"
                                  Name = "$($_.Name)";
                                  Node = "$($Node.Name)";
                                 }
            )
            $AllVMs += $NodeDataArray
        }
    }

    if ($AllVMs.Count -gt 1) {
        $VMMaster = $AllVMs | Out-GridView -Title "Select VM to use for mounting the Deployment Drives." -OutputMode Single
    } else {
        $VMMaster = $AllVMs
    }

    Return $VMMaster
}