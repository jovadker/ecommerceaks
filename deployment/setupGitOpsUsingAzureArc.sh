#!/bin/bash
set -e

echo "GitOps Deployment started"

location=$1
resourceGroup=$2
aksClusterName=$3
azurearcaksClusterName="arc-ecommerceCluster"
k8sconfigurationName="arc-ecommerceaks-cluster-config"
GitRepoUrl=$4
Path=$5
Branch=$6
user=$7
pat=$8

az extension add --name connectedk8s
az extension add --name k8sconfiguration
az extension add --name k8s-configuration

az extension update --name connectedk8s
az extension update --name k8sconfiguration

# Connect an existing Kubernetes cluster to Azure Arc
# Onboard a connected kubernetes cluster with default kube config and kube context, hence we call az aks get-credentials at the beginning
#az aks get-credentials --name $aksClusterName --resource-group $resourceGroup
az connectedk8s connect --name $azurearcaksClusterName --resource-group $resourceGroup

echo "set k8sconfiguration"

aksk8sConfig=$(az k8s-configuration list --resource-group $resourceGroup --cluster-name $azurearcaksClusterName --cluster-type connectedClusters)

if [ "$aksk8sConfig" == "[]" ]; then
    echo "k8sconfiguration doesn't exist"
    # Create Azure-arc enabled Kubernetes configuration for Cluster
   az k8sconfiguration create \
      --name $k8sconfigurationName \
      --cluster-name $azurearcaksClusterName \
      --resource-group $resourceGroup \
      --operator-instance-name cluster-config \
      --operator-namespace cluster-config \
      --repository-url $GitRepoUrl \
      --scope cluster \
      --cluster-type connectedClusters \
      --operator-params="--git-readonly --git-path=$Path --git-branch=$Branch --git-poll-interval 2m" \
      --https-user $user \
      --https-key $pat
      #--ssh-private-key-file $pemFileLocation
      #--ssh-private-key '$MY_CERTIFICATE'
      #--https-user $user \
      #--https-key $pat \
    
else
    echo "k8configuration exists"
fi



