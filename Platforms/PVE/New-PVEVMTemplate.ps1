<#

    This script creates a PVE VM template.

    Requires the "DeployMaster" server to be created and manual installed.
    See Create-DeploymentServer.ps1.

#>


# Do Not Just Execute.
# ------------------------------------------------------------
#break


# Path to PVE scripts and Functions.
# ------------------------------------------------------------
if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $RootPath = $PSScriptRoot
    if (-Not(Test-Path "$RootPath\Functions")) {
        $RootPath = Split-Path -Path $PSScriptRoot -Parent
    }
} else {
    $RootPath  = "C:\Scripts"
}


# Import PVE modules
# ------------------------------------------------------------
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -Confirm:$false
Get-ChildItem -Path "$RootPath\Functions" | ForEach-Object { Import-Module -Name $_.FullName -Force }


# Connect to PVE Cluster
# ------------------------------------------------------------
if (-NOT (Test-Path -Path "$RootPath\Proxmox-Connection.json")) {

    Add-Type -AssemblyName System.Windows.Forms

    $FileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $FileDialog.InitialDirectory = $RootPath
    $FileDialog.Filter = "JSON files (*.json)|*.json"
    $FileDialog.Title  = "Select file"

    if ($FileDialog.ShowDialog() -eq "OK") {
        $PVESecret = Get-Content -Path $FileDialog.FileName | ConvertFrom-Json
    }
    else {
        Throw "No file selected"
    }
} else {
    $PVESecret = Get-Content -Path "$RootPath\Proxmox-Connection.json" | Convertfrom-Json
}

$PVEConnect = PVE-Connect -Authkey "$($PVESecret.User)!$($PVESecret.TokenID)=$($PVESecret.Token)" -Hostaddr $($PVESecret.Host)


# Get Id of Deployment server....
# ------------------------------------------------------------
$MasterID = Get-PVEServerID -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers -ServerName $ENV:Computername


# Get information required to create the template (VM)
# ------------------------------------------------------------
$PVELocation = Get-PVELocation -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers -IncludeNode $MasterID.Node


# List ISO content, and add selected ISO to This VM
# ------------------------------------------------------------
$ISOStorage  = ((Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.name)/storage" -Headers $($PVEConnect.Headers)).data | Where {$_.content -like "*iso*" -and $_.type -eq "dir"}).storage
$ServerISO = (Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.name)/storage/$ISOStorage/content" -Headers $($PVEConnect.Headers)).data | Select-Object -Property volid,format,size | Where {$_.volid -like "*Windows*Server*"} | Out-GridView -OutputMode Single
$DiskId = Get-PVENextDiskID -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers -Node $MasterID.Node -VMID $MasterID.VmID

$Body = "$DiskId=$([uri]::EscapeDataString("$($ServerISO.volid),media=cdrom"))"
$Null = Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.name)/qemu/$($MasterID.VmID)/config" -Body $Body -Method Post -Headers $PVEConnect.Headers -Verbose:$false

$Body = "boot=$([uri]::EscapeDataString("order=scsi0"))"
$null = Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.name)/qemu/$($MasterID.VmID)/config" -Body $Body -Method POST -Headers $PVEConnect.Headers -Verbose:$false


<#

    Now the connection and required information is ready, time to create the template.

#>


# Info of the VM created.
# ------------------------------------------------------------
$VMName = $(-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object {[char]$_}))
$Memory = 4*1024
$Cores = 2
$OSDisk = 20
$TemplateID = Get-PVENextID -ProxmoxAPI $($PVEConnect.PVEAPI) -Headers $($PVEConnect.Headers)


# Default Template Configuration
# ------------------------------------------------------------
$CreateVM = "node=$($MasterID.Node)"
$CreateVM += "&vmid=$TemplateID"
$CreateVM += "&name=$VMName"
$CreateVM += "&bios=ovmf"
$CreateVM += "&cpu=host"
$CreateVM += "&ostype=win11"
$CreateVM += "&machine=pc-q35-9.0"
$CreateVM += "&tpmstate0=$([uri]::EscapeDataString("$($PVELocation.storage):1,size=4M,version=v2.0"))"
$CreateVM += "&efidisk0=$([uri]::EscapeDataString("$($PVELocation.storage):1,efitype=4m,format=raw,pre-enrolled-keys=1"))"
$CreateVM += "&net0=$([uri]::EscapeDataString("virtio,bridge=$($PVELocation.Interface),firewall=1"))"
$CreateVM += "&boot=$([uri]::EscapeDataString("order=net0"))"
$CreateVM += "&scsihw=virtio-scsi-single"
$CreateVM += "&memory=$Memory"
$CreateVM += "&balloon=2048"
$CreateVM += "&cores=$Cores"
#$CreateVM += "&scsi0=$([uri]::EscapeDataString("$($PVELocation.storage):$($OSDisk),format=raw"))"


# Create the Template VM
# ------------------------------------------------------------
$VMCreate = Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($MasterID.Node)/qemu/" -Body $CreateVM -Method POST -Headers $($PVEConnect.Headers) -Verbose:$false
Start-PVEWait -ProxmoxAPI $($PVEConnect.PVEAPI) -Headers $PVEConnect.Headers -node $($MasterID.Node) -taskid $VMCreate.data


