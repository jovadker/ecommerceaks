# Introduction

Deployment of AKS private cluster using AZ CLI scripts.

---
> [!TIP]
> Scripts are only for demonstrating purposes.


# Architecture 
![Architecture diagram](/Architecture/Architecture.jpg)

# Getting Started

## **1. Installation process**

- Use the bash scripts available under the folder 'deployment' to deploy your AKS cluster in your own subscription. 
    - Deploy.sh deploys a private AAD-enabled AKS cluster, whereas 
    - deploy_test.sh deploys only an AAD-enabled AKS cluster.
- AAD group is required to deploy the clusters, see bash variable "aadAdminGroupId="xxxxxxxxxxxxxxxxxxx"
- Tenant ID shall be set accordingly in the scripts where applicable
- Other scripts, like deployAADPodIdentity, NGinx, etc are optional

## **2. Software dependencies**

- Not applicable

# Build and Test

## 1. Use **deploy.sh** or **deploy_test.sh** from your pipelines to deploy the AKS cluster:
```bash 
echo "change chmod to be executable"
sudo chmod +x $(Build.SourcesDirectory)/deployment/deploy.sh
# Fails the AzureCLI task if the below deployment script fails   
set -e
$(Build.SourcesDirectory)/deployment/deploy.sh $(location) $(resourcegroup) $(clustername) $(acrname) $(vaultname)
```

## 2. Deploy an Azure DevOps Agent into the VNET of your AKS cluster ([deployagenttovnet.sh](./adolinuxagent\deployagenttovnet.sh))
```bash
set -e
echo "change chmod to be executable"
sudo chmod +x $(Build.SourcesDirectory)/adolinuxagent/deployagenttovnet.sh
cd $(Build.SourcesDirectory)/adolinuxagent
./deployagenttovnet.sh ${{ parameters.resourcegroup }} $(location) $(acrname) $(vnetid) $(subnetid) $(devopsUrl) $(RegistrationToken) $(adopool)
```

## 3. Post-deployment steps of your AKS cluster

- Deploy AAD POD Identity
- Set up GitOps using Azure Arc if needed

```yml
steps:
- script: |
     #on self hosted agent it is required
     #Install kubectl
     apt-get update
     apt-get install -y apt-transport-https ca-certificates curl
     curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
     echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
     apt-get update
     apt-get install -y kubectl
     curl https://baltocdn.com/helm/signing.asc | apt-key add -
     apt-get install apt-transport-https --yes
     echo "deb https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
     apt-get update
     apt-get install -y helm
     #Install kubelogin
     az aks install-cli
      
- task: AzureCLI@2
  inputs:
    azureSubscription: 'jovadkerAKS'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
     echo "change chmod to be executable"
     set -e
     chmod +x $(Build.SourcesDirectory)/deployment/deployAADPodIdentity.sh
     # Get credentials in case of AAD-enabled cluster
     az aks get-credentials --name $(clustername) --resource-group $(resourcegroup) --overwrite-existing
     kubelogin convert-kubeconfig -l azurecli 
     $(Build.SourcesDirectory)/deployment/deployAADPodIdentity.sh $(resourcegroup) $(clustername)
  displayName: 'Deploy AAD Pod Identity with Gatekeeper'
- task: AzureCLI@2
  inputs:
    azureSubscription: 'jovadkerAKS'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
     echo "change chmod to be executable"
     set -e
     chmod +x $(Build.SourcesDirectory)/deployment/setupGitOpsUsingAzureArc.sh
     # Get credentials in case of AAD-enabled cluster
     az aks get-credentials --name $(clustername) --resource-group $(resourcegroup) --overwrite-existing
     kubelogin convert-kubeconfig -l azurecli 
     $(Build.SourcesDirectory)/deployment/setupGitOpsUsingAzureArc.sh $(location) $(resourcegroup) $(clustername) $(gitRepoUrl) $(fullpath) $(branchName) $(gituser) $(gitpattoken)
  displayName: 'Setup Azure-ARC'


```

## 4. Build and Push a test docker image with the help of your self-hosted agent into the ACR

```yml
trigger:
- none

pool:
  #default pool contains the ACI self-hosted agent
  name: default
  #vmImage: ubuntu-latest
  

variables:
  containerRegistry: 'ecommerceProdRegistry.azurecr.io'
  resourceGroup: 'ecommerce.prod.rg'
steps:
- task: AzureCLI@2
  inputs:
    azureSubscription: 'jovadkerAKS'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
     set -e
     echo "Start building dockerfile"
     cd docker/ubi8web
     my_ip=$(curl https://ifconfig.me)
     echo "My IP: $my_ip"
     az acr update --name $(containerRegistry) --public-network-enabled true 
     #az acr network-rule add --name $(containerRegistry) --ip-address $my_ip
     #az acr login -n $(containerRegistry) --expose-token
     # wait for 5 seconds to get network changes applied
     sleep 5
     az acr build --registry $(containerRegistry) --image redhat/ubi8web:$(Build.BuildId) .
     
     az acr update --name $(containerRegistry) --public-network-enabled false

```

## 5. Kubectl the deployment.yaml or let GitOps do his work
- Use kubectl apply -f ./k8s/deployment.yaml to push changes to the cluster
- If you set up the GitOps part, then you can use the sample under 'cluster-config-prod' to let FluxCD automatically deploy the desired stated of the cluster

# Contribute
Please feel free to reuse these samples. If you think, there are better approaches to accomplish these jobs, please share with us.
