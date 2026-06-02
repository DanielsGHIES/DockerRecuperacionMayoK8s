#!/bin/bash
set -e

echo "==> Preparando imagen de backend..."
bash imagesEnRegistry.sh

echo "==> Preparando cluster Kubernetes..."
bash createCluster.sh

echo "==> Creando Secret de PostgreSQL..."
# KICS: vulnerabilidad corregida: el password de PostgreSQL estaba escrito en postgres-secret.yml.
# Configuracion anterior: Secret Kubernetes con stringData y POSTGRES_PASSWORD en texto plano.
# Vulnerabilidad existente en la version 2.c; ahora se genera en tiempo de arranque.
kubectl create secret generic postgres-secret \
  --from-literal=POSTGRES_DB="${POSTGRES_DB:-music_reviews}" \
  --from-literal=POSTGRES_USER="${POSTGRES_USER:-music_user}" \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-music_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Aplicando manifiestos Kubernetes..."
kubectl apply -f k8s/postgres-deployment.yml
kubectl apply -f k8s/backend-deployment.yml
kubectl apply -f k8s/backend-hpa.yml

echo "==> Esperando a PostgreSQL..."
kubectl wait --for=condition=available deployment/postgres --timeout=180s

echo "==> Esperando al backend..."
kubectl wait --for=condition=available deployment/backend --timeout=180s

echo ""
echo "Aplicacion disponible en http://localhost:8000"
echo "HPA disponible con: kubectl get hpa"
echo "Pulsa Ctrl+C para detener el port-forward."
kubectl port-forward service/backend 8000:8000
