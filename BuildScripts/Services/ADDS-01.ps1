<#
    ______                      _         _____             _             _ _               
    |  _  \                    (_)       /  __ \           | |           | | |          
    | | | |___  _ __ ___   __ _ _ _ __   | /  \/ ___  _ __ | |_ _ __ ___ | | | ___ _ __ 
    | | | / _ \| '_ ` _ \ / _` | | '_ \  | |    / _ \| '_ \| __| '__/ _ \| | |/ _ \ '__|
    | |/ / (_) | | | | | | (_| | | | | | | \__/\ (_) | | | | |_| | | (_) | | |  __/ |   
    |___/ \___/|_| |_| |_|\__,_|_|_| |_|  \____/\___/|_| |_|\__|_|  \___/|_|_|\___|_| 


    Install & Configure FIRST Domain Controller.

#>

<#

    Workgroup taks.
    1. Enable Autologin if not already.
    2. Add RunOnce if not already
    3. Install ADDS.
    4. Create Domain.

#>


# Get Data from Json Config
# ------------------------------------------------------------
If (Test-Path -Path "$PSScriptRoot\ServerConfig.json") {
    $ServerConfig = Get-Content -Path "$PSScriptRoot\ServerConfig.json" | ConvertFrom-Json
}


if (!((Get-WmiObject -Class win32_computersystem).partofdomain)) {


    # Create Active Directory Domain, with Random restore mode password, will be handled with Windows Laps later.
    # ------------------------------------------------------------
    $PWString = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 25 | ForEach-Object {[char]$_})
    $SecurePassword = ConvertTo-SecureString -string $PWString -AsPlainText -Force
    Install-ADDSForest -DomainName $ServerConfig.JoinOptions.UserDNSDomain -SafeModeAdministratorPassword $SecurePassword -force -InstallDNS -DomainNetbiosName $ServerConfig.JoinOptions.UserDomain


    # Change Task to Restart
    # ------------------------------------------------------------
    if ($ServerConfig) {
        ($ServerConfig.Tasks | Where-Object { $_.Name -eq "ADDS-01.ps1" }).status = "Restart"
        $ServerConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath "$RootPath\ServerConfig.json" -Encoding utf8 -Force
    }


    # Wait for Restart
    # ------------------------------------------------------------
    Write-Output "Waiting for Domain Creation, and restart"
    Start-Sleep -Seconds 300

}


<#

    PDC Tasks.
    1. Create DNS Zone
    2. Create Reverse Zone
    3. Create Truesec Active Directory Tiering
    4. GPOs
    5. Add LAPS to DCs
    6. Copy PolicyDefinitions to Central Store
    7. Copy Desired State Configurations to Central Store
    8. Install and Configure Windows Backup, System State

