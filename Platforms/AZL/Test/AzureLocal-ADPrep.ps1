<#

    Prepare Fabric Active Directory to create the Azure Local Cluster.

#>

# OU Name where the cluster will be deployed in AD
$ClusterNo ="Cluster01"

# Distinguished Name (DN) path to cluster base OU
$DeploymentOu = "OU=$clusterNo,OU=HyperConvergedInfrastructure,OU=Servers,OU=Tier0,OU=Admin,DC=lair,DC=net"


# Install req. modules:
$installedModules = Get-InstalledModule
if ($installedModules.Name -contains 'AsHciADArtifactsPreCreationTool') {
    Write-Host "Az HCI Module already installed"
}
else {
    Write-Host "Installing Az HCI Module"
    Install-Module AsHciADArtifactsPreCreationTool -Repository PSGallery -Force
}

# Use the credential object in your command
Write-Host "Enter the username and password for the cluster deployment account" -ForegroundColor Yellow
New-HciAdObjectsPreCreation -AzureStackLCMUserCredential $credential -AsHciOUName $deploymentOu

# Get the most recently created user in the OU
$latestUser = Get-ADUser -SearchBase $deploymentOu -Filter * -Properties whenCreated |
                Sort-Object whenCreated -Descending |
                Select-Object -First 1

# Check if a user was found
if ($latestUser) {
    # Set new display name and description to follow our naming convention on accounts
    $newDisplayName = "[T0SVC] Azure Local $clusterNo"
    $description = "Azure Local Deployment Account $clusterNo"

    # Update the user
    Set-ADUser -Identity $latestUser.SamAccountName -DisplayName $newDisplayName -Description $description
} else {
    Write-Host "No users found in the specified OU."
}
