<#

      ___        _                        _   _               _____ _                              
     / _ \      | |                      | | (_)             /  __ \ |                             
    / /_\ \_   _| |_ ___  _ __ ___   __ _| |_ _  ___  _ __   | /  \/ | ___  __ _ _ __  _   _ _ __  
    |  _  | | | | __/ _ \| '_ ` _ \ / _` | __| |/ _ \| '_ \  | |   | |/ _ \/ _` | '_ \| | | | '_ \ 
    | | | | |_| | || (_) | | | | | | (_| | |_| | (_) | | | | | \__/\ |  __/ (_| | | | | |_| | |_) |
    \_| |_/\__,_|\__\___/|_| |_| |_|\__,_|\__|_|\___/|_| |_|  \____/_|\___|\__,_|_| |_|\__,_| .__/ 
                                                                                            | |    
                                                                                            |_|

    Remove all files and scripts from the system after instalation are done.

#>


# Clear Autologin
# ------------------------------------------------------------
$Winlogon = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

Set-ItemProperty $Winlogon AutoLogonCount 0
Remove-ItemProperty $Winlogon DefaultUserName -ErrorAction SilentlyContinue
Remove-ItemProperty $Winlogon DefaultDomainName -ErrorAction SilentlyContinue
Remove-ItemProperty $Winlogon DefaultPassword -ErrorAction SilentlyContinue


# Clear Autorun
# ------------------------------------------------------------
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "BootStrap" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "BootStrap" -ErrorAction SilentlyContinue


# Clean the Scripts folder
# ------------------------------------------------------------
#Remove-Item "$PSScriptRoot\*" -Recurse -Force
Remove-Item "$($env:windir)\Panther\Unattend.xml" -Force


# Run GPUpdate (Get LAPS PW rotated)
# ------------------------------------------------------------
Gpupdate /Target:Computer /Force


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
