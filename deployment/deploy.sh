#!/bin/bash

# Stop the script if any error occurs
set -e

echo "Deployment started"
echo "Location:$1 RG:$2 Clustername:$3 ACR: $4 KV: $5"

resourceGroup=$2
acrName=$4
location=$1
aksClusterName=$3
appgwname="ecommerceGW"
userAssignedIdentityName="aksuserassignedidentity"
agentPool="agentpool"
systemNodePoolName="systempool"
aadAdminGroupId="xxxxxxxx-yyyy-yyyy-yyyy-cccccccccccc"
tenantId="xxxxxxxx-yyyy-yyyy-yyyy-cccccccccccc"
lawName="ecommercelaw"
aiName="ecommerceAI"
vaultName=$5
certName="k8secommercecert"
sslCertName="k8secommercesslcert"
vnetName="ecommerce-prod-vnet"
vnetAddressCIDR="15.1.19.0/24"
kubesubnetCIDR="15.1.19.0/26"
agentsubnetCIDR="15.1.19.64/27"
pesubnetCIDR="15.1.19.128/27"
pesubnetName="pe-subnet"
kubesubnetName="kubesubnet"
appgwCIDR="15.1.19.96/27"
redisName="ecommerceprodredis"

az group create --name $resourceGroup --location $location
#########################################################################
# VNET 
##########################################################################
vnetsinresourcegroup=$(az network vnet list -g $resourceGroup --query "[?name=='$vnetName'].{Name:name}")
if [ "$vnetsinresourcegroup" == "[]" ]; then
    az network vnet create -g $resourceGroup -n $vnetName --address-prefix $vnetAddressCIDR
    az network vnet subnet create -g $resourceGroup --vnet-name $vnetName -n $kubesubnetName --address-prefixes $kubesubnetCIDR
    az network vnet subnet create -g $resourceGroup \
        --vnet-name $vnetName \
        --name agentsubnet \
        --address-prefixes $agentsubnetCIDR
    az network vnet subnet create --vnet-name $vnetName \
        --resource-group $resourceGroup \
        --name $pesubnetName \
        --address-prefixes $pesubnetCIDR \
        --disable-private-endpoint-network-policies "true"
fi

vnetId=$(az network vnet show -n $vnetName -g $resourceGroup | jq -r '.id')
echo "VNET id: $vnetId"
pesubnetid=$vnetId/subnets/$pesubnetName
echo "PE subnet id: $pesubnetid"

######################################################################
# ACR
######################################################################
acrexist=$(az acr list -g $resourceGroup --query "[?name=='$acrName'].{Name:name}")
if [ "$acrexist" == "[]" ]; then
    az acr create --sku Premium -g $resourceGroup -n $acrName 
    acrid=$(az acr show -g $resourceGroup -n $acrName | jq -r '.id')
    echo "ACR ID: $acrid"

    az network private-endpoint create \
        --name "pe-acr" \
        --resource-group $resourceGroup \
        --subnet $pesubnetid \
        --private-connection-resource-id $acrid \
        --group-id "registry" \
        --connection-name myConnection

    az network private-dns zone create \
    --resource-group $resourceGroup \
    --name "privatelink.azurecr.io"

    az network private-dns link vnet create \
    --resource-group $resourceGroup \
    --zone-name "privatelink.azurecr.io" \
    --name MyDNSLink \
    --virtual-network $vnetId \
    --registration-enabled false

    az network private-endpoint dns-zone-group create \
    --resource-group $resourceGroup \
    --endpoint-name "pe-acr" \
    --name RedisZoneGroup \
    --private-dns-zone "privatelink.azurecr.io" \
    --zone-name redis
    
    # Disable every access except for Private Networks
    az acr update --name $acrName --public-network-enabled false
fi

