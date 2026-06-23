<#

      ___       _   _            ______ _               _                     _____ _           _
     / _ \     | | (_)           |  _  (_)             | |                   |_   _(_)         (_)
    / /_\ \ ___| |_ ___   _____  | | | |_ _ __ ___  ___| |_ ___  _ __ _   _    | |  _  ___ _ __ _ _ __   __ _ 
    |  _  |/ __| __| \ \ / / _ \ | | | | | '__/ _ \/ __| __/ _ \| '__| | | |   | | | |/ _ \ '__| | '_ \ / _` |
    | | | | (__| |_| |\ V /  __/ | |/ /| | | |  __/ (__| || (_) | |  | |_| |   | | | |  __/ |  | | | | | (_| |
    \_| |_/\___|\__|_| \_/ \___| |___/ |_|_|  \___|\___|\__\___/|_|   \__, |   \_/ |_|\___|_|  |_|_| |_|\__, |
                                                                       __/ |                             __/ |
                                                                      |___/                             |___/

#>

# Define path to scripts and Functions.
# ------------------------------------------------------------
if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $RootPath = $PSScriptRoot
} else {
    $RootPath  = "C:\Scripts"
}


# Deployment server Name and Address
# ------------------------------------------------------------
if (-NOT (Test-Path -Path "$RootPath\DeploymentServer.json")) {
    Write-Warning "Missing Deployment server connection information"
    Start-Sleep -Seconds 600
}

$Deployment = Get-Content -Path "$RootPath\DeploymentServer.json" | Convertfrom-Json
try {
    Resolve-DnsName $Deployment.ServerName -QuickTimeout -ErrorAction Stop | Out-Null
    $DeploymentServer = $Deployment.ServerName
}
catch {
    $DeploymentServer = $Deployment.IpAddress
}


if (-not (Test-NetConnection $DeploymentServer -CommonTCPPort HTTP -InformationLevel Quiet)) {
    throw "Unable to connect to Deployment Website"
} else {
    $RepoUrl  = "http://$DeploymentServer/$($Deployment.VirtualPath)"
}


# Create Tier 0 structure
# ------------------------------------------------------------
$DomainInfo = Get-ADDomain


# Create Root OUs
# ------------------------------------------------------------
New-ADOrganizationalUnit -Name "CAF-Principals" -Path $($DomainInfo.DistinguishedName)
New-ADOrganizationalUnit -Name "CAF-Platform" -Path $($DomainInfo.DistinguishedName)
New-ADOrganizationalUnit -Name "CAF-Workloads" -Path $($DomainInfo.DistinguishedName)
New-ADOrganizationalUnit -Name "HybridEndpoints" -Path $($DomainInfo.DistinguishedName)


# Create Principals OUs
# ------------------------------------------------------------
@("ManagedAccounts","ManagedGroups","ServiceAccounts","LocalGroups","ConnectionAccounts") | % {
    New-ADOrganizationalUnit -Name $($_) -Path "OU=CAF-Principals,$($DomainInfo.DistinguishedName)"
}


# Create Platform OUs
# ------------------------------------------------------------
@("Security","Management","Identity","Connectivity") | % {
    New-ADOrganizationalUnit -Name $($_) -Path "OU=CAF-Platform,$($DomainInfo.DistinguishedName)"
}

@("CloudSync","PasswordProtection","EntraConnect","CertificateAuthority") | % {
    New-ADOrganizationalUnit -Name $($_) -Path "OU=Identity,OU=CAF-Platform,$($DomainInfo.DistinguishedName)"
}

@("CloudSync","PasswordProtection","EntraConnect","CertificateAuthority") | % {
    New-ADOrganizationalUnit -Name $($_) -Path "OU=Identity,OU=CAF-Platform,$($DomainInfo.DistinguishedName)"
}



# Create Landing Zone OUs
# ------------------------------------------------------------
@("Corp","Online","Local") | % {
    New-ADOrganizationalUnit -Name $($_) -Path "OU=Landing Zones,$($DomainInfo.DistinguishedName)"
}


# Create Identity OUs
# ------------------------------------------------------------
















# Get Data from Json Config
# ------------------------------------------------------------
If (Test-Path -Path "$RootPath\ServerConfig.json") {
    $ServerConfig = Get-Content -Path "$RootPath\ServerConfig.json" | ConvertFrom-Json
}


# Create Domain Join Group and Account.
# ------------------------------------------------------------
if (-Not(Get-ADOrganizationalUnit -Filter "Name -eq 'Quarantine'")) {
    $NewParrentOU  = New-TSxADOrganizationalUnit -Name "Quarantine" -Path "$($DomainInfo.DistinguishedName)"
    
    $ParrentOU = (Get-ADOrganizationalUnit $($NewParrentOU.DistinguishedName)).DistinguishedName
    $NewComputerOU = New-TSxADOrganizationalUnit -Name "Computers"  -Path $ParrentOU
    $NewUserOU     = New-TSxADOrganizationalUnit -Name "Users"      -Path $ParrentOU

    & redircmp.exe $NewComputerOU.DistinguishedName
    & redirusr.exe $NewUserOU.DistinguishedName
    
    <#
    # Cleanup
    & redircmp.exe "CN=Computers,$($DomainInfo.DistinguishedName)"
    & redircmp.exe "CN=Users,$($DomainInfo.DistinguishedName)"
    
    Get-ADOrganizationalUnit -Filter * -SearchBase $NewParrentOU | Set-ADOrganizationalUnit -ProtectedFromAccidentalDeletion $false
    Get-ADOrganizationalUnit -Identity $NewComputerOU | Remove-ADOrganizationalUnit -Recursive -Confirm:$False
    #>

}

$DomainJoinPassword = ConvertTo-SecureString -string $ServerConfig.JoinOptions.Password -AsPlainText -Force
New-ADUser -Name $ServerConfig.JoinOptions.Username -AccountPassword $DomainJoinPassword -Enabled $true -Path "OU=ServiceAccounts,OU=Tier0,OU=Admin,$($DomainInfo.DistinguishedName)"
    
New-ADGroup -Name "Delegate Control - Join Computers" -Path "OU=Groups,OU=Tier0,OU=Admin,$($DomainInfo.DistinguishedName)" -GroupScope Global
Add-ADGroupMember -Identity "Delegate Control - Join Computers" -Members $ServerConfig.JoinOptions.Username

$ADGroup = Get-ADGroup -Identity "Delegate Control - Join Computers"

@((Get-ADDomain).ComputersContainer
    (Get-ADOrganizationalUnit -Filter "name -eq 'JumpStationsLimited'").DistinguishedName
    (Get-ADOrganizationalUnit -Filter "name -eq 'JumpStations'").DistinguishedName
    (Get-ADOrganizationalUnit -Filter "name -eq 'Servers'").DistinguishedName
) | Foreach { Set-TSxOUPermission -OrganizationalUnitDN $_ -GroupName $ADGroup.Name -ObjectType ComputersCreate }



# Change Task to Completed
# ------------------------------------------------------------
if ($ServerConfig) {
    ($ServerConfig.Tasks | Where-Object { $_.Name -like "*$(Split-Path $PSCommandPath -Leaf)" }).status = "Completed"
    $ServerConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath "$RootPath\ServerConfig.json" -Encoding utf8 -Force
}
