<#

    List all Templates.

#>
Function Get-PVETemplates {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)][string]$ProxmoxAPI,
        [Parameter(Mandatory)][object]$Headers
    )

    $Alltemplates = @()

    $NodesQuery = ((Invoke-WebRequest -Uri "$ProxmoxAPI/cluster/status" -Headers $Headers -Verbose:$false -UseBasicParsing | ConvertFrom-Json)[0]).data | Where {$_.type -eq "node"}

    foreach ($Node in $NodesQuery) {

        $NodeTemplateQuery = ((Invoke-WebRequest -Uri "$ProxmoxAPI/nodes/$($Node.name)/qemu/" -Headers $headers -Verbose:$false -UseBasicParsing | ConvertFrom-Json)[0]).data | Where {$_.template -eq 1}
        foreach ($Template in $NodeTemplateQuery) {

            $TemplateArray = @(
                [PSCustomObject]@{
                                  VmID = "$($Template.vmid)"
                                  Name = "$($Template.Name)";
                                  Node = "$($Node.Name)";
                                 }
                              )
            $Alltemplates += $TemplateArray
        }
    }
    return $Alltemplates
}