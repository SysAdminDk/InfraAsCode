<#

    Connecto to PVE cluster, and used PS Gridview to select Node, Storage, Bridge the VM will be created and connected to.

#>
function Get-PVELocation {
    [CmdletBinding()]
    Param(
        [Parameter(Position=0,Mandatory)][string]$ProxmoxAPI=$PVEConnect.PVEAPI,
        [Parameter(Position=1,Mandatory)][object]$Headers=$PVEConnect.Headers,
        $ExcludeNode,
        $IncludeNode
    )


    # Get NODE info
    # ------------------------------------------------------------
    Write-Verbose "Get Proxmox Nodes"

    Try {
        $NodesData = @()

        $NodesQuery = (Invoke-RestMethod -Uri "$ProxmoxAPI/cluster/status" -Headers $Headers -Verbose:$false).data | Where {$_.type -eq "node"}
        
        foreach ($Node in $NodesQuery) {
            $NodeDataArray = @(
                [PSCustomObject]@{ Name = $Node.Name; }
            )
            $NodesData += $NodeDataArray
        }
    }
    Catch {
        Write-Error "Unable to get any available nodes...."
    }


    # Get Storage info
    # ------------------------------------------------------------
    Write-Verbose "Get Proxmox Nodes Storage"

    Try {
        $StorageData = @()

        foreach ($Node in $NodesData) {
            $NodeStorageQuery = (Invoke-RestMethod -Uri "$ProxmoxAPI/nodes/$($Node.name)/storage" -Headers $Headers -Verbose:$false).data | Where {$_.content -like "*images*"}

            foreach ($Storage in $NodeStorageQuery) {
                $NodeStorageArray = @(
                    [PSCustomObject]@{ Name    = $Node.Name;
                                       Storage = $Storage.storage;
                                       Avail   = [math]::round($Storage.avail / 1Gb);
                                       Used    = [math]::round($Storage.used / 1Gb);
                                       Total   = [math]::round($Storage.total / 1Gb);
                                     }
                )
                $StorageData += $NodeStorageArray
            }
        }

        $StorageData = $StorageData | where {$_.avail -ne 0}

    }
    Catch {
        Write-Error "Unable to get any available storage on any nodes"
    }


    # Get Network info
    # ------------------------------------------------------------
    Write-Verbose "Get Proxmox Bridge"

    Try {
        $BridgeData = @()

        foreach ($Node in $NodesData) {

            $NodeBridgeQuery = ((Invoke-RestMethod -Uri "$ProxmoxAPI/nodes/$($Node.name)/network" -Method Get -Headers $Headers -Verbose:$false).data | where {$_.Type -eq "bridge"}) | Select-Object iface,address,cidr

            foreach ($Bridge in $NodeBridgeQuery) {
                $NodeBridgeArray = @(
                    [PSCustomObject]@{ Name    = $Node.Name;
                                       Address = $Bridge.address;
                                       Network = $Bridge.cidr;
                                       Interface = $Bridge.iface;
                                     }
                )
                $BridgeData += $NodeBridgeArray
            }
        }
    }
    Catch {
        $Switch = ""
    }


    # Join the arrays and show selection
    # ------------------------------------------------------------
    $Result = foreach ($a in $StorageData) {
        foreach ($b in $BridgeData | Where-Object { $_.Name -eq $a.Name }) {
            [PSCustomObject]@{ Name      = $a.Name
                               Storage   = $a.Storage
                               Avail     = $a.Avail
                               Used      = $a.Used
                               Total     = $a.Total
                               Interface = $b.Interface
                            }
        }
    }
    if (($Result | Where {$_.name -eq $IncludeNode}).Name.count -eq 1) {
        $VMLocation = $Result | Where {$_.name -eq $IncludeNode}
    } elseif ($null -ne $IncludeNode) {
        $VMLocation = $Result | Where {$_.name -eq $IncludeNode} | Out-GridView -Title "Select Node, Storage and network for the new VM" -OutputMode Single
    } else {
        $VMLocation = $Result | Where {$_.name -ne $ExcludeNode} | Out-GridView -Title "Select Node, Storage and network for the new VM" -OutputMode Single
    }
    return $VMLocation
}
