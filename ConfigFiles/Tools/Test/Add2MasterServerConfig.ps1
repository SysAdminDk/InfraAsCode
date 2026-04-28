Import-Module -Name "G:\Shares\Personal Github\Shared-Functions\ConvertFunctions.ps1"


$ServerConfigs = Get-Content -Path "G:\Shares\Personal Github\LAB-Deployment\ConfigFiles\MasterServerConfig.json" | ConvertFrom-Json
$NewServer = $ServerConfigs[1] | ConvertTo-Json -Depth 10 | ConvertFrom-Json

$NewServer.name = "AZL-NODE-05"
$NewServer.Description = "Azure Local Server"

$NewServer.Network.IPv4Address = "10.36.0.225"
$NewServer.Network.PhysicalAddress = $(IP2Mac -IpAddress $NewServer.Network.IPv4Address)
#$NewServer.Network.DefaultGateway = "10.36.0.1"
#$NewServer.Network.DNSServers = @("10.36.0.11", "10.36.0.12", "10.36.0.13")
#$NewServer.Network.SubnetMask = "255.255.255.0"

$NewServer.Hardware.CPUSockets = 2
$NewServer.Hardware.CPUCores = 12
$NewServer.Hardware.MinMemory = 8
$NewServer.Hardware.MaxMemory = 256
$NewServer.Hardware.Disks.Data = @(500,500,500,500)

$Roles = @(
    [PSCustomObject]@{"name" = "Hyper-V"; "status" = "Pending"}
    [PSCustomObject]@{"name" = "RSAT-Hyper-V-Tools"; "status" = "Pending"}
)
$NewServer.Roles = "" # $Roles

$Tasks = @(
    [PSCustomObject]@{"name" = "HyperV-Prep.ps1"; "status" = "Pending"}
    [PSCustomObject]@{"name" = "Cleanup.ps1"; "status" = "Pending"}
)
$NewServer.Tasks = "" #$Tasks

$ServerConfigs += $NewServer


<#
$ServerConfigs | ConvertTo-Json -Depth 5 | Out-File -FilePath "G:\Shares\Personal Github\LAB-Deployment\ConfigFiles\MasterServerConfig.json" -Encoding utf8 -Force
#>


$ServerConfigs | Foreach {

    $IPParts = $_.Network.IPv4Address -Split("\.")
    $VMID = "{0}{1:D3}{2:D3}" -f [int]$IPParts[1], [int]$IPParts[2], [int]$IPParts[3]

    if ( ($VMID -Match "^\d{7}[13579]$") -and ( ($_.name -like "*1*") -or ($_.name -like "*3*")) ) {
#        Write-Host "$($_.Name) - $($_.Network.IPv4Address)"
    } elseif ( ($VMID -Match "^\d{7}[2468]$") -and ($_.name -like "*2*") ) {
#        Write-Host "$($_.Name) - $($_.Network.IPv4Address)"
    } else {
        Write-Host "$($_.Name) - $($_.Network.IPv4Address)"
    }
}




##$ServerConfigs | Select-Object Name,@{l="IP"; e={$_.Network.IPv4Address}} | ConvertTo-Csv -Delimiter ";"

$NewIP = Get-Content -Path "G:\Shares\Personal Github\LAB-Deployment\ConfigFiles\newiplist.csv" | Convertfrom-csv -Delimiter ";"

foreach ($VM in $ServerConfigs[6..8]) {
    $VM.Name
    #$VM.Description = 
    ($NewIP | Where {$_.Name -eq $VM.Name}).Description
    #$VM.Network.IPv4Address = 
    ($NewIP | Where {$_.Name -eq $VM.Name}).IP
    #$VM.Network.PhysicalAddress = 
    $(IP2Mac -IpAddress $VM.Network.IPv4Address) -replace(":","-")
}

$ServerConfigs | ConvertTo-Json -Depth 5 | Out-File -FilePath "G:\Shares\Personal Github\LAB-Deployment\ConfigFiles\MasterServerConfig.json" -Encoding utf8
