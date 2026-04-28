<#
    ______ _             _____           _   _        _    _      _                                  
    | ___ (_)           /  __ \         | | | |      | |  | |    | |                                 
    | |_/ /_ _ __   __ _| /  \/ __ _ ___| |_| | ___  | |  | | ___| |__  ___  ___ _ ____   _____ _ __ 
    |  __/| | '_ \ / _` | |    / _` / __| __| |/ _ \ | |/\| |/ _ \ '_ \/ __|/ _ \ '__\ \ / / _ \ '__|
    | |   | | | | | (_| | \__/\ (_| \__ \ |_| |  __/ \  /\  /  __/ |_) \__ \  __/ |   \ V /  __/ |   
    \_|   |_|_| |_|\__, |\____/\__,_|___/\__|_|\___|  \/  \/ \___|_.__/|___/\___|_|    \_/ \___|_|   
                    __/ |                                                                            
                   |___/                                                                             

    ToDo.
    1. ADD Certificate CRL website.



    "Script" actions.
    1. Install IIS
    2. Download and configure Pingcastle free.
#>

<#

    Install & Configure PingCastle Web service

#>

# Select Destination OU
# ------------------------------------------------------------
$TargetPath = (Get-ADOrganizationalUnit -Filter * -SearchBase $TierSearchBase | `
    Where {$_.DistinguishedName -like "OU=*OU=Servers,OU=Tier1,$TierSearchBase"}) | `
        Select-Object Name,DistinguishedName | Out-GridView -Title "Select Destination OU" -OutputMode Single


# Install & Configure Web server (Pingcastle & CA CRL)
# ------------------------------------------------------------
$($ServerInfo | Where {$_.Role -eq "WEB"}).Name | Get-ADComputer -ErrorAction SilentlyContinue | Foreach {

    If ( ($Null -ne $TargetPath) -and ($($_.DistinguishedName) -NotLike "*OU=Servers,OU=Tier1*") ) {
        Move-ADObject -Identity $($_.DistinguishedName) -TargetPath $TargetPath.DistinguishedName
    }    

    $InstallScript = Get-Content -Path "$TxScriptPath\scripts\Install - PingCastle webservice.ps1"


    # Make sure the group exists.
    # ------------------------------------------------------------
    $PingCastleGroup = "PingCastle Report Readers"


    # Connect to the server.
    # ------------------------------------------------------------
    $Session = New-PSSession -ComputerName "$($_.DNSHostName)"


    # Copy required installers to target server
    # ------------------------------------------------------------
    $FilesToCopy = @(

        "AzureConnectedMachineAgent.msi",
        "Install - PingCastle webservice.ps1"

    ) | Foreach {
        Get-ChildItem -Path $TxScriptPath -Filter $_ -Recurse | Copy-Item -Destination "$($ENV:PUBLIC)\downloads\$_" -ToSession $Session -Force
    }


    # Execute commands.
    # ------------------------------------------------------------
    Invoke-Command -Session $Session -ScriptBlock {


        # Install Azure Arc Agent
        # ------------------------------------------------------------
        if (Test-Path -Path "$($ENV:PUBLIC)\downloads\AzureConnectedMachineAgent.msi") {
            Start-Process -FilePath "$($ENV:PUBLIC)\downloads\AzureConnectedMachineAgent.msi" -ArgumentList "/quiet /qn /norestart" -wait
        }


        # Install
        # ------------------------------------------------------------
        & "$($ENV:PUBLIC)\downloads\Install - PingCastle webservice.ps1" -ADGroupName $($Using:PingCastleGroup)


        # Cleanup files.
        # ------------------------------------------------------------
        Get-ChildItem -Path "$($ENV:PUBLIC)\downloads" -Recurse | Remove-Item

        
        # Start the scheduled task to create initial.
        # ------------------------------------------------------------
        Get-ScheduledTask -TaskName "Run PingCastle - Daily" | Start-ScheduledTask

    }

    # Wait until Pingcastle scan have finished.
#    Start-Sleep -Seconds 120


    # Show the first
    # ------------------------------------------------------------
#    Start "http://$($_.DNSHostName)/PingCastle"
#    Start "http://$(($($ServerInfo | Where {$_.Role -eq "WEB"}).Name | Get-ADComputer -ErrorAction SilentlyContinue).DNSHostName)/PingCastle"
}
