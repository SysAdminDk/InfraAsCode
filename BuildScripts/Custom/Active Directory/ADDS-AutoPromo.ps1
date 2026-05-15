# Ensure the required script is avalible.
# ------------------------------------------------------------
$PromoScript = @"
# Get Domain Information
# ------------------------------------------------------------
`$NetBIOSName   = (Get-ADDomain).NetBIOSName
`$PromoUserName = "DomainPromo"
`$T0SearchBase  = Get-ADOrganizationalUnit -Filter "Name -eq 'Tier0'"
`$T0SvcPath     = Get-ADOrganizationalUnit -Filter "Name -eq 'ServiceAccounts'" -SearchBase `$T0SearchBase


# Find any NEW servers to promote
# ------------------------------------------------------------
`$Server = Get-ADComputer -Filter "Name -like 'ADDS-0*'" -Properties adminDescription | `
    Where {`$_.DistinguishedName -Like "*OU=Quarantine*" -and `$_.adminDescription -eq `$null} | `
        Select-Object -First 1


# If no servers, terminate
# ------------------------------------------------------------
if (-NOT `$Server) {
    return
}


# Create Long Random Password
# ------------------------------------------------------------
`$PWString = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 35 | ForEach-Object {[char]`$_})
`$Password = ConvertTo-SecureString -string `$PWString -AsPlainText -Force


# Find or create DC Promo User
# ------------------------------------------------------------
try {
    `$DcPromoUser = Get-AdUser -Identity `$PromoUserName -Properties MemberOf -ErrorAction Stop

    if (`$DcPromoUser) {
        Set-ADAccountPassword -Identity `$DcPromoUser -NewPassword `$Password -Reset
        Enable-ADAccount -Identity `$DcPromoUser
    }
}
catch {
    New-ADUser -Name `$PromoUserName -AccountPassword `$Password -Enabled:`$true -Path `$T0SvcPath
    `$DcPromoUser = Get-AdUser -Identity `$PromoUserName
}


# Add to Domain Admins
# ------------------------------------------------------------
if ("CN=Domain Admins,CN=Users,DC=Dev,DC=SecInfra,DC=Dk" -NotIn `$DcPromoUser.MemberOf) {
    Add-ADGroupMember -Identity "Domain Admins" -Members `$DcPromoUser
}


# Create Required Credential Object.
# ------------------------------------------------------------
`$Credential = New-Object System.Management.Automation.PSCredential ("`$(`$NetBIOSName)\`$(`$DcPromoUser.SamAccountName)", `$Password)


# Update AdminDescription
# ------------------------------------------------------------
Set-ADComputer -Identity `$Server -Replace @{ adminDescription = "Promoting:`$(Get-Date -Format s)" }


try {
    # Connect to server and run DC Promo
    # ------------------------------------------------------------
    Invoke-Command -ComputerName `$Server.DNSHostName -ScriptBlock {
    
        # Promote Domanin Controller
        # ------------------------------------------------------------
        `$SecurePassword = ConvertTo-SecureString -string `$Using:PWString -AsPlainText -Force
        Install-ADDSDomainController -SafeModeAdministratorPassword `$SecurePassword -DomainName `$Using.NetBIOSName -InstallDNS -Credential `$Using:Credential -Force
    }
}
catch {
    # 
}
finally {
    # Clear Admin Description
    # ------------------------------------------------------------
    Set-ADComputer -Identity `$Server -Clear adminDescription


    # Disable DcPromoUser
    # ------------------------------------------------------------
    Disable-ADAccount -Identity `$DcPromoUser
}
"@

# Create Program Files location if not exist.
# ------------------------------------------------------------
If (-NOT (Test-Path -Path "$($ENV:Programfiles)\T0 Automation")) {
    New-Item -Path "$($ENV:Programfiles)\T0 Automation" -ItemType Directory | Out-Null
}
$PromoScript | Out-File -FilePath "$($ENV:Programfiles)\T0 Automation\AutoPromo.ps1" -Encoding utf8
Set-ItemProperty -Path "$($ENV:Programfiles)\T0 Automation\AutoPromo.ps1" -Name IsReadOnly -Value $true


# Setup Auto Promo Schedule.
# ------------------------------------------------------------
$Action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -file `"$($ENV:Programfiles)\T0 Automation\AutoPromo.ps1`""
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 30)
$Principal = New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
$Task = New-ScheduledTask -Action $Action -Principal $Principal -Trigger $Trigger -Settings $Settings
Register-ScheduledTask AutoDCPromo -InputObject $Task | Out-Null
