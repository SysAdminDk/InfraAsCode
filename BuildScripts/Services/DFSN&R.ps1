<#
      ___      _           _         _____ _                    
     / _ \    | |         (_)       /  ___| |                   
    / /_\ \ __| |_ __ ___  _ _ __   \ `--.| |__   __ _ _ __ ___ 
    |  _  |/ _` | '_ ` _ \| | '_ \   `--. \ '_ \ / _` | '__/ _ \
    | | | | (_| | | | | | | | | | | /\__/ / | | | (_| | | |  __/
    \_| |_/\__,_|_| |_| |_|_|_| |_| \____/|_| |_|\__,_|_|  \___|


    Actions
    1. Configure DFS
    2. Configure DFS-R

    3. Update GPO for drive mapping


# Install DFS Namespace Server.
# Create the Namespace Folder.
# Share the Namespace Folder
# - Remote ON DFS Name Space Server.

#>

# Local Variables
# ------------------------------------------------------------
$ShareName = "IT-Admin$"
$DFSRoot = "Shares"


# Verify Domain Membership
# ------------------------------------------------------------
if (-not ((Get-WmiObject -Class win32_computersystem).partofdomain)) {
    
    Throw "Domain join have must have failed"

}


# Is Domain Member, Install...
# ------------------------------------------------------------
if ((Get-WmiObject -Class win32_computersystem).partofdomain) {


    # Install required Featuers on the DFS Namespace Server
    # --
    Install-WindowsFeature -Name FS-DFS-Namespace -IncludeManagementTools


    # Make DFS Root path
    # --
    if (!(Test-Path -Path "C:\DFSRoots\$DFSRoot")) {
        New-Item -Path "C:\DFSRoots\$DFSRoot" -ItemType Directory | Out-Null
    }
    if (!(Get-SmbShare -Name $DFSRoot -ErrorAction SilentlyContinue)) {
        New-SMBShare -Path "C:\DFSRoots\$DFSRoot" -Name $DFSRoot -ErrorAction Stop | Out-Null
    }


    # Test the share exists on all File servers
    # ------------------------------------------------------------
    $FileServers = Get-ADComputer -Filter "Name -ne '$($env:COMPUTERNAME)'" -SearchBase "OU=FileServers,OU=Servers,OU=Tier1,OU=Admin,$((Get-ADDomain).DistinguishedName)"

    $SmbShare = Invoke-Command -ComputerName $FileServers.DNSHostName -ScriptBlock {

        $SmbShare = Get-SMBShare -Name $Using:ShareName -ErrorAction SilentlyContinue
        if (!($SmbShare)) {
            Throw "Missing share, unable to setup replication"
        }
        Return $SmbShare
    }


    # Setup the DFS Root & Grant management permissions.
    # ------------------------------------------------------------
    if (!(Get-DfsnRoot -Path "\\$($env:USERDNSDOMAIN)\$DFSRoot" -ErrorAction SilentlyContinue)) {
        New-DfsnRoot -Path "\\$($env:USERDNSDOMAIN)\$DFSRoot" -TargetPath "\\$($DFSServer.DNSHostName)\$DFSRoot" -Type DomainV2 | Out-Null
    }
    Set-DfsnRoot -GrantAdminAccounts $(Get-ADGroup -Filter "Name -like '*Tier1*DFS*'").Name -Path "\\$($env:USERDNSDOMAIN)\$DFSRoot" | Out-Null
    Set-DfsnRoot -Path "\\$($env:USERDNSDOMAIN)\$DFSRoot" -EnableAccessBasedEnumeration $true -EnableTargetFailback $true | Out-Null


    # Create the DFS Folder, add both Fileservers as Targets.
    # ------------------------------------------------------------
    $DFSShareName = $ShareName -replace("\$","")
    if (!(Get-DfsnFolder -Path "\\$($env:USERDNSDOMAIN)\$DFSRoot\$DFSShareName" -ErrorAction SilentlyContinue)) {
        New-DfsnFolder -Path "\\$($env:USERDNSDOMAIN)\$DFSRoot\$DFSShareName" -TargetPath "\\$($FileServers[0].DNSHostName)\$ShareName" -ReferralPriorityClass globalhigh -ReferralPriorityRank 0 | Out-Null
        New-DfsnFolderTarget -Path "\\$($env:USERDNSDOMAIN)\$DFSRoot\$DFSShareName" -TargetPath "\\$($FileServers[1].DNSHostName)\$ShareName" -ReferralPriorityClass globallow -ReferralPriorityRank 31 | Out-Null
    }


    # Create Replication Group
    # ------------------------------------------------------------
    $FileServers[0].DNSHostName
    If (!(Get-DfsReplicationGroup -GroupName $DFSShareName -ErrorAction SilentlyContinue)) {
        New-DfsReplicationGroup -GroupName $DFSShareName | Out-Null
    
        Grant-DfsrDelegation -GroupName $DFSShareName -AccountName $(Get-ADGroup -Filter "Name -like '*Tier1*DFS*'").Name -Force | Out-Null

        New-DfsReplicatedFolder -GroupName $DFSShareName -FolderName $DFSShareName -DfsnPath "\\$($env:USERDNSDOMAIN)\$DFSRoot\$DFSShareName" | Out-Null
        $FileServers | Foreach {
            Add-DfsrMember -GroupName $DFSShareName -ComputerName $_.DNSHostName | Out-Null
        }

        $PrimaryMember = $SmbShare | Where {$_.PSComputerName -eq $FileServers[0].DNSHostName}
        Set-DfsrMembership -GroupName $DFSShareName -FolderName $DFSShareName -ComputerName $PrimaryMember.PSComputerName -ContentPath $PrimaryMember.Path -PrimaryMember $True -Force | Out-Null

        $SecondaryMember = $SmbShare | Where {$_.PSComputerName -eq $FileServers[1].DNSHostName}
        Set-DfsrMembership -GroupName $DFSShareName -FolderName $DFSShareName -ComputerName $SecondaryMember.PSComputerName -ContentPath $SecondaryMember.Path -Force | Out-Null

        Add-DfsrConnection -GroupName $DFSShareName -SourceComputerName $PrimaryMember.PSComputerName -DestinationComputerName $SecondaryMember.PSComputerName | Out-Null

        Get-DfsnFolderTarget -Path "\\$($env:USERDNSDOMAIN)\$DFSRoot\$DFSShareName" -TargetPath "\\$($FileServers[0].DNSHostName)\$ShareName" | Set-DfsnFolderTarget -ReferralPriorityClass globalhigh -ReferralPriorityRank 0 | Out-Null
        Get-DfsnFolderTarget -Path "\\$($env:USERDNSDOMAIN)\$DFSRoot\$DFSShareName" -TargetPath "\\$($FileServers[1].DNSHostName)\$ShareName" | Set-DfsnFolderTarget -ReferralPriorityClass globallow -ReferralPriorityRank 31 | Out-Null
    }


    # Update GPO drive mapping on for T0 and T1 users.
    # ------------------------------------------------------------
    if (Get-GPO -Name "User - Map IT Admin share" -ErrorAction SilentlyContinue) {

        # Get the path of selected GPO
        # ------------------------------------------------------------
        $GPO = Get-GPO -Name "User - Map IT Admin share"
        $DNSRoot = (Get-ADDomain).DNSRoot
        $GpoPath = "\\$DNSRoot\sysvol\$DNSRoot\Policies\{$($GPO.id.Guid)}"


        # Update Network Path for Drive Mapping to the DFS path
        # ------------------------------------------------------------
        if (Test-Path -Path "$GpoPath\user\Preferences\Drives") {
            $DrivesData = Get-Content -Path "$GpoPath\user\Preferences\Drives\Drives.xml"
            $NewDrivesData = $DrivesData -replace("$($FileServers[0].DNSHostName)\\$($ShareName.Replace("$","\$"))","$($env:USERDNSDOMAIN)\$DFSRoot\$DFSShareName")
            $NewDrivesData | Out-File "$GpoPath\user\Preferences\Drives\Drives.xml" -Encoding utf8 -Force
        }


        # Update the GPT.ini file, to force read of GPO
        # ------------------------------------------------------------
        $GPT = @()
        $GPT += "[General]"
        $GPT += "Version=131072"
        $GPT | Out-File "$GpoPath\GPT.ini" -Encoding utf8 -Force

    }
}