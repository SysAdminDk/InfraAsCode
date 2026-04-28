<#

    Remote Desktop Session Broker Database Server - SQL Always On.

#>


<#

    Install SQL Always On, for Remote Desktop Session Broker.

#>


# Create SQL servers AD Group.
# --
$RDDBServers = ($($ServerInfo | Where {$_.Role -eq "RDDB"}).Name | Get-ADComputer -ErrorAction SilentlyContinue)
$RDDBServers = Get-ADComputer -Filter "Name -like '*RDDB-0*'" | Sort-Object -Property Name
New-ADGroup -Name "RDDB - Servers" -Description "* Group Managed Service account" -GroupScope Global -GroupCategory Security -Path "OU=Groups,OU=Tier1,$TierSearchBase"
Add-ADGroupMember -Identity $(Get-ADGroup -Identity "RDDB - Servers") -Members $RDDBServers


## Remember to reboot the servers after Group Join...
Invoke-Command -ComputerName $RDDBServers.DNSHostName -ScriptBlock {
    $gpresult = gpresult /r /scope computer
    if (!($gpresult -Match "RDDB - Servers")) {
        Gpupdate /force
        Shutdown -r -t 5
    }
}


# Add SQL GMSA
# --
New-TSxServiceAccount -FirstName "Service" -LastName "Account RDDB" -AccountName gMSA_RDDB -UserType gMSA -AccountType T1SVC
Set-ADServiceAccount -Identity gMSA_RDDB -PrincipalsAllowedToRetrieveManagedPassword $(Get-ADGroup -Identity "RDDB - Servers")


# Allow Service account to create SPN on SELF
dsacls $(Get-ADServiceAccount gMSA_RDDB).DistinguishedName /G "SELF:RPWP;servicePrincipalName" | Out-Null
#dsacls $(Get-ADComputer -Identity RDDB).DistinguishedName /G "SELF:RPWP;servicePrincipalName" | Out-Null


setspn -s MSSQLSvc/RDDB-01:1433 Prod\gMSA_RDDB$
setspn -s MSSQLSvc/RDDB-01.PROD.SysAdmins.Dk:1433 Prod\gMSA_RDDB$
setspn -s MSSQLSvc/RDDB-01.PROD.SysAdmins.Dk:5022 Prod\gMSA_RDDB$

setspn -s MSSQLSvc/RDDB-02:1433 Prod\gMSA_RDDB$
setspn -s MSSQLSvc/RDDB-02.PROD.SysAdmins.Dk:1433 Prod\gMSA_RDDB$
setspn -s MSSQLSvc/RDDB-02.PROD.SysAdmins.Dk:5022 Prod\gMSA_RDDB$

setspn -D MSSQLSvc/RDDB-CLU:1433 Prod\gMSA_RDDB$
setspn -D MSSQLSvc/RDDB-CLU.PROD.SysAdmins.Dk:1433 Prod\gMSA_RDDB$

setspn -s MSSQLSvc/RDDB:1433 Prod\gMSA_RDDB$
setspn -s MSSQLSvc/RDDB.PROD.SysAdmins.Dk:1433 Prod\gMSA_RDDB$

#setspn -L Prod\gMSA_RDDB$


Set-ADAccountControl -Identity gMSA_RDDB$ -TrustedForDelegation $false -TrustedToAuthForDelegation $true

$Servers  = @()
$Servers += $(Get-ADComputer -Identity RDDB-01)
$Servers += $(Get-ADComputer -Identity RDDB-02)
$Servers += $(Get-ADComputer -Identity RDDB-CLU)
$Servers += $(Get-ADComputer -Identity RDDB)
Set-ADServiceAccount -Identity gMSA_RDDB$ -PrincipalsAllowedToDelegateToAccount $Servers

#(Get-ADServiceAccount -Identity gMSA_RDDB -Properties PrincipalsAllowedToDelegateToAccount).PrincipalsAllowedToDelegateToAccount


setspn -Q MSSQLSvc/RDDB-01.PROD.SysAdmins.Dk:1433
setspn -Q MSSQLSvc/RDDB-02.PROD.SysAdmins.Dk:1433
setspn -Q MSSQLSvc/RDDB.PROD.SysAdmins.Dk:1433

(Get-ADServiceAccount -Identity gMSA_RDDB$ -Properties *).'msDS-AllowedToDelegateTo'

