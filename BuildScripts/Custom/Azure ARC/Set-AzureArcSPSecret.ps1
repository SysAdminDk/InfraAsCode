<#

    Create encryptedServicePrincipalSecret

#>
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -force -Confirm:$false

Param(
    [Parameter(Mandatory=$True)]
    [string]$ServicePrincipalSecret,
    [Parameter(Mandatory=$True)]
    [string]$ArcShare="\\$((Get-ADDomain).DNSRoot)\sysvol\$((Get-ADDomain).DNSRoot)\scripts\Arc Onbording"
)


# Set variables
# ----------------------------------------------------------
$AzureArcDeployPath = "$ArcShare\AzureArcDeploy"
$DomainComputersSID = (Get-ADDomain).DomainSID.Value + '-515'
$DomainControllersSID = (Get-ADDomain).DomainSID.Value + '-516'
$EndDate = (Get-Date).AddMonths($MonthsValid)


# Verify Encryption module exist
# ----------------------------------------------------------
if (!(Test-Path $AzureArcDeployPath\AzureArcDeployment.psm1)) {
    Write-Output "The required module AzureArcDeployment.psm1 was not found in $AzureArcDeployPath"
    Throw "Verify that the share exist and has a subfolder named AzureArcDeploy with the module file AzureArcDeployment.psm1"
}


# Encrypting the ServicePrincipalSecret to be decrypted only by the Domain Controllers and the Domain Computers
# ----------------------------------------------------------
$DomainComputersSID = "SID=" + $DomainComputersSID
$DomainControllersSID = "SID=" + $DomainControllersSID
$descriptor = @($DomainComputersSID, $DomainControllersSID) -join " OR "
Import-Module $AzureArcDeployPath\AzureArcDeployment.psm1
$encryptedSecret = [DpapiNgUtil]::ProtectBase64($descriptor, $ServicePrincipalSecret)

#Copy encrypted secret to deployment share
$encryptedSecret | Out-File -FilePath (Join-Path -Path $AzureArcDeployPath -ChildPath "encryptedServicePrincipalSecret") -Force