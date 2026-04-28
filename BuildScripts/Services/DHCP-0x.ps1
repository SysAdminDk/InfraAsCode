<#
    ______ _   _ _____ ______   _____                          
    |  _  \ | | /  __ \| ___ \ /  ___|                         
    | | | | |_| | /  \/| |_/ / \ `--.  ___ _ ____   _____ _ __ 
    | | | |  _  | |    |  __/   `--. \/ _ \ '__\ \ / / _ \ '__|
    | |/ /| | | | \__/\| |     /\__/ /  __/ |   \ V /  __/ |   
    |___/ \_| |_/\____/\_|     \____/ \___|_|    \_/ \___|_|   

    
    "Script" actions
    1. Install DHCP role.
    2. Example script to migrate DHCP scopes.
#>


# Verify Domain Membership
# ------------------------------------------------------------
if (-not ((Get-WmiObject -Class win32_computersystem).partofdomain)) {
    
    Throw "Domain join have must have failed"

}


# Is Domain Member, Install...
# ------------------------------------------------------------
if ((Get-WmiObject -Class win32_computersystem).partofdomain) {


    # Install required features.
    # ------------------------------------------------------------
    Install-WindowsFeature -Name DHCP -IncludeManagementTools


    # Download DHCP Migration scripts
    # ------------------------------------------------------------
    if (-Not (Test-Path -Path "C:\TS-Data")) {
        New-Item -Path "C:\TS-Data" -ItemType Directory | Out-Null
    }
    
    $Uri = "https://api.github.com/repos/SysAdminDk/MS-Infrastructure/contents/DHCP%20Scripts?ref=$Branch"
    $Files = Invoke-RestMethod -Uri $Uri -Headers @{ "User-Agent" = "Powershell" }

    $Files | Where {$_.name -like "*.ps1*"} | % { Invoke-WebRequest -Uri $_.download_url -OutFile "C:\TS-Data\$($_.Name)" }


    # Run GPUpdate and restart
    # ------------------------------------------------------------
    Invoke-GPUpdate -Force


    # Cleanup Autologin
    # ------------------------------------------------------------
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -name "AutoLogonCount" -value 0
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -name "AutoAdminLogon" -value 0
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -name "DefaultUserName" -value $null -Force
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultPassword" -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultDomainName" -Value $null -Force


    # Reboot to activate all changes.
    # ------------------------------------------------------------
    & shutdown -r -t 10

}