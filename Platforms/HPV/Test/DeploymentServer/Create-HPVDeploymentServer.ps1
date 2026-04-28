<# 

    Create Deployment server.
    4 vCpu
    8Gb Ram
    50Gb OS Drive
    100GB Data Drive


    Download Server 2025 Eval.
    https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso

    Download Server 2022 Eval.
    https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso

    Download VirtIO Drivers.
    https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso
    

    Windows Installation, You know what to do :)


    When Done, Download required scripts from Git...
    MS-Fabric\Deployment\* -> D:\Deployment\*

#>


# Name of the "Master" VM
# ------------------------------------------------------------
$VMName = "DeployMaster"


# Path to PVE scripts and Functions.
# ------------------------------------------------------------
$RootPath = "G:\Shares\Github Repositories\LAB-Deployment\Proxmox Scripts"


# Import PVE modules
# ------------------------------------------------------------
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -Confirm:$false
Get-ChildItem -Path "$RootPath\Functions" | ForEach-Object { Import-Module -Name $_.FullName -Force }


# Connect to PVE Cluster
# ------------------------------------------------------------
$PVESecret = Get-Content "$RootPath\PVE-Secret.json" | Convertfrom-Json
$PVEConnect = PVE-Connect -Authkey "$($PVESecret.User)!$($PVESecret.TokenID)=$($PVESecret.Token)" -Hostaddr $($PVESecret.Host)


# Get information required to create the template (VM)
# ------------------------------------------------------------
$PVELocation = Get-PVELocation -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers -IncludeNode $MasterID.Node
$ISOStorage = ((Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.name)/storage" -Headers $($PVEConnect.Headers)).data | Where {$_.content -like "*iso*"}).storage


# Download Windows Server 2022 EVAL Iso
# ------------------------------------------------------------
$DownloadBody = "content=iso"
$DownloadBody += "&node=$($PVELocation.name)"
$DownloadBody += "&url=$([uri]::EscapeDataString("https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso"))"
$DownloadBody += "&filename=$([uri]::EscapeDataString("Server2022.iso"))"

$2022Result = Invoke-RestMethod -Method POST -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.name)/storage/$ISOStorage/download-url" -Headers $($PVEConnect.Headers) -Body $DownloadBody


# Download Windows Server 2025 EVAL Iso
# ------------------------------------------------------------
$DownloadBody = "content=iso"
$DownloadBody += "&node=$($PVELocation.name)"
$DownloadBody += "&url=$([uri]::EscapeDataString("https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"))"
$DownloadBody += "&filename=$([uri]::EscapeDataString("Server2025.iso"))"

$2025Result = Invoke-RestMethod -Method POST -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.name)/storage/$ISOStorage/download-url" -Headers $($PVEConnect.Headers) -Body $DownloadBody


# Download VirtIO Windows Drivers.
# ------------------------------------------------------------
$DownloadBody = "content=iso"
$DownloadBody += "&node=$($PVELocation.name)"
$DownloadBody += "&url=$([uri]::EscapeDataString("https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso"))"
$DownloadBody += "&filename=$([uri]::EscapeDataString("virtio-win.iso"))"

$DriverResult = Invoke-RestMethod -Method POST -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.name)/storage/$ISOStorage/download-url" -Headers $($PVEConnect.Headers) -Body $DownloadBody


# Wait all 3 downloads.
# ------------------------------------------------------------
Start-PVEWait -ProxmoxAPI $($PVEConnect.PVEAPI) -Headers $PVEConnect.Headers -node $($PVELocation.Name) -taskid $2022Result.data
Start-PVEWait -ProxmoxAPI $($PVEConnect.PVEAPI) -Headers $PVEConnect.Headers -node $($PVELocation.Name) -taskid $2025Result.data
Start-PVEWait -ProxmoxAPI $($PVEConnect.PVEAPI) -Headers $PVEConnect.Headers -node $($PVELocation.Name) -taskid $DriverResult.data



# Next avalible High VMID
# ------------------------------------------------------------
$VMID = Get-PVENextID -ProxmoxAPI $($PVEConnect.PVEAPI) -Headers $($PVEConnect.Headers)


# Default Deployent Sever Configuration
# ------------------------------------------------------------
$Body = "node=$($PVELocation.Name)"
$Body += "&vmid=$VMID"
$Body += "&name=fsddfsdfa"
$Body += "&bios=ovmf"
$Body += "&cpu=host"
$Body += "&ostype=win11"
$Body += "&machine=pc-q35-9.0"
$Body += "&tpmstate0=$([uri]::EscapeDataString("$($PVELocation.storage):1,size=4M,version=v2.0"))"
$Body += "&efidisk0=$([uri]::EscapeDataString("$($PVELocation.storage):1,efitype=4m,format=raw,pre-enrolled-keys=1"))"
$Body += "&net0=$([uri]::EscapeDataString("virtio,bridge=$($PVELocation.Interface),firewall=1"))"
$Body += "&boot=$([uri]::EscapeDataString("order=scsi0;ide2"))"
$Body += "&scsihw=virtio-scsi-single"
$Body += "&memory=8192"
$Body += "&balloon=2048"
$Body += "&cores=4"
$Body += "&scsi0=$([uri]::EscapeDataString("$($PVELocation.storage):50,ssd=on,format=raw"))"
$Body += "&scsi1=$([uri]::EscapeDataString("$($PVELocation.storage):100,format=raw"))"
$Body += "&ide0=$([uri]::EscapeDataString("local:iso/virtio-win.iso,media=cdrom"))"
$Body += "&ide2=$([uri]::EscapeDataString("local:iso/Server2025.iso,media=cdrom"))"


# Create the Template VM
# ------------------------------------------------------------
$VMCreate = Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.Name)/qemu/" -Body $Body -Method POST -Headers $($PVEConnect.Headers)
Start-PVEWait -ProxmoxAPI $($PVEConnect.PVEAPI) -Headers $PVEConnect.Headers -node $($PVELocation.Name) -taskid $VMCreate.data


# Start new server
# ------------------------------------------------------------
$null = Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.name)/qemu/$VMID/status/start" -Headers $($PVEConnect.Headers) -Method POST
