#!/bin/bash
set -e

echo "==> Preparando imagen de backend..."
bash imagesEnRegistry.sh

echo "==> Preparando cluster Kubernetes..."
bash createCluster.sh

echo "==> Aplicando manifiestos Kubernetes..."
kubectl apply -f k8s/postgres-secret.yml
kubectl apply -f k8s/postgres-deployment.yml
kubectl apply -f k8s/backend-deployment.yml

echo "==> Esperando a PostgreSQL..."
kubectl wait --for=condition=available deployment/postgres --timeout=180s

echo "==> Esperando al backend..."
kubectl wait --for=condition=available deployment/backend --timeout=180s

echo ""
echo "Aplicacion disponible en http://localhost:8000"
echo "Pulsa Ctrl+C para detener el port-forward."
kubectl port-forward service/backend 8000:8000
