<#
     _____      _               ___________   _____                             _   
    |  ___|    | |             |_   _|  _  \ /  __ \                           | |  
    | |__ _ __ | |_ _ __ __ _    | | | | | | | /  \/ ___  _ __  _ __   ___  ___| |_ 
    |  __| '_ \| __| '__/ _` |   | | | | | | | |    / _ \| '_ \| '_ \ / _ \/ __| __|
    | |__| | | | |_| | | (_| |  _| |_| |/ /  | \__/\ (_) | | | | | | |  __/ (__| |_ 
    \____/_| |_|\__|_|  \__,_|  \___/|___/    \____/\___/|_| |_|_| |_|\___|\___|\__|

    Todo
    1. Install Certificate proxy
        - Install NDES Role
        - Install 



    "Script" actions
    1. Install Entra Sync
    2. Install Azure Password protection Proxy
#>


<#

    Install & Configure Azure Active Directory Connect ( Entra ID Connect )

#>

# Select Destination OU
# ------------------------------------------------------------
$TargetPath = (Get-ADOrganizationalUnit -Filter * -SearchBase $TierSearchBase | `
    Where {$_.DistinguishedName -like "OU=*OU=Servers,OU=Tier0,$TierSearchBase"}) | `
        Select-Object Name,DistinguishedName | Out-GridView -Title "Select Destination OU" -OutputMode Single


# Install & Configure Entra ID Connect & Azure Password Protection Proxy.
# ------------------------------------------------------------
$($ServerInfo | Where {$_.Role -eq "AAD"}).Name | Get-ADComputer -ErrorAction SilentlyContinue | Foreach {

    If ( ($Null -ne $TargetPath) -and ($($_.DistinguishedName) -NotLike "*OU=Servers,OU=Tier0*") ) {
        Move-ADObject -Identity $($_.DistinguishedName) -TargetPath $TargetPath.DistinguishedName
    }

    # Connect to the server.
    # ------------------------------------------------------------
    $Session = New-PSSession -ComputerName "$($_.DNSHostName)"


    # Copy required installers to target server
    # ------------------------------------------------------------
    $FilesToCopy = @(
        "AzureConnectedMachineAgent.msi",
        "AzureADConnect.msi",
        "AzureADPasswordProtectionProxySetup.exe",
        "IntuneCertificateConnector.exe"
    )

    $FilesToCopy | Foreach {
        Get-ChildItem -Path $TxScriptPath -Filter $_ -Recurse | Copy-Item -Destination "$($ENV:PUBLIC)\downloads\$_" -ToSession $Session -Force
    }


    # Execute commands.
    # ------------------------------------------------------------
    Invoke-Command -Session $Session -ScriptBlock {


        # Install Azure Arc Agent
        # ------------------------------------------------------------
        if (Test-Path -Path "$($ENV:PUBLIC)\downloads\AzureConnectedMachineAgent.msi") {
            Start-Process -FilePath "$($ENV:PUBLIC)\downloads\AzureConnectedMachineAgent.msi" -ArgumentList "/quiet /qn /norestart" -wait
        }


        # Install AD Connect
        # ------------------------------------------------------------
        if (Test-Path -Path "$($ENV:PUBLIC)\downloads\AzureADConnect.msi") {
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/I $($ENV:PUBLIC)\downloads\AzureADConnect.msi /quiet" -Wait
        }


        # Download and install Entra Password Protection Proxy   
        # ------------------------------------------------------------
        if (Test-Path -Path "$($ENV:PUBLIC)\downloads\AzureADPasswordProtectionProxySetup.exe") {
            Start-Process -FilePath "$($ENV:PUBLIC)\downloads\AzureADPasswordProtectionProxySetup.exe" -ArgumentList "/quiet" -Wait
        }

    }

    Write-Output "Azure AD / Entra ID connect is installed, configuration must be done with RDP to the server."


    # Cleanup files.
    # ------------------------------------------------------------
    Get-ChildItem -Path "$($ENV:PUBLIC)\downloads" -Recurse | Remove-Item


    #& mstsc /v:$($_.DNSHostName)

}
<#

    On each AD Connect server, the Password protection Proxy is also installed, and configured with this.
#>
$($ServerInfo | Where {$_.Role -eq "AAD"}).Name | Get-ADComputer -ErrorAction SilentlyContinue | Foreach {
    Invoke-Command -Session $Session -ScriptBlock {

        Import-Module -Name AzureADPasswordProtection -Verbose -Force
        Register-AzureADPasswordProtectionProxy -AccountUpn ($Using:AzureCreds).UserName -AuthenticateUsingDeviceCode
        Register-AzureADPasswordProtectionForest -AccountUpn ($Using:AzureCreds).UserName -AuthenticateUsingDeviceCode -ForestCredential $Using:Credentials

    }
}