<#

    To apply Windows install wim, move the template OS disk to this server, partition disk and apply wim.

#>


## Move OS disk to THIS server.
## ------------------------------------------------------------
#$TmpDiskID = Reassign-PVEOwner -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers -SourceNode $MasterID.Node -SourceVM $TemplateID -TargetVM $MasterID.VmID -Wait
# Create OS drive on THIS VM.
$DiskId = Get-PVENextDiskID -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers -Node $MasterID.Node -VMID $MasterID.VmID

$Null = Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($MasterID.Node)/qemu/$($MasterID.VmID)/config" -Body "$DiskId=$([uri]::EscapeDataString("$($PVELocation.Storage):$OSDisk"))" -Method Post -Headers $PVEConnect.Headers -Verbose:$false



# Pause 5 sec, need PnP to work
# ------------------------------------------------------------
Start-Sleep -Seconds 2


# Initialize disk, and create UEFI partions
# ------------------------------------------------------------
$VHDDrive = Get-Disk | Where {$_.partitionstyle -eq 'RAW' -and $_.Size -eq $($OSDisk * 1Gb) }
if ($null -eq $VHDDrive) {

    throw "Unable to locate any avalible disk"

} else {

    Initialize-Disk -Number $VHDDrive.number -PartitionStyle GPT

    Get-Partition -DiskNumber $VHDDrive.number | Remove-Partition -Confirm:$false

    $VHDXDrive1 = New-Partition -DiskNumber $VHDDrive.number -GptType  "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" -AssignDriveLetter -Size 100Mb
    $VHDXDrive1 | Format-Volume -FileSystem FAT32 -NewFileSystemLabel System -Confirm:$false | Out-null

    $VHDXDrive2 = New-Partition -DiskNumber $VHDDrive.number -GptType "{e3c9e316-0b5c-4db8-817d-f92df00215ae}" -Size 16Mb

    $VHDXDrive3 = New-Partition -DiskNumber $VHDDrive.number -UseMaximumSize -AssignDriveLetter
    $VHDXDrive3 | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false | Out-null


    # Add Drive letters
    # ------------------------------------------------------------
    $VHDXDrive1 = Get-Partition -DiskNumber $VHDDrive.number -PartitionNumber $VHDXDrive1.PartitionNumber
    $VHDXVolume1 = [string]$VHDXDrive1.DriveLetter+":"

    $VHDXDrive3 = Get-Partition -DiskNumber $VHDDrive.number -PartitionNumber $VHDXDrive3.PartitionNumber
    $VHDXVolume3 = [string]$VHDXDrive3.DriveLetter+":"


    # Find all instances of Install.Wim om THIS computer.
    # --
    $ExcludeDrives = @()
    $ExcludeDrives += $(($env:SystemDrive) -replace(":",""))
    $ExcludeDrives += $VHDXDrive1.DriveLetter
    $ExcludeDrives += $VHDXDrive3.DriveLetter
    #$ExcludeDrives += $(Get-Volume | Where-Object {$_.drivetype -eq 'CD-ROM'}).DriveLetter

    $Drives = Get-Volume | Where {$_.DriveLetter -notin $ExcludeDrives -and $_.DriveLetter -ne $null}
    $FoundImages = $Drives | foreach { (Get-ChildItem -Path "$($_.DriveLetter):\" -Recurse -filter "install.wim" -ErrorAction SilentlyContinue).fullname } | Where-Object { $_ }
    

    if ($FoundImages.GetType().IsArray) {

        $Images = @()
        Foreach ($Image in $FoundImages) {

            $ImageInfo = Get-WindowsImage -ImagePath $Image | Select-Object -Property ImageIndex, ImageName
            $ImageData = $ImageInfo | % { [PSCustomObject]@{ Name = $_.ImageName;  Index = $_.ImageIndex; Path = $Image } }
            $Images += $ImageData

        }
        $SelectedImage = $Images | Out-GridView -OutputMode Single

    } else {
        $ImageInfo = Get-WindowsImage -ImagePath $FoundImages | Select-Object -Property ImageIndex, ImageName | Out-GridView -OutputMode Single
        $SelectedImage = $ImageInfo | % { [PSCustomObject]@{ Name = $_.ImageName;  Index = $_.ImageIndex; Path = $FoundImages } }
    }


    # Expand Selected Server Image
    # ------------------------------------------------------------
    Expand-WindowsImage -ImagePath $SelectedImage.Path -Index $SelectedImage.Index -ApplyPath "$VHDXVolume3\" | Out-Null


    # Make boot files.
    # ------------------------------------------------------------
    & "$VHDXVolume3\Windows\system32\bcdboot.exe" "$VHDXVolume3\Windows" /s "$VHDXVolume1" /f UEFI | Out-Null


    # Find all Server 2025 drivers on all Media drives.
    # ------------------------------------------------------------
    $DriverSource = "$($ENV:TEMP)\Drivers"
    if (-Not(Test-Path -Path $DriverSource)) {
        New-Item -Path $DriverSource -ItemType Directory | Out-Null
    } else {
        Remove-Item -Path "$DriverSource\*" -Recurse -Force
    }
    Export-WindowsDriver -Online -Destination $DriverSource | Out-Null


    # Add Drivers
    # ------------------------------------------------------------
    $FoundDrivers = Get-ChildItem -Path $DriverSource -Recurse | Where {$_.Name -like "*inf"}
    $FoundDrivers | foreach { Add-WindowsDriver -Path "$VHDXVolume3" -Driver $_.FullName } | Out-Null


    # Add Default Unattend
    # ------------------------------------------------------------
    if (!(Test-Path -Path "$VHDXVolume3\Windows\Panther")) {
        New-Item -Path "$VHDXVolume3\Windows\Panther" -ItemType Directory | Out-Null
    }


    # Encode the FirstLogonCommands !
    # ------------------------------------------------------------
    $EncodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes("& `"C:\Scripts\FirstBoot.ps1`""))


    # Create Default Unattended
    # ------------------------------------------------------------
    New-Unattend -ComputerName "*" -FirstLogonCommands @(
            [PSCustomObject]@{ Name = "FirstBoot";  Command = "PowerShell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $EncodedCommand" }
        ) | Out-File -FilePath "$VHDXVolume3\Windows\Panther\unattend.xml" -Encoding utf8
    #notepad "$VHDXVolume3\Windows\Panther\unattend.xml"
    [XML]$Unattended = Get-Content -Path "$VHDXVolume3\Windows\Panther\unattend.xml"
    #(($Unattended.unattend.settings| ? {$_.pass -eq "oobeSystem"}).component | Where {$_.Name -like "*Setup"}).AutoLogon | Select-Object Username,@{Label="Password"; Expression={$_.password.Value}}

    $AutoLogon = (($Unattended.unattend.settings| ? {$_.pass -eq "oobeSystem"}).component | Where {$_.Name -like "*Setup"}).AutoLogon

    Write-Output "-----------------------------------------------------------------"
    Write-Output ""
    Write-Output "Please thake note of default credentials, might be needed for debugging"
    Write-Output ""
    Write-Output "Default Username : $($AutoLogon.Username)"
    Write-Output "Default Password : $($AutoLogon.Password.Value)"
    Write-Output ""
    Write-Output "-----------------------------------------------------------------"
   

    # Add Bootstrap Script
    # ------------------------------------------------------------
    if (!(Test-Path -Path "$VHDXVolume3\Scripts")) {
        New-Item -Path "$VHDXVolume3\Scripts" -ItemType Directory | Out-Null
    }

    Invoke-RestMethod -Uri "http://localhost/deployment/BuildScripts/Common/FirstBoot.ps1" -OutFile "$VHDXVolume3\Scripts\FirstBoot.ps1"
    <#
    ISE "$VHDXVolume3\Scripts\FirstBoot.ps1"
    #>


    # Save GIT Token to Image.
    # ------------------------------------------------------------
    #$GitConnection | ConvertTo-Json | Out-File "$VHDXVolume3\Scripts\GitHub-Connection.json" -Encoding utf8


    # Convert EVAL to Standard
    # ------------------------------------------------------------
    if ($SelectedImage.Name -like "*Eval*") {
        dism /image:$VHDXVolume3 /set-edition:ServerStandard
    }
    

    # Offline disk
    # ------------------------------------------------------------
    Get-Disk $VHDDrive.number | Set-Disk -IsOffline $true

}


<#

    Move OS disk back to template and convert.

#>


# Remove ISO
# ------------------------------------------------------------
$VMStatus = (Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($MasterID.Node)/qemu/$($MasterID.VmID)/config" -Headers $PVEConnect.Headers -Verbose:$false).data
$RemoveDrive = $VMStatus.PSObject.Properties | Where {$_.value -like "*$($ServerISO.volid)*"}
$null = Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($MasterID.Node)/qemu/$($MasterID.VmID)/config" -Body "delete=$($RemoveDrive.Name)&force" -Headers $PVEConnect.Headers -Method Post


# Move Disk to template.
# ------------------------------------------------------------
#$OrgDiskID = Reassign-PVEOwner -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers -SourceNode $MasterID.Node -SourceVM $MasterID.VmID -TargetVM $TemplateID -SourceDisk $TmpDiskID -Wait
$OrgDiskID = Reassign-PVEOwner -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers -SourceNode $MasterID.Node -SourceVM $MasterID.VmID -TargetVM $TemplateID -SourceDisk $DiskId -Wait


# Add virtio0 to boot..
# ------------------------------------------------------------
$Body = "boot=$([uri]::EscapeDataString("order=$OrgDiskID"))"
$body += "&name=$(($SelectedImage.Name -split(`" `"))[2,3] -join(`"-`"))"
$null = Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($MasterID.Node)/qemu/$TemplateID/config" -Body $Body -Method POST -Headers $($PVEConnect.Headers)


# Convert TO template
# ------------------------------------------------------------
$null = Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($MasterID.Node)/qemu/$TemplateID/template" -Method POST -Headers $($PVEConnect.Headers)
