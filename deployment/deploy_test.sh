#!/bin/bash
echo "Deployment started"

echo "Location:$1 RG:$2 Clustername:$3 ACR: $4 KV: $5"

resourceGroup=$2
acrName=$4
appGwName="ecommerceGW"
location=$1
aksClusterName=$3
lawName="ecommercelaw"
aadAdminGroupId="xxxxxxxx-yyyy-yyyy-yyyy-cccccccccccc"
vaultName=$5
certName="ecommerceCert"
sslCertName="ecommerceSslCert"
# Must be unique
redisName="ecommerceredis202110"


az group create --name $resourceGroup --location $location
az acr create --sku Basic -g $resourceGroup -n $acrName 

# Create Monitoring (Log Analytics workspace)
workspaceId=$(az monitor log-analytics workspace create -g $resourceGroup -n $lawName --location $location | jq -r '.id')
echo "Log Analytics workspace id: $workspaceId"

az aks create \
    --resource-group $resourceGroup \
    --name $aksClusterName \
    --node-count 3 \
    --enable-addons monitoring \
    --kubernetes-version 1.21.2 \
    --appgw-name $appGwName \
    -a ingress-appgw \
    --appgw-subnet-cidr "10.2.2.0/24" \
    --load-balancer-sku standard \
    --enable-managed-identity \
    --no-ssh-key \
    --enable-aad \
    #--enable-private-cluster \
    --network-plugin kubenet \
    --network-policy calico \
    --aad-admin-group-object-ids $aadAdminGroupId

#Enable Monitoring 
az aks enable-addons -a monitoring -n $aksClusterName -g $resourceGroup --workspace-resource-id $workspaceId

#Enable Diagnostic Settings for audit logging
aksId=$(az aks show --name $aksClusterName --resource-group $resourceGroup | jq -r '.id')
az monitor diagnostic-settings create \
--name Audit-Diagnostics \
--resource $aksId \
--logs '[{"category": "kube-audit","enabled": true}, {"category": "kube-audit-admin","enabled": true}, {"category": "guard","enabled": true}]' \
--workspace $workspaceId

#Enable Azure Open Service Mesh
az feature register --namespace Microsoft.ContainerService --name AKS-OpenServiceMesh
az provider register -n Microsoft.ContainerService
az aks enable-addons --addons open-service-mesh -g $resourceGroup -n $aksClusterName

clusterSPID=$(az aks show --name $aksClusterName --resource-group $resourceGroup | jq -r '.identity.principalId')
echo "AKS cluster SP ID: $clusterSPID"

agentpoolSPID=$(az aks show --name $aksClusterName --resource-group $resourceGroup | jq -r '.identityProfile.kubeletidentity.objectId')
echo "AKS cluster AgentPool SP ID: $agentpoolSPID"

# in the form of /subscriptions/id/resourceGroups/rg/providers/Microsoft.ContainerRegistry/registries/ecommerceRegistry
acrnameFullPath=$(az acr show --name $acrName --query id --output tsv)
echo "ACR name full path: $acrnameFullPath"

#Note that the documented command uses the Application ID for your Service Principal. 
#This also requires access to the Azure Active Directory Graph. 
#As such, you will need to replace --assignee $SERVICE_PRINCIPAL_ID with --assignee-object-id $SERVICE_PRINCIPAL_OBJECT_ID where $SERVICE_PRINCIPAL_OBJECT_ID is the Object ID of the Service Principal, and not the Application ID which we would usually use.
#For example:
# az role assignment create --assignee-object-id $SERVICE_PRINCIPAL_OBJECT_ID --scope $ACR_REGISTRY_ID --role acrpull
# See: https://github.com/Azure/AKS/issues/1517
echo "Assigning Cluster Identity to ACR"
az role assignment create --assignee-object-id $clusterSPID --scope $acrnameFullPath --role acrpull --assignee-principal-type ServicePrincipal

echo "Assigning AgentPool Identity to ACR"
az role assignment create --assignee-object-id $agentpoolSPID --scope $acrnameFullPath --role acrpull --assignee-principal-type ServicePrincipal

#CREATE SSL CERTIFICATE FOR Application Gateway Ingress Controller
#Link: https://azure.github.io/application-gateway-kubernetes-ingress/features/appgw-ssl-certificate/
MCResourceGroup="MC_${resourceGroup}_${aksClusterName}_${location}"

