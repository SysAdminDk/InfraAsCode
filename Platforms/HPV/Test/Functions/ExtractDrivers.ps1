<#

    Copy script to running server to extract Suplier Drivers.

#>


# Find USB drive, where to copy the extracted drivers.
# ------------------------------------------------------------
$DriveLetter = $(Get-WmiObject -Class Win32_volume -Filter "DriveType = '2'").DriveLetter

if (!($DriveLetter)) {

    Write-Warning "USB drive not found, unable to copy drivers"

} else {

    # Extract drivers
    # ------------------------------------------------------------
    Export-WindowsDriver -Destination "$DriveLetter" -Online -Verbose

}


Get-NetAdapter -Physical | Select-Object -Property Name,MacAddress,LinkSpeed | ConvertTo-Json | Out-File "$DriveLetter\NetAdapters.json"