$SPNs = setspn -L Prod\gMSA_RDDB$
Set-ADServiceAccount -Identity gMSA_RDDB$ -Add @{'msDS-AllowedToDelegateTo'=$spns}




setspn -Q MSSQLSvc/RDDB-01.PROD.SysAdmins.Dk:1433
setspn -Q MSSQLSvc/RDDB-02.PROD.SysAdmins.Dk:1433

setspn -L RDDB-01$
setspn -L RDDB-02$



# Create Cluster objects
$Path = ($RDDBServers[0].DistinguishedName -Split(","))[1..99] -Join(",")
New-ADComputer -Name "RDDB-CLU" -Path $Path -Enabled $False
$ACL = Get-ACL -Path "AD:\CN=RDDB-CLU,$Path"
$ACL.Access | Where {$_.IdentityReference -like "*RDDB-0*"}

<#
ActiveDirectoryRights : GenericAll
InheritanceType       : None
ObjectType            : 00000000-0000-0000-0000-000000000000
InheritedObjectType   : 00000000-0000-0000-0000-000000000000
ObjectFlags           : None
AccessControlType     : Allow
IdentityReference     : PROD\RDDB-01$
IsInherited           : False
InheritanceFlags      : None
PropagationFlags      : None

ActiveDirectoryRights : GenericAll
InheritanceType       : None
ObjectType            : 00000000-0000-0000-0000-000000000000
InheritedObjectType   : 00000000-0000-0000-0000-000000000000
ObjectFlags           : None
AccessControlType     : Allow
IdentityReference     : PROD\RDDB-02$
IsInherited           : False
InheritanceFlags      : None
PropagationFlags      : None
#>


New-ADComputer -Name "RDDB" -Path $Path -Enabled $False
$ACL = Get-ACL -Path "AD:\CN=RDDB,$Path"
$ACL.Access | Where {$_.IdentityReference -like "*RDDB-Clu*"}

<#
ActiveDirectoryRights : GenericAll
InheritanceType       : None
ObjectType            : 00000000-0000-0000-0000-000000000000
InheritedObjectType   : 00000000-0000-0000-0000-000000000000
ObjectFlags           : None
AccessControlType     : Allow
IdentityReference     : PROD\RDDB-Clu$
IsInherited           : False
InheritanceFlags      : None
PropagationFlags      : None

ActiveDirectoryRights : WriteProperty
InheritanceType       : None
ObjectType            : 3e978926-8c01-11d0-afda-00c04fd930c9
InheritedObjectType   : 00000000-0000-0000-0000-000000000000
ObjectFlags           : ObjectAceTypePresent
AccessControlType     : Allow
IdentityReference     : PROD\RDDB-Clu$
IsInherited           : False
InheritanceFlags      : None
PropagationFlags      : None

ActiveDirectoryRights : WriteProperty
InheritanceType       : None
ObjectType            : 3e978925-8c01-11d0-afda-00c04fd930c9
InheritedObjectType   : 00000000-0000-0000-0000-000000000000
ObjectFlags           : ObjectAceTypePresent
AccessControlType     : Allow
IdentityReference     : PROD\RDDB-Clu$
IsInherited           : False
InheritanceFlags      : None
PropagationFlags      : None
#>



# Download SQL eval install
#$TxScriptPath = "C:\TS-Data"
Invoke-WebRequest -Uri "https://download.microsoft.com/download/4/1/b/41b9a8c3-c2b4-4fcc-a3d5-62feed9e6885/SQL2022-SSEI-Eval.exe?culture=en-us&country=us" -OutFile "$($TxScriptPath)\Download\SQL-Eval-2022.exe"
& "$($TxScriptPath)\Download\SQL-Eval-2022.exe" Action=Download MEDIATYPE=ISO MEDIAPATH="$($TxScriptPath)\Download" QUIET 


Invoke-WebRequest -Uri "https://download.microsoft.com/download/9/b/e/9bee9f00-2ee2-429a-9462-c9bc1ce14c28/SSMS-Setup-ENU.exe" -OutFile "$($TxScriptPath)\Download\SSMS-Setup-ENU.exe"
# Install this on MGMT-11 and MGMT-12 / Perhaps also on MGMT-01 and MGMT-02


