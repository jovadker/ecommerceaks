#!/bin/bash
set -e 

#INPUTS
resourceGroup=$1
location=$2
#name of acr without suffix '.'
containerRegistryName=$3
vnetid=$4
subnetId=$5
ado_url=$6
ado_token=$7
ado_pool=$8

echo "resourceGroup: $resourceGroup"
echo "location: $location"
#name of acr without suffix '.'
echo "containerRegistryName: $containerRegistryName"
echo "vnetid: $vnetid"
echo "subnetId: $subnetId"
echo "ado_url: $ado_url"
echo "ado_token: $ado_token"
echo "ado_pool: $ado_pool"

az group create --name $resourceGroup --location $location

aciname="jovadkerrunner"

# Container Registry
# Create a container registry for only self-hosted agent images
az acr create --sku Standard -g $resourceGroup -n $containerRegistryName 

# Storage accounts
ACI_PERS_STORAGE_ACCOUNT_NAME="${aciname}sa"
echo "ACI SA Account: $ACI_PERS_STORAGE_ACCOUNT_NAME"
ACI_PERS_SHARE_NAME="acishare"

# Create the storage account with the parameters
az storage account create \
    --resource-group $resourceGroup \
    --name $ACI_PERS_STORAGE_ACCOUNT_NAME \
    --location $location \
    --sku Standard_LRS

# Create the file share
az storage share create \
  --name $ACI_PERS_SHARE_NAME \
  --account-name $ACI_PERS_STORAGE_ACCOUNT_NAME

# Storage account key
STORAGE_KEY=$(az storage account keys list --resource-group $resourceGroup --account-name $ACI_PERS_STORAGE_ACCOUNT_NAME --query "[0].value" --output tsv)

versionNumber=$(date +'%Y%m%d%H%M%S')
image="azuredevops/linuxagent:$versionNumber"
az acr build --registry $containerRegistryName --image $image .

az acr update -n $containerRegistryName --admin-enabled true
#get the password for admin-enabled
registryPassword=$(az acr credential show -n $containerRegistryName | jq -r '.passwords[0].value')

fullImageName="${containerRegistryName}.azurecr.io/${image}"

# Wait for container to be ready in ACR
sleep 10

echo "Full image: $fullImageName"

az container create --resource-group $resourceGroup --name $aciname \
 --image $fullImageName \
 --registry-username $containerRegistryName \
 --registry-password $registryPassword \
 --restart-policy never \
 --vnet $vnetid \
 --subnet $subnetId \
 --environment-variables AZP_URL=$ado_url AZP_TOKEN=$ado_token AZP_POOL=$ado_pool \
 --azure-file-volume-account-name $ACI_PERS_STORAGE_ACCOUNT_NAME \
 --azure-file-volume-account-key $STORAGE_KEY \
 --azure-file-volume-share-name $ACI_PERS_SHARE_NAME \
 --azure-file-volume-mount-path /aci/adoagent/ \
 --cpu 2 \
 --memory 4

az acr update -n $containerRegistryName --admin-enabled false