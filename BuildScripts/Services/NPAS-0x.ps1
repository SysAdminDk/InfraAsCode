<#
     _   _ ______  ___   _____  ______          _ _
    | \ | || ___ \/ _ \ /  ___| | ___ \        | (_)
    |  \| || |_/ / /_\ \\ `--.  | |_/ /__ _  __| |_ _   _ ___ 
    | . ` ||  __/|  _  | `--. \ |    // _` |/ _` | | | | / __|
    | |\  || |   | | | |/\__/ / | |\ \ (_| | (_| | | |_| \__ \
    \_| \_/\_|   \_| |_/\____/  \_| \_\__,_|\__,_|_|\__,_|___/


    ToDo.
    1. 

#>


<#

    This region is used to Install & Configure MFA Servers

#>


# Fix the Warning (RequireMsgAuth and/or limitProxyState configuration is in Disable mode)
# ------------------------------------------------------------
netsh nps set limitproxystate all = "enable"
netsh nps set requiremsgauth all = "enable"


# Fix the NTLM issue om IAS.
# ------------------------------------------------------------
New-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\RemoteAccess\Policy" -Name "Enable NTLMv2 Compatibility" -Value 1 -Force | Out-Null
