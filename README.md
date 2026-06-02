# Music Reviews App - Docker a Kubernetes

Aplicacion web Flask + PostgreSQL con CRUD de discos y comentarios.

Este repositorio corresponde a la practica de recuperacion: migracion de una app Docker multicontenedor a Kubernetes con HPA y posterior analisis de infraestructura. El commit indicado como 2.c conserva las vulnerabilidades sin corregir; el estado actual inicia el apartado 3 con correcciones documentadas.

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

- `k8s/postgres-deployment.yml`
- `k8s/backend-deployment.yml`
- `k8s/backend-hpa.yml`

El Secret de PostgreSQL se crea durante el arranque desde `start.sh` para no guardar la password en un manifiesto YAML.

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

## 3. Analisis con KICS

Informe HTML a generar con KICS:

- `kics-results/kics-report.html`

Comando usado para generar el informe:

```powershell
docker run --rm -v "${PWD}:/path" checkmarx/kics:latest scan -p /path/k8s -o /path/kics-results --report-formats html,json --output-name kics-report
```

En PowerShell se usa `${PWD}` porque `"$PWD:/path"` se interpreta como una variable no valida por el caracter `:`.

Archivos con vulnerabilidades corregidas:

- `k8s/backend-deployment.yml`
- `k8s/postgres-deployment.yml`
- `start.sh`

Vulnerabilidad corregida:

- Contenedores y pods sin contexto de seguridad explicito.
- Configuracion anterior: los manifiestos no declaraban `securityContext`, `seccompProfile`, `allowPrivilegeEscalation` ni eliminaban Linux capabilities.
- Configuracion actual: se anade `seccompProfile: RuntimeDefault`, ejecucion sin root con usuario numerico cuando corresponde, `allowPrivilegeEscalation: false` y `capabilities.drop: ALL`.
- La vulnerabilidad era existente en la version 2.c, no introducida a proposito.
- Secret de PostgreSQL con password escrito en YAML.
- Configuracion anterior: `k8s/postgres-secret.yml` contenia `POSTGRES_PASSWORD` en `stringData`.
- Configuracion actual: el Secret se genera en `start.sh` durante el arranque con `kubectl create secret ... --dry-run=client -o yaml | kubectl apply -f -`.
- Volumen persistente de PostgreSQL montado en ruta de sistema.
- Configuracion anterior: el PVC se montaba en `/var/lib/postgresql/data`.
- Configuracion actual: el PVC se monta en `/postgres-data` y PostgreSQL usa `PGDATA=/postgres-data/pgdata`.
