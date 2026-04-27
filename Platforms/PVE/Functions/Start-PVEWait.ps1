<#

    Get and Wait on PVE task.

#>
function Start-PVEWait {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)][string]$ProxmoxAPI,
        [Parameter(Mandatory)][object]$Headers,
        [Parameter(Mandatory)][string]$Node,
        [Parameter(Mandatory)][string]$Taskid
    )

    $TimeoutSeconds = 300
    $StartTime = Get-Date
    $EndTime = $StartTime.AddSeconds($TimeoutSeconds)

    do {
        $TaskStatus = Invoke-RestMethod -Uri "$ProxmoxAPI/nodes/$Node/tasks/$Taskid/status" -Headers $headers -Verbose:$false
        
        if ($TaskStatus.data.status -ne "running") {
            Write-Progress -Activity "Waiting for PVE Task ($($TaskStatus.data.type))" -Status "Completed" -PercentComplete 100 -Completed
            return
        } elseif ((Get-Date) -ge $EndTime) {
            Write-Progress -Activity "Waiting for PVE Task ($($TaskStatus.data.type))" -Status "Completed" -PercentComplete 100 -Completed
            throw "Wait task timeout reached."
        }

        $Elapsed = (Get-Date) - $StartTime
        $Percent = [math]::Min(($elapsed.TotalSeconds / $TimeoutSeconds) * 100, 100)
        
        Write-Progress -Activity "Waiting for PVE Task ($($TaskStatus.data.type))" -Status "Running" -PercentComplete $Percent
        Start-Sleep -Seconds 1

    } while ($true)
}
