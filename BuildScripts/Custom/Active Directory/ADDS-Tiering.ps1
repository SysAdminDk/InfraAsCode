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

# Path to PVE scripts and Functions.
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


# Wait until AD Tiering file is copied.
# ------------------------------------------------------------
if (-NOT (Test-Path -Path "$RootPath\ADTiering.zip")) {
    Write-Output "Please copy the Truesec Active Directory Tiering file to $RootPath"
    for ($i=0; $i -lt 9999; $i++) {
        if (Test-Path -Path "$RootPath\ADTiering.zip") {
            break
        } else {
            Start-Sleep -Seconds 30
        }
    }
}


# Extract Tiering Package
# ------------------------------------------------------------
Expand-Archive -Path "$RootPath\ADTiering.zip" -DestinationPath $RootPath -Force


# Find the AD Tiering Scripts
# ------------------------------------------------------------
$ADTieringScript = Get-ChildItem -Path $RootPath -Recurse -Include "Deploy-TSxADTiering.ps1"


# Setup TS AD Tiering
# ------------------------------------------------------------
Remove-Item -Path (Get-ChildItem -Path $($ADTieringScript.Directory.FullName) -Filter "*.csv").fullname

& $($ADTieringScript.FullName) -CompanyName "$((Get-ADDomain).Name) Endpoints" -TierOUName "Admin" -NoOfTiers 1 -SkipTierEndpointsPAW -SkipTierEndpoints -SkipComputerRedirect -WindowsLAPSOnly
#    & $($ADTieringScript.FullName) -CompanyName "$((Get-ADDomain).Name) Endpoints" -TierOUName "Admin" -NoOfTiers 2 -WindowsLAPSOnly


# Import TS Tiering Module
# ------------------------------------------------------------
Import-Module (Get-ChildItem -Path $PSScriptRoot -Recurse -Filter "TSxTieringModule.psm1").FullName -Force


# List all OrganizationalUnits used in Domain JSON files.
# ------------------------------------------------------------
$DomainInfo = $(Get-ADDomain)

$MACFilter = @("00", "00") + ((((Get-NetAdapter | Where {$_.Status -eq "UP"} | Select-Object -First 1).MacAddress) -Split("-"))[2..4]) -Join("-")

$URL = "$RepoUrl/ConfigFiles/JSON"

$FLResponse = Invoke-WebRequest -Uri $URL -ErrorAction Stop -UseBasicParsing
$GitJsonFiles = ($FLResponse.Links.href | Where {$_ -like "*$MACFilter*"}) -replace("/$($Deployment.VirtualPath)","")

$CreateOUs = New-Object System.Collections.ArrayList
$CreateServers = New-Object System.Collections.ArrayList

$GitJsonFiles | Foreach {

    Invoke-WebRequest -Uri "$RepoUrl/$($_)" -UseBasicParsing -OutFile "$($ENV:TEMP)\JsonConvert.json"
    $ServerData = Get-Content -Path "$($ENV:TEMP)\JsonConvert.json" -Raw -Encoding UTF8 | ConvertFrom-Json

    if ($ServerData.JoinOptions.OrganizationalUnit) {
        $OrganizationalUnit = @($($ServerData.JoinOptions.OrganizationalUnit), $($DomainInfo.DistinguishedName)) -join(",")
        $CreateServers += [PSCustomObject]@{ Name = $($ServerData.name); Path = $OrganizationalUnit }
            
        try {
            $OUTest = Get-ADOrganizationalUnit -Identity $OrganizationalUnit
        }
        Catch {

            $OUParts = $OrganizationalUnit -split(",")

            $OUName = $OUParts[0] -replace '^OU='

            $AdminOUIndex = $OUParts.IndexOf('OU=Admin')
            if ($AdminOUIndex -gt 0) { $OUTier = $OUParts[$AdminOUIndex - 1] -replace '^OU=' }

            $CreateOUs += $([PSCustomObject]@{ Name = $OUName; Tier = $OUTier })
        }
    }
}


# Create all OUs listed in Domain JSON files.
# ------------------------------------------------------------
$CreateOUs | Sort-Object -Unique -Property Name | Foreach {
    New-TSxSubOU -Tier $_.Tier -Name $_.Name -Description "$($_Tier) $($_.Name)" -TierOUName "Admin" -CompanyName "Dev Endpoints" -WindowsLAPSOnly -Cleanup
}
    

# Get Data from Json Config
# ------------------------------------------------------------
If (Test-Path -Path "$PSScriptRoot\ServerConfig.json") {
    $ServerConfig = Get-Content -Path "$PSScriptRoot\ServerConfig.json" | ConvertFrom-Json
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

@((Get-ADOrganizationalUnit -Filter "name -eq 'ComputerQuarantine'").DistinguishedName
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
