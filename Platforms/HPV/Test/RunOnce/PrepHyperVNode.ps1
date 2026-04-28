<#

    Configure Fabric HyperV node

#>

# Ensure we have Hyper-V installed.
# ------------------------------------------------------------
if (Get-Command -Name New-VMSwitch -ErrorAction SilentlyContinue) {


    # Create VM Switch
    # ------------------------------------------------------------
    $Interface = Get-NetAdapter -Physical | Where-Object {$_.Status -EQ "UP"} #| Sort-Object -Property InterfaceDescription
    if ($Interface.count -gt 1) {
        $Interface = $Interface[0]
    }
    $CurrentIP = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $Interface.ifIndex
    Get-NetAdapter -InterfaceIndex $Interface.ifIndex | Rename-NetAdapter -NewName "Uplink Network 1"

    if ((Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\$($Interface.PnPDeviceID)").FriendlyName -ne "Red Hat VirtIO Uplink Interface 1") {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\$($Interface.PnPDeviceID)" -Name "FriendlyName" -Value "Red Hat VirtIO Uplink Interface 1"
    }

    New-VMSwitch -Name "Uplink Switch" -AllowManagementOS $true -MinimumBandwidthMode Weight -EnableEmbeddedTeaming $true -NetAdapterName $(Get-NetAdapter -InterfaceIndex $Interface.ifIndex).name
    Get-VMNetworkAdapter -ManagementOS | Set-VMNetworkAdapter -DeviceNaming On


    # Add Uplink Interface
    # ------------------------------------------------------------
    $Interfaces = Get-NetAdapter -Physical | Where-Object {$_.Status -ne "UP"}
    if ($Interfaces.count -gt 1) {
        $SelectedInterface = $Interfaces | Out-GridView -Title "Select additional Uplink Adapter" -OutputMode Single
    } else {
        $SelectedInterface = $Interfaces
    }
    if ($SelectedInterface) {
        Enable-NetAdapter -Name $SelectedInterface.Name
        Get-NetAdapter -InterfaceIndex $SelectedInterface.ifIndex | Rename-NetAdapter -NewName "Uplink Network 2"

        if ((Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\$($UplinkInterface.PnPDeviceID)").FriendlyName -ne "Red Hat VirtIO Uplink Interface 2") {
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\$($UplinkInterface.PnPDeviceID)" -Name "FriendlyName" -Value "Red Hat VirtIO Uplink Interface 2"
        }

        Get-VMSwitch | Add-VMSwitchTeamMember -NetAdapterName $(Get-NetAdapter -InterfaceIndex $SelectedInterface.ifIndex).name
    }    


    # Allow PING and Hyper-V replica.
    # ------------------------------------------------------------
    Get-NetFirewallRule | Where {$_.Name -like "*ICMP4*" -AND $_.Direction -eq "Inbound"} | Set-NetFirewallRule -Enabled True
    Get-NetFirewallRule | Where {$_.Name -like "VIRT-HVRHTTP*" -AND $_.Direction -eq "Inbound"} | Set-NetFirewallRule -Enabled True


    # Move Media Drive Letter.
    # - If any MEDIA Drive on D, change the drive letter
    # ------------------------------------------------------------
    $MediaDrive = Get-WmiObject -Class Win32_volume -Filter "DriveType = '5' and DriveLetter = 'D:'"
    if ($null -ne $MediaDrive) {
        Set-WmiInstance -InputObject $MediaDrive -Arguments @{DriveLetter='X:'} | Out-Null
    }

    
    # Create HyperV Data volume
    # ------------------------------------------------------------
    Get-Disk | Where {$_.PartitionStyle -eq "RAW" -and $_.Size -gt "100Gb"} | Initialize-Disk -PassThru | New-Partition -UseMaximumSize -DriveLetter D | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Data" -Confirm:$false


    # Prepare Hyper-V Replica.
    # ------------------------------------------------------------
    $Result = Get-Volume | Where {$_.Size -gt "100Gb"}
    $VMReplicaLocation = "$($Result.driveletter):\VMReplica"


    If (!(Test-Path "$VMReplicaLocation")) {
        New-Item -Path $VMReplicaLocation -ItemType Directory | Out-Null
    }

    Set-VMReplicationServer -ReplicationEnabled $true -AllowedAuthenticationType Kerberos -KerberosAuthenticationPort 80 -ReplicationAllowedFromAnyServer $true -DefaultStorageLocation $VMReplicaLocation


    # Set Default VM storage location
    # ------------------------------------------------------------
    $VMLocation = "$($Result.driveletter):\VMData"
    If (!(Test-Path "$VMLocation")) {
        New-Item -Path $VMLocation -ItemType Directory | Out-Null
    }
}


# Clear Autologin
# ------------------------------------------------------------
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -Value '0' -ErrorAction SilentlyContinue


# Cleanup System drive
# ------------------------------------------------------------
if (Test-Path -Path "$($ENV:SystemDrive)\Windows.old") {
    Remove-Item -Path "$($ENV:SystemDrive)\Windows.old" -Force
}


# Change Administrator password and show on screen.
# ------------------------------------------------------------
if (!((gwmi win32_computersystem).partofdomain)) {
    $NewPassword = $(-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 15 | ForEach-Object {[char]$_}))
    $SecurePassword = ConvertTo-SecureString -string $NewPassword -AsPlainText -Force
    Set-LocalUser -Name Administrator -Password $SecurePassword

    $PwdCmd = @()
    $PwdCmd += "Write-Host `"=== IMPORTANT: Temporary local admin password ===`"`r`n" 
    $PwdCmd += "write-host `"`"`r`n" 
    $PwdCmd += "write-host `"Username : Administrator`r`n"
    $PwdCmd += "write-host `"Password : $NewPassword`r`n"
    $PwdCmd += "write-host `"`"`r`n" 
    $PwdCmd += "Write-Host `"Please take a note of it or change to a known`"`r`n" 
    $PwdCmd += "Write-Host `"RDP access is avalible on $($CurrentIP.IPAddress)`"`r`n" 
    $PwdCmd += "write-host `"`"`r`n" 
    $PwdCmd += "Read-Host -Prompt 'Press ENTER to close this window'`r`n" 
    $PwdCmd += "exit`r`n"

    Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoExit -Command $PwdCmd"

}
