#!/bin/bash
echo "Setup Azure Service Mesh"

location=$1
resourceGroup=$2
aksClusterName=$3

# Specify the OSM version that will be leveraged throughout these instructions
OSM_VERSION=v0.9.1

curl -sL "https://github.com/openservicemesh/osm/releases/download/$OSM_VERSION/osm-$OSM_VERSION-linux-amd64.tar.gz" | tar -vxzf -

sudo mv ./linux-amd64/osm /usr/local/bin/osm
sudo chmod +x /usr/local/bin/osm

# Check the current Open Service Mesh configuration
kubectl get meshconfig osm-mesh-config -n kube-system -o yaml

# Set the Permissive 
kubectl patch meshconfig osm-mesh-config -n kube-system -p '{"spec":{"traffic":{"enablePermissiveTrafficPolicyMode":true}}}' --type=merge

# set up mesh for namespace redhat
osm namespace add redhat

# Restart deployment
#kubectl rollout restart deployment/redhat-web-app -n redhat