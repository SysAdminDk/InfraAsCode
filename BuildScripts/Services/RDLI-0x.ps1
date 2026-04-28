<#
    ____________   _     _                    _             
    | ___ \  _  \ | |   (_)                  (_)            
    | |_/ / | | | | |    _  ___ ___ _ __  ___ _ _ __   __ _ 
    |    /| | | | | |   | |/ __/ _ \ '_ \/ __| | '_ \ / _` |
    | |\ \| |/ /  | |___| | (_|  __/ | | \__ \ | | | | (_| |
    \_| \_|___/   \_____/_|\___\___|_| |_|___/_|_| |_|\__, |
                                                       __/ |
                                                      |___/ 
#>

<#
    
    Install and Activete Remote Desktop Licensing service.
    - Add License Pack on Remote Desktop

#>

# Select Destination OU
# ------------------------------------------------------------
$TargetPath = (Get-ADOrganizationalUnit -Filter * -SearchBase $TierSearchBase | `
    Where {$_.DistinguishedName -like "OU=*OU=Servers,OU=Tier1,$TierSearchBase"}) | `
        Select-Object Name,DistinguishedName | Out-GridView -Title "Select Destination OU" -OutputMode Single


# Install & Configure Remote Desktop Licensing server
# ------------------------------------------------------------
$($ServerInfo | Where {$_.Role -eq "RDLI"}).Name | Get-ADComputer -ErrorAction SilentlyContinue | Foreach {

    If ( ($Null -ne $TargetPath) -and ($($_.DistinguishedName) -NotLike "*OU=Servers,OU=Tier1*") ) {
        Move-ADObject -Identity $($_.DistinguishedName) -TargetPath $TargetPath.DistinguishedName
    }    


    # Connect to the server.
    # ------------------------------------------------------------
    $Session = New-PSSession -ComputerName "$($_.DNSHostName)"


    # Copy required installers to target server
    # ------------------------------------------------------------
    @(
        "AzureConnectedMachineAgent.msi"

    ) | Foreach {
        #Get-ChildItem -Path $TxScriptPath -Filter $_ -Recurse | Copy-Item -Destination "$($ENV:PUBLIC)\downloads\$_" -ToSession $Session -Force
    }


    # Execute commands.
    # ------------------------------------------------------------
    Invoke-Command -Session $Session -ScriptBlock {


        # Install Azure Arc Agent
        # ------------------------------------------------------------
        if (Test-Path -Path "$($ENV:PUBLIC)\downloads\AzureConnectedMachineAgent.msi") {
            Start-Process -FilePath "$($ENV:PUBLIC)\downloads\AzureConnectedMachineAgent.msi" -ArgumentList "/quiet /qn /norestart" -wait
        }


        # ------------------------------------------------------------
        # Install Remote Desktop Licensing Services
        # ------------------------------------------------------------
        Install-WindowsFeature -Name "RDS-Licensing" -IncludeManagementTools


        # ------------------------------------------------------------
        # Activate
        # ------------------------------------------------------------
        $wmiClass = ([wmiclass]"\\localhost\root\cimv2:Win32_TSLicenseServer")
        $wmiClass.GetActivationStatus().ActivationStatus

        $wmiTSLicenseObject = Get-WMIObject Win32_TSLicenseServer
        $wmiTSLicenseObject.FirstName="John"
        $wmiTSLicenseObject.LastName="Doe"
        $wmiTSLicenseObject.Company=$CompanyName
        $wmiTSLicenseObject.CountryRegion="Denmark"
        $wmiTSLicenseObject.Put()

        $wmiClass.ActivateServerAutomatic()

        $wmiClass.GetActivationStatus().ActivationStatus

    }

    # Add server to "Terminal Server License Servers"
    # ------------------------------------------------------------
    $RDLicenceServer = $($_.Name)
    Add-ADGroupMember -Members "$(Get-ADComputer -Identity "$RDLicenceServer")" -Identity $(Get-ADGroup -Identity "Terminal Server License Servers")


    # Install License (For now with RDP)
    # ------------------------------------------------------------
#    & mstsc /v:$($_.DNSHostName)
}


# Fun with Windows :)
# ------------------------------------------------------------
add-type -AssemblyName microsoft.VisualBasic
add-type -AssemblyName System.Windows.Forms
Start-Process licmgr.exe
start-sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait("{enter}")
start-sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait("%")
[System.Windows.Forms.SendKeys]::SendWait("{DOWN 4}")
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
[System.Windows.Forms.SendKeys]::SendWait("RDLI-01")
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
start-sleep -Milliseconds 1000
[System.Windows.Forms.SendKeys]::SendWait("{RIGHT 3}")
start-sleep -Milliseconds 1000
[System.Windows.Forms.SendKeys]::SendWait("%")
[System.Windows.Forms.SendKeys]::SendWait("{DOWN}")
[System.Windows.Forms.SendKeys]::SendWait("{ENTER 2}")

# To be continued :)




# ------------------------------------------------------------
# Create GPO with settings to this licensing server
# ------------------------------------------------------------
# Configure RD Licensing (If Required)
# ------------------------------------------------------------
if ( ($RDLicenceServer) -And (!(Get-GPO -Name "Admin - Set Remote Desktop Licensing server" -ErrorAction SilentlyContinue)) ) {
    $GPO = New-GPO -Name "Admin - Set Remote Desktop Licensing server"
    (Get-GPO -Name $GPO.DisplayName).GpoStatus = "UserSettingsDisabled"

    Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -ValueName LicensingMode -Value 4 -Type DWord | Out-Null
    Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -ValueName LicenseServers -Value $RDLicenceServer -Type String | Out-Null

    $(Get-ADOrganizationalUnit -Filter "Name -like '*Jump*'") | foreach {
        Get-GPO -Name $GPO.DisplayName | New-GPLink -Target $($_.DistinguishedName) -LinkEnabled Yes | Out-Null
    }
}

