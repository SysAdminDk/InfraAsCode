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


# Define Default SearchBase for this script
# ------------------------------------------------------------
$TierSearchBase = (Get-ADOrganizationalUnit -Filter "Name -like '*$TierOUName*'" -SearchScope OneLevel).DistinguishedName



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
($($ServerInfo | Where {$_.Role -eq "CA"}).Name | Get-ADComputer -ErrorAction SilentlyContinue) | Foreach {


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

        <#
        Enter-pssession adca-01
        #>

        # Remove unused templates.
        # - Run on CA server
        # ---
        $TemplatesToRemove = @("User", "Machine", "WebServer", "EFS", "EFSRecovery", "SubCa")
        Get-CATemplate | Where {$_.Name -in $TemplatesToRemove} | Remove-CATemplate -Force
        

<#

    Create NPS Server Certificate Template

#>

# Copy "RAS and IAS Server" Template to NPSServers
# ------------------------------------------------------------
$NewTemplateDisplayName = "AOVPN NPS Servers"
$NewTemplateShortName = $NewTemplateDisplayName -replace(" ","")

# Get CA Path, and templates
# ------------------------------------------------------------
$ConfigPath = ([adsi]"LDAP://rootdse").ConfigurationNamingContext
$TemplatePath = (Get-ADObject -Identity "CN=Certificate Templates,CN=Public Key Services,CN=Services,$ConfigPath").DistinguishedName


# Connect to ADSI and get Source Template
# ------------------------------------------------------------
$ADSIConnect = [ADSI]("LDAP://$TemplatePath")
$SourceTemplate = [ADSI]("LDAP://CN=RASAndIASServer,$TemplatePath")

# Required properties to copy.
# ------------------------------------------------------------
$SelectedProperties = @(
    "pKIDefaultKeySpec",
    "pKIKeyUsage",
    "pKIMaxIssuingDepth",
    "pKICriticalExtensions",
    "pKIExpirationPeriod",
    "pKIOverlapPeriod",
    "pKIExtendedKeyUsage",
    "pKIDefaultCSPs",
    "msPKI-RA-Signature",
    "msPKI-Enrollment-Flag",
    "msPKI-Private-Key-Flag",
    "msPKI-Certificate-Name-Flag",
    "msPKI-Minimal-Key-Size",
    "msPKI-Template-Schema-Version",
    "msPKI-Template-Minor-Revision",
    "msPKI-Cert-Template-OID",
    "msPKI-Certificate-Application-Policy",
    "flags",
    "revision"
)
$testtemplatedata = $SourceTemplate | Select-Object -Property $SelectedProperties

# Change to only Server Auth
# ------------------------------------------------------------
$testtemplatedata.pKIExtendedKeyUsage = $testtemplatedata.pKIExtendedKeyUsage | Where {$_ -like '*.1'}
$testtemplatedata.'msPKI-Certificate-Application-Policy' = $testtemplatedata.'msPKI-Certificate-Application-Policy' | Where {$_ -like '*.1'}

# Change Subject name to DNS Name
# ------------------------------------------------------------
$testtemplatedata.'msPKI-Private-Key-Flag' = "16842752"
$testtemplatedata.'msPKI-Certificate-Name-Flag' = "402653184"

# Generate template OID
# ------------------------------------------------------------
$testtemplatedata.'msPKI-Cert-Template-OID' = "1.3.6.1.4.1.311.21.8.4720717.9068502.9979033.3515622.807326.160." + $(Get-Random -Minimum 1 -Maximum 9999999) + "." + $(Get-Random -Minimum 1 -Maximum 99999999)

# Create new template
# ------------------------------------------------------------
$NewTemplate = $ADSIConnect.Create("pKICertificateTemplate","CN=$NewTemplateShortName")
$NewTemplate.put("distinguishedName","CN=$NewTemplateShortName,$TemplatePath")
$NewTemplate.put("displayName",$NewTemplateDisplayName)

# Set required properties on new template.
# ------------------------------------------------------------
$testtemplatedata.psobject.properties | % { $NewTemplate.put($($_.Name),$($_.Value)) }
$NewTemplate.SetInfo()

# Create AD Group.
# ------------------------------------------------------------
$GroupPath = $(Get-ADOrganizationalUnit -Filter "Name -eq 'Groups'" -SearchBase $(Get-ADOrganizationalUnit -Filter "name -eq 'Tier1'")).DistinguishedName
#New-ADGroup -Name $NewTemplateDisplayName -GroupCategory Security -GroupScope Global -Path $GroupPath

# Ensure the template is avalible and information is replicated.
Get-TSxObject -ADObject $(($NewTemplate).distinguishedName) -Verbose


# Add AutoEnroll permissions to Cert Template.
# ------------------------------------------------------------
$CurrentAcl = Get-ACL "AD:$($NewTemplate.distinguishedName)"

$GroupSid = New-Object System.Security.Principal.SecurityIdentifier (Get-ADGroup $NewTemplateDisplayName).SID
$AccessRule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($GroupSid, "ExtendedRight", "Allow", $([GUID]"a05b8cc2-17bc-4802-a710-e7c15ab866a2"), "None", $([GUID]"00000000-0000-0000-0000-000000000000"))
$CurrentAcl.AddAccessRule($AccessRule)

Set-ACL -ACLObject $CurrentAcl -Path "AD:$($NewTemplate.distinguishedName)"

# Add template to Cert list
# ------------------------------------------------------------


Invoke-Command -ComputerName ADCA-01 -ScriptBlock {
    Get-CATemplate | Where {$_.Name -eq "AOVPNNPSServers"} | Add-CATemplate -Confirm:$False
}



<#

    Create VPN Server Certificate Template

#>

# Copy "RAS and IAS Server" Template to VPN Servers
# ------------------------------------------------------------
$NewTemplateDisplayName = "AOVPN VPN Servers"
$NewTemplateShortName = $NewTemplateDisplayName -replace(" ","")

# Get CA Path, and templates
# ------------------------------------------------------------
$ConfigPath = ([adsi]"LDAP://rootdse").ConfigurationNamingContext
$TemplatePath = "CN=Certificate Templates,CN=Public Key Services, CN=Services,$ConfigPath"

# Connect to ADSI and get Source Template
# ------------------------------------------------------------
$ADSIConnect = [ADSI]("LDAP://$TemplatePath")
$xSourceTemplate = [ADSI]("LDAP://CN=AOVPNNPSServers,$TemplatePath")

# Required properties to copy.
# ------------------------------------------------------------
$SelectedProperties = @(
    "flags",
    "revision",
    "pKIDefaultKeySpec",
    "pKIKeyUsage",
    "pKIMaxIssuingDepth",
    "pKICriticalExtensions",
    "pKIExpirationPeriod",
    "pKIOverlapPeriod",
    "pKIExtendedKeyUsage",
    "pKIDefaultCSPs",
    "msPKI-RA-Signature",
    "msPKI-Enrollment-Flag",
    "msPKI-Private-Key-Flag",
    "msPKI-Certificate-Name-Flag",
    "msPKI-Minimal-Key-Size",
    "msPKI-Template-Schema-Version",
    "msPKI-Template-Minor-Revision",
    "msPKI-Cert-Template-OID",
    "msPKI-Certificate-Application-Policy"
)
$NewTemplateData = $SourceTemplate | Select-Object -Property $SelectedProperties

# Change to only Server Auth
# ------------------------------------------------------------
$NewTemplateData.pKIExtendedKeyUsage = $NewTemplateData.pKIExtendedKeyUsage | Where {$_ -like '*.1'}
$NewTemplateData.'msPKI-Certificate-Application-Policy' = $NewTemplateData.'msPKI-Certificate-Application-Policy' | Where {$_ -like '*.1'}

# Change Subject name to DNS Name
# ------------------------------------------------------------
$NewTemplateData.'msPKI-Private-Key-Flag' = "16842752"
$NewTemplateData.'msPKI-Certificate-Name-Flag' = "402653184"

# Generate template OID
# ------------------------------------------------------------
$NewTemplateData.'msPKI-Cert-Template-OID' = "1.3.6.1.4.1.311.21.8.4720717.9068502.9979033.3515622.807326.160." + $(Get-Random -Minimum 1 -Maximum 9999999) + "." + $(Get-Random -Minimum 1 -Maximum 99999999)


# Set Certificate Compability Version
# ------------------------------------------------------------
$NewTemplateData.'msPKI-Cert-Template-OID' = "1.3.6.1.4.1.311.21.8.4720717.9068502.9979033.3515622.807326.160." + $(Get-Random -Minimum 1 -Maximum 9999999) + "." + $(Get-Random -Minimum 1 -Maximum 99999999)


# Create new template
# ------------------------------------------------------------
$NewTemplate = $ADSI.Create("pKICertificateTemplate","CN=$NewTemplateShortName")
$NewTemplate.put("distinguishedName","CN=$NewTemplateShortName,CM=Certificate Template,CN=Public Key Services,CN=Services,$Config")
$NewTemplate.put("displayName",$NewTemplateDisplayName)

# Set required properties on new template.
# ------------------------------------------------------------
$NewTemplateData.psobject.properties | % { $NewTemplate.put($($_.Name),$($_.Value)) }
$NewTemplate.SetInfo()

# Create AD Group.
# ------------------------------------------------------------
$GroupPath = $(Get-ADOrganizationalUnit -Filter "Name -eq 'Groups'" -SearchBase $(Get-ADOrganizationalUnit -Filter "name -eq 'Tier1'")).DistinguishedName
New-ADGroup -Name $NewTemplateDisplayName -GroupCategory Security -GroupScope Global -Path $GroupPath

# Add AutoEnroll permissions to Cert Template.
# ------------------------------------------------------------
$CurrentAcl = Get-ACL "AD:$($NewTemplate.distinguishedName)"

$GroupSid = New-Object System.Security.Principal.SecurityIdentifier (Get-ADGroup $NewTemplateDisplayName).SID
$AccessRule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($GroupSid, "ExtendedRight", "Allow", $([GUID]"a05b8cc2-17bc-4802-a710-e7c15ab866a2"), "None", $([GUID]"00000000-0000-0000-0000-000000000000"))
$CurrentAcl.AddAccessRule($AccessRule)

Set-ACL -ACLObject $CurrentAcl -Path "AD:$($NewTemplate.distinguishedName)"

# Add template to Cert list
# ------------------------------------------------------------
Invoke-Command -ComputerName ADCA-01 -ScriptBlock {
    Add-CATemplate -Name $NewTemplateShortName -Confirm:$False
}





"Copy of RAS and IAS Server"





# Copy Workstation Template to ....
$Config = ([adsi]"LDAP://rootdse").ConfigurationNamingContext
$SourceTemplate = [adsi]("LDAP://CN=Workstation,CN=Certificate Templates,CN=Public Key Services,CN=Services,$Config")

$SelectedProperties = @(
    "pKIDefaultKeySpec",
    "pKIKeyUsage",
    "pKIMaxIssuingDepth",
    "pKICriticalExtensions",
    "pKIExpirationPeriod",
    "pKIOverlapPeriod",
    "pKIExtendedKeyUsage",
    "pKIDefaultCSPs",
    "msPKI-RA-Signature",
    "msPKI-Enrollment-Flag",
    "msPKI-Private-Key-Flag",
    "msPKI-Certificate-Name-Flag",
    "msPKI-Minimal-Key-Size",
    "msPKI-Template-Schema-Version",
    "msPKI-Template-Minor-Revision",
    "msPKI-Cert-Template-OID",
    "msPKI-Certificate-Application-Policy",
    "flags",
    "revision"
)
$testtemplatedata = $SourceTemplate | Select-Object -Property $SelectedProperties

$NewTemplate = $ADSI.Create("pKICertificateTemplate","CN=WorkstationNew")
$NewTemplate.put("distinguishedName","CN=WorkstationNew,CM=Certificate Template,CN=Public Key Services,CN=Services,$Config")
$NewTemplate.put("displayName","Workstation New")

$testtemplatedata.psobject.properties | % { $NewTemplate.put($($_.Name),$($_.Value)) }

$NewTemplate.SetInfo()



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
