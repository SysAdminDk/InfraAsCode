<#
     _____           _   _  __ _           _          ___        _   _                _ _         
    /  __ \         | | (_)/ _(_)         | |        / _ \      | | | |              (_) |        
    | /  \/ ___ _ __| |_ _| |_ _  ___ __ _| |_ ___  / /_\ \_   _| |_| |__   ___  _ __ _| |_ _   _ 
    | |    / _ \ '__| __| |  _| |/ __/ _` | __/ _ \ |  _  | | | | __| '_ \ / _ \| '__| | __| | | |
    | \__/\  __/ |  | |_| | | | | (_| (_| | ||  __/ | | | | |_| | |_| | | | (_) | |  | | |_| |_| |
     \____/\___|_|   \__|_|_| |_|\___\__,_|\__\___| \_| |_/\__,_|\__|_| |_|\___/|_|  |_|\__|\__, |
                                                                                             __/ |
                                                                                            |___/ 
    Todo.
    1. Verify Instalation
    2. Verify Templates
    3. Add Remote Destion Connection template.


    "Script" Actions.
    1. 
    2. 




    NOTE ... I only install on One !!!
    https://www.informaticar.net/implementing-two-tier-pki-on-windows-server-2022-part-1/
    https://www.informaticar.net/implementing-two-tier-pki-on-windows-server-2022-part-2/
    https://www.informaticar.net/implementing-two-tier-pki-on-windows-server-2022-part-3/
    https://www.informaticar.net/implementing-two-tier-pki-on-windows-server-2022-part-4/
    https://www.informaticar.net/implementing-two-tier-pki-on-windows-server-2022-part-5/
    https://www.informaticar.net/implementing-two-tier-pki-on-windows-server-2022-part-6/
    https://www.informaticar.net/implementing-two-tier-pki-on-windows-server-2022-part-7/
    https://www.informaticar.net/implementing-two-tier-pki-on-windows-server-2022-part-8/

#>


# Find Media Drive & Configuration Settings
# ------------------------------------------------------------
$Manufacturer = (Get-CimInstance Win32_ComputerSystem).Manufacturer
if ($Manufacturer -match 'VMware|Microsoft|QEMU|Red Hat|KVM|Xen') {
    $MediaDrives = Get-WmiObject -Class Win32_volume -Filter "DriveType = '5'"
}
foreach ($MediaDrive in $MediaDrives) {

    # Get content from User Data 
    # ------------------------------------------------------------
    $HostConfigFile = Get-ChildItem -Path $MediaDrive.Name -Recurse -Filter "USER_DATA" -ErrorAction SilentlyContinue
    if ($HostConfigFile) {
        $HostConfig = Get-Content -Path $HostConfigFile.FullName

        # Host Config
        # ------------------------------------------------------------
        if ($HostConfig) {

            # Extract values from User Data
            # ------------------------------------------------------------
            $DomainName = (($HostConfig | Where {$_ -like "*fqdn*"})     -Replace("^(?:\w+):\s","") -split("\.", 2))[1]
            $Username =   (($HostConfig | Where {$_ -like "*user*"})[0]) -Replace("^(?:\w+):\s","")
            $Password =   ($HostConfig  | Where {$_ -like "*password*"}) -Replace("^(?:\w+):\s","")
        }
    }
}




<#

    Install & Configure Active Directory Certificate Services

#>

# Check to see if we need to Skip this and install CA manualy
# ------------------------------------------------------------
if (($($ServerInfo | Where {$_.Role -eq "CA"}).Name | Get-ADComputer -ErrorAction SilentlyContinue).Count -gt 1) {

    Throw "Multiple CA servers, make sure the Root is avalible prior to installing the Issuing CAs"

}


$TargetPath = (Get-ADOrganizationalUnit -Filter * -SearchBase $TierSearchBase | `
    Where {$_.DistinguishedName -like "OU=*OU=Servers,OU=Tier0,$TierSearchBase"}) | `
        Select-Object Name,DistinguishedName | Out-GridView -Title "Select Destination OU" -OutputMode Single


# Install & Configure 
# ------------------------------------------------------------
($($ServerInfo | Where {$_.Role -eq "CA"}).Name | Get-ADComputer -ErrorAction SilentlyContinue)[0] | Foreach {


    # Move the CA server to Tier 0
    # ------------------------------------------------------------
    If ( ($Null -ne $TargetPath) -and ($($_.DistinguishedName) -NotLike "*OU=Servers,OU=Tier0*") ) {
        Move-ADObject -Identity $($_.DistinguishedName) -TargetPath $TargetPath.DistinguishedName
    }

    # Create AD Groups Certificate Templates
    # ------------------------------------------------------------
    $SearchBase = (Get-ADOrganizationalUnit -Filter "Name -EQ 'Tier0'").DistinguishedName
    $GroupOU = $(Get-ADOrganizationalUnit -Filter "Name -EQ 'Groups'" -SearchBase $SearchBase).DistinguishedName
    New-ADGroup -Name "AutoEnrol Certificate - Web Servers" -GroupCategory Security -GroupScope DomainLocal -Path $GroupOU
    New-ADGroup -Name "AutoEnrol Certificate - RD Servers" -GroupCategory Security -GroupScope DomainLocal -Path $GroupOU


    # Connect to the server.
    # ------------------------------------------------------------
    $Session = New-PSSession -ComputerName "$($_.DNSHostName)"

    # Copy required installers to target server
    # ------------------------------------------------------------
    $FilesToCopy = @(
        "AzureConnectedMachineAgent.msi"
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
#            Start-Process -FilePath "$($ENV:PUBLIC)\downloads\AzureConnectedMachineAgent.msi" -ArgumentList "/quiet /qn /norestart" -wait
        }


        # Install Certification Authority
        # ------------------------------------------------------------
        Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools


        # Configure Certification Authority
        # ------------------------------------------------------------
        Install-AdcsCertificationAuthority `
            -CAType "EnterpriseRootCA" `
            -HashAlgorithmName "SHA256" `
            -KeyLength "2048" `
            -ValidityPeriod Years `
            -ValidityPeriodUnits 10 `
            -CACommonName "$($ENV:UserDomain) Enterprise Certification Authority" `
            -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" `
            -OverwriteExistingCAinDS `
            -OverwriteExistingKey `
            -OverwriteExistingDatabase `
            -Force `
            -Verbose


        # ------------------------------------------------------------
        # Create Remote Desktop Server Certificate template
        # - Are only needed from client to jumphosts / management servers.
        #   All other connection from JumpHosts are secured by kerberos...
        # ------------------------------------------------------------
        # Allowed servers = $(Get-ADGroup -Identity "Domain Computers")



        # Remove unused templates.
        # - Run on CA server
        # ---
        $TemplatesToRemove = @("User", "Machine", "WebServer", "EFS", "EFSRecovery", "SubCa")
        Get-CATemplate | Where {$_.Name -in $TemplatesToRemove} | Remove-CATemplate -Force



        # ------------------------------------------------------------
        # Create NPS & Web Server Certificate templates
        # ------------------------------------------------------------
        #throw "Remote Desktop Server Certificate template"
<#
        $AddTemplateScript = @()
        $AddTemplateScript += "if (!(Get-CATemplate | Where {`$_.Name -eq `"RASAndIASServer`"})) {"
        $AddTemplateScript += "    Add-CATemplate -Name `"RASAndIASServer`" -Confirm:`$False"
        $AddTemplateScript += "}"
        $AddTemplateScript += ""
        $AddTemplateScript += "if (!(Get-CATemplate | Where {`$_.Name -eq `"WebServer`"})) {"
        $AddTemplateScript += "    Add-CATemplate -Name `"WebServer`" -Confirm:`$False -Force"
        $AddTemplateScript += "}"
    
        $AddTemplateScript | Out-File "$($ENV:TEMP)\AddTemplatesScript.ps1" -force

        $ScheduleActions = @()
        $ScheduleActions += New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$($ENV:TEMP)\AddTemplatesScript.ps1`""
        $ScheduleActions += New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "Remove-Item -Path `"$($ENV:TEMP)\AddTemplatesScript.ps1`" -Force"
        $Scheduletrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(10);
        $ScheduleSettings = New-ScheduledTaskSettingsSet -Compatibility Win8
        $SchedulePrincipal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Limited
        $ScheduledTask = New-ScheduledTask -Action $ScheduleActions -Trigger $Scheduletrigger -Settings $ScheduleSettings -Principal $SchedulePrincipal
        $ScheduledTask.triggers[0].EndBoundary  = (Get-Date).AddSeconds(30).ToString("s")
        $ScheduledTask.Settings.DeleteExpiredTaskAfter = "PT0S"
        Register-ScheduledTask -TaskName "Add Templates" -InputObject $ScheduledTask | Out-Null
#>

        # Cleanup files.
        # ------------------------------------------------------------
        do {
            Start-Sleep -Seconds 5
        } While ($(Get-Process).name -contains "msiexec")

        Get-ChildItem -Path "$($ENV:PUBLIC)\downloads" -Recurse | Remove-Item


        # ------------------------------------------------------------
        # Reboot to activate all the changes.
        # ------------------------------------------------------------
        Restart-Computer -Force
    }
}


# Cleanup Session
# ------------------------------------------------------------
Get-PSSession $Session.Id | Remove-PSSession


# ------------------------------------------------------------
# Set ACLs on certificates.
# ------------------------------------------------------------
## DSACLS "CN=RASAndIASServer,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$((Get-ADDomain).DistinguishedName)" /G "RAS And IAS Servers:CA;AutoEnrollment" # | Out-Null
## DSACLS "CN=WebServer,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$((Get-ADDomain).DistinguishedName)" /G "AutoEnrol Certificate - Web Servers:CA;Enroll" # | Out-Null

#endregion
