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


# Get Required Files from GIT
# ------------------------------------------------------------
$GitConnection = Get-Content -Path "$RootPath\GitHub-Connection.json" | Convertfrom-Json


if ($($GitConnection.Token)) {
    $Response = Invoke-RestMethod -Uri "$($GitConnection.Url)/LAB-Infrastructure/contents/Tools/ADTiering.zip" -Headers @{ Authorization = "token $($GitConnection.Token)" }
} else {
    $Response = Invoke-RestMethod -Uri "$($GitConnection.Url)/LAB-Infrastructure/contents/Tools/ADTiering.zip"
}
$FileBytes = [System.Convert]::FromBase64String($Response.content)
[System.IO.File]::WriteAllBytes("$PSScriptRoot\$($Response.name)", $FileBytes)


# Setup Active Directory Tiering.
# ------------------------------------------------------------
if (Test-Path -Path "$PSScriptRoot\$($Response.name)") {


    # Extract the TS AD Tiering Package
    # ------------------------------------------------------------
    Expand-Archive -Path "$PSScriptRoot\$($Response.name)" -DestinationPath $PSScriptRoot -Force


    # Find the AD Tiering Scripts
    # ------------------------------------------------------------
    $ADTieringScript = Get-ChildItem -Path $PSScriptRoot -Recurse -Include "Deploy-TSxADTiering.ps1"


    # Setup TS AD Tiering
    # ------------------------------------------------------------
    Remove-Item -Path (Get-ChildItem -Path $($ADTieringScript.Directory.FullName) -Filter "*.csv").fullname

#    & $($ADTieringScript.FullName) -CompanyName "$((Get-ADDomain).Name) Endpoints" -TierOUName "Admin" -NoOfTiers 1 -SkipTierEndpointsPAW -SkipTierEndpoints -SkipComputerRedirect -WindowsLAPSOnly
    & $($ADTieringScript.FullName) -CompanyName "$((Get-ADDomain).Name) Endpoints" -TierOUName "Admin" -NoOfTiers 2 -WindowsLAPSOnly


    # Import TS Tiering Module
    # ------------------------------------------------------------
    Import-Module (Get-ChildItem -Path $PSScriptRoot -Recurse -Filter "TSxTieringModule.psm1").FullName -Force


    # List all OrganizationalUnits used in Domain JSON files.
    # ------------------------------------------------------------
    $DomainInfo = $(Get-ADDomain)

    $MACFilter = @("00", "00") + ((((Get-NetAdapter | Where {$_.Status -eq "UP"} | Select-Object -First 1).MacAddress) -Split("-"))[2..4]) -Join("-")

    $URL = "$($GitConnection.Url)/LAB-Deployment/contents/ConfigFiles/JSON"

    if ($($GitConnection.Token)) {
        $FLResponse = Invoke-RestMethod -Uri $URL -Headers @{ Authorization = "token $($GitConnection.Token)" } -ErrorAction Stop
    } else {
        $FLResponse = Invoke-RestMethod -Uri $URL -ErrorAction Stop
    }
    $GitJsonFiles = $FLResponse.Name | % { ($_ -split("\."))[0] } | Where {$_ -like "$MACFilter*"}

    $CreateOUs = New-Object System.Collections.ArrayList
    $CreateServers = New-Object System.Collections.ArrayList

    $GitJsonFiles | Foreach {
        if ($($GitConnection.Token)) {
            $DLResponse = Invoke-RestMethod -Uri "$($GitConnection.Url)/LAB-Deployment/contents/ConfigFiles/JSON/$($_).json" -Headers @{ Authorization = "token $($GitConnection.Token)" } -ErrorAction Stop
        } else {
            $DLResponse = Invoke-RestMethod -Uri "$($GitConnection.Url)/LAB-Deployment/contents/ConfigFiles/JSON/$($_).json" -ErrorAction Stop
        }
        $FileBytes = [System.Convert]::FromBase64String($DLResponse.content)
        $JsonText = ([System.Text.Encoding]::UTF8.GetString($FileBytes)).TrimStart([char]0xFEFF)
        $ServerData = $JsonText | ConvertFrom-Json

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
    if (-Not(Get-ADOrganizationalUnit -Filter "Name -eq 'ComputerQuarantine'")) {
        $NewOU = New-TSxADOrganizationalUnit -Name "ComputerQuarantine" -Path "OU=Admin,$($DomainInfo.DistinguishedName)"
        & redircmp.exe $NewOU.DistinguishedName
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

}


# Get Data from Json Config
# ------------------------------------------------------------
If (Test-Path -Path "$PSScriptRoot\ServerConfig.json") {
    $ServerConfig = Get-Content -Path "$PSScriptRoot\ServerConfig.json" | ConvertFrom-Json
}


# Change Task to Completed
# ------------------------------------------------------------
if ($ServerConfig) {
    ($ServerConfig.Tasks | Where-Object { $_.Name -eq "ADDS-01.ps1" }).status = "Completed"
    $ServerConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath "$RootPath\ServerConfig.json" -Encoding utf8 -Force
}
