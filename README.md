# Music Reviews App - migracion a Kubernetes

Aplicacion web multicontenedor para gestionar discos de musica y comentarios asociados.

Este repositorio esta en el punto intermedio 2.b de la practica: el cluster Kubernetes ya se crea con kind y la aplicacion ya tiene Deployments y Services configurados, pero todavia no tiene HPA.

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

El script construye y publica la imagen del backend en el registry local, crea o reutiliza el cluster kind, aplica los manifiestos Kubernetes y abre un `port-forward`.

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

En este punto intermedio no existe ningun manifiesto HPA. Para comprobarlo:

```bash
kubectl get hpa
```

Para comprobar los Deployments:

```bash
kubectl get deployments
kubectl get pods
kubectl get services
```

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
|   |-- backend-deployment.yml
|   |-- postgres-deployment.yml
|   `-- postgres-secret.yml
|-- README.md
|-- start.sh
`-- steps
    `-- paso1.md
```

## Commit intermedio solicitado

- Punto 2.a: `f931252e227eb6a692d4429e4a8f27dbaf28ac11`. En ese commit la app funciona con Docker y el cluster se crea con `createCluster.sh`, pero aun no hay Deployments.
- Punto 2.b: el commit de este estado contiene los manifiestos de Deployment y Service, pero aun no contiene HPA.
