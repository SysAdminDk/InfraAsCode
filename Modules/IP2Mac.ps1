# Convert IP Address to Mac Address, using known prefeix
# - Ref : https://ss64.com/ps/syntax-f-operator.html
# ------------------------------------------------------------
Function IP2Mac {
    param (
        [cmdletbinding()]
        [Parameter(Mandatory)][string]$IpAddress
    )

    $ip = $IpAddress.Split('.')
    $mac = "BC-24-{0:X2}-{1:X2}-{2:X2}-{3:X2}" -f [int]$ip[0], [int]$ip[1], [int]$ip[2], [int]$ip[3]
    return $mac
}
