<#

    Prepare Azure Arc GPO Deployment

#>

Import-Module ActiveDirectory

$DownloadFolder = "$($ENV:USERPROFILE)\Downloads"
$DomainInfo = Get-ADDomain


# Get latest version of the Arc GPO Deployment Script
# ------------------------------------------------------------
$LatestRelease = (Invoke-WebRequest -Uri "https://api.github.com/repos/Azure/ArcEnabledServersGroupPolicy/releases" -UseBasicParsing | ConvertFrom-Json)[0]
$Uri = $LatestRelease.assets.browser_download_url
$OutFile = $LatestRelease.assets.name

if (!(Test-Path -Path "$DownloadFolder\$OutFile")) {
    Write-Verbose "Resolved latest stable version, $($LatestRelease.Name)"
    Invoke-WebRequest -Uri $Uri -OutFile "$DownloadFolder\$OutFile" -UseBasicParsing
}

Expand-Archive -Path "$DownloadFolder\$OutFile" -DestinationPath "$DownloadFolder" -Force

$ArcAgent = Get-ChildItem -Path $DownloadFolder -Filter "AzureConnectedMachineAgent.msi" -Recurse
if ($null -eq $ArcAgent) {
    Invoke-WebRequest -Uri "https://gbl.his.arc.azure.com/azcmagent/latest/AzureConnectedMachineAgent.msi" -OutFile "$DownloadFolder\AzureConnectedMachineAgent.msi"
}

# Create SysVol Share.
$FolderRemotepath = "C:\Windows\SYSVOL\sysvol\Fabric.SecInfra.Dk\scripts\Arc Onbording"
if (!(Test-Path -Path $FolderRemotepath)) {
    New-Item -Path $FolderRemotepath -ItemType Directory | Out-Null
}
if (Test-Path -Path $FolderRemotepath) {

    # Create Required Folders.
    $AzureArcDeployPath = "$FolderRemotepath\AzureArcDeploy"
    New-Item -Path $AzureArcDeployPath -ItemType Directory | Out-Null

    $AzureArcLoggingPath = "$FolderRemotepath\AzureArcLogging"
    New-Item -Path $AzureArcLoggingPath -ItemType Directory | Out-Null

    # Assign appropiate permissions to the folders
    $Acl = Get-ACL -Path $AzureArcDeployPath
    $Acl.SetAccessRuleProtection($True, $True)
    Set-Acl -Path $AzureArcDeployPath -AclObject $Acl

    $Acl = Get-ACL -Path $AzureArcLoggingPath
    $Acl.SetAccessRuleProtection($True, $True)
    Set-Acl -Path $AzureArcLoggingPath -AclObject $Acl

    #Add Access to Domain Computers and Domain Controllers
    $DomainNetbios = $DomainInfo.NetBIOSName
    $DomainComputersSID = $DomainInfo.DomainSID.Value + '-515'
    $DomainComputersName = (Get-ADGroup -Filter "SID -eq `'$DomainComputersSID`'").Name
    $DomainControllersSID = $DomainInfo.DomainSID.Value + '-516'
    $DomainControllersName = (Get-ADGroup -Filter "SID -eq `'$DomainControllersSID`'").Name

    $identity = "$DomainNetbios\$DomainComputersName"
    $identity2 = "$DomainNetbios\$DomainControllersName"

    #Deploy Path
    $NewAcl = Get-ACL -Path $AzureArcDeployPath
    $fileSystemAccessRules = 
    @(   
        [System.Security.AccessControl.FileSystemAccessRule]::new($identity, 'ReadandExecute', "ContainerInherit,ObjectInherit", 'None', 'Allow')
        [System.Security.AccessControl.FileSystemAccessRule]::new($identity2, 'ReadandExecute', "ContainerInherit,ObjectInherit", 'None', 'Allow')  
    )
    foreach ($fileSystemAccessRule in $fileSystemAccessRules) {

        $NewAcl.SetAccessRule($fileSystemAccessRule)
        Set-Acl -Path $AzureArcDeployPath -AclObject $NewAcl
    }

    #Logging Path
    $NewAcl = Get-ACL -Path $AzureArcLoggingPath
    $fileSystemAccessRules = 
    @(   
        [System.Security.AccessControl.FileSystemAccessRule]::new($identity, 'ReadandExecute,Write,Modify', "ContainerInherit,ObjectInherit", 'None', 'Allow')
        [System.Security.AccessControl.FileSystemAccessRule]::new($identity2, 'ReadandExecute,Write,Modify', "ContainerInherit,ObjectInherit", 'None', 'Allow')  
    )
    foreach ($fileSystemAccessRule in $fileSystemAccessRules) {
        $NewAcl.SetAccessRule($fileSystemAccessRule)
        Set-Acl -Path $AzureArcLoggingPath -AclObject $NewAcl
    }

    # Copy Files.
    $ArcFiles = @()
    $ArcFiles += (Get-ChildItem -Path $DownloadFolder -Recurse -Filter "EnableAzureArc.ps1").FullName
    $ArcFiles += (Get-ChildItem -Path $DownloadFolder -Recurse -Filter "AzureArcDeployment.psm1").FullName
    $ArcFiles += (Get-ChildItem -Path $DownloadFolder -Recurse -Filter "AzureConnectedMachineAgent.msi").FullName

    $ArcFiles | Foreach { Copy-Item -Path $_ -Destination $AzureArcDeployPath }

    $ArcConnectionInfo = @{"ServicePrincipalClientId"="";"SubscriptionId"="";"ResourceGroup"="";"Location"="";"TenantId"="";"PrivateLinkScopeId"=""; "AgentProxy"=""; "Tags"=""}
    $ArcConnectionInfo | ConvertTo-Json | Out-File -FilePath "$AzureArcDeployPath\ArcInfo.json"

    Notepad "$AzureArcDeployPath\ArcInfo.json"
}