#Get the user assigned identity used for managing Application Gateway
#Something like this "/subscriptions/38628df3-5cd3-48ee-acae-07caf525b43f/resourcegroups/MC_ecommerce.rg_ecommerceCluster_northeurope/providers/Microsoft.ManagedIdentity/userAssignedIdentities/ingressapplicationgateway-ecommercecluster
userAssignedIdentityForAppGWResourceId=$(az aks show --name $aksClusterName --resource-group $resourceGroup | jq -r '.addonProfiles.ingressApplicationGateway.identity.resourceId')
userAssignedIdentityForAppGWObjectId=$(az aks show --name $aksClusterName --resource-group $resourceGroup | jq -r '.addonProfiles.ingressApplicationGateway.identity.objectId')
# One time operation, create Azure key vault and certificate (can done through portal as well)
az keyvault create -n $vaultName -g $resourceGroup --enable-soft-delete -l $location

az network application-gateway identity assign \
  --gateway-name $appGwName \
  --resource-group $MCResourceGroup \
  --identity $userAssignedIdentityForAppGWResourceId

# Redis cache for Azure
echo "Deploying Redis Cache for Azure"
#vm size from c0 to c6
az redis create --location $location \
   --name $redisName \
   --resource-group $resourceGroup \
   --sku Standard \
   --vm-size c0 \
   #--enable-non-ssl-port \
   --redis-version="6"

redisresourceid=$(az redis show --name $redisName --resource-group $resourceGroup | jq -r '.id')
# when vnet is automatically created by cluster
aksvnetid=$(az network vnet list --resource-group MC_ecommerce.rg_ecommerceCluster_northeurope | jq -r '.[0].id')
aksvnetname=$(az network vnet list --resource-group MC_ecommerce.rg_ecommerceCluster_northeurope | jq -r '.[0].name')

# Default VNET created by AKS, Address space:10.0.0.0/8
echo "resource-group: $MCResourceGroup"
echo "vnet-name: $aksvnetname"
az network vnet subnet create --vnet-name $aksvnetname \
                              --resource-group $MCResourceGroup \
                              --name "pe-subnet" \
                              --address-prefixes 10.99.99.0/24 \
                              --disable-private-endpoint-network-policies "true"

pesubnetName="/subnets/pe-subnet"
pesubnetid=$aksvnetid$pesubnetName
# create private endpoint on the vnet
az network private-endpoint create --name "pe-redis"\
                                   --connection-name "redisconnection" \
                                   --private-connection-resource-id $redisresourceid\
                                   --resource-group $resourceGroup\
                                   --subnet $pesubnetid \
                                   --group-id "redisCache"
# Create private dns zone
az network private-dns zone create -g $resourceGroup -n "privatelink.redis.cache.windows.net"

az network private-dns link vnet create \
    --resource-group $resourceGroup \
    --zone-name "privatelink.redis.cache.windows.net" \
    --name MyDNSLink \
    --virtual-network $aksvnetid \
    --registration-enabled false

az network private-endpoint dns-zone-group create \
   --resource-group $resourceGroup \
   --endpoint-name "pe-redis" \
   --name MyZoneGroup \
   --private-dns-zone "privatelink.redis.cache.windows.net" \
   --zone-name redis

#az network private-dns record-set a add-record -g $resourceGroup -z "privatelink.redis.cache.windows.net" \
#    -n $redisName -a 10.99.99.5

# One time operation, assign the identity GET secret access to Azure Key Vault
az keyvault set-policy \
-n $vaultName \
-g $resourceGroup \
--object-id $userAssignedIdentityForAppGWObjectId \
--secret-permissions get

# For each new certificate, create a cert on keyvault and add unversioned secret id to Application Gateway
az keyvault certificate create \
--vault-name $vaultName \
-n $certName \
-p "$(az keyvault certificate get-default-policy)"

versionedSecretId=$(az keyvault certificate show -n $certName --vault-name $vaultName --query "sid" -o tsv)
unversionedSecretId=$(echo $versionedSecretId | cut -d'/' -f-5) # remove the version from the url

# For each new certificate, Add the certificate to AppGw
az network application-gateway ssl-cert create \
-n $sslCertName \
--gateway-name $appGwName \
--resource-group $MCResourceGroup \
--key-vault-secret-id $unversionedSecretId # ssl certificate with name "$sslCertName" will be configured on AppGw
