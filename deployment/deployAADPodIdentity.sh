#!/bin/bash
set -e

resourceGroup=$1
aksClusterName=$2
aadpodnamespace="aadpodidentity"
gatekeepernamespace="gatekeeper"

echo "Cluster name: $aksClusterName and Resource-Group: $resourceGroup"

# Install AAD Pod Identity
kubectl get namespace | grep -q "^$aadpodnamespace " || kubectl create namespace $aadpodnamespace
nmi=`kubectl get pods --namespace $aadpodnamespace | grep "nmi"|awk '{print $1}'`

#Check the variable is set or not
if [ -z "$nmi" ]; then
  echo "‘nmi’ pod is not present"
  helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
  helm install aad-pod-identity aad-pod-identity/aad-pod-identity --set nmi.allowNetworkPluginKubenet=true --namespace $aadpodnamespace
else
  helm uninstall aad-pod-identity --namespace $aadpodnamespace
  sleep 5
  helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
  helm install aad-pod-identity aad-pod-identity/aad-pod-identity --set nmi.allowNetworkPluginKubenet=true --namespace $aadpodnamespace
  echo "‘nmi’ pod is running"
fi

# Install Gatekeeper if not exists
# ARP spoofing security vulnerabilities: https://docs.microsoft.com/en-us/azure/aks/use-azure-ad-pod-identity
kubectl get namespace | grep -q "^$gatekeepernamespace " || kubectl create namespace $gatekeepernamespace

gatekeeper=`kubectl get pods --namespace $gatekeepernamespace | grep "gatekeeper"|awk '{print $1}'`

#Check the variable is set or not
if [ -z "$gatekeeper" ]; then
  echo "‘gatekeeper’ pods are not present"
  helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
  helm install gatekeeper gatekeeper/gatekeeper --namespace $gatekeepernamespace
else
  helm uninstall gatekeeper --namespace $gatekeepernamespace
  sleep 5
  helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
  helm install gatekeeper gatekeeper/gatekeeper --namespace $gatekeepernamespace
  echo "gatekeeper pods are running"
fi

# If you are not using Azure Policy, you can use OpenPolicyAgent admission controller together with Gatekeeper validating webhook. 
# Provided you have Gatekeeper already installed in your cluster, add the ConstraintTemplate of type K8sPSPCapabilities:
kubectl apply --namespace $gatekeepernamespace -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/pod-security-policy/capabilities/template.yaml

cat << EOF | kubectl apply --namespace=$gatekeepernamespace -f -
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPCapabilities
metadata:
  name: prevent-net-raw
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    excludedNamespaces: ["kube-system", "cluster-config", "flux-system", "monitoring"]
  parameters:
    requiredDropCapabilities: ["NET_RAW"]
EOF


