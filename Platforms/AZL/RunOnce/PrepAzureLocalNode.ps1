<#

    Auto Configure Azure Local node

    Required configurations needed when running Azure Local Nodes as VMs on Proxmox nodes.

#>


# Clear Autologin
# ------------------------------------------------------------
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -Value '0' -ErrorAction SilentlyContinue


<#
# Exclude Memory Tests
# ------------------------------------------------------------
Write-Host "Excluding ECC Memory validation step"
$Manufacturer = (Get-CimInstance Win32_ComputerSystem).Manufacturer
if ($Manufacturer -match 'VMware|Microsoft|QEMU|Red Hat|KVM|Xen') {
    $ModulePath = "C:\Program Files\WindowsPowerShell\Modules\AzStackHci.EnvironmentChecker\10.2508.0.2047"

    if (!(Test-Path $ModulePath)) {
        New-Item -Path $ModulePath -ItemType Directory -Force | Out-Null
    }
    if (!(Test-Path "$ModulePath\ExcludeTests.txt")) {
        Set-Content -Path "$ModulePath\ExcludeTests.txt" -Value "Test-MemoryProperties" -Encoding UTF8
    }
}
Get-Content -Path "$ModulePath\ExcludeTests.txt"
Start-Sleep -Seconds 120
#>


# Cleanup System drive
# ------------------------------------------------------------
if (Test-Path -Path "$($ENV:SystemDrive)\Windows.old") {
    Remove-Item -Path "$($ENV:SystemDrive)\Windows.old" -Force
}


# Rename Network Adapters and Configure IP address.
# ------------------------------------------------------------
$ServerNodes = Get-Content -Path "$($env:SystemDrive)\TS-Data\Nodes.json" | ConvertFrom-Json
$ServerNode = $ServerNodes | Where {$_.Node -eq $($env:COMPUTERNAME)}
$Interfaces = $ServerNode.Interfaces -replace("[:-]","-")


# Verify NO interface have the Management IP Address
# ------------------------------------------------------------
Get-NetIPAddress -AddressFamily IPv4 | ForEach-Object {
    if ($_.IPAddress -eq $ServerNode.IPAddress) {
        Remove-NetIPAddress -InterfaceIndex $_.InterfaceIndex -Confirm:$false
    }
}


# Calculate IP Prefix
# ------------------------------------------------------------
$IPPrefix = (($($ServerNode.Subnet) -split '\.' | ForEach-Object { [Convert]::ToString($_,2).PadLeft(8,'0') } ) -join("")) -replace '0','' | Measure-Object -Character | Select-Object -ExpandProperty Characters


if ($Interfaces.Count -eq 4) {

    $Uplink01 = Get-NetAdapter -Physical | Where {$_.MacAddress -eq $Interfaces[0]}
    Rename-NetAdapter -Name $Uplink01.Name -NewName "MgmtCompute01"
    New-NetIPAddress -InterfaceIndex $Uplink01.ifIndex -IPAddress $ServerNode.IPAddress -PrefixLength $IPPrefix -DefaultGateway $ServerNode.Gateway -AddressFamily IPv4
    Set-DnsClientServerAddress -InterfaceIndex $Uplink01.ifIndex -ServerAddresses $ServerNode.DNSServers

    $Uplink02 = Get-NetAdapter -Physical | Where {$_.MacAddress -eq $Interfaces[1]}
    Rename-NetAdapter -Name $Uplink02.Name -NewName "MgmtCompute02"

    $Storage01 = Get-NetAdapter -Physical | Where {$_.MacAddress -eq $Interfaces[2]}
    Rename-NetAdapter -Name $Storage01.Name -NewName "Storage01"

    $Storage02 = Get-NetAdapter -Physical | Where {$_.MacAddress -eq $Interfaces[3]}
    Rename-NetAdapter -Name $Storage02.Name -NewName "Storage02"

} elseif ($Interfaces.Count -eq 6) {

    $Uplink01 = Get-NetAdapter -Physical | Where {$_.MacAddress -eq $Interfaces[0]}
    Rename-NetAdapter -Name $Uplink01.Name -NewName "Uplink01"

    $Uplink02 = Get-NetAdapter -Physical | Where {$_.MacAddress -eq $Interfaces[1]}
    Rename-NetAdapter -Name $Uplink02.Name -NewName "Uplink02"

    $VMData01 = Get-NetAdapter -Physical | Where {$_.MacAddress -eq $Interfaces[2]}
    Rename-NetAdapter -Name $VMData01.Name -NewName "VMData01"

    $VMData02 = Get-NetAdapter -Physical | Where {$_.MacAddress -eq $Interfaces[3]}
    Rename-NetAdapter -Name $VMData02.Name -NewName "VMData02"

    $Storage01 = Get-NetAdapter -Physical | Where {$_.MacAddress -eq $Interfaces[4]}
    Rename-NetAdapter -Name $Storage01.Name -NewName "Storage01"

    $Storage02 = Get-NetAdapter -Physical | Where {$_.MacAddress -eq $Interfaces[5]}
    Rename-NetAdapter -Name $Storage02.Name -NewName "Storage02"

} else {

    Write-Warning "Unexpected number of interfaces ($($Interfaces.Count)) detected."

}


# Setup Time Sync.
# ------------------------------------------------------------
w32tm /config /manualpeerlist:"europe.pool.ntp.org" /syncfromflags:manual /update


<#
# Install Required AZ modules.
# ------------------------------------------------------------
$PSProvidors = @(
    [PSCustomObject]@{ Name = "NuGet";               RequiredVersion = "latest"; }
    [PSCustomObject]@{ Name = "PowerShellGet";       RequiredVersion = "latest"; }
)

