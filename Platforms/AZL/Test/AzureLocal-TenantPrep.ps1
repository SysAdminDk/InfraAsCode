<#

    Prepare Azure to create the Azure Local Cluster.

#>

# In my tenant I use a shortnames from subscriptions when I build my RG:s, e.g. Development eq. dev
$subShortName = "dev"

# Location full name e.g. westeurope, eastus
$location = "westeurope"

# I use e.g. azl01, azl02, azl03
$deploymentNo = "azl01"

# Subscription name
$subscription = ""

# Account used for the deployment
$cloudAdminEmail = ""

# Define a hashtable of region short names
$shortNames = @{
    "eastus"           = "eus"
    "westeurope"       = "weu"
    "australiaeast"    = "aue"
    "southeastasia"    = "sea"
    "indiacentral"     = "inc"
    "canadacentral"    = "cac"
    "japaneast"        = "jpe"
    "southcentralus"   = "scus"
}

# Set variables
$regionShortName = $shortNames[$location]
$rgNameAzl = "rg-$subShortName-$regionShortName-$deploymentNo"
$subShortName = $subscription.Substring(0,3).ToLower()

# Output result
Write-Host "Short name for region '$location' is '$regionShortName'" -ForegroundColor Green

$installedModules = Get-InstalledModule
if ($installedModules.Name -contains 'Az') {
    Write-Host "Az Module already installed" -ForegroundColor Yellow
}
else {
    Write-Host "Installing Az Module" -ForegroundColor Green


    Install-PackageProvider -Name NuGet -Force -Confirm:$false


    Install-Module -Name Az -Repository PSGallery -Force -Confirm:$false
}

Set-ExecutionPolicy -ExecutionPolicy Bypass
Import-Module Az.Accounts -Force -NoClobber

# Login to Azure (if not already logged in) and enter correct subscription
Connect-AzAccount -DeviceCode
$setSubscription = Set-AzContext -Subscription $subscription
$tenant = (Get-AzTenant).TenantId

# Create the resource group
$checkRg = Get-AzResourceGroup "$rgNameAzl" -ErrorAction SilentlyContinue
if ($checkRg -eq $null) {
    Write-Host "Creating resource group: $rgNameAzl in location: $location" -ForegroundColor Green
    New-AzResourceGroup -Name $rgNameAzl -Location $location
} else {
    Write-Host "Resource group $rgNameAzl already exists." -ForegroundColor Yellow
}


# If Resource Providers is missing let's register required resource providers
Write-Host "Checking subscription Resource Providers:" -ForegroundColor Green
$AzProvs = "Microsoft.HybridCompute","Microsoft.GuestConfiguration","Microsoft.HybridConnectivity","Microsoft.AzureStackHCI","Microsoft.Kubernetes","Microsoft.KubernetesConfiguration","Microsoft.ExtendedLocation","Microsoft.ResourceConnector","Microsoft.HybridContainerService","Microsoft.Attestation","Microsoft.Storage","Microsoft.Insights"
    foreach($AzProv in $AzProvs) {
    $provider = Get-AzResourceProvider -ProviderNamespace $AzProv
    if ($provider.RegistrationState -ne "Registered") {
        try {
            Write-Host "Registering resource provider $AzProv..."
            Register-AzResourceProvider -ProviderNamespace $AzProv -ErrorAction Stop

            # Wait until the provider is registered
            $maxRetries = 30
            $retryCount = 0
            while (($provider.RegistrationState -ne "Registered") -and ($retryCount -lt $maxRetries)) {
                Write-Host "Waiting for $AzProv to be registered..."
                Start-Sleep -Seconds 10
                $provider = Get-AzResourceProvider -ProviderNamespace $AzProv
                $retryCount++
            }

            if ($provider.RegistrationState -ne "Registered") {
                Write-Host "Unable to register resource provider $AzProv after multiple attempts, exiting..."
                Exit
            }
        } catch {
            Write-Host "Unable to register resource provider $AzProv, exiting..."
            Exit
        }
    } else {
        Write-Host "Resource provider $AzProv is already registered."
    }
}



$cloudAdmin = Get-AzADUser -UserPrincipalName $cloudAdminEmail
$cloudAdminId = $cloudAdmin.id
$subOwner = Get-AzRoleAssignment -Scope "/subscriptions/$($setSubscription.Subscription.Id)" -RoleDefinitionId "8e3af657-a8ff-443c-a75c-2fe8c4bcb635" | Where-Object { $_.ObjectId -eq $cloudAdminId}
$OwnerRoles = "Storage Account Contributor","Key Vault Secrets Officer","Key Vault Data Access Administrator"
$Roles = "Reader","Azure Stack HCI Administrator","Key Vault Contributor","Azure Connected Machine Onboarding","Azure Connected Machine Resource Administrator"
$Roles = $Roles + $OwnerRoles

if ($subOwner -eq $null) {

    foreach ($role in $roles) {
        $assignedRoles = Get-AzRoleAssignment -ObjectId $cloudAdminId -RoleDefinitionName $role -Scope "/subscriptions/$($setSubscription.Subscription.Id)"
        if (-not $assignedRoles){
            Write-Host "Assigning role $role at subscription: $subscription" -ForegroundColor Green
            New-AzRoleAssignment -ObjectId $cloudAdminId -RoleDefinitionName $role -Scope "/subscriptions/$($setSubscription.Subscription.Id)"
        } else {
            Write-Host "User already has role $role at subscription: $subscription" -ForegroundColor Yellow
        }
    }

} else {

    foreach ($role in $OwnerRoles) {
        $assignedRoles = Get-AzRoleAssignment -ObjectId $cloudAdminId -RoleDefinitionName $role -Scope "/subscriptions/$($setSubscription.Subscription.Id)"
        if (-not $assignedRoles) {
            Write-Host "Assigning role $role at subscription: $subscription" -ForegroundColor Green
            New-AzRoleAssignment -ObjectId $cloudAdminId -RoleDefinitionName $role -Scope "/subscriptions/$($setSubscription.Subscription.Id)"
        } else {
            Write-Host "User already has role $role at subscription: $subscription" -ForegroundColor Yellow
        }
    }
}
