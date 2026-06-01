#!/bin/bash
set -e

echo "==> Verificando kind..."
if ! command -v kind >/dev/null 2>&1; then
  echo "    Instalando kind..."
  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind
else
  echo "    kind ya esta instalado."
fi

echo "==> Verificando kubectl..."
if ! command -v kubectl >/dev/null 2>&1; then
  echo "    Instalando kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/kubectl
else
  echo "    kubectl ya esta instalado."
fi

echo "==> Generando kind-config.yaml..."
cat <<EOF > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
    endpoint = ["http://registry:5000"]
EOF

echo "==> Creando cluster kind..."
if kind get clusters 2>/dev/null | grep -q "^kind$"; then
  echo "    El cluster 'kind' ya existe, omitiendo creacion."
else
  kind create cluster --config kind-config.yaml
fi

echo "==> Conectando registry a la red de kind..."
docker network connect kind registry 2>/dev/null || echo "    El registry ya estaba conectado."

echo ""
echo "Cluster listo. Los Deployments de la app se aplican desde start.sh o con kubectl apply -f k8s/."
kubectl get nodes
