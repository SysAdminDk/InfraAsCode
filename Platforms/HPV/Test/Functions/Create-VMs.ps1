<#

    Run this on Fabric Hyper-V Node 1

#>


$TemplateFile = "D:\TS-Data\Reference\Windows Server 2025 Standard.vhdx"


# Create VMs
# ------------------------------------------------------------
$VMName = "ADDS-01"
New-VM –Name $VMName -Generation 2 –MemoryStartupBytes 2048MB -Path "D:\VMData" -switchname "UplinkSwitch" -NoVHD | Out-Null
Set-VMMemory –VMName $VMName -DynamicMemoryEnabled $true -MaximumBytes (1Gb*8) -MinimumBytes (1Gb*1) -StartupBytes (1Gb*2) | Out-Null
SET-VMProcessor –VMName $VMName –count 4 | Out-Null
$VMPath = (Get-VM -Name $VMName).path

# Add TPM
# Remove TimeSync, Data exchange, Backup
# Disable Checkpoints
# Stop Action = Shutdown

New-Item -ItemType directory -Path "$VMPath\Virtual Hard Disks" | Out-Null
$OSVHDxFile = "$VMPath\Virtual Hard Disks\$($VMName)_Disk_0.vhdx"
Copy-Item -Path $TemplateFile -Destination $OSVHDxFile
Add-VMHardDiskDrive -VMName ADDS-01 -ControllerNumber 0 -ControllerLocation 0 –Path $OSVHDxFile | Out-Null

$BackupDrive = New-VHD -Path "D:\VMData\ADDS-01\Virtual Hard Disks\ADDS-01_Disk_2.vhdx" -SizeBytes 100Gb -Dynamic
Add-VMHardDiskDrive -VMName ADDS-01 -ControllerNumber 0 -ControllerLocation 3 –Path $BackupDrive.Path | Out-Null

# Add Unattend...
# Add Scripts...
# Start ADDS-01


# Member VMs..
$MemberServers = @("RDGW-01","AMFA-01","NPAS-01","FILE-01","Deploy","MGMT-01","MGMT-11")

Foreach ($VMName in $MemberServers) {

    New-VM –Name $VMName -Generation 2 –MemoryStartupBytes 2048MB -Path "D:\VMData" -switchname "UplinkSwitch" -NoVHD | Out-Null
    Set-VMMemory –VMName $VMName -DynamicMemoryEnabled $true -MaximumBytes (1Gb*8) -MinimumBytes (1Gb*1) -StartupBytes (1Gb*2) | Out-Null
    SET-VMProcessor –VMName $VMName –count 4 | Out-Null
    $VMPath = (Get-VM -Name $VMName).path
    $OSVHDxFile = "$VMPath\Virtual Hard Disks\$($VMName)_Disk_0.vhdx"

    New-Item -ItemType directory -Path "$VMPath\Virtual Hard Disks" | Out-Null
    Copy-Item -Path $TemplateFile -Destination $OSVHDxFile
    Add-VMHardDiskDrive -VMName $VMName -ControllerNumber 0 -ControllerLocation 0 –Path $OSVHDxFile | Out-Null

    # Add Unattend...
    # Add Scripts...

}
