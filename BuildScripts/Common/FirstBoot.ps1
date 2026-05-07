<# 

    Wrapper to download latest Bootstrap from GIT

#>

# Path to PVE scripts and Functions.
# ------------------------------------------------------------
if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $RootPath = $PSScriptRoot
} else {
    $RootPath  = "C:\Scripts"
}


# Deployment server Name and Address
# ------------------------------------------------------------
$Deployment = Get-Content -Path "$RootPath\DeploymentServer.json" | Convertfrom-Json
try {
    Resolve-DnsName $Deployment.ServerName -QuickTimeout -ErrorAction Stop | Out-Null
    $DeploymentServer = $Deployment.ServerName
}
catch {
    $DeploymentServer = $Deployment.IpAddress
}


if (-not (Test-NetConnection $DeploymentServer -CommonTCPPort HTTP -InformationLevel Quiet)) {
    throw "Unable to connect to Deployment Website"
} else {
    $RepoUrl  = "http://$DeploymentServer/$($Deployment.VirtualPath)"
}


# Download Bootstrap
# ------------------------------------------------------------
$Filename = "BootStrap.ps1"
Invoke-RestMethod -Uri "$RepoUrl/BuildScripts/Common/$Filename" -OutFile "$RootPath\$Filename"


# Start Bootstrap.
# ------------------------------------------------------------
if (Test-Path -Path "$RootPath\$Filename") {
    #Start-Process -FilePath powershell.exe -ArgumentList "-file `"$RootPath\$Filename`""
} else {
    Throw "Bootstrap NOT found"
    Start-Sleep -Seconds 9999
}
