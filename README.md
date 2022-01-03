# Introduction

Deployment of AKS private cluster using AZ CLI scripts.

---
> [!TIP]
> Scripts are only for demonstrating purposes.

# Getting Started

**1. Installation process**

- Use the bash scripts available under the folder 'deployment' to deploy your AKS cluster in your own subscription. Deploy.sh deploys a private AAD-enabled AKS cluster, whereas deploy_test.sh deploys only an AAD-enabled AKS cluster.
- AAD group is required to deploy the clusters, see bash variable "aadAdminGroupId="xxxxxxxxxxxxxxxxxxx"
- Tenant ID shall be set accordingly in the scripts where applicable
- Other scripts, like deployAADPodIdentity, NGinx, etc are optional

**2. Software dependencies**

- Not applicable

# Build and Test

1. Use **deploy.sh** or **deploy_test.sh** from your pipelines to deploy the AKS cluster:

```echo "change chmod to be executable"
sudo chmod +x $(Build.SourcesDirectory)/deployment/deploy.sh
# Fails the AzureCLI task if the below deployment script fails   
set -e
$(Build.SourcesDirectory)/deployment/deploy.sh $(location) $(resourcegroup) $(clustername) $(acrname) $(vaultname)
```

2. Deploy an Azure DevOps Agent into the VNET of your AKS cluster (adolinuxagent\deployagenttovnet.sh)
``` set -e
    echo "change chmod to be executable"
    sudo chmod +x $(Build.SourcesDirectory)/adolinuxagent/deployagenttovnet.sh
    cd $(Build.SourcesDirectory)/adolinuxagent
    ./deployagenttovnet.sh ${{ parameters.resourcegroup }} $(location) $(acrname) $(vnetid) $(subnetid) $(devopsUrl) $(RegistrationToken) $(adopool)
```

3. Build a test Docker image

4. Push the test image with the help of your self-hosted agent into the ACR

5. 


# Contribute