##############################################################
# AKS
##############################################################
aksexist=$(az aks list -g $resourceGroup --query "[?name=='$aksClusterName'].{Name:name}")
if [ "$aksexist" == "[]" ]; then

    # Create Monitoring (Log Analytics workspace)
    workspaceId=$(az monitor log-analytics workspace create -g $resourceGroup -n $lawName --location $location | jq -r '.id')
    echo "Log Analytics workspace id: $workspaceId"

    managedAppID=$(az identity create --name $userAssignedIdentityName --resource-group $resourceGroup | jq -r '.principalId')
    managedObjectID=$(az identity create --name $userAssignedIdentityName --resource-group $resourceGroup | jq -r '.id')
    echo "Managed Identity App ID: $managedAppID"

    kubesubnetid=$(az network vnet subnet show -g $resourceGroup --vnet-name $vnetName -n $kubesubnetName | jq -r '.id')

    #ServicePrincipal on behalf of the build agent runs shall have User Access Administrator rights, otherwise vnet AAD propagation will not work
    az aks create \
        --resource-group $resourceGroup \
        --name $aksClusterName \
        --node-count 3 \
        --min-count 3 \
        --max-count 5 \
        --enable-cluster-autoscaler \
        --enable-addons monitoring \
        --network-plugin kubenet \
        --assign-identity $managedObjectID \
        --kubernetes-version 1.21.2 \
        --appgw-name $appgwname \
        --appgw-subnet-cidr $appgwCIDR \
        -a ingress-appgw \
        --load-balancer-sku standard \
        --enable-managed-identity \
        --nodepool-name $systemNodePoolName \
        --no-ssh-key \
        --enable-aad \
        --enable-private-cluster \
        --aad-admin-group-object-ids $aadAdminGroupId \
        --aad-tenant-id $tenantId \
        --vnet-subnet-id $kubesubnetid #\
        #--debug
        #--workspace-resource-id $workspaceId
        #--network-policy calico \
        #--vnet-subnet-id /subscriptions/13b35c71-93a1-4a21-b44f-033ec51c04c6/resourceGroups/ecommerce_teszt/providers/Microsoft.Network/virtualNetworks/ecommerceTestVNet/subnets/ecommerce_TEST_Proxy \
    
    #Check whether nodepool exists
    nodepool=$(az aks nodepool list --cluster-name $aksClusterName --resource-group $resourceGroup --query "[?name=='agentpool'].{Name:name}")
    if [ "$nodepool" == "[]" ]; then
        echo "nodepool doesn't exist"
        az aks nodepool add \
        --resource-group $resourceGroup \
        --cluster-name $aksClusterName \
        --name $agentPool \
        --mode User \
        --node-vm-size standard_d2_v3 \
        --node-count 3 \
        --max-count 4 \
        --min-count 3 \
        --enable-cluster-autoscaler
        
    else
        echo "Nodepool exists"
    fi

    #Enable Monitoring 
    az aks enable-addons -a monitoring -n $aksClusterName -g $resourceGroup --workspace-resource-id $workspaceId

    #Enable Diagnostic Settings for audit logging
    aksId=$(az aks show --name $aksClusterName --resource-group $resourceGroup | jq -r '.id')
    az monitor diagnostic-settings create  \
    --name Audit-Diagnostics \
    --resource $aksId \
    --logs '[{"category": "kube-audit","enabled": true}, {"category": "kube-audit-admin","enabled": true}, {"category": "guard","enabled": true}]' \
    --workspace $workspaceId

    clusterSPID=$managedAppID
    echo "AKS cluster SP ID: $managedAppID"

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
    # PrincipalID is required: https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/howto-assign-access-cli
    echo "Assigning Cluster Identity to ACR"
    az role assignment create --assignee $clusterSPID --scope $acrnameFullPath --role acrpull

    echo "Assigning AgentPool Identity to ACR"
    az role assignment create --assignee-object-id $agentpoolSPID --scope $acrnameFullPath --role acrpull --assignee-principal-type ServicePrincipal
fi

