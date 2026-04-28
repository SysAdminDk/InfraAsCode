<#

    Pre Execution requirements.
    1. Download latest Windows Server 2025 install media.
        - Mount ISO, and copy content to "D:\TS-Data\Server Reference\Server 2025 Files"

    2. Get Drivers from Physical Node (Manufacture install, and export drivers)
        - Copy drivers to "D:\TS-Data\Server Reference\Windows Drivers"


    This script will do the following.
    1. Extract Server Datacenter from WIM
    2. Add Required Drivers
    3. Add AutoUnattend.xml
    4. Add NODE setup script

#>
#break

$ProductKey = "N6W6X-H4P77-RJYTG-W77HT-RRKXT"


# Hyper-V Nodes.
$Nodes = @(
    [PSCustomObject]@{ Node = "HV-NODE-01"; IPAddress = "10.36.100.201"; Subnet = "255.255.255.0"; Gateway = "10.36.100.1"; DNSServers = @("8.8.8.8","8.8.4.4"); Interfaces = @("BC:24:11:E3:40:79","BC:24:11:E1:48:AC","BC:24:11:B2:07:17","BC:24:11:FF:D1:8A");  }
    [PSCustomObject]@{ Node = "HV-NODE-02"; IPAddress = "10.36.100.211"; Subnet = "255.255.255.0"; Gateway = "10.36.100.1"; DNSServers = @("8.8.8.8","8.8.4.4"); Interfaces = @("BC:24:11:D9:12:71","BC:24:11:01:B8:82","BC:24:11:77:43:7C","BC:24:11:F0:18:E8");  }
)


# Azure Local Nodes.
#$Nodes = @(
#    [PSCustomObject]@{ Node = "AZ-NODE-01"; IPAddress = "10.36.100.221"; Subnet = "255.255.255.0"; Gateway = "10.36.100.1"; DNSServers = @("10.36.100.11","10.36.100.11"); Interfaces = @("BC:24:11:DF:39:80","BC:24:11:9C:FB:CA","BC:24:11:CF:8A:42","BC:24:11:07:7A:A4");  }
#    [PSCustomObject]@{ Node = "AZ-NODE-02"; IPAddress = "10.36.100.231"; Subnet = "255.255.255.0"; Gateway = "10.36.100.1"; DNSServers = @("10.36.100.11","10.36.100.11"); Interfaces = @("BC:24:11:1D:F0:90","BC:24:11:31:9A:BE","BC:24:11:5C:38:98","BC:24:11:9B:B4:69");  }
#    [PSCustomObject]@{ Node = "AZ-NODE-03"; IPAddress = "10.36.100.241"; Subnet = "255.255.255.0"; Gateway = "10.36.100.1"; DNSServers = @("10.36.100.11","10.36.100.11"); Interfaces = @("BC:24:11:25:1C:33","BC:24:11:4D:B5:E8","BC:24:11:45:B7:A0","BC:24:11:76:6A:D6");  }
#)


$TemplatePath = "D:\TS-Data\$($Nodes.node[0].Substring(0,2))-NODES"
$ShortPath = Split-Path -Path $TemplatePath -Leaf
$ISOFiles = "$(Split-Path -Path $TemplatePath)\ISO Files"
$MountPath = "D:\TS-Data\mount"


# Ensure all Directories exist.
# ------------------------------------------------------------
If (!(Test-Path -Path $TemplatePath)) {
    New-Item -Path $TemplatePath -ItemType Directory | Out-Null
}
If (!(Test-Path -Path $ISOFiles)) {
    New-Item -Path $ISOFiles -ItemType Directory | Out-Null
}
If (!(Test-Path -Path $MountPath)) {
    New-Item -Path $MountPath -ItemType Directory | Out-Null
}


# Locate the Data Drive.
# ------------------------------------------------------------
$ExcludeDrives = @()
$ExcludeDrives += $(($env:SystemDrive) -replace(":",""))
$ExcludeDrives += $(Get-Volume | Where-Object {$_.drivetype -eq 'CD-ROM'}).DriveLetter

$Drives = Get-Volume | Where {$_.DriveLetter -notin $ExcludeDrives -and $_.DriveLetter -ne $null}