Foreach ($PSProvidor in $PSProvidors) {
    $Installed = Get-PackageProvider -Name $($PSProvidor.Name)
    if (($Null -eq $Installed) -and ($PSProvidor.RequiredVersion -eq "latest")) {
        Install-PackageProvider -Name $PSProvidor.Name -Force -Confirm:$false
    }
}
#>

<#
$PSModules = @(
    [PSCustomObject]@{ Name = "AZ.ConnectedMachine"; RequiredVersion = "latest"; }
    [PSCustomObject]@{ Name = "AZ.Accounts";         RequiredVersion = "4.0.2";  }
    [PSCustomObject]@{ Name = "AZ.Resources";        RequiredVersion = "7.8.0";  }
)
Foreach ($Module in $PSModules) {
    $Installed = Get-InstalledModule -Name $($Module.Name) -AllVersions -ErrorAction SilentlyContinue
    $Installed | Select-Object Name,Version
    if ($Module.RequiredVersion -eq "latest") {
        if ($null -ne $Installed) {
            $LatestVersion = Find-Module -Name $($Module.Name) -IncludeDependencies
            if ($($Installed.Version.ToString()) -ne $($LatestVersion.Version.ToString())) {
                Write-Host "Latest Uninstall"
                UnInstall-Module -Name $($Module.Name) -AllVersions -Force -Confirm:$false
            } else {
                Continue
            }
        }

        Write-Host "Latest Install"
        Install-Module -Name $($Module.Name) -Force -Confirm:$false
    } else {
        if ($Null -ne $Installed) {
            if ($($Installed.Version.ToString()) -ne $($Module.RequiredVersion)) {
                Write-Host "Version Diff, Unisntall"
                UnInstall-Module -Name $($Module.Name) -AllVersions -Force -Confirm:$false
            } else {
                Write-Host "Continue"
                Continue
            }
        }
        Write-Host "Required version, Install"
        Install-Module -Name $($Module.Name) -RequiredVersion $($Module.RequiredVersion) -Force -Confirm:$false
    }
}
#>


# Invoke the Azure Arc registration script. Use a supported region.
# - If posible add Client Secret..
# ------------------------------------------------------------
$AzureData = Get-content -Path "$($env:SystemDrive)\TS-Data\SubscriptionData.json" | ConvertFrom-Json

$ArcCmd = @()
$ArcCmd += "Read-Host -Prompt 'Press ENTER to begin Azure device login for Arc initialization...'`r`n"
$ArcCmd += "write-host `"`"`r`n"
$ArcCmd += "Write-Host `"Starting Azure Arc initialization...`"`r`n"
if ($($AzureData.Proxy) -and $($AzureData.ProxyBypass)) {
    $ArcCmd += "Invoke-AzStackHciArcInitialization -TenantId $($AzureData.TenantId) -SubscriptionID $($AzureData.SubscriptionID) -ResourceGroup $($AzureData.ResourceGroup) -Region $($AzureData.Region) -Cloud $($AzureData.Cloud) -Proxy $($AzureData.Proxy) -ProxyBypass $($AzureData.ProxyBypass)`r`n"
} else {
    $ArcCmd += "Invoke-AzStackHciArcInitialization -TenantId $($AzureData.TenantId) -SubscriptionID $($AzureData.SubscriptionID) -ResourceGroup $($AzureData.ResourceGroup) -Region $($AzureData.Region) -Cloud $($AzureData.Cloud)`r`n"
}
$ArcCmd += "write-host `"`"`r`n"
$ArcCmd += "write-host `"Install required featuers`"`r`n"
$ArcCmd += "Install-WindowsFeature -Name NetworkATC, DataCenterBridging, BitLocker -IncludeAllSubFeature`r`n"
$ArcCmd += "write-host `"`"`r`n"
$ArcCmd += "Read-Host -Prompt 'Completed. Press ENTER to close this window'"

Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoExit -Command $ArcCmd"


# Get  Current IP Address
# ------------------------------------------------------------
$Interface = Get-NetAdapter -Physical | Where-Object {$_.Status -EQ "UP"}
$CurrentIP = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $Interface.ifIndex


# Change Administrator password and show on screen.
# ------------------------------------------------------------
if (!((gwmi win32_computersystem).partofdomain)) {
    #$NewPassword = $(-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 15 | ForEach-Object {[char]$_}))
    $NewPassword = "P@ssw0rd2025.!!"
    $SecurePassword = ConvertTo-SecureString -string $NewPassword -AsPlainText -Force
    Set-LocalUser -Name Administrator -Password $SecurePassword

    $PwdCmd = @()
    $PwdCmd += "Write-Host `"=== IMPORTANT: Temporary local admin password ===`"`r`n" 
    $PwdCmd += "write-host `"`"`r`n" 
    $PwdCmd += "write-host `"Username : Administrator`r`n"
    $PwdCmd += "write-host `"Password : $NewPassword`r`n"
    $PwdCmd += "write-host `"`"`r`n" 
    $PwdCmd += "Write-Host `"Please ensure you are using the same password on all AZ Nodes`"`r`n" 
    $PwdCmd += "Write-Host `"RDP access is avalible on $($CurrentIP.IPAddress)`"`r`n" 
    $PwdCmd += "write-host `"`"`r`n" 
    $PwdCmd += "Read-Host -Prompt 'Press ENTER to close this window'`r`n" 
    $PwdCmd += "exit`r`n"

    Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoExit -Command $PwdCmd"

}
