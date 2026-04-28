<#
     _   _ ______  ___   _____  ___  _________ ___  
    | \ | || ___ \/ _ \ /  ___| |  \/  ||  ___/ _ \ 
    |  \| || |_/ / /_\ \\ `--.  | .  . || |_ / /_\ \
    | . ` ||  __/|  _  | `--. \ | |\/| ||  _||  _  |
    | |\  || |   | | | |/\__/ / | |  | || |  | | | |
    \_| \_/\_|   \_| |_/\____/  \_|  |_/\_|  \_| |_/

    ToDo.
    1. 


    "Script" actions.
    1. Install NPAS
    2. Setup Radius clients
    3. Configure NAP & CAP
    4. Install Radius NPS Extention / Azure MFA
    5. Configure Azure MFA
#>


<#

    This region is used to Install & Configure MFA Servers

#>

# 
# ------------------------------------------------------------



# Install NPAS (Radius)
# ------------------------------------------------------------
if (!(Get-Command -Name Export-NpsConfiguration -ErrorAction SilentlyContinue)) {
    Install-WindowsFeature -Name NPAS -IncludeManagementTools
}


# Install Azure MFA installer
# ------------------------------------------------------------
if (-NOT (Test-Path -Path "$($ENV:USERPROFILE)\downloads\NpsExtnForAzureMfaInstaller.exe")) {
    Invoke-WebRequest -Uri "https://download.microsoft.com/download/b/f/f/bffb4f12-9c09-4dbc-a4af-08e51875eea9/NpsExtnForAzureMfaInstaller.exe" -OutFile "$($ENV:USERPROFILE)\Downloads\NpsExtnForAzureMfaInstaller.exe"
}
if (Test-Path -Path "$($ENV:USERPROFILE)\downloads\NpsExtnForAzureMfaInstaller.exe") {
    Start-Process -FilePath "$($ENV:USERPROFILE)\downloads\NpsExtnForAzureMfaInstaller.exe" -ArgumentList "/quiet /norestart" -Wait
}
        
<#
# Configure Radius Clients
# ------------------------------------------------------------
$($Using:ServerInfo | Where {$_.Role -eq "RDGW"}) | Foreach {
    $ServerName = $_.Name
    $IPAddress = (Resolve-DnsName -Name "$ServerName.$($ENV:UserDNSDomain)" -Type A)[0].IPAddress #"$($_).$($ENV:UserDNSDomain)"
    if (!(Get-NpsRadiusClient | Where {$_.Name -EQ $ServerName})) {
        New-NpsRadiusClient -Name $ServerName -Address $IPAddress -SharedSecret $Using:NPSSharedSecret -AuthAttributeRequired 1 | Out-Null
    }
}
#>

<#

    Configure CAP and NAP

#>


# Export current configuration to backup file.
# ------------------------------------------------------------
$XMLBackup = "$($ENV:PUBLIC)\downloads\NPSConfig.xml"
Export-NpsConfiguration -Path $XMLBackup


# Load required XML modules
# ------------------------------------------------------------
Add-Type -AssemblyName "System.Xml.Linq"
Add-Type -AssemblyName "System.Xml"


# Load current (default) configuration to memory
# ------------------------------------------------------------
$XML = [System.Xml.Linq.XDocument]::Load($XMLBackup)
$XMLRoot = $xml.Root.Element("Children").Element("Microsoft_Internet_Authentication_Service").Element("Children")


# Verify RDG_NPS_NAP dont exists before createing.
If ($XMLRoot.Element("RadiusProfiles").Element("Children").Nodes().Name.LocalName -Notcontains "RDG_NPS_NAP") {
    # Create Radius Profile template
    # ------------------------------------------------------------
    $RadiusProfileTemplate  = "<RDG_NPS_NAP name=`"RDG NPS NAP`">"
    $RadiusProfileTemplate += " <Properties>"
    $RadiusProfileTemplate += "  <IP_Filter_Template_Guid xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"string`">{00000000-0000-0000-0000-000000000000}</IP_Filter_Template_Guid>"
    $RadiusProfileTemplate += "  <Opaque_Data xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"string`"></Opaque_Data>"
    $RadiusProfileTemplate += "  <Template_Guid xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"string`">{00000000-0000-0000-0000-000000000000}</Template_Guid>"
    $RadiusProfileTemplate += "  <msIgnoreUserDialinProperties xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"boolean`">1</msIgnoreUserDialinProperties>"
    $RadiusProfileTemplate += "  <msNPAllowDialin xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"boolean`">1</msNPAllowDialin>"
    $RadiusProfileTemplate += "  <msNPAuthenticationType2 xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"int`">3</msNPAuthenticationType2>"
    $RadiusProfileTemplate += "  <msNPAuthenticationType2 xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"int`">9</msNPAuthenticationType2>"
    $RadiusProfileTemplate += "  <msNPAuthenticationType2 xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"int`">4</msNPAuthenticationType2>"
    $RadiusProfileTemplate += "  <msNPAuthenticationType2 xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"int`">10</msNPAuthenticationType2>"
    $RadiusProfileTemplate += "  <msNPAuthenticationType2 xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"int`">7</msNPAuthenticationType2>"
    $RadiusProfileTemplate += "  <msRADIUSFramedProtocol xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"int`">1</msRADIUSFramedProtocol>"
    $RadiusProfileTemplate += "  <msRADIUSServiceType xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"int`">2</msRADIUSServiceType>"
    $RadiusProfileTemplate += "  <msRASBapLinednLimit xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"int`">50</msRASBapLinednLimit>"
    $RadiusProfileTemplate += "  <msRASBapLinednTime xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"int`">120</msRASBapLinednTime>"
    $RadiusProfileTemplate += " </Properties>"
    $RadiusProfileTemplate += "</RDG_NPS_NAP>"

    $RadiusProfileElement = [System.Xml.Linq.XElement]::Parse($RadiusProfileTemplate);
    $XMLRoot.Element("RadiusProfiles").Element("Children").AddFirst($RadiusProfileElement)
}