#CREATE SSL CERTIFICATE FOR Application Gateway Ingress Controller
#Link: https://azure.github.io/application-gateway-kubernetes-ingress/features/appgw-ssl-certificate/
MCResourceGroup="MC_${resourceGroup}_${aksClusterName}_${location}"
#Get the user assigned identity used for managing Application Gateway
#Something like this "/subscriptions/38628df3-5cd3-48ee-acae-07caf525b43f/resourcegroups/MC_ecommerce.rg_ecommerceCluster_northeurope/providers/Microsoft.ManagedIdentity/userAssignedIdentities/ingressapplicationgateway-ecommercecluster
userAssignedIdentityForAppGWResourceId=$(az aks show --name $aksClusterName --resource-group $resourceGroup | jq -r '.addonProfiles.ingressApplicationGateway.identity.resourceId')
userAssignedIdentityForAppGWObjectId=$(az aks show --name $aksClusterName --resource-group $resourceGroup | jq -r '.addonProfiles.ingressApplicationGateway.identity.objectId')
# One time operation, create Azure key vault and certificate (can done through portal as well)

echo "Checking Key Vault"
keyvaultexist=$(az keyvault list -g $resourceGroup --query "[?name=='$vaultName'].{Name:name}")
if [ "$keyvaultexist" == "[]" ]; then
    echo "Creating Key Vault"
    az keyvault create -n $vaultName -g $resourceGroup -l $location

    az network application-gateway identity assign \
    --gateway-name $appgwname \
    --resource-group $MCResourceGroup \
    --identity $userAssignedIdentityForAppGWResourceId

    # One time operation, assign the identity GET secret access to Azure Key Vault
    az keyvault set-policy \
    -n $vaultName \
    -g $resourceGroup \
    --object-id $userAssignedIdentityForAppGWObjectId \
    --secret-permissions get

    #check whether we have the certificate in Key Vault

    certificateInKeyVault=$(az keyvault certificate list --vault-name $vaultName --query "[?name=='$certName']")
    if [ "$certificateInKeyVault" == "[]" ]; then
        echo "Certificate doesn't exist, create one"
        # For each new certificate, create a cert on keyvault and add unversioned secret id to Application Gateway
        az keyvault certificate create \
        --vault-name $vaultName \
        -n $certName \
        -p "$(az keyvault certificate get-default-policy)"    
    else
        echo "Certificate in Key Vault exists, no overwrite takes place"
    fi

    versionedSecretId=$(az keyvault certificate show -n $certName --vault-name $vaultName --query "sid" -o tsv)
    unversionedSecretId=$(echo $versionedSecretId | cut -d'/' -f-5) # remove the version from the url

    # For each new certificate, Add the certificate to AppGw
    az network application-gateway ssl-cert create \
    -n $sslCertName \
    --gateway-name $appgwname \
    --resource-group $MCResourceGroup \
    --key-vault-secret-id $unversionedSecretId # ssl certificate with name "$sslCertName" will be configured on AppGw
fi

##################################################################
# Redis cache for Azure
##################################################################
redisexist=$(az redis list -g $resourceGroup)
if [ "$redisexist" == "[]" ]; then
    echo "Deploying Redis Cache for Azure"
    #vm size from c0 to c6
    az redis create --location $location \
    --name $redisName \
    --resource-group $resourceGroup \
    --sku Standard \
    --vm-size c0 \
    --enable-non-ssl-port \
    --redis-version="6"

    redisresourceid=$(az redis show --name $redisName --resource-group $resourceGroup | jq -r '.id')
    #vnetResourceGroup=$(az network vnet show --ids $vnetId | jq '.resourceGroup')

    #we need to wait until Redis is running
    redisState=$(az redis show -n $redisName -g $resourceGroup | jq -r ".provisioningState")
    while [[ $redisState != "Succeeded" ]]  
    do
        echo "Redis state: $redisState"
        sleep 5
        redisState=$(az redis show -n $redisName -g $resourceGroup | jq -r ".provisioningState")
    done

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
        --virtual-network $vnetId \
        --registration-enabled false

    az network private-endpoint dns-zone-group create \
    --resource-group $resourceGroup \
    --endpoint-name "pe-redis" \
    --name RedisZoneGroup \
    --private-dns-zone "privatelink.redis.cache.windows.net" \
    --zone-name redis
fi


# Call AAD Pod Identity Deployment
#./deployment/deployAADPodIdentity.sh $resourceGroup $aksClusterName

# Call Azure Key Vault deployment 
# ./deployment/deployKeyVaultWithCSIdriver.sh $location $resourceGroup $aksClusterName

