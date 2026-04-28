<#

    Configure Fabric HyperV node

#>

# Get Admin Password from Registry, and save to Desktop
# ------------------------------------------------------------
if (!((gwmi win32_computersystem).partofdomain)) {
    $Password = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultPassword" -ErrorAction SilentlyContinue
    if ($Password) {
        $Password | Out-File -FilePath "$($ENV:ALLUSERSPROFILE)\Desktop\DefaultPassword.txt" -Encoding utf8
    }
}


# Get windows version from registry.
# ------------------------------------------------------------
$WindowsVersion = (Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "ProductName").ProductName


# Enable RDP
# ------------------------------------------------------------
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Force
Get-NetFirewallRule -Name "RemoteDesktop-UserMode-In-UDP" | Enable-NetFirewallRule
Get-NetFirewallRule -Name "RemoteDesktop-UserMode-In-TCP" | Enable-NetFirewallRule


# Install Required Roles
# ------------------------------------------------------------
#if (!(Get-Command -Name New-VMSwitch -ErrorAction SilentlyContinue)) {
#    Get-WindowsFeature -Name *Hyper-V* | Install-WindowsFeature -IncludeManagementTools
#}


if (Get-Command -Name New-VMSwitch -ErrorAction SilentlyContinue) {

    if ($WindowsVersion -like "Windows Server 2025*") {

        # Create UPLink Switch
        # ------------------------------------------------------------
        $UplinkInterface = Get-NetAdapter -Physical | Where-Object {$_.Status -EQ "UP"}
        $CurrentIP = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $UplinkInterface.ifIndex
        Get-NetAdapter -InterfaceIndex $UplinkInterface.ifIndex | Rename-NetAdapter -NewName "Uplink Network 1"

        if ((Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\$($UplinkInterface.PnPDeviceID)").FriendlyName -ne "Red Hat VirtIO Uplink Interface 1") {
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\$($UplinkInterface.PnPDeviceID)" -Name "FriendlyName" -Value "Red Hat VirtIO Uplink Interface 1"
        }

        New-VMSwitch -Name "UplinkSwitch" -AllowManagementOS $true -MinimumBandwidthMode Weight -EnableEmbeddedTeaming $true -NetAdapterName $(Get-NetAdapter -InterfaceIndex $UplinkInterface.ifIndex).name
        Get-VMNetworkAdapter -ManagementOS | Set-VMNetworkAdapter -DeviceNaming On


        # Add Uplink Interface
        # ------------------------------------------------------------
        $UplinkInterface = Get-NetAdapter -Physical | Where-Object {$_.Status -ne "UP"} | Out-GridView -Title "Select additional Uplink Adapter" -OutputMode Single
        $UplinkInterface = $Selected
        Enable-NetAdapter -Name $UplinkInterface.Name
        Get-NetAdapter -InterfaceIndex $UplinkInterface.ifIndex | Rename-NetAdapter -NewName "Uplink Network 2"

        if ((Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\$($UplinkInterface.PnPDeviceID)").FriendlyName -ne "Red Hat VirtIO Uplink Interface 2") {
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\$($UplinkInterface.PnPDeviceID)" -Name "FriendlyName" -Value "Red Hat VirtIO Uplink Interface 2"
        }

        Add-VMSwitchTeamMember -VMSwitchName "UplinkSwitch" -NetAdapterName $(Get-NetAdapter -InterfaceIndex $UplinkInterface.ifIndex).name
    
    }


    # Allow PING and Hyper-V replica.
    # ------------------------------------------------------------
    Get-NetFirewallRule | Where {$_.Name -like "*ICMP4*" -AND $_.Profile -match 'Public|Domain' -AND $_.Direction -eq "Inbound"} | Set-NetFirewallRule -Enabled True
    Get-NetFirewallRule | Where {$_.Name -like "VIRT-HVRHTTP*" -AND $_.Direction -eq "Inbound"} | Set-NetFirewallRule -Enabled True


    # Move Media Drive Letter.
    # - If any MEDIA Drive on D, change the drive letter
    # ------------------------------------------------------------
    $MediaDrive = Get-WmiObject -Class Win32_volume -Filter "DriveType = '5' and DriveLetter = 'D:'"
    if ($null -ne $MediaDrive) {
        Set-WmiInstance -InputObject $MediaDrive -Arguments @{DriveLetter='X:'} | Out-Null
    }

    
    # Only Enable Hyper-V Replica and create Hyper-V Volume if Server 2025 Datacenter
    # ------------------------------------------------------------
    if ($WindowsVersion -like "Windows Server 2025*") {

        # Create HyperV Data volume
        # ------------------------------------------------------------
        Get-Disk | Where {$_.PartitionStyle -eq "RAW" -and $_.Size -gt "100Gb"} | Initialize-Disk -PassThru | New-Partition -UseMaximumSize -DriveLetter D | Format-Volume -FileSystem NTFS -NewFileSystemLabel "NTDS Disk" -Confirm:$false


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
}
