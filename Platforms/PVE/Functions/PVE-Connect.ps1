<#

    Connecto to PVE cluster.

#>
function PVE-Connect {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)][string]$Authkey,
        [Parameter(Mandatory)][string]$Hostaddr
    )


    # HTTP Headers for connection.
    # ------------------------------------------------------------
    $DefaultHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $DefaultHeaders.Add("Authorization", "PVEAPIToken=$AuthKey")
    $DefaultHeaders.Add("Accept", "application/json")


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


    # Proxmox API address.
    # ------------------------------------------------------------
    $DefaultProxmoxAPI = "https://$($HostAddr):8006/api2/json"

    return @( [PSCustomObject]@{ PVEAPI  = $DefaultProxmoxAPI; Headers = $DefaultHeaders } )

}

