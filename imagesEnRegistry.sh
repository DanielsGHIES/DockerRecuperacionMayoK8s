#!/bin/bash
set -e

REGISTRY_NAME="registry"
REGISTRY_PORT="5000"
IMAGE_NAME="music-reviews-backend"
IMAGE_TAG="1.0"
IMAGE="localhost:${REGISTRY_PORT}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "==> Levantando registry local..."
if docker ps -a --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
  docker start "${REGISTRY_NAME}" >/dev/null 2>&1 || true
  echo "    Registry local reutilizado."
else
  docker run -d --name "${REGISTRY_NAME}" --restart=always -p "${REGISTRY_PORT}:5000" registry:2
  echo "    Registry local creado en localhost:${REGISTRY_PORT}."
fi

echo "==> Construyendo imagen backend..."
docker build -t "${IMAGE}" ./backend

echo "==> Subiendo imagen al registry local..."
docker push "${IMAGE}"

echo ""
echo "Listo. Imagen disponible en ${IMAGE}."
echo "La aplicacion Docker sigue arrancando con ./start.sh."
