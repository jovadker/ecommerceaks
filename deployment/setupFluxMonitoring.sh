#!bin/bash
echo "Flux monitoring"

# Link: https://fluxcd.io/docs/guides/monitoring/

# Prometheus shall be installed before kustomization
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
			--namespace monitoring \
			--create-namespace \
			--wait

# Get the Flux monitorin code
flux create source git monitoring \
  --interval=30m \
  --url=https://github.com/fluxcd/flux2 \
  --branch=main

# Kustomization contains the path inside the branch of the repository to be synched with AKS cluster
# a dummy folder needs to be created locally
mkdir -p ./manifests

#Install monitoring of Flux
flux create kustomization monitoring-stack \
  --interval=1h \
  --prune=true \
  --source=monitoring \
  --path="./manifests/monitoring/kube-prometheus-stack" \
  --health-check="Deployment/kube-prometheus-stack-operator.monitoring" \
  --health-check="Deployment/kube-prometheus-stack-grafana.monitoring"

#Install grafana
  flux create kustomization monitoring-config \
  --interval=1h \
  --prune=true \
  --source=monitoring \
  --path="./manifests/monitoring/monitoring-config"