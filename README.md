# Music Reviews App - Docker a Kubernetes

Aplicacion web Flask + PostgreSQL con CRUD de discos y comentarios.

Este repositorio corresponde a la practica de recuperacion: migracion de una app Docker multicontenedor a Kubernetes con HPA. El estado actual es la version 2.c/3.c funcional en K8s con HPA configurado. La app conserva vulnerabilidades sin corregir.

## 1. Aplicacion Docker

Arranque:

```bash
docker compose up --build
```

URL:

```text
http://localhost:8000
```

Comprobacion minima:

- Backend Flask.
- Base de datos PostgreSQL persistente.
- CRUD de discos y comentarios.
- Archivo principal: `docker-compose.yml`.

## 2. Migracion a Kubernetes

Arranque principal:

```bash
chmod +x start.sh
./start.sh
```

El script construye la imagen, prepara el cluster, instala/configura `metrics-server`, aplica los manifiestos y abre el acceso local.

Manifiestos principales:

- `k8s/postgres-secret.yml`
- `k8s/postgres-deployment.yml`
- `k8s/backend-deployment.yml`
- `k8s/backend-hpa.yml`

Comprobacion:

```bash
kubectl get deployments
kubectl get pods
kubectl get services
kubectl get hpa
kubectl top pods
```

## HPA y prueba de estres

Condiciones de escalado:

- HPA: `backend-hpa`.
- Deployment escalado: `backend`.
- Minimo: 2 replicas.
- Maximo: 8 replicas.
- Metrica: CPU media.
- Umbral: 20%.

Prueba en GitHub Codespaces o Bash, usando tres terminales:

```bash
kubectl port-forward service/backend 8001:8000
```

```bash
while true; do curl -s "http://localhost:8001/stress?seconds=0.5" >/dev/null; done
```

```bash
watch -n 2 'kubectl get hpa; kubectl top pods'
```

Resultado esperado: el HPA muestra un porcentaje de CPU, supera el 20% durante la carga y aumenta las replicas del backend.

## Commits solicitados

| Apartado | Commit | Que demuestra |
| --- | --- | --- |
| 2.a | `f931252e227eb6a692d4429e4a8f27dbaf28ac11` | App Docker funcional y creacion del cluster, sin Deployments. |
| 2.b | `6c07778fe90853d6f656d15b55011ec892538823` | Cluster, Deployments y Services configurados, sin HPA. |
| 2.c / 3.c | `a1b5d98aa7894584f7ab3c333e9397a4bd3d2116` | App funcional en K8s con HPA configurado, sin corregir vulnerabilidades. |

Creacion del cluster solicitada en 2.a:

- Archivo: `createCluster.sh`.
- Bloque: seccion `echo "==> Creando cluster kind..."`, donde se ejecuta `kind create cluster --config kind-config.yaml` si el cluster no existe.

Archivos de Deployments solicitados en 2.b:

- `k8s/postgres-deployment.yml`
- `k8s/backend-deployment.yml`

## Comandos utilizados

```bash
docker compose up --build
chmod +x start.sh
./start.sh
kubectl get deployments
kubectl get hpa
watch -n 2 'kubectl get hpa; kubectl top pods'
```

Tiempo estimado de arranque completo con `./start.sh`: unos 5 minutos.