# Verify RDG_NPS_NAP dont exists before createing.
If ($XMLRoot.Element("NetworkPolicy").Element("Children").Nodes().Name.LocalName -Notcontains "RDG_NPS_NAP") {

    # Create Network Policy template
    # ------------------------------------------------------------
    $NetworkPolicyTemplate  = "<RDG_NPS_NAP name=`"RDG NPS NAP`">"
    $NetworkPolicyTemplate += " <Properties>"
    $NetworkPolicyTemplate += "  <Opaque_Data xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"string`"></Opaque_Data>"
    $NetworkPolicyTemplate += "  <Policy_Enabled xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"boolean`">1</Policy_Enabled>"
    $NetworkPolicyTemplate += "  <Policy_SourceTag xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"int`">1</Policy_SourceTag>"
    $NetworkPolicyTemplate += "  <Template_Guid xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"string`">{00000000-0000-0000-0000-000000000000}</Template_Guid>"
    $NetworkPolicyTemplate += "  <msNPAction xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"string`">RDG_NPS_NAP</msNPAction>"
    $NetworkPolicyTemplate += "  <msNPConstraint xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"string`">TIMEOFDAY(`"0 00:00-24:00; 1 00:00-24:00; 2 00:00-24:00; 3 00:00-24:00; 4 00:00-24:00; 5 00:00-24:00; 6 00:00-24:00`")</msNPConstraint>"
    $NetworkPolicyTemplate += "  <msNPSequence xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"int`">1</msNPSequence>"
    $NetworkPolicyTemplate += " </Properties>"
    $NetworkPolicyTemplate += "</RDG_NPS_NAP>"

    $NetworkPolicyElement = [System.Xml.Linq.XElement]::Parse($NetworkPolicyTemplate);
    $XMLRoot.Element("NetworkPolicy").Element("Children").AddFirst($NetworkPolicyElement)

    if ($XMLRoot.Element("NetworkPolicy").Element("Children").Element("Connections_to_other_access_servers").Element("Properties").element("msNPSequence").value -ne 999999) {
        $XMLRoot.Element("NetworkPolicy").Element("Children").Element("Connections_to_other_access_servers").Element("Properties").element("msNPSequence").setvalue("999999")
    }
    if ($XMLRoot.Element("NetworkPolicy").Element("Children").Element("Connections_to_Microsoft_Routing_and_Remote_Access_server").Element("Properties").element("msNPSequence").value -ne 999998) {
        $XMLRoot.Element("NetworkPolicy").Element("Children").Element("Connections_to_Microsoft_Routing_and_Remote_Access_server").Element("Properties").element("msNPSequence").setvalue("999998")
    }
}


# Verify RDG_NPS_CAP dont exists before createing.
If ($XMLRoot.Element("Proxy_Policies").Element("Children").Nodes().Name.LocalName -Notcontains "RDG_NPS_CAP") {

    # Create Proxy Profile template
    # ------------------------------------------------------------
    $ProxyProfileTemplate  = "<RDG_NPS_CAP name=`"RDG NPS CAP`">"
    $ProxyProfileTemplate += " <Properties>"
    $ProxyProfileTemplate += "  <Opaque_Data xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"string`"></Opaque_Data>"
    $ProxyProfileTemplate += "  <Policy_Enabled xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"boolean`">1</Policy_Enabled>"
    $ProxyProfileTemplate += "  <Policy_SourceTag xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"int`">1</Policy_SourceTag>"
    $ProxyProfileTemplate += "  <Template_Guid xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"string`">{00000000-0000-0000-0000-000000000000}</Template_Guid>"
    $ProxyProfileTemplate += "  <msNPAction xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"string`">RDG_NPS_CAP</msNPAction>"
    $ProxyProfileTemplate += "  <msNPConstraint xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"string`">TIMEOFDAY(`"0 00:00-24:00; 1 00:00-24:00; 2 00:00-24:00; 3 00:00-24:00; 4 00:00-24:00; 5 00:00-24:00; 6 00:00-24:00`")</msNPConstraint>"
    $ProxyProfileTemplate += "  <msNPConstraint xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"string`">MATCH(`"NAS-Port-Type=^5$`")</msNPConstraint>"
    $ProxyProfileTemplate += "  <msNPSequence xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"int`">1</msNPSequence>"
    $ProxyProfileTemplate += " </Properties>"
    $ProxyProfileTemplate += "</RDG_NPS_CAP>"

    $ProxyProfileElement = [System.Xml.Linq.XElement]::Parse($ProxyProfileTemplate);
    $XMLRoot.Element("Proxy_Policies").Element("Children").AddFirst($ProxyProfileElement)
}


