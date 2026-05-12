# Music Reviews App - migracion a Kubernetes

Aplicacion web multicontenedor para gestionar discos de musica y comentarios asociados.

Este repositorio esta en el punto 2.c de la practica: la aplicacion funciona en Kubernetes con Deployments, Services y HPA configurado. La version aun conserva vulnerabilidades de infraestructura para analizarlas y corregirlas en el apartado posterior con KICS.

## Tecnologias utilizadas

- Flask
- PostgreSQL
- Docker
- Docker Compose
- kind
- kubectl
- metrics-server

## Funcionalidades

- Crear discos con nombre y grupo o artista.
- Listar discos almacenados.
- Editar discos almacenados.
- Anadir comentarios a cada disco.
- Ver comentarios por disco.
- Editar comentarios.
- Eliminar discos y comentarios.

## Como ejecutar la aplicacion en Kubernetes

```bash
./start.sh
```

El script construye y publica la imagen del backend en el registry local, crea o reutiliza el cluster kind, aplica los manifiestos Kubernetes, configura el HPA y abre un `port-forward`.

La aplicacion se expone en:

```text
http://localhost:8000
```

Para detener el `port-forward`, pulsa `Ctrl+C`.

## Como ejecutar la version Docker original

La version Docker Compose se conserva para comprobar el punto 2.a:

```bash
docker compose up --build
```

Tambien se expone en:

```text
http://localhost:8000
```

La base de datos PostgreSQL persiste en el volumen Docker `postgres_data`.

## Preparacion de imagen para Kubernetes

El backend se construye como imagen portable y se sube a un registry local:

```bash
chmod +x imagesEnRegistry.sh
./imagesEnRegistry.sh
```

Imagen generada:

```text
localhost:5000/music-reviews-backend:1.0
```

## Creacion del cluster Kubernetes

El cluster se crea en el archivo `createCluster.sh`. Este script:

- Verifica o instala `kind`.
- Verifica o instala `kubectl`.
- Genera `kind-config.yaml`.
- Crea el cluster `kind`.
- Conecta el registry local a la red de kind.
- Instala `metrics-server`.
- Ajusta `metrics-server` y el periodo de sincronizacion del HPA para pruebas posteriores.

Comandos:

```bash
chmod +x createCluster.sh
./createCluster.sh
```

La parte exacta de la aplicacion donde se crea el cluster esta en `createCluster.sh`, en este bloque:

```bash
echo "==> Creando cluster kind..."
if kind get clusters 2>/dev/null | grep -q "^kind$"; then
  echo "    El cluster 'kind' ya existe, omitiendo creacion."
else
  kind create cluster --config kind-config.yaml
fi
```

## Referencia del punto 6 del tutorial

- En el commit `f931252e227eb6a692d4429e4a8f27dbaf28ac11`, la aplicacion funcionaba con Docker Compose.
- Existe un registry local para publicar la imagen del backend.
- Existe un cluster kind preparado para la migracion mediante `createCluster.sh`.
- `metrics-server` queda instalado para el HPA de los siguientes pasos.
- En ese commit todavia no existian manifiestos `Deployment`, `Service` ni `HPA` de la aplicacion.
- En el estado actual del repositorio ya existen los Deployments del punto 2.b, pero todavia no existe HPA.

Para comprobar el cluster:

```bash
kubectl get nodes
kubectl get pods -A
```

## Deployments configurados

Los Deployment de la aplicacion se definen en estos archivos:

- `k8s/postgres-deployment.yml`: define el `Deployment` de PostgreSQL, el `Service` interno `postgres` y el `PersistentVolumeClaim` `postgres-data`.
- `k8s/backend-deployment.yml`: define el `Deployment` del backend Flask con 2 replicas y el `Service` interno `backend`.

El Secret usado por ambos Deployments esta en:

- `k8s/postgres-secret.yml`: define las credenciales de PostgreSQL usadas por el contenedor de base de datos y por el backend.

## HPA configurado

El HPA se define en:

- `k8s/backend-hpa.yml`: escala el `Deployment` `backend` entre 2 y 8 replicas cuando la CPU media supera el 20%.

El componente que escala es el backend Flask:

- Deployment escalado: `backend`.
- Pods escalados: los pods creados por ese Deployment, con nombres tipo `backend-xxxxxxxxxx-yyyyy`.
- Selector de los pods: etiqueta `app=backend`.
- Service asociado: `backend`, que reparte el trafico entre las replicas disponibles.

El escalado funciona asi:

- El HPA `backend-hpa` observa el consumo medio de CPU del Deployment `backend`.
- Si la CPU media supera el `20%` de la CPU solicitada, Kubernetes aumenta replicas.
- El minimo configurado es `2` replicas y el maximo `8`.
- En subida puede anadir hasta `4` pods cada `10s`.
- En bajada puede retirar hasta `2` pods cada `30s`.

El backend declara `resources.requests` y `resources.limits` en `k8s/backend-deployment.yml`, requisito necesario para que Kubernetes pueda calcular la utilizacion de CPU.

Para comprobar el HPA:

```bash
kubectl get hpa
```

Para comprobar los Deployments:

```bash
kubectl get deployments
kubectl get pods
kubectl get services
```

## Prueba de estres para HPA

Con la aplicacion levantada y el `port-forward` activo en `http://localhost:8000`, se puede generar carga contra el endpoint `/stress`:

```bash
while true; do curl -s "http://localhost:8000/stress?seconds=0.5" >/dev/null; done
```

Para generar mas carga, abrir varias terminales con el mismo comando o usar `hey` si esta instalado:

```bash
hey -z 2m -c 30 "http://localhost:8000/stress?seconds=0.5"
```

Mientras se ejecuta la prueba:

```bash
kubectl get hpa
kubectl get deployments
kubectl get pods
```

El HPA deberia aumentar progresivamente las replicas del `backend` cuando tenga metricas disponibles de `metrics-server`.

## Estructura del proyecto

```text
.
|-- backend
|   |-- app.py
|   |-- Dockerfile
|   |-- requirements.txt
|   |-- static
|   |   `-- styles.css
|   `-- templates
|       `-- index.html
|-- db
|   `-- init.sql
|-- createCluster.sh
|-- docker-compose.yml
|-- imagesEnRegistry.sh
|-- k8s
|   |-- backend-hpa.yml
|   |-- backend-deployment.yml
|   |-- postgres-deployment.yml
|   `-- postgres-secret.yml
|-- README.md
|-- start.sh
`-- steps
    `-- paso1.md
```

## Commit intermedio solicitado

Estos son los commits que se deben indicar en la entrega de la practica hasta este punto:

| Apartado | Commit | Estado |
| --- | --- | --- |
| 2.a | `f931252e227eb6a692d4429e4a8f27dbaf28ac11` | La app funciona con Docker y el cluster se crea con `createCluster.sh`, pero aun no hay Deployments. |
| 2.b | `7ff39b6fd05afcc93daabec4fe09742ed7c7c292` | El cluster y los Deployments estan configurados, pero no existe HPA. |
| 2.c | `aafeefe18dc18c1ac03a8394aedfcb6c39c57f56` | La app funciona en K8s con HPA configurado y conserva vulnerabilidades sin corregir para el analisis KICS. |
