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
kind export kubeconfig --name kind

echo "==> Conectando registry a la red de kind..."
docker network connect kind registry 2>/dev/null || echo "    El registry ya estaba conectado."

echo "==> Instalando metrics-server..."
if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
  echo "    metrics-server ya existe, omitiendo instalacion."
else
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

  echo "==> Configurando metrics-server para kind..."
  kubectl patch deployment metrics-server -n kube-system \
    --type='json' \
    -p='[
      {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
      {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--metric-resolution=5s"}
    ]'

  echo "    Esperando a que metrics-server este listo..."
  kubectl rollout status deployment/metrics-server -n kube-system --timeout=90s
fi

echo "==> Configurando HPA sync period..."
if docker exec kind-control-plane grep -q "horizontal-pod-autoscaler-sync-period" \
  /etc/kubernetes/manifests/kube-controller-manager.yaml; then
  docker exec kind-control-plane sed -i \
    's/--horizontal-pod-autoscaler-sync-period=.*/--horizontal-pod-autoscaler-sync-period=10s/' \
    /etc/kubernetes/manifests/kube-controller-manager.yaml
else
  docker exec kind-control-plane sed -i \
    '/- kube-controller-manager/a\    - --horizontal-pod-autoscaler-sync-period=10s' \
    /etc/kubernetes/manifests/kube-controller-manager.yaml
fi

echo "    Esperando reinicio del controller manager..."
sleep 15

echo ""
echo "Cluster listo. Los Deployments de la app se aplican desde start.sh o con kubectl apply -f k8s/."
kubectl get nodes
