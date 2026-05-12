# Music Reviews App - migracion a Kubernetes

Aplicacion web multicontenedor para gestionar discos de musica y comentarios asociados.

Este repositorio esta en el punto intermedio 2.a de la practica: la aplicacion sigue funcionando con Docker Compose, pero ya incluye los cambios hasta el punto 6 del tutorial para preparar la migracion a Kubernetes y crear el cluster local con kind. En este punto todavia no se crean Deployments de la aplicacion.

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

## Como ejecutar la aplicacion Docker

```bash
./start.sh
```

Comando equivalente:

```bash
docker compose up --build
```

La aplicacion se expone en:

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

## Estado del punto 6 del tutorial

- La aplicacion funciona con Docker Compose mediante `./start.sh`.
- Existe un registry local para publicar la imagen del backend.
- Existe un cluster kind preparado para la migracion.
- `metrics-server` queda instalado para el HPA de los siguientes pasos.
- Todavia no existen manifiestos `Deployment`, `Service` ni `HPA` de la aplicacion.

Para comprobar el cluster:

```bash
kubectl get nodes
kubectl get pods -A
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
|-- README.md
|-- start.sh
`-- steps
    `-- paso1.md
```

## Commit intermedio solicitado

El codigo del commit correspondiente al punto 6 del tutorial debe indicarse como el commit que contiene estos archivos y este README. En este punto la app funciona con Docker y el cluster se crea con `createCluster.sh`, pero aun no hay Deployments.