# Select Destination OU
# ------------------------------------------------------------
$TargetPath = (Get-ADOrganizationalUnit -Filter * -SearchBase $TierSearchBase | `
    Where {$_.DistinguishedName -like "OU=*OU=Servers,OU=Tier1,$TierSearchBase"}) | `
        Select-Object Name,DistinguishedName | Out-GridView -Title "Select Destination OU" -OutputMode Single


# Install & Configure 
# ------------------------------------------------------------
$RDDBServers | Foreach {

    If ( ($Null -ne $TargetPath) -and ($($_.DistinguishedName) -NotLike "*OU=Servers,OU=Tier1*") ) {
        Move-ADObject -Identity $($_.DistinguishedName) -TargetPath $TargetPath.DistinguishedName
    }


    # Connect to the server.
    # ------------------------------------------------------------
    $Session = New-PSSession -ComputerName "$($_.DNSHostName)"


    # Copy required installers to target server
    # ------------------------------------------------------------
    @(
        "AzureConnectedMachineAgent.msi",
        "SQLServer2022-x64-ENU.iso"

    ) | Foreach {
#        Get-ChildItem -Path $TxScriptPath -Filter $_ -Recurse | Copy-Item -Destination "$($ENV:PUBLIC)\downloads\$_" -ToSession $Session -Force
    }


    # Execute commands.
    # ------------------------------------------------------------
    Invoke-Command -Session $Session -ScriptBlock {

        # Install Azure Arc Agent
        # ------------------------------------------------------------
        if (Test-Path -Path "$($ENV:PUBLIC)\downloads\AzureConnectedMachineAgent.msi") {
            #Start-Process -FilePath "$($ENV:PUBLIC)\downloads\AzureConnectedMachineAgent.msi" -ArgumentList "/quiet /qn /norestart" -wait
        }


        # Ensure the CDROM, if any dont use the D: Drive
        # ------------------------------------------------------------
        $MediaDrive = Get-WmiObject -Class Win32_volume -Filter "DriveType = '5' and DriveLetter != 'X:'"
        if ($null -ne $MediaDrive) {
            Set-WmiInstance -InputObject $MediaDrive -Arguments @{DriveLetter='X:'} | Out-Null
        }


        # Get any RAW drives, format and assign Drive letter.
        # ------------------------------------------------------------
        $RawDisks = (Get-Disk | Where {$_.PartitionStyle -eq "RAW"}) | Sort-Object -Property Size -Descending
        $RawDisks | Where {$_.PartitionStyle -eq "RAW" -AND $_.Size -eq 30Gb} | Initialize-Disk -PassThru | New-Partition -UseMaximumSize -DriveLetter "D" | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Data Disk" -Confirm:$false
        $RawDisks | Where {$_.PartitionStyle -eq "RAW" -AND $_.Size -eq 10Gb} | Initialize-Disk -PassThru | New-Partition -UseMaximumSize -DriveLetter "L" | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Logs Disk" -Confirm:$false


        # Install Required Features.
#        Install-WindowsFeature -Name @("Failover-Clustering","Storage-Replica","NET-Framework-Features") -IncludeManagementTools -Verbose
        Install-WindowsFeature -Name @("Failover-Clustering","NET-Framework-Features") -IncludeManagementTools -Verbose


        # Mount SQL install media
        $ISODrive = Mount-DiskImage -ImagePath "$($ENV:PUBLIC)\Downloads\SQLServer2022-x64-ENU.iso" -StorageType ISO


<#

        # Install SQL standard.

#>

        # Open Firewall for 1433 & 5022
        if (!(Get-NetFirewallRule -DisplayName "Allow MSSQL on 1433")) {
            New-NetFirewallRule -DisplayName "Allow MSSQL on 1433" -Direction Inbound -Action Allow -Protocol TCP -LocalPort "1433" | Out-Null
        }
        Get-NetFirewallRule -DisplayName "Allow MSSQL on 1433" | Set-NetFirewallRule -RemoteAddress @RDCBServers

#        New-NetFirewallRule -DisplayName "Allow MSSQL on 1434" -Direction Inbound -Action Allow -Protocol TCP -LocalPort "1434" | Out-Null
#        Get-NetFirewallRule -DisplayName "Allow MSSQL on 1434" | Set-NetFirewallRule -RemoteAddress @....

        if (!(Get-NetFirewallRule -DisplayName "Allow MSSQL on 5022")) {
            New-NetFirewallRule -DisplayName "Allow MSSQL on 5022" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5022 | Out-Null
        }
        Get-NetFirewallRule -DisplayName "Allow MSSQL on 5022" | Set-NetFirewallRule -RemoteAddress @SQLServers


        # Test if we have a D:\ Drive where the shares can be created.
        # ------------------------------------------------------------
        if ( (!(Get-Partition -DriveLetter $Using:ServerDataDrive -ErrorAction SilentlyContinue)) -And (!($Disk)) ) {
            Throw "No drive avalible"
        }
    }
}


# Create Windows Server Failower Cluster
# ------------------------------------------------------------
$CluAddress = ($ImportServerInfo | Where {$_.role -eq "CLU" -and $_.Name -eq "RDDB-Clu"}).IpAddress
$CluAddress = "10.36.8.51"
$CluName = (($ImportServerInfo | Where {$_.role -eq "CLU" -and $_.Name -eq "RDDB-CLU"})[0]).Name
$CluName = "RDDB-Clu"
if ($Null -eq (Get-Cluster -Domain $ENV:USERDOMAIN | Where {$_.Name -eq "$CluName"})) {
    New-Cluster -Name "$CluName" -Node $RDDBServers.DNSHostName -StaticAddress $CluAddress
}


# Create Connection Broker Database, and enable "Always On"
# ------------------------------------------------------------
$DBName = "RDConnectionBroker"
$DbAddress = "10.36.8.58"

Invoke-Command -ComputerName $RDDBServers[0].DNSHostName -ScriptBlock {
#Enter-PSSession -ComputerName $RDDBServers[0].DNSHostName

    if (!(Get-Module -Name SQLPS)) {
        Import-Module "C:\Program Files (x86)\Microsoft SQL Server\160\Tools\PowerShell\Modules\SQLPS\SQLPS.psd1"
    }

    # Enable SQL Always On.
    if ((get-item  "SQLSERVER:\SQL\$($ENV:ComputerName)\Default").IsHadrEnabled) {
        Disable-SqlAlwaysOn -Path "SQLSERVER:\SQL\$($ENV:ComputerName)\Default" -Force
    }
    if (!((get-item  "SQLSERVER:\SQL\$($ENV:ComputerName)\Default").IsHadrEnabled)) {
        Enable-SqlAlwaysOn -Path "SQLSERVER:\SQL\$($ENV:ComputerName)\Default" -Force
    }


    # Restart SQL Service
    Get-Service -Name MSSQLSERVER | Restart-Service -Force


    # Add Connection Broker Group to SQL
    # ------------------------------------------------------------
    Invoke-Sqlcmd -Query "Create Login [PROD\RDCB - Servers] from Windows"
    Invoke-Sqlcmd -Query "Alter Server role DBCreator add member [PROD\RDCB - Servers]"

    # Verify connection broker Database Name
    # ------------------------------------------------------------
    try {
        Invoke-Sqlcmd -Query "Use $Using:DBName" -ErrorAction Stop
        Invoke-Sqlcmd -Query "Use $DBName" -ErrorAction Stop
    }
    Catch {
        Invoke-Sqlcmd -Query "CREATE DATABASE [$Using:DBName]"
        Invoke-Sqlcmd -Query "CREATE DATABASE [$DBName]"
    }

#    Invoke-Sqlcmd -Query "CREATE LOGIN [PROD\RDDB - Servers] FROM WINDOWS WITH DEFAULT_DATABASE=[$Using:DBName];"
#    Invoke-Sqlcmd -Query "USE [$DBName]; CREATE USER [PROD\RDDB - Servers] FOR LOGIN [PROD\RDDB - Servers];"
#    Invoke-Sqlcmd -Query "USE [$DBName]; ALTER ROLE [db_owner] ADD MEMBER [PROD\RDDB - Servers];"

    Invoke-Sqlcmd -Query "CREATE LOGIN [PROD\RDCB - Servers] FROM WINDOWS WITH DEFAULT_DATABASE=[$DBName];"
    Invoke-Sqlcmd -Query "Alter Server role DBCreator add member [PROD\RDCB - Servers]"
    Invoke-Sqlcmd -Query "USE [$DBName]; CREATE USER [PROD\RDCB - Servers] FOR LOGIN [PROD\RDCB - Servers];"
    Invoke-Sqlcmd -Query "USE [$DBName]; ALTER ROLE [db_owner] ADD MEMBER [PROD\RDCB - Servers];"


#    Invoke-Sqlcmd -Query "USE [$DBName]; ALTER ROLE [reader] ADD MEMBER [PROD\RDCB - Servers];"
#    Invoke-Sqlcmd -Query "USE [$DBName]; ALTER ROLE [db_owner] ADD MEMBER [PROD\RDCB - Servers];"

#
#    Invoke-Sqlcmd -Query "CREATE LOGIN [PROD\RDCB-01$] FROM WINDOWS WITH DEFAULT_DATABASE=[RDConnectionBroker];"
#    Invoke-Sqlcmd -Query "USE [RDConnectionBroker]; CREATE USER [PROD\RDCB-01$] FOR LOGIN [PROD\RDCB-01$];"
#    Invoke-Sqlcmd -Query "USE [RDConnectionBroker]; ALTER ROLE [db_owner] ADD MEMBER [PROD\RDCB-01$];"
#
#    Invoke-Sqlcmd -Query "CREATE LOGIN [PROD\RDCB-02$] FROM WINDOWS WITH DEFAULT_DATABASE=[RDConnectionBroker];"
#    Invoke-Sqlcmd -Query "USE [RDConnectionBroker]; CREATE USER [PROD\RDCB-02$] FOR LOGIN [PROD\RDCB-02$];"
#    Invoke-Sqlcmd -Query "USE [RDConnectionBroker]; ALTER ROLE [db_owner] ADD MEMBER [PROD\RDCB-02$];"
#
#
    Invoke-Sqlcmd -Query "CREATE LOGIN [PROD\gmsa_rddb$] FROM WINDOWS WITH DEFAULT_DATABASE=[master]"

    Invoke-Sqlcmd -Query "BACKUP DATABASE [$DBName] TO DISK = N'D:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Backup\RDConnectionBroker.bak' WITH NOFORMAT, NOINIT,  NAME = N'RDConnectionBroker-Full Database Backup', SKIP, NOREWIND, NOUNLOAD,  STATS = 10"

    Invoke-Sqlcmd -Query "CREATE ENDPOINT [Hadr_endpoint] AS TCP (LISTENER_PORT = 5022) FOR DATA_MIRRORING (ROLE = ALL, ENCRYPTION = REQUIRED ALGORITHM AES, AUTHENTICATION = WINDOWS KERBEROS)"
    Invoke-Sqlcmd -Query "ALTER ENDPOINT [Hadr_endpoint] STATE = STARTED"

    Invoke-Sqlcmd -Query "GRANT CONNECT ON ENDPOINT::[Hadr_endpoint] TO [PROD\gmsa_rddb$]"
    Invoke-Sqlcmd -Query "ALTER EVENT SESSION [AlwaysOn_health] ON SERVER WITH (STARTUP_STATE=ON)"
    Invoke-Sqlcmd -Query "ALTER EVENT SESSION [AlwaysOn_health] ON SERVER STATE=START"


    $RDDBServers = $Using:RDDBServers

    $SQLQuery = "USE [Master]; CREATE AVAILABILITY GROUP [RDDB-AG] WITH (AUTOMATED_BACKUP_PREFERENCE = SECONDARY, DB_FAILOVER = ON, DTC_SUPPORT = NONE,"
    $SQLQuery += "REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0) FOR DATABASE [$($Using:DBName)]"
    $SQLQuery += "REPLICA ON N'$($RDDBServers[0].Name)' WITH (ENDPOINT_URL = N'TCP://$($RDDBServers[0].DNSHostName):5022', FAILOVER_MODE = AUTOMATIC, AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, BACKUP_PRIORITY = 50, SEEDING_MODE = AUTOMATIC, SECONDARY_ROLE(ALLOW_CONNECTIONS = NO)),"
    $SQLQuery += "N'$($RDDBServers[1].Name)' WITH (ENDPOINT_URL = N'TCP://$($RDDBServers[1].DNSHostName):5022', FAILOVER_MODE = AUTOMATIC, AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, BACKUP_PRIORITY = 50, SEEDING_MODE = AUTOMATIC, SECONDARY_ROLE(ALLOW_CONNECTIONS = NO));"
    Invoke-Sqlcmd -Query $SQLQuery

    $SQLQuery = "USE [Master]; CREATE AVAILABILITY GROUP [RDDB-AG] WITH (AUTOMATED_BACKUP_PREFERENCE = SECONDARY, DB_FAILOVER = ON, DTC_SUPPORT = NONE,"
    $SQLQuery += "REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0) FOR DATABASE [$DBName]"
    $SQLQuery += "REPLICA ON N'RDDB-01' WITH (ENDPOINT_URL = N'TCP://RDDB-01.prod.sysadmins.dk:5022', FAILOVER_MODE = AUTOMATIC, AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, BACKUP_PRIORITY = 50, SEEDING_MODE = AUTOMATIC, SECONDARY_ROLE(ALLOW_CONNECTIONS = NO)),"
    $SQLQuery += "N'RDDB-02' WITH (ENDPOINT_URL = N'TCP://RDDB-02.prod.sysadmins.dk:5022', FAILOVER_MODE = AUTOMATIC, AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, BACKUP_PRIORITY = 50, SEEDING_MODE = AUTOMATIC, SECONDARY_ROLE(ALLOW_CONNECTIONS = NO));"
    Invoke-Sqlcmd -Query $SQLQuery


    Invoke-Sqlcmd -Query "USE [Master]; ALTER AVAILABILITY GROUP [RDDB-AG] ADD LISTENER N'$Using:DBName' (WITH IP ((N'$Using:DbAddress', N'255.255.255.0')), PORT=1433);"
    Invoke-Sqlcmd -Query "USE [Master]; ALTER AVAILABILITY GROUP [RDDB-AG] ADD LISTENER N'$DBName' (WITH IP ((N'$DbAddress', N'255.255.255.0')), PORT=1433);"
}
#exit

Invoke-Command -ComputerName $RDDBServers[1].DNSHostName -ScriptBlock {
#Enter-PSSession -ComputerName $RDDBServers[1].DNSHostName

    if (!(Get-Module -Name SQLPS)) {
        Import-Module "C:\Program Files (x86)\Microsoft SQL Server\160\Tools\PowerShell\Modules\SQLPS\SQLPS.psd1"
    }

    # Enable SQL Always On.
    if ((get-item  "SQLSERVER:\SQL\$($ENV:ComputerName)\Default").IsHadrEnabled) {
        Disable-SqlAlwaysOn -Path "SQLSERVER:\SQL\$($ENV:ComputerName)\Default" -Force
    }
    if (!((get-item  "SQLSERVER:\SQL\$($ENV:ComputerName)\Default").IsHadrEnabled)) {
        Enable-SqlAlwaysOn -Path "SQLSERVER:\SQL\$($ENV:ComputerName)\Default" -Force
    }
    
    # Restart SQL Service
    Get-Service -Name MSSQLSERVER | Restart-Service -Force


    # Add Connection Broker Group to SQL
    # ------------------------------------------------------------
    Invoke-Sqlcmd -Query "Create Login [PROD\RDCB - Servers] from Windows"
    Invoke-Sqlcmd -Query "Alter Server role DBCreator add member [PROD\RDCB - Servers]"

#    Invoke-Sqlcmd -Query "CREATE LOGIN [PROD\RDDB - Servers] FROM WINDOWS WITH DEFAULT_DATABASE=[master]"

    Invoke-Sqlcmd -Query "CREATE ENDPOINT [Hadr_endpoint] AS TCP (LISTENER_PORT = 5022) FOR DATA_MIRRORING (ROLE = ALL, ENCRYPTION = REQUIRED ALGORITHM AES, AUTHENTICATION = WINDOWS KERBEROS)"
    Invoke-Sqlcmd -Query "ALTER ENDPOINT [Hadr_endpoint] STATE = STARTED"

    Invoke-Sqlcmd -Query "CREATE LOGIN [PROD\gmsa_rddb$] FROM WINDOWS WITH DEFAULT_DATABASE=[master]"

    Invoke-Sqlcmd -Query "GRANT CONNECT ON ENDPOINT::[Hadr_endpoint] TO [PROD\gmsa_rddb$]"
    Invoke-Sqlcmd -Query "ALTER EVENT SESSION [AlwaysOn_health] ON SERVER WITH (STARTUP_STATE=ON)"
    Invoke-Sqlcmd -Query "ALTER EVENT SESSION [AlwaysOn_health] ON SERVER STATE=START"

    Invoke-Sqlcmd -Query "ALTER AVAILABILITY GROUP [RDDB-AG] JOIN;"
    Invoke-Sqlcmd -Query "ALTER AVAILABILITY GROUP [RDDB-AG] GRANT CREATE ANY DATABASE;"

##
    Invoke-Sqlcmd -Query "ALTER AVAILABILITY GROUP [RDDB-AG] FAILOVER;"

}
#exit