# Verify RDG_NPS_CAP dont exists before createing.
If ($XMLRoot.Element("Proxy_Profiles").Element("Children").Nodes().Name.LocalName -Notcontains "RDG_NPS_CAP") {

    # Create Proxy Policy template
    # ------------------------------------------------------------
    $ProxyPolicyTemplate  = "<RDG_NPS_CAP name=`"RDG NPS CAP`">"
    $ProxyPolicyTemplate += " <Properties>"
    $ProxyPolicyTemplate += "  <IP_Filter_Template_Guid xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"string`">{00000000-0000-0000-0000-000000000000}</IP_Filter_Template_Guid>"
    $ProxyPolicyTemplate += "  <Opaque_Data xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"string`"></Opaque_Data>"
    $ProxyPolicyTemplate += "  <Template_Guid xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"string`">{00000000-0000-0000-0000-000000000000}</Template_Guid>"
    $ProxyPolicyTemplate += "  <msAuthProviderType xmlns:dt=`"urn:schemas-microsoft-com:datatypes`" dt:dt=`"int`">1</msAuthProviderType>"
    $ProxyPolicyTemplate += " </Properties>"
    $ProxyPolicyTemplate += "</RDG_NPS_CAP>"

    $ProxyPolicyElement = [System.Xml.Linq.XElement]::Parse($ProxyPolicyTemplate);
    $XMLRoot.Element("Proxy_Profiles").Element("Children").AddFirst($ProxyPolicyElement)

    if ($XMLRoot.Element("Proxy_Policies").Element("Children").Element("Use_Windows_authentication_for_all_users").Element("Properties").element("msNPSequence").value -ne 999999) {
        $XMLRoot.Element("Proxy_Policies").Element("Children").Element("Use_Windows_authentication_for_all_users").Element("Properties").element("msNPSequence").setvalue("999999")
    }
}


# Ensure formating of the import file.
# ------------------------------------------------------------
$settings = new-object System.Xml.XmlWriterSettings
$settings.Indent = $true;
$settings.Encoding = [System.Text.Encoding]::UTF8
$xmlWriter = [System.Xml.XmlWriter]::Create($XMLBackup,$settings)


# Save the backup file.
# ------------------------------------------------------------
try
{
    $xml.WriteTo($xmlWriter)
}
finally
{
    $xmlWriter.Close()
}


# Import Configuration from backup file.
# ------------------------------------------------------------
Import-NpsConfiguration -Path $XMLBackup


# Fix the Warning (RequireMsgAuth and/or limitProxyState configuration is in Disable mode)
# ------------------------------------------------------------
netsh nps set limitproxystate all = "enable"
netsh nps set requiremsgauth all = "enable"


# Fix the NTLM issue om IAS.
# ------------------------------------------------------------
New-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\RemoteAccess\Policy" -Name "Enable NTLMv2 Compatibility" -Value 1 -Force | Out-Null


# Install MS Graph (Nuget)
# ------------------------------------------------------------
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false | Out-Null
Install-Module PowershellGet -Force -Confirm:$false | Out-Null


# Install MS Graph modules.
Install-Module Microsoft.Graph -Force -Confirm:$false | Out-Null




# Setup MFA
# ------------------------------------------------------------
if (Test-Path -Path "C:\Program Files\Microsoft\AzureMfa\Config") {
    Set-Location -Path "C:\Program Files\Microsoft\AzureMfa\Config"

    Connect-MgGraph -Scopes Application.ReadWrite.All -NoWelcome -UseDeviceCode -Verbose
    New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\AzureMfa -Name "TENANT_ID" -Value (Get-MgContext).TenantId -Force -PropertyType STRING

    & .\AzureMfaNpsExtnConfigSetup.ps1

    New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\AzureMfa -Name "OVERRIDE_NUMBER_MATCHING_WITH_OTP" -Value FALSE -Force -PropertyType STRING | Out-Null
}