# Find all instances of Install.Wim om THIS computer.
# ------------------------------------------------------------
$FoundImages = $Drives | foreach { (Get-ChildItem -Path "$($_.DriveLetter):\" -Recurse -filter "install.wim" -ErrorAction SilentlyContinue).FullName }
$FoundImages = $FoundImages | Where {$_ -notlike "*$TemplatePath*"}


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


# Copy Installation files.
# ------------------------------------------------------------
Copy-Item -Path "$(Split-Path (Split-Path $SelectedImage.path))\*" -Destination $TemplatePath -Recurse -Exclude @("*install.wim*") -Force


# Copy Startup Scripts
# ------------------------------------------------------------
if (!(Test-Path -Path "$TemplatePath\Sources\`$OEM`$\`$1\TS-Data")) {
    New-Item -Path "$TemplatePath\Sources\`$OEM`$\`$1\TS-Data" -ItemType Directory | Out-Null
}
Copy-Item "C:\Scripts\PrepNode.ps1" -Destination "$TemplatePath\Sources\`$OEM`$\`$1\TS-Data" -Force


# Extract Server WIM
# ------------------------------------------------------------
if (Test-Path -Path "$TemplatePath\Sources\Install.wim") {
    Remove-Item -Path "$TemplatePath\Sources\Install.wim" -Force
}
if (!(Test-Path -Path "$TemplatePath\Sources\Install.wim")) {
    Export-WindowsImage -SourceImagePath $($SelectedImage.Path) -SourceIndex $($SelectedImage.Index) -DestinationImagePath "$TemplatePath\Sources\Install.wim" -DestinationName $($SelectedImage.Name) | Out-Null
} else {
    throw "Install wim still exists"
}


# Mount Image
# ------------------------------------------------------------
Mount-WindowsImage -ImagePath "$TemplatePath\Sources\Install.wim" -Index 1 -Path $MountPath | Out-Null


# Find OEM drivers.
# ------------------------------------------------------------
$FoundDrivers = $Drives | foreach { Get-ChildItem -Path "$($_.DriveLetter):\" -Recurse -ErrorAction SilentlyContinue }
$FoundDrivers = $FoundDrivers | Where {$_.FullName -like "*2K25*" -and $_.FullName -like "*amd*"-and $_.Name -like "*inf"}
$FoundDrivers = $FoundDrivers | Where {$_.Name -ne "pvpanic-pci.inf" -and $_.Name -ne "smbus.inf"} | Select-Object -Unique


# Add Drivers to Install.WIM
# ------------------------------------------------------------
$FoundDrivers | foreach { Add-WindowsDriver -Path $MountPath -Driver $_.FullName } | Out-Null


# Set PowerConfig
# ------------------------------------------------------------
## ??? Registry ???


# Enable Hyper-V.
# ------------------------------------------------------------
Get-WindowsOptionalFeature -Path $MountPath -FeatureName *Hyper-V* | ForEach-Object {
    Try {
        Enable-WindowsOptionalFeature -Path $MountPath -FeatureName $_.FeatureName -All -ErrorAction Stop | Out-Null
    } Catch {
        Write-Verbose "Skipping feature $($_.FeatureName): $_"
    }
}



# Enable Clustering.
# ------------------------------------------------------------
if ($Nodes.Name[0] -like "AZ*") {
    Get-WindowsOptionalFeature -Path $MountPath -FeatureName *Cluster* | ForEach-Object {
        Try {
            Enable-WindowsOptionalFeature -Path $MountPath -FeatureName $_.FeatureName -All -ErrorAction Stop | Out-Null
        } Catch {
            Write-Verbose "Skipping feature $($_.FeatureName): $_"
        }
    }
}


# Save image
# ------------------------------------------------------------
Dismount-WindowsImage -Path $MountPath -Save | Out-Null


# Add Storage Drivers to BOOT.wim
# ------------------------------------------------------------
Mount-WindowsImage -ImagePath "$TemplatePath\sources\boot.wim" -Index 2 -Path $MountPath | Out-Null
$FoundDrivers | Where {$_.name -match "vioscsi|viostor"} | foreach { Add-WindowsDriver -Path $MountPath -Driver $_.fullname } | Out-Null


# Save Boot image
# ------------------------------------------------------------
Dismount-WindowsImage -Path $MountPath -Save | Out-Null


# Import module New-ISOFIle.ps1
# - Source : https://github.com/TheDotSource/New-ISOFile/blob/main/New-ISOFile.ps1
# ------------------------------------------------------------
Import-Module -Name "C:\SCRIPTS\Functions\New-ISOFile.ps1" -Force -Verbose
Import-Module -Name "C:\SCRIPTS\Functions\new-Unattend.ps1" -Force -Verbose


foreach ($Node in $Nodes) {

    # Add AutoUnattend
    # ------------------------------------------------------------
    if (Test-Path -Path $TemplatePath) {

        # -ProductKey "N6W6X-H4P77-RJYTG-W77HT-RRKXT" 
        New-Unattend -ComputerName $Node.Node -RunAtStartup "PrepNode.ps1" -Interfaces $Node.Interfaces -ProductKey $ProductKey `
            -IPAddress $Node.IPAddress -SubnetMask $Node.Subnet -Gateway $Node.Gateway -DNSServers $Node.DNSServers | Out-File "$TemplatePath\AutoUnattend.xml" -Encoding utf8 -Force
    }

    
    # Make ISO
    # ------------------------------------------------------------ 
    #New-ISOFile -source "HV-NODES" -destinationIso "$($Node)-2025DC.iso" -bootFile "HV-NODES\efi\microsoft\boot\efisys.bin" -title "$($Node)-2025DC" -force
    if (Test-Path -Path $ISOFiles) {
        New-ISOFile -source $TemplatePath -destinationIso "$ISOFiles\$($Node.Node).iso" -bootFile "$TemplatePath\efi\microsoft\boot\efisys_noprompt.bin" -title "$($Node.Node)" -force
    }

}
