#!/bin/bash

location=$1
resourceGroup=$2
aksClusterName=$3

keyvaultName="ecommercetestkv"
servicePrincipalName="http://kv-secrets-store-test"
csiNamespace="csi"
tenantId="xxxxxxxx-yyyy-yyyy-yyyy-cccccccccccc"

echo "Location: $location and Resource-Group: $resourceGroup"

#Creating the keyvault and adding access to 
az keyvault create --location $location --name $keyvaultName --resource-group $resourceGroup

# Create a service principal to access keyvault
export SERVICE_PRINCIPAL_CLIENT_SECRET="$(az ad sp create-for-rbac --skip-assignment --name $servicePrincipalName --query 'password' -otsv)"
export SERVICE_PRINCIPAL_CLIENT_ID="$(az ad sp show --id $servicePrincipalName --query 'appId' -otsv)"

#Assign access policy to key vault
az keyvault set-policy -n $keyvaultName --secret-permissions get --spn $SERVICE_PRINCIPAL_CLIENT_ID
az keyvault set-policy -n $keyvaultName --key-permissions get --spn $SERVICE_PRINCIPAL_CLIENT_ID
az keyvault set-policy -n $keyvaultName --certificate-permissions get --spn $SERVICE_PRINCIPAL_CLIENT_ID

#Add a sample secret
az keyvault secret set --vault-name $keyvaultName --name secret1 --value "Hello!"

#Install Secret Store Driver
az aks get-credentials --name $aksClusterName --resource-group $resourceGroup --overwrite-existing
kubectl create ns $csiNamespace

helm repo add csi-secrets-store-provider-azure https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts
helm install csi csi-secrets-store-provider-azure/csi-secrets-store-provider-azure -n $csiNamespace

kubectl create secret generic secrets-store-creds --from-literal clientid=$SERVICE_PRINCIPAL_CLIENT_ID --from-literal clientsecret=$SERVICE_PRINCIPAL_CLIENT_SECRET
kubectl label secret secrets-store-creds secrets-store.csi.k8s.io/used=true

cat << EOF
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: azure-kvname
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "false"
    userAssignedIdentityID: ""
    keyvaultName: "$keyvaultName"
    objects: |
      array:
        - |
          objectName: secret1              
          objectType: secret
          objectVersion: ""
    tenantId: "$tenantId"
EOF

cat <<EOF | kubectl apply --namespace=$csiNamespace -f -
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: azure-kvname
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "false"
    userAssignedIdentityID: ""
    keyvaultName: "$keyvaultName"
    objects: |
      array:
        - |
          objectName: secret1              
          objectType: secret
          objectVersion: ""
    tenantId: "$tenantId"
EOF

cat << EOF
kind: Pod
apiVersion: v1
metadata:
  name: busybox-secrets-store-inline
spec:
  containers:
  - name: busybox
    image: k8s.gcr.io/e2e-test-images/busybox:1.29
    command:
      - "/bin/sleep"
      - "10000"
    volumeMounts:
    - name: secrets-store-inline
      mountPath: "/mnt/secrets-store"
      readOnly: true
  volumes:
    - name: secrets-store-inline
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "azure-kvname"
        nodePublishSecretRef:                       # Only required when using service principal mode
          name: secrets-store-creds                 # Only required when using service principal mode
EOF

cat <<EOF | kubectl apply --namespace=$csiNamespace -f -
kind: Pod
apiVersion: v1
metadata:
  name: busybox-secrets-store-inline
spec:
  containers:
  - name: busybox
    image: k8s.gcr.io/e2e-test-images/busybox:1.29
    command:
      - "/bin/sleep"
      - "10000"
    volumeMounts:
    - name: secrets-store-inline
      mountPath: "/mnt/secrets-store"
      readOnly: true
  volumes:
    - name: secrets-store-inline
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "azure-kvname"
        nodePublishSecretRef:                       # Only required when using service principal mode
          name: secrets-store-creds                 # Only required when using service principal mode
EOF
