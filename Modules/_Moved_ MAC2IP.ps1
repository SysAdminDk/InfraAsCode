# Convert MAC Address IP Address, using known prefeix
# - Ref : https://ss64.com/ps/syntax-f-operator.html
# ------------------------------------------------------------
Function MAC2IP {
    param (
        [cmdletbinding()]
        [Parameter(Mandatory)][string]$MACAddress
    )

    $bytes = $MACAddress.Split('-|:')[2..5] | ForEach-Object { [Convert]::ToInt32($_, 16) }
    $ip = "{0}.{1}.{2}.{3}" -f $bytes[0], $bytes[1], $bytes[2], $bytes[3]
    Return $ip
}
