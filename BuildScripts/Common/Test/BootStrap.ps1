<# 

     _____          _        _ _       _   _              ______             _       _                   
    |_   _|        | |      | | |     | | (_)             | ___ \           | |     | |                  
      | | _ __  ___| |_ __ _| | | __ _| |_ _  ___  _ __   | |_/ / ___   ___ | |_ ___| |_ _ __ __ _ _ __  
      | || '_ \/ __| __/ _` | | |/ _` | __| |/ _ \| '_ \  | ___ \/ _ \ / _ \| __/ __| __| '__/ _` | '_ \ 
     _| || | | \__ \ || (_| | | | (_| | |_| | (_) | | | | | |_/ / (_) | (_) | |_\__ \ |_| | | (_| | |_) |
     \___/_| |_|___/\__\__,_|_|_|\__,_|\__|_|\___/|_| |_| \____/ \___/ \___/ \__|___/\__|_|  \__,_| .__/ 
                                                                                                  | |    
                                                                                                  |_| 
#>


# Path to PVE scripts and Functions.
# ------------------------------------------------------------
if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $RootPath = $PSScriptRoot
} else {
    $RootPath  = "C:\Scripts"
}


# GIT Defaults.
# ------------------------------------------------------------
#Write-Output "Script Start : $LogDate" | Out-File $LogFile -Force
#$GitConnection = Get-Content -Path "$PSScriptRoot\GitHub-Connection.json" | Convertfrom-Json
#$gitToken = $GitConnection.Token
#$RepoUrl  = $GitConnection.Url
$RepoUrl  = "http://coredeployment.localdomain/deployment"


# Expand OS Volume if needed.
# ------------------------------------------------------------
#Write-Output "Expand OS Drive, if needed" | Out-File $LogFile -Append
$OSDrive = Get-Volume -DriveLetter ($ENV:SYstemDrive).Replace(":","")
$SizeBefore = (Get-Volume -DriveLetter $OSDrive.DriveLetter).Size
$Partition = Get-Partition -DriveLetter $OSDrive.DriveLetter
$Supported = Get-PartitionSupportedSize -DriveLetter $OSDrive.DriveLetter

if ($Partition.Size -lt $Supported.SizeMax) {
    Resize-Partition -DriveLetter $OSDrive.DriveLetter -Size $Supported.SizeMax -ErrorAction Stop
}


# Get Default Network Information
# ------------------------------------------------------------
$Interface = Get-NetAdapter -Physical | Where-Object {$_.Status -EQ "UP"}
$IPConfig = $Interface | Get-NetIPAddress -AddressFamily IPv4


# Get Server Config from GIT
# ------------------------------------------------------------
#Write-Output "Get Server Config file from GIT"
if (-NOT (Test-Path -Path "$RootPath\ServerConfig.json")) {

    $MACAddress = @("00","00") + (($($Interface.MacAddress) -split("-"))[2..5]) -join("-")

#    if ($($GitConnection.Token)) {
#        $Response = Invoke-RestMethod -Uri "$($GitConnection.Url)/LAB-Deployment/contents/ConfigFiles/JSON/$MACAddress.json" -Headers @{ Authorization = "token $($GitConnection.Token)" }
#    } else {
#        $Response = Invoke-RestMethod -Uri "$($GitConnection.Url)/LAB-Deployment/contents/ConfigFiles/JSON/$MACAddress.json"
#    }
#
#    $FileBytes = [System.Convert]::FromBase64String($Response.content)
#    [System.IO.File]::WriteAllBytes("$RootPath\ServerConfig.json", $FileBytes)
    
    Invoke-WebRequest -Uri "$RepoUrl/ConfigFiles/JSON/$MACAddress.json" -UseBasicParsing -OutFile "$RootPath\ServerConfig.json"

}



# Import Config data
# ------------------------------------------------------------
if (Test-Path -Path "$RootPath\ServerConfig.json") {
    $ServerConfig = Get-Content -Path "$RootPath\ServerConfig.json" | ConvertFrom-Json
} else {
    Throw "Server config is missing"
    Start-Sleep -Seconds 99999
}

<#

    Process Config Data

#>


# Setup Autorun Bootstrap
# ------------------------------------------------------------
if (!(Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "BootStrap" -ErrorAction SilentlyContinue)) {
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "BootStrap" -Value "Powershell.exe -ExecutionPolicy Bypass -NoProfile -File `"$($MyInvocation.MyCommand.Definition)`"" -Force | Out-Null
}



# Update IP Address from Config
# ------------------------------------------------------------
#Write-Output "Update Network Configuration"
if ($IPConfig.PrefixOrigin -eq "DHCP") {
    $Bits = ([string]([Convert]::ToString(([IPAddress]::Parse($ServerConfig.Network.SubnetMask).address),2)))
    $Prefix = $Bits.ToCharArray().Count

    $Interface | New-NetIPAddress -IPAddress $ServerConfig.Network.IPv4Address -PrefixLength $Prefix -DefaultGateway $ServerConfig.Network.DefaultGateway | Out-Null
    $Interface | Set-DnsClientServerAddress -ServerAddresses $ServerConfig.Network.DNSServers | Out-Null
}


# Set Computer Name
# ------------------------------------------------------------
#Write-Output "Change Computer Name"
if ($env:COMPUTERNAME -ne $ServerConfig.Name) {

    if ($null -eq $ServerConfig.DomainName) {

        # Only if Workgroup machine.
        # ------------------------------------------------------------
        Rename-Computer -NewName $ServerConfig.Name -Force -Restart

    } else {

        # Ensure we have a DOMAIN to talk to.
        # ------------------------------------------------------------
        $SrvRecord = "_ldap._tcp.dc._msdcs.$($ServerConfig.DomainName)"
        $Attempt = 0
        $Ready = $false

        do {
            $Attempt++
            try {
                Write-Host "Checking SRV record $SrvRecord (attempt $Attempt)..."

                $Result = Resolve-DnsName -Name $SrvRecord -Type SRV -ErrorAction Stop

                if ($Result) {
                    Write-Host "SRV record found. Domain is ready."
                    $Ready = $true
                }
            }
            catch {
                Write-Host "SRV record not found yet, waiting 10 seconds..."
                Start-Sleep -Seconds 5
            }

        } until ($Ready -or $Attempt -ge 10)

        if (-not $Ready) {
            throw "Domain not ready - SRV record not found after $Attempt attempts"
        }


        # If Domain specified, join Domain..
        # ------------------------------------------------------------
        $CryptPassword = ConvertTo-SecureString $($ServerConfig.JoinOptions.Password) -AsPlainText -Force
        $Credentials = New-Object System.Management.Automation.PSCredential ("$($ServerConfig.JoinOptions.UserDomain)\$($ServerConfig.JoinOptions.Username)", $CryptPassword)


        if ($($ServerConfig.JoinOptions.OrganizationalUnit)) {

            # If OU specified, try to join to that OU
            # ------------------------------------------------------------
            $DomainDN = (($ServerConfig.DomainName -split("\.")) | ForEach-Object { "DC=$($_)" }) -join(",")
            $JoinMachineOU = @($($($ServerConfig.JoinOptions.OrganizationalUnit)) ,$DomainDN) -Join(",")


            Rename-Computer -NewName $ServerConfig.Name -Restart:$False
            Start-Sleep -Seconds 2
            Add-Computer -DomainName $ServerConfig.DomainName -force –Options JoinWithNewName,accountcreate -OUPath $JoinMachineOU -Credential $Credentials -Restart

        } else {

            # If no OU, just join..
            # ------------------------------------------------------------
            Add-Computer -NewName $ServerConfig.Name -DomainName $ServerConfig.DomainName -Credential $Credentials -Restart

        }
    }
}


# Install Server Roles
# ------------------------------------------------------------
Foreach ($Role in $ServerConfig.Roles) {

    $RoleStatus = Get-WindowsFeature -Name $Role.Name

    switch ($Role.status) {
        "Pending" {

            # Change Task to Started
            # ------------------------------------------------------------
            $Role.status = "Started"
            $ServerConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath "$RootPath\ServerConfig.json" -Encoding utf8 -Force


            # Install selected Role / Feature
            # ------------------------------------------------------------
            if ($RoleStatus.InstallState -eq "Available") {
                Install-WindowsFeature -Name $Role.Name -IncludeManagementTools -Restart
            }
        }

        "Started" {

            if ($RoleStatus.InstallState -eq "Installed") {

                # Change Task to Completed
                # ------------------------------------------------------------
                $Role.status = "Completed"
                $ServerConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath "$RootPath\ServerConfig.json" -Encoding utf8 -Force
            }
        }

        "Completed" {
        }
    }
}


# Get Scripts, and execute
# ------------------------------------------------------------
Foreach ($Task in $ServerConfig.Tasks) {

    # Ensure we have the required script avalible
    # ------------------------------------------------------------
    if (Test-Path -Path "$RootPath\$($Task.Name)") {

        try {
            $FileUri = "LAB-Infrastructure/contents/Build/$($Task.Name)"

            if ($($GitConnection.Token)) {
                $Response = Invoke-RestMethod -Uri "$($GitConnection.Url)/$FileUri" -Headers @{ Authorization = "token $($GitConnection.Token)" } -ErrorAction Stop
            } else {
                $Response = Invoke-RestMethod -Uri "$($GitConnection.Url)/$FileUri" -ErrorAction Stop
            }

            $FileBytes = [System.Convert]::FromBase64String($Response.content)
            [System.IO.File]::WriteAllBytes("$RootPath\$($Response.name)", $FileBytes)

            $ErrorCode = $null
        }
        Catch {
            $ErrorCode = ($_.ErrorDetails.Message | ConvertFrom-Json).message
        }
        
        if ($ErrorCode) {
            $Task.status = $ErrorCode
            $ServerConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath "$RootPath\ServerConfig.json" -Encoding utf8 -Force
        }
    }

    # Execute the scripts.
    # ------------------------------------------------------------
    if ( ($Task.status -eq "Pending") -OR ($Task.status -eq "Restart") ) {

        # Change Task to Started
        # ------------------------------------------------------------
        $Task.status = "Executed"
        $ServerConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath "$RootPath\ServerConfig.json" -Encoding utf8 -Force


        # Execute configuraton Script
        # ------------------------------------------------------------
        Start-Process -FilePath powershell.exe -ArgumentList "-file `"$RootPath\$($Task.Name)`"" -Wait


        # Read Task Status (Restart or Completed)
        # ------------------------------------------------------------
        $ServerConfig = Get-Content -Path "$RootPath\ServerConfig.json" | ConvertFrom-Json
        $Task = $ServerConfig.Tasks | Where-Object { $_.Name -eq $Task.Name }
    }


    if ($Task.status -eq "Running") {

        # Should newer end up here.

    }


    if ($Task.status -eq "Completed") {
        Remove-Item "$RootPath\$($Task.Name)" -Force
    }

}
