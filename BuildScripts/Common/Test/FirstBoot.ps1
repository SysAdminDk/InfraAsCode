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


# GIT Token and address
# ------------------------------------------------------------
#$GitConnection = Get-Content -Path "$PSScriptRoot\GitHub-Connection.json" | Convertfrom-Json
#$gitToken = $GitConnection.Token
#$RepoUrl  = $GitConnection.Url
$RepoUrl  = "http://coredeployment.localdomain/deployment"


# Bootstrap location
# ------------------------------------------------------------
$Filename = "BootStrap.ps1"
#$URL = "$RepoUrl/Unattended/contents/WindowsServer/$Filename"
$URL = "$RepoUrl/BuildScripts/Common/$Filename"


# Verify access to GIT
# ------------------------------------------------------------
for ($i=0; $i -lt 10; $i++) {
    try {
        #if ($gitToken -ne "") {
        #    $Response = Invoke-RestMethod -Uri $url -Headers @{ Authorization = "token $gitToken" }
        #} else {
            $Response = Invoke-RestMethod -Uri $url -OutFile "$RootPath\$Filename"
        #}
        
        #if (-not $Response) {
        #    throw "Git returned no content for $Filename"
        #} else {
        #    $FileBytes = [System.Convert]::FromBase64String($Response.content)
        #    [System.IO.File]::WriteAllBytes("$RootPath\$Filename", $FileBytes)
        #}

        if (Test-Path -Path "$RootPath\$Filename") {
            break
        }
    }
    catch {
        Start-Sleep -Seconds 30
    }
}


# Start Bootstrap.
# ------------------------------------------------------------
if (Test-Path -Path "$RootPath\$Filename") {

    Start-Process -FilePath powershell.exe -ArgumentList "-file `"$RootPath\$Filename`""

} else {
    Throw "Bootstrap NOT found"
    Start-Sleep -Seconds 9999
}
