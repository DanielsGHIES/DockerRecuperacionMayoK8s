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
  echo "    metrics-server ya existe, reutilizando instalacion."
else
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
fi

echo "==> Configurando metrics-server para kind..."
METRICS_ARGS="$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{.}{"\n"}{end}' 2>/dev/null || true)"
if echo "$METRICS_ARGS" | grep -q -- "--kubelet-insecure-tls" && \
   echo "$METRICS_ARGS" | grep -q -- "--metric-resolution=5s"; then
  echo "    metrics-server ya esta configurado; no se reinicia."
else
  kubectl patch deployment metrics-server -n kube-system \
    --type='json' \
    -p='[
      {"op":"replace","path":"/spec/template/spec/containers/0/args","value":[
        "--cert-dir=/tmp",
        "--secure-port=10250",
        "--kubelet-preferred-address-types=InternalIP,Hostname,ExternalIP",
        "--kubelet-use-node-status-port",
        "--kubelet-insecure-tls",
        "--metric-resolution=5s"
      ]}
    ]'

  echo "    Esperando a que metrics-server este listo..."
  if ! kubectl rollout status deployment/metrics-server -n kube-system --timeout=180s; then
    echo "    metrics-server aun no esta listo. Estado actual:"
    kubectl get pods -n kube-system -l k8s-app=metrics-server
    echo "    Continuo para aplicar la app; el HPA empezara a medir cuando metrics-server quede disponible."
  fi
fi

echo "==> Configurando HPA sync period..."
if docker exec kind-control-plane grep -q -- "--horizontal-pod-autoscaler-sync-period=10s" \
  /etc/kubernetes/manifests/kube-controller-manager.yaml; then
  echo "    HPA sync period ya estaba configurado."
elif docker exec kind-control-plane grep -q "horizontal-pod-autoscaler-sync-period" \
  /etc/kubernetes/manifests/kube-controller-manager.yaml; then
  docker exec kind-control-plane sed -i \
    's/--horizontal-pod-autoscaler-sync-period=.*/--horizontal-pod-autoscaler-sync-period=10s/' \
    /etc/kubernetes/manifests/kube-controller-manager.yaml
  echo "    Esperando reinicio del controller manager..."
  sleep 10
else
  docker exec kind-control-plane sed -i \
    '/- kube-controller-manager/a\    - --horizontal-pod-autoscaler-sync-period=10s' \
    /etc/kubernetes/manifests/kube-controller-manager.yaml
  echo "    Esperando reinicio del controller manager..."
  sleep 10
fi

echo ""
echo "Cluster listo. Los Deployments de la app se aplican desde start.sh o con kubectl apply -f k8s/."
kubectl get nodes
