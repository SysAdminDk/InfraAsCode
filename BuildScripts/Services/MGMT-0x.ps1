<#
    ___  ___                                                  _     _____
    |  \/  |                                                 | |   /  ___|
    | .  . | __ _ _ __   __ _  __ _  ___ _ __ ___   ___ _ __ | |_  \ `--.  ___ _ ____   _____ _ __ ___ 
    | |\/| |/ _` | '_ \ / _` |/ _` |/ _ \ '_ ` _ \ / _ \ '_ \| __|  `--. \/ _ \ '__\ \ / / _ \ '__/ __|
    | |  | | (_| | | | | (_| | (_| |  __/ | | | | |  __/ | | | |_  /\__/ /  __/ |   \ V /  __/ |  \__ \
    \_|  |_/\__,_|_| |_|\__,_|\__, |\___|_| |_| |_|\___|_| |_|\__| \____/ \___|_|    \_/ \___|_|  |___/
                               __/ |
                              |___/
#>

<#

    Install & Configure Management Server(s)

#>


# Verify Domain Membership
# ------------------------------------------------------------
if (-not ((Get-WmiObject -Class win32_computersystem).partofdomain)) {
    
    Throw "Domain join have must have failed"

}


# Is Domain Member, Install...
# ------------------------------------------------------------
if ((gwmi win32_computersystem).partofdomain) {

    # Install RDCM
    # ------------------------------------------------------------
    Invoke-WebRequest -URI "https://download.sysinternals.com/files/RDCMan.zip" -OutFile "$($env:USERPROFILE)\Downloads\RDCMan.zip"
    if (!(Test-Path -Path "$($env:ProgramFiles)\RDCMan")) {
        New-Item -Path "$($env:ProgramFiles)\RDCMan" -ItemType Directory | Out-Null
    }

    Expand-Archive -Path "$($env:USERPROFILE)\Downloads\RDCMan.zip" -DestinationPath "$($env:ProgramFiles)\RDCMan"

    if (!(Test-Path -Path "$($env:ALLUSERSPROFILE)\Microsoft\Windows\Start Menu\Programs\Sysinternals")) {
        New-Item -Path "$($env:ALLUSERSPROFILE)\Microsoft\Windows\Start Menu\Programs\Sysinternals" -ItemType Directory | Out-Null
    }
    
    $TargetFile = "$($env:ProgramFiles)\RDCMan\RDCMan.exe"
    $ShortcutFile = "$($env:ALLUSERSPROFILE)\Microsoft\Windows\Start Menu\Programs\Sysinternals\RDCMan.lnk"
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
    $Shortcut.TargetPath = $TargetFile
    $Shortcut.Save()

}
