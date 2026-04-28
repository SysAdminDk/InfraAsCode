<#
    ____________   _____       _                           
    | ___ \  _  \ |  __ \     | |                          
    | |_/ / | | | | |  \/ __ _| |_ _____      ____ _ _   _ 
    |    /| | | | | | __ / _` | __/ _ \ \ /\ / / _` | | | |
    | |\ \| |/ /  | |_\ \ (_| | ||  __/\ V  V / (_| | |_| |
    \_| \_|___/    \____/\__,_|\__\___| \_/\_/ \__,_|\__, |
                                                      __/ |
                                                     |___/ 
    Todo
    1. CA Request / LetsEncrypt Install

    
    "Script" Actions
    1. Install RDGW
    2. Configure remote NPS / Radius servers
    3. Configure CAP
    4. Setup NLB if required.
    5. Add RRDNS if required.s

#>

<#

    This region is used to Install & Configure RDGW Servers

#>

# Get NPS Secret from a MFA Server
# ------------------------------------------------------------
($($ServerInfo | Where {$_.Role -eq "MFA"}).Name | Get-ADComputer -ErrorAction SilentlyContinue)[0] | foreach {
    $ConfiguredNPSSharedSecret = Invoke-Command -ComputerName $_.DNSHostName -ScriptBlock {

        $XMLBackup = "$($ENV:PUBLIC)\downloads\NPSConfig.xml"
        Export-NpsConfiguration -Path $XMLBackup
        $xml = [xml](Get-Content -Path $XMLBackup)
        
        $SharedSecret = $xml.ChildNodes.Children.Microsoft_Internet_Authentication_Service.Children.Protocols.Children.Microsoft_Radius_Protocol.Children.Clients.Children.FirstChild.Properties.Shared_Secret.'#text'

        # Cleanup files.
        # ------------------------------------------------------------
        Get-ChildItem -Path "$($ENV:PUBLIC)\downloads" -Recurse | Remove-Item

        Return $SharedSecret
    }
}
if ($ConfiguredNPSSharedSecret -ne $NPSSharedSecret) {
    $NPSSharedSecret = $ConfiguredNPSSharedSecret
}


# Select Destination OU
# ------------------------------------------------------------
$TargetPath = (Get-ADOrganizationalUnit -Filter * -SearchBase $TierSearchBase | `
    Where {$_.DistinguishedName -like "OU=*OU=Servers,OU=Tier0,$TierSearchBase"}) | `
        Select-Object Name,DistinguishedName | Out-GridView -Title "Select Destination OU" -OutputMode Single


# Install & Configure Remote Desktop Gateway Servers
# ------------------------------------------------------------
$RDGWServers = $($ServerInfo | Where {$_.Name -match "^RDGW-0[0-9]{1}$"}).Name | Get-ADComputer -ErrorAction SilentlyContinue

$RDGWServers | Foreach {

    If ( ($Null -ne $TargetPath) -and ($($_.DistinguishedName) -NotLike "*OU=Servers,OU=Tier1*") ) {
        Move-ADObject -Identity $($_.DistinguishedName) -TargetPath $TargetPath.DistinguishedName
    }

    # Connect to the server.
    # ------------------------------------------------------------
    $Session = New-PSSession -ComputerName "$($_.DNSHostName)"


    # Copy required installers to target server
    # ------------------------------------------------------------
    $FilesToCopy = @(

        "AzureConnectedMachineAgent.msi"

    ) | Foreach {
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


        # Install Remote Desktop Gateway Services
        # ------------------------------------------------------------
        $Features = @()
        if (($Using:RDGWServers).count -gt 1) {
            $Features += "NLB"
        }
        $Features += "RDS-Gateway"
        
        Install-WindowsFeature -Name $Features -IncludeManagementTools


        # Load module
        # ------------------------------------------------------------
        Import-Module RemoteDesktopServices


        # Create Remote NPS servers
        # ------------------------------------------------------------
        $($Using:ServerInfo | Where {$_."Name" -like "AMFA*"}).Name | Foreach {
            if (!(Test-Path -Path "RDS:\GatewayServer\NPSServers\$($_).$($ENV:UserDNSDomain)")) {
                New-Item -Path "RDS:\GatewayServer\NPSServers\" -Name "$($_).$($ENV:UserDNSDomain)" -SharedSecret $Using:NPSSharedSecret | Out-Null
            }
        }
        

        # Set Connection Request Policy to Central policy store.
        # ------------------------------------------------------------
        If ((Get-Item -Path "RDS:\GatewayServer\CentralCAPEnabled").CurrentValue -ne "1") {
            Set-Item -Path "RDS:\GatewayServer\CentralCAPEnabled" -Value 1
        }


        # Create Resource Authorization Policy
        # ------------------------------------------------------------
        if (!(Test-Path -Path "RDS:\GatewayServer\RAP\Remote Desktop Gateway - MFA")) {
            New-Item -Path "RDS:\GatewayServer\RAP" -Name "Remote Desktop Gateway - MFA" -UserGroups "Domain ConnectionAccounts@$($ENV:UserDomain)" -ComputerGroupType 2 | Out-Null
        }


        # Set the Timeouts on both Central NPS servers
        # ------------------------------------------------------------
        $XMLBackup = "$($ENV:PUBLIC)\downloads\NPSConfig.xml"
        Export-NpsConfiguration -Path $XMLBackup
        $xml = [xml](Get-Content -Path $XMLBackup)

        $xml.ChildNodes.Children.Microsoft_Internet_Authentication_Service.Children.RADIUS_Server_Groups.Children.TS_GATEWAY_SERVER_GROUP.Children.ChildNodes | Foreach {
            $_.Properties.Timeout.innerText="60"
            $_.Properties.Blackout_Interval.innerText="60"
            $_.Properties.Send_Signature.innerText="1"
        }
        $XML.Save($XMLBackup)


        # Ensure the service is up and running after install
        # ------------------------------------------------------------        
        for ($i; $i -lt 10; $i++) {
            if ($(get-service -name IAS).status -eq "Running") {
                break
            } else {
                Write-warning "Wait 10"
                Start-Sleep -Seconds 10
            }
        }
        Import-NpsConfiguration -Path $XMLBackup


        # Fix the Warning (RequireMsgAuth and/or limitProxyState configuration is in Disable mode)
        # ------------------------------------------------------------
        netsh nps set limitproxystate all = "enable"
        netsh nps set requiremsgauth all = "enable"


        # ------------------------------------------------------------
        # Request the Certificate
        # ------------------------------------------------------------
        Write-Warning "Make the Certificate request, perhaps use LetsEncrypt script....."


        # Cleanup files.
        # ------------------------------------------------------------
        Get-ChildItem -Path "$($ENV:PUBLIC)\downloads" -Recurse | Remove-Item


        # Reboot to activate all the changes.
        # ------------------------------------------------------------
        Restart-Computer -Force
    }
}



<#

    TEST - When Enforce NTLMv2 then we need this GPO

#>
$GPO = New-GPO -Name "Admin - Allow NTLM from NPS servers2"
(Get-GPO -Name $GPO.DisplayName).GpoStatus = "UserSettingsDisabled"
New-GPLink -Name $GPO.DisplayName -Target $(Get-ADDomain).DomainControllersContainer | Out-Null

# Set this, manualy.
# Network security: Restrict NTLM: Add server exceptions in this domain = NPS Servers & RDGW Servers
# Computer Configuration -> Policies -> Windows Setttings -> Security Settings -> Local Policies ->
#   Security Options -> Network security: Restrict NTLM: Add server exceptions in this domain = RDGW*, AMFA*



<#

    Skip if hardware Load Balancer is in use.

#>
# Setup NLB on RDGWs
# ------------------------------------------------------------
$NLBAddress = $ImportServerInfo | Where {$_.Role -eq "NLB" -and $_.Name -like "T*-RDGW*"}

if ($RDGWServers.Count -gt 1) {
        
    $Interfaces = @(
        $RDGWServers | Foreach {
            [PSCustomObject]@{
                Name = $_.DNSHostName;
                Interface=$(Invoke-Command -ComputerName $_.DNSHostName -ScriptBlock { $(Get-NetAdapter | Where {$_.Status -eq "UP"}).Name });
                NlbCluster=$(Get-NlbCluster -HostName $_.DNSHostName -ErrorAction SilentlyContinue)
            }
        }
    )

    if (!($Interfaces.NlbCluster -ne $null)) {

        New-NlbCluster -HostName $RDGWServers[0].DNSHostName -InterfaceName $($Interfaces | Where {$_.name -eq $RDGWServers[0].DNSHostName}).Interface -ClusterName $($NLBAddress.name) -ClusterPrimaryIP $($NLBAddress.IpAddress)

        Get-NlbClusterPortRule -HostName $RDGWServers[0].DNSHostName | Set-NlbClusterPortRule -NewStartPort 443 -NewEndPort 443
        Get-NlbCluster -HostName $RDGWServers[0].DNSHostName | Add-NlbClusterPortRule -StartPort 80 -EndPort 80
        Get-NlbCluster -HostName $RDGWServers[0].DNSHostName | Add-NlbClusterNode -NewNodeInterface $($Interfaces | Where {$_.name -eq $RDGWServers[1].DNSHostName}).Interface -NewNodeName $RDGWServers[1].DNSHostName

    }
}



# Setup RRDNS if no NLB. "Tier1"
# ------------------------------------------------------------
if (!((Get-NlbCluster -HostName $RDGWServers[0].DNSHostName) -or (Get-NlbCluster -HostName $RDGWServers[1].DNSHostName))) {
    $($ServerInfo | Where {$_.Name -match "^RDGW-1{1}[0-9]{1}$"}).IPAddress | foreach {

        # Create RDGW - DNS Record
        # ------------------------------------------------------------
        if ($NUll -ne $RDGWName) {
            Add-DnsServerResourceRecordA -Name $RDGWName -IPv4Address $_ -ZoneName $($ENV:USERDNSDOMAIN) -ComputerName $((Get-ADDomain).PDCEmulator) -ErrorAction SilentlyContinue
        }

    }
} else {

    # Create NLB DNS Record(s)
    # ------------------------------------------------------------
    Add-DnsServerResourceRecordA -Name $($NLBAddress.Name) -IPv4Address $($NLBAddress.IpAddress) -ZoneName $($ENV:USERDNSDOMAIN) -ComputerName $((Get-ADDomain).PDCEmulator) -ErrorAction SilentlyContinue
}
<#
Resolve-DNSName -Name "$($NLBAddress.Name).$($ENV:UserDnsDomain)" -ErrorAction SilentlyContinue
#>
