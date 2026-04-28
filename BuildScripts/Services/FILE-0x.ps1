<#
      ___      _           _         _____ _                    
     / _ \    | |         (_)       /  ___| |                   
    / /_\ \ __| |_ __ ___  _ _ __   \ `--.| |__   __ _ _ __ ___ 
    |  _  |/ _` | '_ ` _ \| | '_ \   `--. \ '_ \ / _` | '__/ _ \
    | | | | (_| | | | | | | | | | | /\__/ / | | | (_| | | |  __/
    \_| |_/\__,_|_| |_| |_|_|_| |_| \____/|_| |_|\__,_|_|  \___|


    Actions
    1. Format largest RAW disk
    2. Create file share
    3. Create GPO for drive mapping

#>


# Verify Domain Membership
# ------------------------------------------------------------
if (-not ((Get-WmiObject -Class win32_computersystem).partofdomain)) {
    
    Throw "Domain join have must have failed"

}


# Is Domain Member, Install...
# ------------------------------------------------------------
if ((Get-WmiObject -Class win32_computersystem).partofdomain) {

    
    # Local Variables
    # ------------------------------------------------------------
    $MappedDriveLetter = "Q"
    $ServerDataDrive = "D"
    $ShareName = "IT-Admin$"
    $SharePath = "$($ServerDataDrive):\Shares\IT Admin Share"
    $ShareDescription = "File share for IT Admins"
    $RWADGroup = Get-ADGroup -Identity "Admin File Share RW" -ErrorAction SilentlyContinue
    $ROADGroup = Get-ADGroup -Identity "Admin File Share RO" -ErrorAction SilentlyContinue


    # Ensure the CDROM, if any dont use the D: Drive
    # ------------------------------------------------------------
    $MediaDrive = Get-WmiObject -Class Win32_volume -Filter "DriveType = '5' and DriveLetter != 'X:'"
    if ($null -ne $MediaDrive) {
        Set-WmiInstance -InputObject $MediaDrive -Arguments @{DriveLetter='X:'} | Out-Null
    }


    # Get any RAW drives, format and assign Drive letter.
    # ------------------------------------------------------------
    $RawDisks = (Get-Disk | Where {$_.PartitionStyle -eq "RAW"}) | Sort-Object -Property Size -Descending
    $RawDisks | Select-Object -First 1 | Get-Disk | Initialize-Disk -PassThru | New-Partition -UseMaximumSize -DriveLetter $Using:ServerDataDrive | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Data Disk" -Confirm:$false


    # Test if we have a D:\ Drive where the shares can be created.
    # ------------------------------------------------------------
    if ( (!(Get-Partition -DriveLetter $Using:ServerDataDrive -ErrorAction SilentlyContinue)) -And (!($Disk)) ) {
        Throw "No drive avalible"
    }


    # Create Tier Share.
    # ------------------------------------------------------------
    If (!(Test-Path -Path $SharePath)) {
        New-Item -Path $SharePath -ItemType Directory
    }

    if ( (Test-Path -Path $SharePath) -AND (!(Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) ) {

        New-SmbShare -Name $ShareName -Description $ShareDescription -CachingMode None -Path $SharePath -EncryptData $true -ChangeAccess "NT AUTHORITY\Authenticated Users"

        # Read ACL and Disable inheritance
        $Acl = Get-Acl -Path $SharePath
        $acl.SetAccessRuleProtection($True, $True)
        $Acl | Set-Acl $SharePath


        # Read ACL agin.
        $Acl = Get-Acl -Path $SharePath

        # Remove users
        $Acl.Access | Where {$_.IdentityReference -eq "BUILTIN\Users"} | % {
            $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("$($_.IdentityReference)", "$($_.FileSystemRights)", "$($_.InheritanceFlags)", "$($_.PropagationFlags)", "$($_.AccessControlType)")
            $Acl.RemoveAccessRule($AccessRule)
        }

        # Add new groups
        if ($RWADGroup) {
            $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("$($ENV:USERDOMAIN)\$($RWADGroup)", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
            $Acl.AddAccessRule($AccessRule)
        }
        if ($ROADGroup) {
            $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("$($ENV:USERDOMAIN)\$($ROADGroup)", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")  
            $Acl.AddAccessRule($AccessRule)
        }

        $Acl | Set-Acl $SharePath
    }


<#
    # Create GPO drive mapping on for T0 and T1 users.
    # - Only to first file server, if DFS the GPO i updated in other script.
    # ------------------------------------------------------------
    if (!(Get-GPO -Name "User - Map IT Admin share" -ErrorAction SilentlyContinue)) {
        $GPO = New-GPO -Name "User - Map IT Admin share" -ErrorAction Stop
        (Get-GPO -Name $GPO.DisplayName).GpoStatus = "ComputerSettingsDisabled"

        $GpoPath = "\\$((Get-ADDomain).DNSRoot)\sysvol\$((Get-ADDomain).DNSRoot)\Policies\{$($GPO.id.Guid)}"

        if (!(Test-Path -Path "$GpoPath\user\Preferences\Drives")) {
            New-Item -Path "$GpoPath\user\Preferences\Drives" -ItemType Directory -Force | Out-Null
        }

        $Createdate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $DrivesData = @()
        $DrivesData += "<?xml version=`"1.0`" encoding=`"utf-8`"?>"
        $DrivesData += "<Drives clsid=`"{8FDDCC1A-0C3C-43cd-A6B4-71A6DF20DA8C}`">"
        $DrivesData += " <Drive clsid=`"{935D1B74-9CB8-4e3c-9914-7DD559B7A417}`" name=`"$($MappedDriveLetter):`" status=`"$($MappedDriveLetter):`" image=`"2`" changed=`"$Createdate`" uid=`"`">"
        $DrivesData += "  <Properties action=`"U`" thisDrive=`"NOCHANGE`" allDrives=`"NOCHANGE`" userName=`"`" path=`"\\$($FileServer[0].DNSHostName)\IT-Admin`$`" label=`"$($ShareDescription)`" persistent=`"1`" useLetter=`"1`" letter=`"Q`"/>"
        $DrivesData += " </Drive>"
        $DrivesData += "</Drives>"

        $DrivesData | Out-File "$GpoPath\user\Preferences\Drives\Drives.xml" -Encoding utf8 -Force


        # Update GPO version, Add Extention GUID, force read of XLM
        # ------------------------------------------------------------
        $GPT = @()
        $GPT += "[General]"
        $GPT += "Version=131072"
        $GPT | Out-File "$GpoPath\GPT.ini" -Encoding utf8 -Force


        # Wait for AD Replication
        # ------------------------------------------------------------
        Start-Sleep -Seconds 30
        Get-ADObject -Identity $($(Get-GPO -Name $GPO.DisplayName).Path) -ErrorAction SilentlyContinue | `
            Set-ADObject -Replace @{gPCUserExtensionNames="[{00000000-0000-0000-0000-000000000000}{2EA1A81B-48E5-45E9-8BB7-A6E3AC170006}][{5794DAFD-BE60-433F-88A2-1A31939AC01F}{2EA1A81B-48E5-45E9-8BB7-A6E3AC170006}]"}


        # Assign GPO to Admin Users
        # ------------------------------------------------------------
        $(Get-ADOrganizationalUnit -Filter "Name -like '*AdminAccounts*'") | foreach {
            Get-GPO -Name $GPO.DisplayName | New-GPLink -Target $($_.DistinguishedName) -LinkEnabled Yes | Out-Null
        }
    }
#>

}