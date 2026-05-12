# Music Reviews App - migracion de Docker a Kubernetes

Aplicacion web multicontenedor para gestionar discos de musica y comentarios asociados.

Este repositorio corresponde a la practica de recuperacion de migracion de una aplicacion Docker a Kubernetes. La aplicacion original se conserva con Docker Compose y la version actual funciona en Kubernetes usando Deployments, Services, Secret, PersistentVolumeClaim y HPA.

## Tecnologias utilizadas

- Flask: backend web de la aplicacion.
- PostgreSQL: base de datos relacional.
- Docker y Docker Compose: version original multicontenedor.
- kind: cluster Kubernetes local.
- kubectl: gestion de recursos Kubernetes.
- registry local: almacenamiento de la imagen Docker del backend.
- metrics-server: metricas necesarias para el escalado automatico HPA.

## Funcionalidades de la aplicacion

La aplicacion permite:

- Crear discos indicando nombre y grupo o artista.
- Listar los discos almacenados.
- Editar discos existentes.
- Eliminar discos.
- Anadir comentarios a cada disco.
- Ver los comentarios asociados a cada disco.
- Editar comentarios.
- Eliminar comentarios.
- Generar carga de CPU desde `/stress` para probar el HPA.

## Flujo completo de la aplicacion

1. El usuario accede a `http://localhost:8000`.
2. El Service `backend` recibe la peticion reenviada por `kubectl port-forward`.
3. Kubernetes reparte la peticion entre las replicas disponibles del Deployment `backend`.
4. El contenedor Flask procesa la peticion.
5. El backend se conecta al Service interno `postgres`.
6. El Service `postgres` envia la conexion al pod del Deployment `postgres`.
7. PostgreSQL guarda los discos y comentarios en el volumen persistente `postgres-data`.
8. Flask renderiza la plantilla HTML y devuelve la pagina al navegador.

En Kubernetes el backend no se conecta directamente a una IP fija de la base de datos. Usa el nombre DNS interno `postgres`, definido por el Service de PostgreSQL. Esto permite que la aplicacion siga funcionando aunque cambie el pod de base de datos.

## Ejecucion principal con start.sh

Para levantar todo el entorno Kubernetes se usa:

```bash
chmod +x start.sh
./start.sh
```

El script `start.sh` automatiza el despliegue completo:

1. Ejecuta `imagesEnRegistry.sh`.
2. Levanta o reutiliza el registry local en `localhost:5000`.
3. Construye la imagen Docker del backend.
4. Sube la imagen `localhost:5000/music-reviews-backend:1.0` al registry local.
5. Ejecuta `createCluster.sh`.
6. Crea o reutiliza el cluster kind.
7. Configura kind para poder descargar imagenes desde el registry local.
8. Instala y configura `metrics-server`.
9. Ajusta el periodo de sincronizacion del HPA a `10s` para facilitar las pruebas.
10. Aplica los manifiestos Kubernetes de Secret, PostgreSQL, backend y HPA.
11. Espera a que los Deployments `postgres` y `backend` esten disponibles.
12. Abre el `port-forward` del Service `backend` al puerto local `8000`.

Cuando termina, la aplicacion queda disponible en:

```text
http://localhost:8000
```

Para detener el acceso local creado por `port-forward`, se pulsa `Ctrl+C`.

## Version Docker Compose original

La version original de la aplicacion se conserva para comprobar el funcionamiento previo a la migracion:

```bash
docker compose up --build
```

Tambien expone la aplicacion en:

```text
http://localhost:8000
```

En Docker Compose hay dos servicios:

- `backend`: aplicacion Flask.
- `db`: base de datos PostgreSQL.

La base de datos persiste en el volumen Docker `postgres_data`.

## Recursos Kubernetes creados

Los manifiestos estan en la carpeta `k8s/`.

| Archivo | Recurso | Funcion |
| --- | --- | --- |
| `k8s/postgres-secret.yml` | Secret `postgres-secret` | Guarda las variables de base de datos usadas por PostgreSQL y Flask. |
| `k8s/postgres-deployment.yml` | PVC `postgres-data` | Reserva almacenamiento persistente para PostgreSQL. |
| `k8s/postgres-deployment.yml` | Deployment `postgres` | Ejecuta PostgreSQL con una replica. |
| `k8s/postgres-deployment.yml` | Service `postgres` | Da un nombre interno estable para acceder a la base de datos. |
| `k8s/backend-deployment.yml` | Deployment `backend` | Ejecuta la aplicacion Flask con 2 replicas iniciales. |
| `k8s/backend-deployment.yml` | Service `backend` | Reparte el trafico entre las replicas del backend. |
| `k8s/backend-hpa.yml` | HPA `backend-hpa` | Escala automaticamente el backend segun el uso de CPU. |

## Condiciones de escalado HPA

El escalado automatico se define en `k8s/backend-hpa.yml`.

El HPA escala el Deployment `backend` con estas condiciones:

- Deployment escalado: `backend`.
- Pods escalados: pods con etiqueta `app=backend`.
- Minimo de replicas: `2`.
- Maximo de replicas: `8`.
- Metrica usada: CPU.
- Condicion de escalado: CPU media superior al `20%` de la CPU solicitada.
- Politica de subida: puede anadir hasta `4` pods cada `10s`.
- Politica de bajada: puede retirar hasta `2` pods cada `30s`.
- Ventana de estabilizacion al subir: `10s`.
- Ventana de estabilizacion al bajar: `30s`.

El backend define recursos en `k8s/backend-deployment.yml`:

```yaml
requests:
  cpu: 20m
  memory: 128Mi
limits:
  cpu: 100m
  memory: 256Mi
```

El `request` de CPU es importante porque el HPA calcula el porcentaje de uso comparando la CPU real con la CPU solicitada. Sin `resources.requests.cpu`, Kubernetes no puede calcular correctamente la utilizacion media de CPU para el autoscaling.

## Prueba de estres para comprobar el HPA

Con la aplicacion levantada mediante `./start.sh`, se puede generar carga contra el endpoint `/stress`:

```bash
while true; do curl -s "http://localhost:8000/stress?seconds=0.5" >/dev/null; done
```

Para generar mas carga se pueden abrir varias terminales con el mismo comando. Si esta instalado `hey`, tambien se puede usar:

```bash
hey -z 2m -c 30 "http://localhost:8000/stress?seconds=0.5"
```

Mientras se genera carga, se comprueba el escalado con:

```bash
kubectl get hpa
kubectl get deployments
kubectl get pods
```

El comportamiento esperado es que el HPA aumente progresivamente las replicas del Deployment `backend` cuando `metrics-server` tenga metricas disponibles y la CPU media supere el umbral configurado.

## Comandos usados

