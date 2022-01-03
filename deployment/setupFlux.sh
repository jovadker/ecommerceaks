#!/bin/bash
echo "Flux Deployment started"

resourceGroup=$2
location=$1
aksClusterName=$3
GitRepoUrl="https://dev.azure.com/jovadker/DevOps/_git/eCommerceAKSGitOps"
user=$4
pat=$5

#Installation steps
# https://fluxcd.io/docs/use-cases/azure/#flux-installation-for-azure-devops

curl -s https://fluxcd.io/install.sh | sudo bash

# create the flux.yaml that will be deployed to cluster
mkdir -p ./flux-system
flux install \
  --export > ./flux-system/gotk-components.yaml
kubectl apply -f ./flux-system/gotk-components.yaml

flux create source git flux-system \
  --git-implementation=libgit2 \
  --url=$GitRepoUrl \
  --branch=main \
  --username=$user \
  --password=$pat \
  --interval=1m
# check the deployment of flux-system
flux check

# Kustomization contains the path inside the branch of the repository to be synched with AKS cluster
# a dummy folder needs to be created locally
mkdir -p ./cluster-config-prod
flux create kustomization flux-system \
  --source=flux-system \
  --path="./cluster-config-prod" \
  --prune=true \
  --interval=10m

# check the kustomizations
flux get kustomizations --watch