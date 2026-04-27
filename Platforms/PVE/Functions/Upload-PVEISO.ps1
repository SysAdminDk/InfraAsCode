<#

    Custom hacked script to upload ISO files to PVE Iso storage.
    - I use this to upload the custom Cloud Init disks, see New-PVEServer.ps1

#>
function Upload-PVEISO {
    param(
        [string]$ProxmoxAPI,
        [Object]$Headers,
        [string]$Node,
        [string]$Storage,
        [string]$IsoPath
    )


    # I only use this function to upload Configuration ISOs, why the size limit.
    # ------------------------------------------------------------
    if ($(Get-Item $IsoPath).Length -gt (100MB)) {
        throw "ISO file is too large, max allowed size is 100MB."
    }


    $FileName = [System.IO.Path]::GetFileName($IsoPath)
    $Boundary = [System.Guid]::NewGuid().ToString()

    $Body = @()
    $Body += "--$Boundary"
    $Body += 'Content-Disposition: form-data; name="content"'
    $Body += ""
    $Body += "iso"
    $Body += "--$Boundary"
    $Body += "Content-Disposition: form-data; name=""filename""; filename=""$fileName"""
    $Body += "Content-Type: application/octet-stream"
    $Body += ""

    $BodyBytes = [Text.Encoding]::ASCII.GetBytes(($Body -join "`r`n") + "`r`n")
    $FileBytes = [System.IO.File]::ReadAllBytes($IsoPath)
    $PostBytes = [System.Text.Encoding]::ASCII.GetBytes("`r`n--$Boundary--`r`n")

    $AllBytes = New-Object byte[] ($BodyBytes.Length + $FileBytes.Length + $PostBytes.Length)
    [Array]::Copy($BodyBytes, 0, $AllBytes, 0, $BodyBytes.Length)
    [Array]::Copy($FileBytes, 0, $AllBytes, $BodyBytes.Length, $FileBytes.Length)
    [Array]::Copy($PostBytes, 0, $AllBytes, $BodyBytes.Length + $FileBytes.Length, $PostBytes.Length)

    $Request = [System.Net.HttpWebRequest]::Create("$ProxmoxAPI/nodes/$Node/storage/$Storage/upload")
    $Request.Method = "POST"
    $Request.Headers.Add("Authorization", $Headers["Authorization"])
    $Request.Accept = "application/json"
    $Request.ContentType = "multipart/form-data; boundary=$Boundary"
    $Request.ContentLength = $AllBytes.Length

    $ReqStream = $Request.GetRequestStream()
    $ReqStream.Write($AllBytes, 0, $AllBytes.Length)
    $ReqStream.Close()

    $Response = $Request.GetResponse()
    $SR = New-Object System.IO.StreamReader($Response.GetResponseStream())
    $Result = $SR.ReadToEnd()
    $SR.Close()
    $Response.Close()

    return $Result
}
