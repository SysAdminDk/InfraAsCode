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

#>


<#

    This region is used to Install & Configure RDGW Servers

#>

# Set Variables
# ------------------------------------------------------------
$NPSGroup = Get-ADGroup -Identity "RAS and IAS Servers" -Properties ObjectGUID
if ($NPSGroup) {
    $GroupGUID = ($NPSServers.ObjectGUID).ToByteArray()
    $Key = (New-Object System.Security.Cryptography.SHA256Managed).ComputeHash($GroupGUID)
    $SharedSecret = -join ($Key | ForEach-Object { "{0:X2}" -f $_ })
}


# Load module
# ------------------------------------------------------------
Import-Module RemoteDesktopServices


# Create Remote NPS servers
# ------------------------------------------------------------
$NPSServers = Get-ADComputer -Filter "Name -like '*AMFA*'"
if ($NPSServers) {
    $NPSServers | Foreach {
        if (!(Test-Path -Path "RDS:\GatewayServer\NPSServers\$($_.DNSHostName)")) {
            New-Item -Path "RDS:\GatewayServer\NPSServers\" -Name "$($_.DNSHostName)" -SharedSecret $SharedSecret | Out-Null
        }
    }
}


# Set Connection Request Policy to Central policy store.
# ------------------------------------------------------------
if ($NPSServers) {
    If ((Get-Item -Path "RDS:\GatewayServer\CentralCAPEnabled").CurrentValue -ne "1") {
        Set-Item -Path "RDS:\GatewayServer\CentralCAPEnabled" -Value 1
    }
}


# Create Resource Authorization Policy
# ------------------------------------------------------------
if (!(Test-Path -Path "RDS:\GatewayServer\RAP\Remote Desktop Gateway - MFA")) {
    New-Item -Path "RDS:\GatewayServer\RAP" -Name "Remote Desktop Gateway - MFA" -UserGroups "Domain ConnectionAccounts@$($ENV:UserDomain)" -ComputerGroupType 2 | Out-Null
}


# Set the Timeouts on both Central NPS servers
# ------------------------------------------------------------
if ($NPSServers) {
    $XMLBackup = "$($ENV:PUBLIC)\downloads\NPSConfig.xml"
    Export-NpsConfiguration -Path $XMLBackup
    $xml = [xml](Get-Content -Path $XMLBackup)

    $xml.ChildNodes.Children.Microsoft_Internet_Authentication_Service.Children.RADIUS_Server_Groups.Children.TS_GATEWAY_SERVER_GROUP.Children.ChildNodes | Foreach {
        $_.Properties.Timeout.innerText="60"
        $_.Properties.Blackout_Interval.innerText="60"
        $_.Properties.Send_Signature.innerText="1"
    }
    $XML.Save($XMLBackup)
}


# Ensure the service is up and running after install
# ------------------------------------------------------------        
if ($XMLBackup) {
    for ($i; $i -lt 10; $i++) {
        if ($(get-service -name IAS).status -eq "Running") {
            break
        } else {
            Write-warning "Wait 10"
            Start-Sleep -Seconds 10
        }
    }
    Import-NpsConfiguration -Path $XMLBackup
}


# Fix the Warning (RequireMsgAuth and/or limitProxyState configuration is in Disable mode)
# ------------------------------------------------------------
netsh nps set limitproxystate all = "enable"
netsh nps set requiremsgauth all = "enable"


<#
# Request the Certificate
# ------------------------------------------------------------
Write-Warning "Make the Certificate request, perhaps use LetsEncrypt script....."
#>
