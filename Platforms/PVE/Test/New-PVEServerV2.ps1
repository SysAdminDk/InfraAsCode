<#

    Steps.
    1. Create VM in hypervisor.
    2. Mount Install ISO
    3. Mount AutoUnattended ISO
        a. Create Unattended with WinPW steps, to add Storage Driver (Perhaps also Network)
        b. Copy required files to ISO
        c. Upload ISO to hypervisor
        d. Add ISO to VM
    4. Mount Drivers Media

#>
Function New-2PVEServer {
    param (
        [cmdletbinding()]
        [Parameter(Mandatory)][object]$APIConnection,
        [Parameter(Mandatory)][object]$Location,
        [Parameter(Mandatory)][object]$DnsServers,
        [Parameter(Mandatory)][string]$FQDN,
        [Parameter(Mandatory)][string]$IpAddress,
        [Parameter(Mandatory)][string]$IpSubnet,
        [Parameter(Mandatory)][string]$IpGateway,
        [Parameter()][string]$MachineOU,
        [Parameter()][string]$DomainJoin,
        [Parameter()][string]$DomainOU,
        [Parameter()][string]$LocalUsername,
        [Parameter()][string]$LocalPassword,
        [Parameter()][string]$ProductKey,
        [Parameter()][string]$StartFile,
        [Parameter()][nullable[int]]$vlan,
        [Parameter()][int]$OSDisk,
        [Parameter()][int]$VMMemory,
        [Parameter()][int]$VMCores,
        [Parameter()][switch]$Start
    )
}



# Path to PVE scripts and Functions.
# ------------------------------------------------------------
$RootPath          = "\\10.36.1.32\NewGit"
$ScriptPath        = Join-Path -Path $RootPath -ChildPath "PVE-Platform"


# Import PVE modules
# ------------------------------------------------------------
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -Confirm:$false
Get-ChildItem -Path "$ScriptPath\Functions" | ForEach-Object { Import-Module -Name $_.FullName -Force }


# Import required Shared Modules
# ------------------------------------------------------------
@("New-ISOFile.ps1", "new-Unattend.ps1", "New-CloudInitDrive.ps1") | ForEach-Object {
    If (Test-Path "$RootPath\Shared Functions\$($_)") {
        Import-Module -Name "$RootPath\Shared Functions\$($_)" -Force
    }
}


# Extract Info of the VM created.
# ------------------------------------------------------------
$VMName = $(($FQDN -split("\."))[0])
$VMID = (($($IpAddress -Split("\."))[1]).PadLeft(2,"0")) + (($($IpAddress -Split("\."))[2]).PadLeft(2,"0")) + (($($IpAddress -Split("\."))[3]).PadLeft(3,"0"))
$VMDomain = $(($FQDN -split("\."))[1..9]) -join(".")

$TempPath = "$($ENV:Temp)\$VMName"


# Create Machine Temp Folder.
# ------------------------------------------------------------
If (!(Test-Path -Path $TempPath)) {
    New-Item -Path $TempPath -ItemType Directory | Out-Null
}




<#
New-Unattendv2 -HostName ADDS-01 -IpAddress 10.36.200.11 -Netmask 255.255.255.0 -Gateway 10.36.200.1 -DnsServers @("8.8.8.8","8.8.4.4")
#>
New-Unattend -ComputerName $VMName -AdminUsername "Administrator" -AdminPassword "Dharma05052023.!!" -DiskId 0 -ImageIndex 2 -Interfaces all `
    -IPAddress $IpAddress -SubnetMask $IpSubnet -Gateway $IpGateway -DNSServers $DnsServers -DomainName $VMDomain | `
    Out-File -FilePath "$TempPath\AutoUnattend.xml" -Encoding utf8 -Force
#notepad "$TempPath\AutoUnattend.xml"


# Create AutoUnattend ISO
# ------------------------------------------------------------
$IsoPath = Split-Path -Path $TempPath
New-ISOFile -source $TempPath -destinationIso "$IsoPath\$FQDN.iso" -title "Unattend Media" -force | Out-Null


# Upload ISO.
# ------------------------------------------------------------
$ISOStorage = ((Invoke-RestMethod -Uri "$($DefaultConnection.PVEAPI)/nodes/$($DefaultLocation.name)/storage" -Headers $DefaultConnection.Headers -Verbose:$false).data | Where {$_.content -like "*iso*" -and $_.type -eq "dir"}).storage
$Upload = Upload-PVEISO -ProxmoxAPI $($DefaultConnection.PVEAPI) -Headers $($DefaultConnection.Headers) -Node $($DefaultLocation.name) -Storage $ISOStorage -IsoPath "$IsoPath\$FQDN.iso"

Start-PVEWait -ProxmoxAPI $DefaultConnection.PVEAPI -Headers $DefaultConnection.Headers -node $($DefaultLocation.name) -taskid $($Upload.Replace("{`"data`":`"","").Replace("`"}",""))







