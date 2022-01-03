#!/bin/bash
echo "Deploy nginx controller"

#Link: https://docs.microsoft.com/en-us/learn/modules/aks-workshop/07-deploy-ingress

kubectl create namespace nginx-ingress

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install nginx-ingress ingress-nginx/ingress-nginx \
    --namespace nginx-ingress \
    --set controller.replicaCount=2 \
    --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux

