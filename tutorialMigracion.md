# De Docker Compose a Kubernetes — Guía paso a paso

> **Aplicación de ejemplo:** `counter-app` — un contador de visitas y clics con tres servicios: Nginx (proxy), Flask/Gunicorn (web) y Redis (datos).

---

## Leyenda

A lo largo de esta guía se distinguen dos tipos de pasos:

- 🟢 **Paso común** — aplica a cualquier aplicación que migre de Docker Compose a Kubernetes.
- 🟡 **Paso específico** — aparece por las tecnologías concretas de esta aplicación.

---

## Índice

1. [Contexto: la aplicación de ejemplo](#1-contexto-la-aplicaci%C3%B3n-de-ejemplo)
2. [Mapa conceptual: Docker vs Kubernetes](#2-mapa-conceptual-docker-vs-kubernetes)
3. [Analizar la aplicación Docker](#3--analizar-la-aplicaci%C3%B3n-docker)
4. [Hacer las imágenes portables](#4--hacer-las-im%C3%A1genes-portables)
5. [Publicar las imágenes en un registro](#5--publicar-las-im%C3%A1genes-en-un-registro)
6. [Crear el clúster Kubernetes](#6--crear-el-cl%C3%BAster-kubernetes)
7. [Escribir los manifiestos: Deployments y Services](#7--escribir-los-manifiestos-deployments-y-services)
8. [Gestionar secretos con kubectl secret](#8--gestionar-secretos-con-kubectl-secret)
9. [Ajustar puertos no privilegiados](#9--ajustar-puertos-no-privilegiados)
10. [Añadir límites de recursos](#10--a%C3%B1adir-l%C3%ADmites-de-recursos)
11. [Aplicar los manifiestos](#11--aplicar-los-manifiestos)
12. [Crear script de arranque](#12--crear-script-de-arranque)
13. [Solución de errores de sesión](#13--soluci%C3%B3n-de-errores-de-sesi%C3%B3n)
14. [Verificar funcionamiento del escalado](#14--verificar-funcionamiento-del-escalado)

---

## 1. Contexto: la aplicación de ejemplo

La aplicación `counter-app` está formada por tres servicios que se comunican entre sí:

```
Usuario → Nginx (puerto 8080) → Flask/Gunicorn (puerto 5000) → Redis (puerto 6379)
```

| Servicio | Tecnología     | Imagen                | Tipo de imagen |
| -------- | -------------- | --------------------- | -------------- |
| `redis`  | Redis 7        | `redis:7-alpine`      | Pública (hub)  |
| `web`    | Python + Flask | Build local `./web`   | Personalizada  |
| `nginx`  | Nginx          | Build local `./nginx` | Personalizada  |

Las tecnologías usadas condicionarán algunos pasos específicos:

- **Flask** usa una `secret_key` para firmar sesiones de usuario.
- **Nginx** no puede escuchar en el puerto 80 si corre sin root.
- **Redis** necesita un volumen para persistir sus datos.

---

## 2. Mapa conceptual: Docker vs Kubernetes

Antes de migrar, es fundamental entender que cada concepto de Docker Compose tiene su equivalente en Kubernetes, aunque con mayor granularidad:

| Concepto Docker Compose   | Equivalente Kubernetes                 | Diferencia clave                                                  |
| ------------------------- | -------------------------------------- | ----------------------------------------------------------------- |
| `service` (contenedor)    | `Deployment` + `Pod`                   | K8s separa «qué ejecutar» (Deployment) de «la instancia» (Pod)    |
| `networks` (DNS interno)  | `Service` (ClusterIP)                  | K8s necesita un objeto Service explícito para exponer DNS interno |
| `ports` (host:container)  | `Service` NodePort / LoadBalancer      | El acceso externo se gestiona en el Service, no en el Pod         |
| `volumes` (named)         | `PersistentVolumeClaim`                | K8s abstrae el almacenamiento del nodo físico                     |
| `environment` / `.env`    | `env` en spec / `ConfigMap` / `Secret` | Los datos sensibles van en Secret; el resto en env o ConfigMap    |
| `depends_on`              | `readinessProbe` / `initContainers`    | K8s no tiene `depends_on`; usa sondas de salud                    |
| `build` (imagen local)    | Imagen en registro externo             | K8s no construye imágenes; las descarga siempre de un registro    |
| `scale` (`--scale web=3`) | `replicas`                             | K8s permite definir cuantas replicas debe mantener el Deployment  |

---

## 3. 🟢 Analizar la aplicación Docker

**El punto de partida es el `docker-compose.yml`.** Por cada servicio hay que fijarse en los siguientes elementos:

- ¿Qué imagen usa?
- ¿Qué puertos expone?
- ¿Qué variables de entorno necesita?
- ¿Qué volúmenes monta?

```yaml
# docker-compose.yml (counter-app, versión Docker)

services:
  redis:
    image: redis:7-alpine        # ← imagen pública, no hace build
    volumes:
      - redis_data:/data         # ← volumen nombrado → PVC en K8s
    networks: [counter-network]

  web:
    build: ./web                 # ← build local → necesita registro
    environment:
      - REDIS_HOST=redis         # ← DNS interno → Service en K8s
      - REDIS_PORT=6379
    depends_on: [redis]          # ← no existe en K8s

  nginx:
    build: ./nginx               # ← build local → necesita registro
    ports: ["8080:80"]           # ← puerto host → Service NodePort
    depends_on: [web]
```

**Resultado de la revisión:**

- 3 servicios (Docker) → 3 Deployments + 3 Services (k8s).
- 2 build local → deben subirse a un registro.
- 1 volumen nombrado → 1 `PersistentVolumeClaim` (PVC).
- 2 variables de entorno → fijar `env` literal en el manifiesto.
- 1 `depends_on` → sustituir por reintentos de conexión en la aplicación.
- 1 puerto expuesto al host → Service de tipo NodePort.

> **Nota:** La app Docker también tiene un secreto implícito: la `secret_key` de Flask se generaba con `os.urandom(24)`, cambiando en cada reinicio. Esto romperá las sesiones cuando haya múltiples pods. Se aborda en el [Paso 8](#8--gestionar-secretos-con-kubectl-secret).

---

## 4. 🟢 Hacer que las imágenes corran sin privilegios

Kubernetes impone políticas de seguridad que pueden hacer fallar imágenes que en Docker funcionaban. La regla de oro es: **el contenedor no debe correr como root**. Los directorios que el proceso necesita escribir deben pertenecer al usuario del proceso. A partir de aquí hacemos los primeros cambios en nuestra aplicación.

### Cambio en `web/Dockerfile`

Se añade un usuario sin privilegios al final, antes del `CMD`:

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
COPY templates/ ./templates/
ENV PYTHONPATH=/app
ENV FLASK_APP=app.py

# ✅ Crear usuario sin privilegios y hacerle propietario de /app
RUN addgroup --system appgroup && \
    adduser --system --ingroup appgroup appuser && \
    chown -R appuser:appgroup /app

# ✅ Cambiar al usuario sin privilegios antes de lanzar el proceso
USER appuser

EXPOSE 5000
CMD ["python3", "-m", "gunicorn", "--bind", "0.0.0.0:5000",
     "--workers", "1", "--timeout", "60", "app:app"]
```

### Cambio en `nginx/Dockerfile`

Nginx necesita permisos sobre sus directorios de caché y log:

```dockerfile
FROM nginx:alpine
RUN rm /etc/nginx/conf.d/default.conf
COPY default.conf /etc/nginx/conf.d/default.conf

# ✅ Dar permisos al usuario 'nginx' sólo sobre lo que necesita
RUN chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    chown -R nginx:nginx /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && \
    chown nginx:nginx /var/run/nginx.pid

USER nginx
```

> **Nota sobre Redis:** La imagen oficial `redis:7-alpine` ya corre como usuario `redis` sin privilegios. No requiere cambios en el Dockerfile. Esto es un aspecto específico de esta aplicación: las imágenes públicas bien mantenidas suelen venir ya preparadas.

---

## 5. 🟢 Publicar las imágenes en un registro

A diferencia de Docker Compose, Kubernetes **no puede construir imágenes localmente**. Cada nodo del clúster debe descargarlas desde un registro de contenedores. En este entorno de laboratorio del proyecto usamos un registry local con `kind`.

> **En producción real** se usaría Docker Hub, GitHub Container Registry, AWS ECR, Google Artifact Registry, etc. La idea general sería hacer `docker build → docker tag → docker push`.

Podemos agrupar los comandos necesarios en este script `imagesEnRegistry.sh`:

```bash
#!/bin/bash
set -e  # detener si cualquier comando falla

echo "==> Levantando registry local..."
if docker ps -a --format '{{.Names}}' | grep -q "^registry$"; then
  docker start registry 2>/dev/null || true
  echo "    El registry ya existía, arrancado."
else
  docker run -d --name registry --restart=always -p 5000:5000 registry:2
  echo "    Registry creado."
fi

echo "==> Construyendo imágenes..."
docker build -t localhost:5000/counter-web:1.0   ./web
docker build -t localhost:5000/counter-nginx:1.0 ./nginx

echo "==> Subiendo imágenes al registry..."
docker push localhost:5000/counter-web:1.0
docker push localhost:5000/counter-nginx:1.0

echo ""
echo "✅ Listo. Imágenes disponibles en el registry local."
echo "   Puedes seguir ejecutando 'docker compose up' con normalidad."
```

Una vez creado el script lo ejecutamos con:

```bash
chmod +x imagesEnRegistry.sh
./imagesEnRegistry.sh
```

---

## 6. 🟡 Crear el clúster Kubernetes

Todas las aplicaciones necesitarán un clúster, pero su contenido es específico del entorno. El proyecto usa **kind** (Kubernetes in Docker) para desarrollo local. En un entorno real normalmente se usaría un clúster remoto (Amazon EKS, Microsoft AKS, etc.).

Para generar el clúster debemos:

- Instalar kind si no está instalado en la máquina.
- Instalar kubectl si no está instalado en la máquina (para ejecutar comandos propios de k8s).
- Generar archivo kind-config.yaml
- Crear el clúster
- Conectar el registry a la red de kind

Por comodidad, lo crearemos todo con el siguiente script `createCluster.sh`:

```bash
#!/bin/bash
set -e

# ── 1. Instalar kind si no está ────────────────────────────────
echo "==> Verificando kind..."
if ! command -v kind &>/dev/null; then
  echo "    Instalando kind..."
  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind
  echo "    kind instalado."
else
  echo "    kind ya está instalado."
fi

# ── 2. Instalar kubectl si no está ─────────────────────────────
echo "==> Verificando kubectl..."
if ! command -v kubectl &>/dev/null; then
  echo "    Instalando kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/kubectl
  echo "    kubectl instalado."
else
  echo "    kubectl ya está instalado."
fi

# ── 3. Generar kind-config.yaml ─────────────────────────────────
echo "==> Generando kind-config.yaml..."
cat <<EOF > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
    endpoint = ["http://registry:5000"]
EOF

# ── 4. Crear el clúster ─────────────────────────────────────────
echo "==> Creando clúster kind..."
if kind get clusters 2>/dev/null | grep -q "^kind$"; then
  echo "    El clúster 'kind' ya existe, omitiendo creación."
else
  kind create cluster --config kind-config.yaml
fi

# ── 5. Conectar el registry a la red de kind ────────────────────
echo "==> Conectando registry a la red de kind..."
docker network connect kind registry 2>/dev/null || echo "    Ya estaba conectado."

echo ""
echo "✅ Clúster listo."
kubectl get nodes
```

Una vez creado el script apagamos los puertos que estén activos y lo ejecutamos con:

```bash
chmod +x createCluster.sh
./createCluster.sh
```

---

## 7. 🟢 Escribir los manifiestos: Deployments y Services

Cada servicio de Docker Compose se convierte en un fichero YAML con (mínimo) dos objetos: un **Deployment** y un **Service**. Todos los manifiestos se colocan en el directorio `k8s/`.

> **Nota:** Los manifiestos que se muestran a continuación ya incluyen referencias a recursos que se crean en pasos posteriores: el `flask-secret` (paso 8) y el puerto `8080` de Nginx (paso 9). Es normal que al aplicarlos en el paso 11 algunos de estos recursos ya estén creados de antemano. Si sigues el tutorial en orden y aplicas los manifiestos al llegar al paso 11, todos los recursos necesarios ya existirán.

### 7.1 Redis — imagen pública, servicio interno

```yaml
# k8s/redis-deployment.yml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
spec:
  replicas: 1           # Redis NO escala horizontalmente
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels: {app: redis}
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
        volumeMounts:
        - name: redis-data
          mountPath: /data
      volumes:
      - name: redis-data
        emptyDir: {}    # En lab está bien; producción → PVC
---
apiVersion: v1
kind: Service
metadata:
  name: redis           # mismo nombre que en docker-compose; el DNS no cambia
spec:
  selector: {app: redis}
  ports:
  - port: 6379
    targetPort: 6379
  # Sin 'type' → ClusterIP por defecto (solo acceso interno)
```

> **`emptyDir` vs `PVC`:** `emptyDir` es un volumen temporal que desaparece cuando el pod se reinicia. Es suficiente para un laboratorio, pero en producción se debe usar un `PersistentVolumeClaim` para no perder los datos de Redis entre reinicios.

### 7.2 Web — imagen custom, múltiples réplicas, secreto

```yaml
# k8s/web-deployment.yml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 2     # Podemos escalar; Redis gestiona el estado compartido
  selector:
    matchLabels: {app: web}
  template:
    metadata:
      labels: {app: web}
    spec:
      containers:
      - name: web
        image: localhost:5000/counter-web:1.0  # registro local de kind
        imagePullPolicy: Always
        ports:
        - containerPort: 5000
        env:
        - name: REDIS_HOST
          value: "redis"         # DNS del Service redis
        - name: REDIS_PORT
          value: "6379"
        - name: SECRET_KEY       # ← secreto Flask (ver Paso 8)
          valueFrom:
            secretKeyRef:
              name: flask-secret
              key: secret-key
        resources:               # define solicitudes y limites del contenedor
          requests:
            memory: "64Mi"
            cpu: "10m"
          limits:
            memory: "128Mi"
            cpu: "50m"
---
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector: {app: web}
  ports:
  - port: 5000
    targetPort: 5000
  # ClusterIP por defecto → solo accesible internamente por nginx
```

### 7.3 Nginx — servicio de entrada, tipo NodePort

```yaml
# k8s/nginx-deployment.yml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels: {app: nginx}
  template:
    metadata:
      labels: {app: nginx}
    spec:
      containers:
      - name: nginx
        image: localhost:5000/counter-nginx:1.0
        imagePullPolicy: Always
        ports:
        - containerPort: 8080    # ← 8080, no 80 (ver Paso 9)
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  type: NodePort               # ← expone el servicio fuera del clúster
  selector: {app: nginx}
  ports:
  - port: 80                   # puerto del Service (interno)
    targetPort: 8080           # ← apunta al puerto 8080 del contenedor
    nodePort: 30080            # puerto accesible desde fuera del clúster
```

---

## 8. 🟡 Gestionar secretos con kubectl secret

En la versión Docker, la app usaba `app.secret_key = os.urandom(24)`: cada vez que arrancaba el contenedor se generaba una clave aleatoria nueva. Con **un solo contenedor** no era problema, pero **con múltiples réplicas en Kubernetes cada pod tendría una clave diferente**, lo que haría que las sesiones de usuario no se validasen correctamente entre pods.

La solución tiene dos partes:

### Parte A — Cambio en el código (`web/app.py`)

```python
# ANTES (Docker) — clave aleatoria en cada arranque:
app.secret_key = os.urandom(24)

# DESPUÉS (K8s) — clave fija inyectada como variable de entorno:
app.secret_key = os.environ.get('SECRET_KEY', 'fallback-local')
```

### Parte B — Crear el Secret en el clúster

```bash
kubectl create secret generic flask-secret \
  --from-literal=secret-key='clave-super-secreta' \
  --dry-run=client -o yaml | kubectl apply -f -

# si el secret ya existe lo actualiza; si no, lo crea.
# Tener esta clave "hardcodeada" será una de las vulnerabilidades que nos descubrirá KICS.
```

> ⚠️ **Nunca guardes la clave en el repositorio.** En producción la clave debería generarse con `openssl rand -base64 32` y almacenarse en un gestor de secretos externo (HashiCorp Vault, AWS Secrets Manager, etc.).

---

## 9. 🟡 Ajustar puertos no privilegiados

En Linux, los puertos por debajo de 1024 son «puertos privilegiados» y solo los puede abrir el usuario root (o un proceso con la capability `CAP_NET_BIND_SERVICE`). Como ahora el contenedor corre con el usuario `nginx`, **intentar escuchar en el puerto 80 daría un error de permisos**.

La solución es cambiar el puerto de escucha en la configuración de Nginx:

```nginx
# nginx/default.conf

server {
    listen 8080;  # ← Antes era 80; ahora es un puerto no privilegiado

    location / {
        proxy_pass http://web:5000;   # DNS interno: Service "web"
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Este cambio obliga a ajustar el `targetPort` del Service de Nginx para que apunte a `8080` en lugar de `80` (ya aplicado en el manifiesto del Paso 7.3).

> **Patrón general:** cualquier servicio que en Docker escuchaba en un puerto < 1024 dentro del contenedor (Apache en 80, HTTPS en 443, etc.) necesitará este mismo ajuste si el contenedor pasa a ejecutarse sin privilegios root.

---

## 10. 🟢 Añadir límites de recursos

En Kubernetes conviene declarar solicitudes y limites de recursos para que el scheduler pueda reservar capacidad y para evitar que un contenedor consuma recursos sin control.

El Deployment puede declarar `resources.requests` y `resources.limits` dentro del contenedor:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "64Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
```

Estos valores se ajustan segun el consumo real de la aplicacion y la capacidad disponible del cluster.

---

## 11. 🟢 Aplicar los manifiestos

```bash
# 1. Aplicar todos los manifiestos del directorio k8s/
kubectl apply -f k8s/
# deployment.apps/redis created
# service/redis created
# deployment.apps/web created
# service/web created
# deployment.apps/nginx created
# service/nginx created

# 2. Esperar a que todos los pods estén Running
kubectl wait --for=condition=ready pod --all --timeout=120s

# 3. Ver el estado general
kubectl get pods,svc

# 4. Exponer localmente (en entornos sin LoadBalancer externo)
kubectl port-forward service/nginx 8080:80
# Acceder en http://localhost:8080
```

---

## 12. 🟢 Crear script de arranque

Una vez que todos los pasos anteriores funcionan de forma manual, conviene automatizarlos en un único script `start.sh` que levante la aplicación desde cero con un solo comando. El script llama a los scripts ya creados en los pasos anteriores y añade la creación del secret y la aplicación de los manifiestos:

```bash
#!/bin/bash
set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       counter-app — arranque en K8s      ║"
echo "╚══════════════════════════════════════════╝"

# ── 1. Imágenes en el registry ──────────────────────────────────
echo ""
echo "▶ [1/4] Construyendo y pusheando imágenes..."
bash imagesEnRegistry.sh

# ── 2. Clúster Kubernetes ───────────────────────────────────────
echo ""
echo "▶ [2/4] Creando clúster kind..."
bash createCluster.sh

# ── 3. Secret de Flask y manifiestos ───────────────────────────
echo ""
echo "▶ [3/4] Aplicando secret y manifiestos..."
kubectl create secret generic flask-secret \
  --from-literal=secret-key='clave-super-secreta' \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f k8s/

# ── 4. Esperar pods y arrancar ──────────────────────────────────
echo ""
echo "▶ [4/4] Esperando a que los pods estén listos..."
kubectl wait --for=condition=ready pod --all --timeout=120s

echo ""
kubectl get pods

echo ""
echo "✅ ¡Todo listo! Abriendo en http://localhost:8080"
echo "   (Ctrl+C para detener el port-forward)"
echo ""
kubectl port-forward service/nginx 8080:80
```

Una vez creado el script lo ejecutamos con:

```bash
chmod +x start.sh
./start.sh
```

---

## 13. 🟡 Solución de errores de sesión

En este punto la aplicación arranca, pero nos encontraremos un problema dentro de la aplicación debido a las diferencias entre Docker y K8s.

Las sesiones de Flask se guardan en una cookie firmada con la `SECRET_KEY`, pero el contador de sesión `session['session_clicks']` se guarda **en la cookie del navegador**, y cada vez que se hace una petición, Nginx la manda a uno de los dos pods de forma aleatoria (round-robin). Como cada pod tiene su propia memoria, el contador de sesión que tiene pod A no lo tiene pod B.

La solución está en modificar el `web/app.py`, sacar `session_clicks` de la cookie y guardarlo en Redis, igual que ya se hace con `global_clicks`:

```python
# web/app.py
from flask import Flask, render_template, request, jsonify, session
import redis
import os

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'fallback-local')

redis_client = redis.Redis(
    host=os.environ.get('REDIS_HOST', 'redis'),
    port=int(os.environ.get('REDIS_PORT', 6379)),
    decode_responses=True
)

@app.route('/')
def index():
    visits = redis_client.incr('global_visits')

    # Obtener o crear un ID de sesión persistente
    if 'session_id' not in session:
        import uuid
        session['session_id'] = str(uuid.uuid4())

    session_id = session['session_id']
    session_clicks = int(redis_client.get(f'session_clicks:{session_id}') or 0)
    global_clicks = int(redis_client.get('global_clicks') or 0)

    return render_template('index.html',
                         visits=visits,
                         session_clicks=session_clicks,
                         global_clicks=global_clicks)

@app.route('/click', methods=['POST'])
def click():
    if 'session_id' not in session:
        import uuid
        session['session_id'] = str(uuid.uuid4())

    session_id = session['session_id']

    # Incrementar clicks de sesión en Redis (no en la cookie)
    session_clicks = redis_client.incr(f'session_clicks:{session_id}')
    global_clicks = redis_client.incr('global_clicks')

    return jsonify({
        'session_clicks': session_clicks,
        'global_clicks': global_clicks
    })

@app.route('/submit_text', methods=['POST'])
def submit_text():
    text = request.json.get('text', '').strip()
    if text:
        redis_client.lpush('submitted_texts', text)
        return jsonify({'success': True, 'message': 'Texto guardado'})
    return jsonify({'success': False, 'message': 'Texto vacío'}), 400

@app.route('/get_texts', methods=['GET'])
def get_texts():
    texts = redis_client.lrange('submitted_texts', 0, -1)
    return jsonify({'texts': texts})

@app.route('/reset_session', methods=['POST'])
def reset_session():
    if 'session_id' in session:
        # Limpiar también el contador en Redis
        redis_client.delete(f'session_clicks:{session["session_id"]}')
    session.clear()
    return jsonify({'success': True})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

El cambio clave es que `session_clicks` ya no vive en la cookie del navegador sino en Redis bajo la clave `session_clicks:<uuid>`.

Una vez hecho este cambio, hay que actualizar la imagen que hay en el registry y forzar que los pods cojan la nueva imagen:

```bash
kubectl rollout restart deployment/web
```

Verificamos que los pods nuevos están corriendo:

```bash
kubectl get pods -w
```

Esperamos a que los dos pods `web` muestren `Running` con `RESTARTS` a 0, y entonces probamos la aplicación.

---

## 14. 🟢 Verificar funcionamiento

Para comprobar que la aplicacion responde desde Kubernetes se puede observar el estado de los pods y generar peticiones al Service.

**Terminal 1 — monitorizacion en tiempo real:**

```bash
watch -n 2 'kubectl get pods,svc'
```

**Terminal 2 — generar peticiones:**

```bash
kubectl run stress --image=busybox --restart=Never -it --rm \
  -- sh -c "while true; do wget -q -O- http://web:5000/; done"
```

Este pod temporal se lanza dentro del cluster y envia peticiones al Service `web` directamente, repartiendo el trafico entre las replicas activas.

---

**Conclusión:** Los pasos marcados como 🟢 **comunes** forman un *checklist* universal que aplica a casi cualquier aplicación que migre de Docker Compose a Kubernetes: inventario, imágenes en registro, manifiestos Deployment+Service, usuarios no-root y límites de recursos. Los pasos 🟡 **específicos** aparecen por las tecnologías concretas usadas en esta aplicación de ejemplo (Flask, Nginx sin root, etc). Cada tecnología tendrá sus particularidades a tener en cuenta.