# Import Refrence GPO
$GPOName =  "MSFT Azure Arc Servers Onboarding"
New-GPO -Name $GPOName | Out-Null
(Get-GPO -Name $GPOName).GpoStatus = "UserSettingsDisabled"

$BackupPath = Get-ChildItem -Path $(Split-Path -Path $ArcFiles[0]) -Recurse -Directory -Filter "{*}"
$Backupid = ($BackupPath | Select-Object -First 1 -ExpandProperty Name) -replace "{" -replace "}"

$GPOData = Import-GPO -Path $(Split-Path $BackupPath.FullName) -TargetName $GPOName -BackupId $Backupid


# Change GPO Schedule
# ------------------------------------------------------------
[XML]$Schedule = Get-Content -Path "\\$($env:USERDNSDOMAIN)\sysvol\$($env:USERDNSDOMAIN)\Policies\{$($GPOData[0].ID)}\Machine\Preferences\ScheduledTasks\ScheduledTasks.xml"

$NewArgument = "-ExecutionPolicy Bypass -Command `"Copy-Item '\\$($DomainInfo.DNSroot)\SYSVOL\$($DomainInfo.DNSroot)\Scripts\Arc Onbording\AzureArcDeploy\EnableAzureArc.ps1' `$ENV:LOCALAPPDATA -Force -ErrorAction Stop; &  `$ENV:LOCALAPPDATA\EnableAzureArc.ps1 -ReportServerFQDN $($DomainInfo.DNSroot) -ArcRemoteShare 'SYSVOL\$($DomainInfo.DNSroot)\Scripts\Arc Onbording'`""
$Schedule.ScheduledTasks.ImmediateTaskV2.Properties.Task.Actions.Exec[0].Arguments = $NewArgument

$Schedule.Save("\\$($env:USERDNSDOMAIN)\sysvol\$($env:USERDNSDOMAIN)\Policies\{$($GPOData[0].ID)}\Machine\Preferences\ScheduledTasks\ScheduledTasks.xml")

# Link GPO to OUs
$GPOTargets += $DomainInfo.DomainControllersContainer
$GPOTargets | % { Get-GPO -Name $GPOName | New-GPLink -Target $_ }
    

# Assign All Servers WMI filter.
$allWmiFilters = $(New-Object Microsoft.GroupPolicy.GPDomain).SearchWmiFilters($(New-Object Microsoft.GroupPolicy.GPSearchCriteria))
$DefaultWMIFilter = ($allWmiFilters | Where-Object {$_.Name -like "*Windows*Server*[ALL]*"})[0]

if ($DefaultWMIFilter) {
    $(Get-GPO -Name $GPOName).WmiFilter = $DefaultWMIFilter
}
