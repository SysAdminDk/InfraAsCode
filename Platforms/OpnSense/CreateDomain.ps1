# New Vlan Tag
# ------------------------------------------------------------
$NewTag = "200"


# Add requried configuration to OpnSense for LAB domain.
# ------------------------------------------------------------
$FWAddress = "10.36.255.3:8443"
$Key    = "wWMFSMMtsDddvfEbA7vDUxnug9H9CuO+9Z74I6gclaai8sU2Uh7HqAmDMNVa7sf4e+HO4ZbDbHT5nJCi"
$Secret = "5OYYk9i6Uy1lTBRUCB400XmHepFBqvCc4XqVWtpv9OgW7TYcg2eQwUPtWmfdkujA2QNNhJhwsAg+TgPS"


# Define Headers
# ------------------------------------------------------------
$Pair = @($Key, $Secret) -join(":")
$Bytes = [System.Text.Encoding]::ASCII.GetBytes($Pair)
$Encoded = [Convert]::ToBase64String($Bytes)

$Headers = @{
    Authorization = "Basic $Encoded"
}


# Ignore Self Signed Cert.
# ------------------------------------------------------------
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[System.Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#$Status = Invoke-RestMethod -Uri "https://$FWAddress/api/core/system/status" -Headers $Headers

# Get LAN interface.
# ------------------------------------------------------------
#$InterfaceData = Invoke-RestMethod -Uri "https://$FWAddress/api/interfaces/overview/interfacesInfo" -Headers $Headers
#$MasterInterface = $($InterfaceData.rows | Where {$_.identifier -eq "lan"}).device


# Check if VLAN exists.
# ------------------------------------------------------------
$response = Invoke-RestMethod -Uri "https://$FWAddress/api/interfaces/vlan_settings/searchItem" -Headers $Headers
if ($NewTag -NotIn $response.rows.tag) {

    # Create New VLAN
    # ------------------------------------------------------------
    $Data = [PSCustomObject]@{
        vlan  = [PSCustomObject]@{
            vlanif = "vlan0.$NewTag"
            if = $MasterInterface
            tag = $NewTag
            descr = "Vlan 100"
        }
    } | ConvertTo-Json

    $TagAdd = Invoke-RestMethod -Uri "https://$FWAddress/api/interfaces/vlan_settings/add_item" -Body $Data -Headers $Headers -Method Post -ContentType "application/json"
    if ($TagAdd.result -ne "saved") {
        $TagAdd.validations
    }

}








Invoke-RestMethod -Uri "https://$FWAddress/api/firewall/filter" -Headers $Headers

Invoke-RestMethod -Uri "https://$FWAddress/api/unbound/settings" -Headers $Headers

Invoke-RestMethod -Uri "https://$FWAddress/api/kea" -Headers $Headers

