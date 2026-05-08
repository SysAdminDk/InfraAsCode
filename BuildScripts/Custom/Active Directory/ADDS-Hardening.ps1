<#

      ___       _   _            ______ _               _                     _   _               _            _             
     / _ \     | | (_)           |  _  (_)             | |                   | | | |             | |          (_)            
    / /_\ \ ___| |_ ___   _____  | | | |_ _ __ ___  ___| |_ ___  _ __ _   _  | |_| | __ _ _ __ __| | ___ _ __  _ _ __   __ _ 
    |  _  |/ __| __| \ \ / / _ \ | | | | | '__/ _ \/ __| __/ _ \| '__| | | | |  _  |/ _` | '__/ _` |/ _ \ '_ \| | '_ \ / _` |
    | | | | (__| |_| |\ V /  __/ | |/ /| | | |  __/ (__| || (_) | |  | |_| | | | | | (_| | | | (_| |  __/ | | | | | | | (_| |
    \_| |_/\___|\__|_| \_/ \___| |___/ |_|_|  \___|\___|\__\___/|_|   \__, | \_| |_/\__,_|_|  \__,_|\___|_| |_|_|_| |_|\__, |
                                                                       __/ |                                            __/ |
                                                                      |___/                                            |___/ 


    Adding MSFT  security baselines, and assigning them to Domain Controllers.

#>

# Install MSFT Baselines.
# ------------------------------------------------------------
$Uri = "https://api.github.com/repos/SysAdminDk/InfraTools/contents/Active%20Directory/Configure/Security%20Baselines/MSFT%20Baseline?ref=main"
$Files = Invoke-RestMethod -Uri $Uri -Headers @{ "User-Agent" = "Powershell" }

$Files | % { Invoke-WebRequest -Uri $_.download_url -OutFile "$PSScriptRoot\$($_.Name)" }


# Get MY Add WMI Filters script.
# ------------------------------------------------------------
$Uri = "https://api.github.com/repos/SysAdminDk/InfraTools/contents/Active%20Directory/Configure/Security%20Baselines/WMI-Filters?ref=main"
$Files = Invoke-RestMethod -Uri $Uri -Headers @{ "User-Agent" = "Powershell" }

$Files | % { Invoke-WebRequest -Uri $_.download_url -OutFile "$PSScriptRoot\$($_.Name)" }


# Get and install MSFT Baselines
# ------------------------------------------------------------
& "$PSScriptRoot\Import-MSFT-Baselines.ps1" -Path "$PSScriptRoot\Temp" -Action AutoInstall -OSVersions @("2022","2025") -Cleanup
& "$PSScriptRoot\Create-Overrides.ps1"
& "$PSScriptRoot\Update-MSFT-AuditPolicy.ps1"


# Create WMI Filters
# ------------------------------------------------------------
& "$PSScriptRoot\Create-WMIfilters.ps1"
& "$PSScriptRoot\Set-VMIFilters.ps1"


# Link MSFT Domain Controller Baselines to Domain Controllers OU
# ------------------------------------------------------------
Get-GPO -All | Where {$_.DisplayName -like "MSFT*Domain Controller"} | Sort-Object -Property DisplayName -Descending | New-GPLink -Target $(Get-ADDomain).DomainControllersContainer


# Link MSFT Baselines to Servers and JumpStations OUs
# ------------------------------------------------------------
$SearchBase = (Get-ADOrganizationalUnit -Filter "Name -like '*Admin*'" -SearchScope OneLevel).DistinguishedName

if ($SearchBase) {
    $GPOTargets = @()
    $GPOTargets += (Get-ADOrganizationalUnit -Filter "Name -like 'JumpStations*'" -SearchBase $SearchBase).DistinguishedName
    $GPOTargets += (Get-ADOrganizationalUnit -Filter "Name -eq 'Servers'" -SearchBase $SearchBase).DistinguishedName

    $GPOTargets | % { Get-GPO -All | Where {$_.DisplayName -like "MSFT*Member Server" -or $_.DisplayName -like "MSFT*Member Server*Overrides*"} | Sort-Object -Property DisplayName -Descending | New-GPLink -Target $_ }
}


# Create DISABLE Windows Laps Policy
# - GPO only applied IF C:\Windows\Panther\unattend.xml Exists.
# ------------------------------------------------------------
if (-NOT (Get-GPO -Name "MSFT - DISABLE Windows LAPS" -ErrorAction SilentlyContinue)) {
    $GPO = New-GPO -Name "MSFT - DISABLE Windows LAPS"
    (Get-GPO -Name $GPO.DisplayName).GpoStatus = "UserSettingsDisabled"
    
    Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS" -ValueName AutomaticAccountManagementEnabled -Value 0 -Type DWord | Out-Null
    Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS" -ValueName AutomaticAccountManagementTarget -value 1 -Type DWord | Out-Null
    Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS" -ValueName BackupDirectory -Value 0 -Type DWord | Out-Null

    # Create WMI Filter.
    # ------------------------------------------------------------
    "Detect Running Deployment; SELECT * From CIM_Datafile WHERE Name = `"C:\\Windows\\Panther\\unattend.xml`"" | `
        Out-File "$PSScriptRoot\WMI Query.txt" -Encoding utf8 -Append

    & "$PSScriptRoot\Create-WMIfilters.ps1"


    # Set WMI Filter
    # ------------------------------------------------------------
    $GPDomain = New-Object Microsoft.GroupPolicy.GPDomain
    $WMIFilter = $(New-Object Microsoft.GroupPolicy.GPDomain).SearchWmiFilters($(New-Object Microsoft.GroupPolicy.GPSearchCriteria)) | `
        Where-Object {$_.Name -like "Detect Running Deployment"}

    if ($WMIFilter) { $GPO.WmiFilter = $WMIFilter }


    # Link this Above other LAPS GPOs.
    # ------------------------------------------------------------
    $RefGpos = Get-GPO -All | Where {$_.DisplayName -like "*WindowsLAPS*Tier*"}
    foreach ($RefGpo in $RefGpos) {
        [XML]$GPReport = Get-GPOReport -ReportType Xml -Guid $RefGpo.ID

        foreach ($SOMPath in $GPReport.GPO.LinksTo) {

            $SomPathArray = ($SOMPath.SOMPath -replace "^[^/]+/","").Split("/")
            [array]::Reverse($SomPathArray)
            $OUPath = (($SomPathArray | % { $("OU=$($_)")}) -Join(",")) + ",$($(Get-ADDomain).DistinguishedName)"

            $LinkNumber = ((Get-GPInheritance -Target $OUPath).GpoLinks | Select-Object -Property Target,DisplayName,Enabled,Enforced,Order | Where {$_.DisplayName -eq $RefGpo.DisplayName}).Order
            New-GPLink -Name $GPO.DisplayName -Target $OUPath -LinkEnabled Yes -Order $LinkNumber | Out-Null
        }
    }
}


# Get Data from Json Config
# ------------------------------------------------------------
If (Test-Path -Path "$PSScriptRoot\ServerConfig.json") {
    $ServerConfig = Get-Content -Path "$PSScriptRoot\ServerConfig.json" | ConvertFrom-Json
}


# Change Task to Completed
# ------------------------------------------------------------
if ($ServerConfig) {
    ($ServerConfig.Tasks | Where-Object { $_.Name -like "*$(Split-Path $PSCommandPath -Leaf)" }).status = "Completed"
    $ServerConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath "$RootPath\ServerConfig.json" -Encoding utf8 -Force
}
