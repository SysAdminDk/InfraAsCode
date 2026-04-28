<#
    ______                      _         _____             _             _ _               
    |  _  \                    (_)       /  __ \           | |           | | |              
    | | | |___  _ __ ___   __ _ _ _ __   | /  \/ ___  _ __ | |_ _ __ ___ | | | ___ _ __ ___ 
    | | | / _ \| '_ ` _ \ / _` | | '_ \  | |    / _ \| '_ \| __| '__/ _ \| | |/ _ \ '__/ __|
    | |/ / (_) | | | | | | (_| | | | | | | \__/\ (_) | | | | |_| | | (_) | | |  __/ |  \__ \
    |___/ \___/|_| |_| |_|\__,_|_|_| |_|  \____/\___/|_| |_|\__|_|  \___/|_|_|\___|_|  |___/


    Install & Configure Additional Domain Controllers.
#>


if ((gwmi win32_computersystem).partofdomain) {

    if ((gwmi win32_computersystem).DomainRole -ne 4) {

        # Install ADDS & DNS
        # --------------------------------------------------------------------------------------------------
        if ((Get-WindowsFeature -Name AD-Domain-Services).InstallState -eq "Available") {
            Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
        }
    }
}
