#!/bin/bash
echo "Let's encrypt"

# Install the CustomResourceDefinition resources separately
#kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.14/deploy/manifests/00-crds.yaml

# Create the namespace for cert-manager
kubectl create namespace cert-manager

# Label the cert-manager namespace to disable resource validation
#kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true

# Add the Jetstack Helm repository
#helm repo add jetstack https://charts.jetstack.io

# Update your local Helm chart repository cache
#helm repo update

# Install the cert-manager Helm chart
# Helm v3+
#helm install \
#  cert-manager jetstack/cert-manager \
# --namespace cert-manager \
#  --version v0.14.0 \
  # --set installCRDs=true

#To automatically install and manage the CRDs as part of your Helm release, 
#   you must add the --set installCRDs=true flag to your Helm installation command.

kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.5.4/cert-manager.yaml

cat << EOF | kubectl apply -f - 
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: jozsef.vadkerti@hotmail.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencryptprivatekeysecret
    solvers:
     - http01:
        ingress:
         class: nginx
EOF