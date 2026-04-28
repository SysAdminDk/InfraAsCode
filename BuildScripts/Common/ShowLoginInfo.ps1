# Get  Current IP Address
# ------------------------------------------------------------
$Interface = Get-NetAdapter -Physical | Where-Object {$_.Status -EQ "UP"}
$CurrentIP = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $Interface.ifIndex


# Change Administrator password and show on screen.
# ------------------------------------------------------------
if (!((Get-WmiObject -Class win32_computersystem).partofdomain)) {
    $NewPassword = $(-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 15 | ForEach-Object {[char]$_}))
    $SecurePassword = ConvertTo-SecureString -string $NewPassword -AsPlainText -Force
    Set-LocalUser -Name Administrator -Password $SecurePassword
}

$PwdCmd = @()
$PwdCmd += "Write-Host `"=== IMPORTANT: Temporary local admin password ===`"`r`n" 
$PwdCmd += "write-host `"`"`r`n" 
$PwdCmd += "write-host `"Username : Administrator`r`n"
$PwdCmd += "write-host `"Password : $NewPassword`r`n"
$PwdCmd += "write-host `"`"`r`n" 
$PwdCmd += "Write-Host `"RDP access is avalible on $($CurrentIP.IPAddress)`"`r`n" 
$PwdCmd += "write-host `"`"`r`n" 
$PwdCmd += "Read-Host -Prompt 'Press ENTER to close this window'`r`n" 
$PwdCmd += "exit`r`n"

Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoExit -Command $PwdCmd"