#>
# Run after Domain have been created.
# ------------------------------------------------------------
if ((Get-WmiObject -Class win32_computersystem).DomainRole -eq 5) {

    $DownloadFolder = "$($ENV:USERPROFILE)\Downloads"
    $DomainInfo = Get-ADDomain
    

    # Get current network configuration
    # ------------------------------------------------------------
    $NetAdapter = Get-NetAdapter | Where {$_.Status -eq "UP"} | Select-Object -First 1
    $CurrentIP = $NetAdapter | Get-NetIPAddress -AddressFamily IPv4


    # Add Reverse lookup DNS Zone
    # ------------------------------------------------------------
    $DNSZone = (($CurrentIP.IPAddress -split("\.")) | Select-Object -SkipLast 1) -join(".")
    $DNSZoneReverse = $DNSZone -split("\.")
    [array]::Reverse($DNSZoneReverse)
    $DNSZoneReverse = $DNSZoneReverse -join(".")
    $IPSubnet = "$DNSZone.0/$($CurrentIP.PrefixLength)"

    if (!(Get-DnsServerZone -Name "$DNSZoneReverse.in-addr.arpa" -ErrorAction SilentlyContinue)) {
        Add-DnsServerPrimaryZone -NetworkID $IPSubnet -ReplicationScope "Forest"
    }


    # Create DNS Subnet
    # ------------------------------------------------------------
    $SiteName = (Get-ADReplicationSite).Name
    if (!(Get-ADReplicationSubnet -Filter "Name -like '*$IPSubnet*'")) {
        New-ADReplicationSubnet -Name $IPSubnet -Site $SiteName
    }


    # Create Deployment Server DNS record.
    # ------------------------------------------------------------
    $DeploymentAddress = (Resolve-DnsName -Name Deployment -Server 10.36.1.1 -Type A).IPAddress
    Add-DnsServerResourceRecordA -Name "Deployment" -IPv4Address $DeploymentAddress -ZoneName $ServerConfig.JoinOptions.UserDNSDomain


    # Create GPO - Disable Server Manager
    # ------------------------------------------------------------
    if (-NOT (Get-GPO -Name "Admin - Disable Server Manager" -ErrorAction SilentlyContinue)) {
        $GPO = New-GPO -Name "Admin - Disable Server Manager"
        Get-GPO -Name $GPO.DisplayName | New-GPLink -Target $DomainInfo.DomainControllersContainer -LinkEnabled Yes | Out-Null
        if ($GPOTargets) {
            $GPOTargets | % { Get-GPO -Name $GPO.DisplayName | New-GPLink -Target $_ }
        }
        (Get-GPO -Name $GPO.DisplayName).GpoStatus = "UserSettingsDisabled"

        Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\Software\Policies\Microsoft\Windows\Server\ServerManager" -ValueName DoNotOpenAtLogon -Value 1 -Type DWord | Out-Null
        Set-GPPrefRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Microsoft\ServerManager" -ValueName "DoNotOpenServerManagerAtLogon" -Value 1 -Type DWord -Context Computer -Action Update | Out-Null
        Set-GPPrefRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Microsoft\ServerManager" -ValueName "DoNotPopWACConsoleAtSMLaunch" -Value 1 -Type DWord -Context Computer -Action Update | Out-Null
    }


    # Create GPO - Enable Remote Desktop
    # ------------------------------------------------------------
    if (!((Get-GPInheritance -Target $DomainInfo.DomainControllersContainer).gpolinks | Where {$_.displayname -like "*Enable Remote Desktop*"})) {
        
        # Tiering not executed, make sure we can RDP to the servers.
        # ------------------------------------------------------------
        $GPO = New-GPO -Name "Admin - Enable Remote Desktop"
        Get-GPO -Name $GPO.DisplayName | New-GPLink -Target $DomainInfo.DomainControllersContainer -LinkEnabled Yes | Out-Null
        Get-GPO -Name $GPO.DisplayName | New-GPLink -Target $DomainInfo.DistinguishedName -LinkEnabled Yes | Out-Null
        (Get-GPO -Name $GPO.DisplayName).GpoStatus = "UserSettingsDisabled"

        Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -ValueName "fDenyTSConnections" -Value 0 -Type DWord | Out-Null
        Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\FirewallRules" -ValueName "RemoteDesktop-UserMode-In-UDP" -Value "v2.31|Action=Allow|Active=TRUE|Dir=In|Protocol=17|LPort=3389|App=%SystemRoot%\system32\svchost.exe|Svc=termservice|Name=@FirewallAPI.dll,-28776|Desc=@FirewallAPI.dll,-28777|EmbedCtxt=@FirewallAPI.dll,-28752|" -Type String | Out-Null
        Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\FirewallRules" -ValueName "RemoteDesktop-UserMode-In-TCP" -Value "v2.31|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=3389|App=%SystemRoot%\system32\svchost.exe|Svc=termservice|Name=@FirewallAPI.dll,-28775|Desc=@FirewallAPI.dll,-28756|EmbedCtxt=@FirewallAPI.dll,-28752|" -Type String | Out-Null
        Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\FirewallRules" -ValueName "RemoteDesktop-Shadow-In-TCP" -Value "v2.31|Action=Allow|Active=TRUE|Dir=In|Protocol=6|App=%SystemRoot%\system32\RdpSa.exe|Name=@FirewallAPI.dll,-28778|Desc=@FirewallAPI.dll,-28779|EmbedCtxt=@FirewallAPI.dll,-28752|Edge=TRUE|Defer=App|" -Type String | Out-Null
    }


    # Create GPO - Cleanup Server Desktop
    # ------------------------------------------------------------
    if (-NOT (Get-GPO -Name "User - Cleanup Server Desktop" -ErrorAction SilentlyContinue)) {
        $GPO = New-GPO -Name "User - Cleanup Server Desktop"
        Get-GPO -Name $GPO.DisplayName | New-GPLink -Target $DomainInfo.DomainControllersContainer -LinkEnabled Yes | Out-Null
        (Get-GPO -Name $GPO.DisplayName).GpoStatus = "ComputerSettingsDisabled"

        Set-GPPrefRegistryValue -Name $GPO.DisplayName -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValueName HideFileExt -Value 0 -Type DWord -Action Update -Context User | Out-Null
        Set-GPPrefRegistryValue -Name $GPO.DisplayName -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValueName ShowTaskViewButton -Value 0 -Type DWord -Action Update -Context User | Out-Null
        Set-GPPrefRegistryValue -Name $GPO.DisplayName -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" -ValueName SearchboxTaskbarMode -Value 0 -Type DWord -Action Update -Context User | Out-Null
        Set-GPPrefRegistryValue -Name $GPO.DisplayName -Key "HKCU\Control Panel\Desktop" -ValueName UserPreferencesMask -Value ([byte[]](0x90,0x32,0x07,0x80,0x10,0x00,0x00,0x00)) -Type Binary -Context User -Action Update | Out-Null
    }


    # Create GPO - Disable Cortana
    # ------------------------------------------------------------
    if (-NOT (Get-GPO -Name "Computer - Disable Cortana" -ErrorAction SilentlyContinue)) {
        $GPO = New-GPO -Name "Computer - Disable Cortana"
        Get-GPO -Name $GPO.DisplayName | New-GPLink -Target $DomainInfo.DistinguishedName -LinkEnabled Yes | Out-Null
        (Get-GPO -Name $GPO.DisplayName).GpoStatus = "UserSettingsDisabled"

        Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -ValueName AllowCortana -Value 0 -Type DWord | Out-Null
    }


    # Update Schema with Windows Laps.
    # ------------------------------------------------------------
    Update-LapsADSchema -confirm:0


    # Create Windows Laps Policy
    # ------------------------------------------------------------
    if (-NOT (Get-GPO -Name "MSFT - Windows LAPS Domain Controller" -ErrorAction SilentlyContinue)) {
        $GPO = New-GPO -Name "MSFT - Windows LAPS Domain Controller"
        Get-GPO -Name $GPO.DisplayName | New-GPLink -Target $DomainInfo.DomainControllersContainer -LinkEnabled Yes | Out-Null
        (Get-GPO -Name $GPO.DisplayName).GpoStatus = "UserSettingsDisabled"

        Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS" -ValueName ADBackupDSRMPassword -Value 1 -Type DWord | Out-Null
        Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS" -ValueName ADPasswordEncryptionEnabled -Value 1 -Type DWord | Out-Null
        Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS" -ValueName BackupDirectory -Value 2 -Type DWord | Out-Null
        Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS" -ValueName PasswordComplexity -Value 4 -Type DWord | Out-Null
        Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS" -ValueName PasswordLength -Value 25 -Type DWord | Out-Null
        Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS" -ValueName PasswordAgeDays -Value 90 -Type DWord | Out-Null
        Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS" -ValueName PassphraseLength -Value 6 -Type DWord | Out-Null
    }


    # Make PolicyDefinitions folder
    # ------------------------------------------------------------
    if (!(Test-Path -Path "$($ENV:WinDir)\SYSVOL\domain\Policies\PolicyDefinitions")) {
         Copy-Item -Path "$($ENV:WinDir)\PolicyDefinitions" -Destination "$($ENV:WinDir)\SYSVOL\domain\Policies" -Recurse
    }


    # Change Task to Completed
    # ------------------------------------------------------------
    if ($ServerConfig) {
        ($ServerConfig.Tasks | Where-Object { $_.Name -like "*$(Split-Path $PSCommandPath -Leaf)" }).status = "Completed"
        $ServerConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath "$RootPath\ServerConfig.json" -Encoding utf8 -Force
    }

}
