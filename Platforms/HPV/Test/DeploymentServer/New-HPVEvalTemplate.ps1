<#

    Download and create Windows Server refrence WIMs

#>

Invoke-WebRequest -Uri "https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso" -OutFile "D:\Windows_Server_2025_eval.iso"


# Where to save the VHDx files.
# ------------------------------------------------------------
$VHDXPath  = "D:\TS-Data\Reference"
$DiskImage = "D:\en-us_windows_server_2025_updated_aug_2025_x64_dvd_9236d79b.iso"


# Create Template directory
# ------------------------------------------------------------
if (!(Test-Path $VHDXPath)) {
    New-Item -Path $VHDXPath -ItemType Directory | Out-Null
}


# Mount ISO to extract WIM.
# ------------------------------------------------------------
if (Test-Path $DiskImage) {
	Mount-DiskImage -ImagePath $DiskImage | Out-Null
	$MountDrive = $((Get-DiskImage -ImagePath $DiskImage | get-volume).DriveLetter) + ":"
}




    $ExcludeDrives = @()
    $ExcludeDrives += $(($env:SystemDrive) -replace(":",""))
    $ExcludeDrives += $VHDXDrive1.DriveLetter
    $ExcludeDrives += $VHDXDrive3.DriveLetter
    $ExcludeDrives += $(Get-Volume | Where-Object {$_.drivetype -eq 'CD-ROM'}).DriveLetter

    $Drives = Get-Volume | Where {$_.DriveLetter -notin $ExcludeDrives -and $_.DriveLetter -ne $null}
    $FoundImages = $Drives | foreach { (Get-ChildItem -Path "$($_.DriveLetter):\" -Recurse -filter "install.wim" -ErrorAction SilentlyContinue).fullname }


    if ($FoundImages.Count -gt 1) {

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






# Get Windows Server Standard Desktop image index.
# ------------------------------------------------------------
$WinVersions = Get-WindowsImage -ImagePath "$MountDrive\Sources\install.wim"
$WinVersions | Where { $_.ImageName -like "*Standard*Desktop*" } | foreach {

	# Create New VHDx
    $VHDFileName = $_.ImageName -replace(" \(Desktop Experience\)","")
    $VHDXFile = Join-Path -Path $VHDXPath -ChildPath $($VHDFileName + ".vhdx")
    $ImageIndex = $($_.ImageIndex)

    if (!(Test-Path $VHDXFile)) {

	    New-VHD -Path $VHDXFile -Dynamic -SizeBytes 50Gb | Out-Null
	    Mount-DiskImage -ImagePath $VHDXFile

	    $VHDXDisk = Get-DiskImage -ImagePath $VHDXFile | Get-Disk
	    $VHDXDiskNumber = [string]$VHDXDisk.Number

	    # Create Partitions
	    Initialize-Disk -Number $VHDXDiskNumber -PartitionStyle GPT
        Get-Partition -DiskNumber $VHDXDiskNumber | Remove-Partition -Confirm:$false

        $VHDXDrive1 = New-Partition -DiskNumber $VHDXDiskNumber -GptType  "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" -AssignDriveLetter -Size 100Mb
        $VHDXDrive1 | Format-Volume -FileSystem FAT32 -NewFileSystemLabel System -Confirm:$false | Out-null
        $VHDXDrive2 = New-Partition -DiskNumber $VHDXDiskNumber -GptType "{e3c9e316-0b5c-4db8-817d-f92df00215ae}" -Size 16Mb
        $VHDXDrive3 = New-Partition -DiskNumber $VHDXDiskNumber -UseMaximumSize -AssignDriveLetter
        $VHDXDrive3 | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false | Out-null

        # Add Drive letters
        # ------------------------------------------------------------
        $VHDXDrive1 = Get-Partition -DiskNumber $VHDXDiskNumber -PartitionNumber $VHDXDrive1.PartitionNumber
        $VHDXVolume1 = [string]$VHDXDrive1.DriveLetter+":"

        $VHDXDrive3 = Get-Partition -DiskNumber $VHDXDiskNumber -PartitionNumber $VHDXDrive3.PartitionNumber
        $VHDXVolume3 = [string]$VHDXDrive3.DriveLetter+":"

	    # Extract Server image, and apply to VHDx
	    Expand-WindowsImage -ImagePath "$MountDrive\Sources\install.wim" -Index $ImageIndex -ApplyPath $VHDXVolume3\ -ErrorAction Stop -LogPath Out-Null

	    # Apply BootFiles
        & "$VHDXVolume3\Windows\system32\bcdboot.exe" "$VHDXVolume3\Windows" /s "$VHDXVolume1" /f UEFI | Out-Null


        # Add default Unattend
        # ------------------------------------------------------------




        if (!(Test-Path -Path "$VHDXVolume3\Windows\Panther")) {
            New-Item -Path "$VHDXVolume3\Windows\Panther" -ItemType Directory | Out-Null
        }


	    Dismount-DiskImage -ImagePath $VHDXFile | Out-Null
    }

	Dismount-DiskImage -ImagePath $DiskImage | Out-Null
}