| Comando | Para que sirve |
| --- | --- |
| `chmod +x start.sh` | Da permisos de ejecucion al script principal. |
| `./start.sh` | Ejecuta todo el despliegue Kubernetes de forma automatica. |
| `chmod +x imagesEnRegistry.sh` | Da permisos de ejecucion al script de imagenes. |
| `./imagesEnRegistry.sh` | Crea/reutiliza el registry local, construye la imagen del backend y la sube al registry. |
| `chmod +x createCluster.sh` | Da permisos de ejecucion al script de creacion del cluster. |
| `./createCluster.sh` | Crea/reutiliza el cluster kind y prepara `kubectl`, `metrics-server` y el HPA. |
| `docker compose up --build` | Arranca la version original de Docker Compose y reconstruye las imagenes si hace falta. |
| `docker run -d --name registry --restart=always -p 5000:5000 registry:2` | Crea un registry Docker local en el puerto `5000`. |
| `docker build -t localhost:5000/music-reviews-backend:1.0 ./backend` | Construye la imagen Docker del backend Flask. |
| `docker push localhost:5000/music-reviews-backend:1.0` | Sube la imagen del backend al registry local. |
| `kind create cluster --config kind-config.yaml` | Crea el cluster local de Kubernetes usando kind. |
| `kind export kubeconfig --name kind` | Configura `kubectl` para usar el cluster kind. |
| `docker network connect kind registry` | Conecta el registry local a la red Docker usada por kind. |
| `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml` | Instala `metrics-server`, necesario para que el HPA tenga metricas de CPU. |
| `kubectl patch deployment metrics-server -n kube-system ...` | Ajusta `metrics-server` para funcionar correctamente en kind con TLS inseguro y resolucion de metricas de `5s`. |
| `docker exec kind-control-plane sed -i ... kube-controller-manager.yaml` | Modifica el controller manager para que el HPA sincronice cada `10s`. |
| `kubectl apply -f k8s/postgres-secret.yml` | Crea el Secret con las credenciales de PostgreSQL. |
| `kubectl apply -f k8s/postgres-deployment.yml` | Crea PostgreSQL, su Service y su volumen persistente. |
| `kubectl apply -f k8s/backend-deployment.yml` | Crea el Deployment y el Service del backend Flask. |
| `kubectl apply -f k8s/backend-hpa.yml` | Crea el HPA que escala el backend automaticamente. |
| `kubectl wait --for=condition=available deployment/postgres --timeout=180s` | Espera a que PostgreSQL este disponible. |
| `kubectl wait --for=condition=available deployment/backend --timeout=180s` | Espera a que el backend este disponible. |
| `kubectl port-forward service/backend 8000:8000` | Expone el Service del backend en `localhost:8000`. |
| `kubectl get nodes` | Comprueba los nodos del cluster. |
| `kubectl get pods -A` | Muestra todos los pods de todos los namespaces. |
| `kubectl get deployments` | Comprueba el estado de los Deployments de la aplicacion. |
| `kubectl get services` | Muestra los Services creados. |
| `kubectl get hpa` | Comprueba el estado del escalado automatico. |
| `kubectl describe hpa backend-hpa` | Muestra el detalle del HPA, metricas y eventos de escalado. |
| `kubectl logs deployment/backend` | Consulta los logs del backend Flask. |
| `kubectl logs deployment/postgres` | Consulta los logs de PostgreSQL. |

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
|   |-- backend-hpa.yml
|   |-- postgres-deployment.yml
|   `-- postgres-secret.yml
|-- README.md
|-- start.sh
`-- steps
    `-- paso1.md
```

## Commits de referencia de la practica

| Apartado | Commit | Estado |
| --- | --- | --- |
| 2.a | `f931252e227eb6a692d4429e4a8f27dbaf28ac11` | La app funciona con Docker Compose y el cluster se crea con `createCluster.sh`, pero aun no hay Deployments. |
| 2.b | `7ff39b6fd05afcc93daabec4fe09742ed7c7c292` | El cluster y los Deployments estan configurados, pero aun no existe HPA. |
| 2.c | `aafeefe18dc18c1ac03a8394aedfcb6c39c57f56` | La app funciona en Kubernetes con HPA configurado y conserva vulnerabilidades sin corregir para el analisis KICS. |

## Resumen para la entrega

La aplicacion parte de una arquitectura Docker Compose con un backend Flask y una base de datos PostgreSQL. En la version migrada, ambos componentes se despliegan en Kubernetes: PostgreSQL mantiene los datos en un PVC, el backend se ejecuta con replicas y el acceso se realiza mediante Services. El script `start.sh` automatiza todo el proceso de construccion de imagen, preparacion del cluster, aplicacion de manifiestos y exposicion local de la aplicacion. El HPA permite escalar el backend entre 2 y 8 replicas cuando la CPU media supera el 20%.
