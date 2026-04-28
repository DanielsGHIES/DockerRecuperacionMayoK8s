# Music Reviews App

Aplicacion web multicontenedor para gestionar discos de musica y comentarios asociados.

## Tecnologias utilizadas
- Flask
- PostgreSQL
- Docker
- Docker Compose

## Funcionalidades
- Crear discos con nombre y grupo o artista.
- Listar discos almacenados.
- Editar discos almacenados.
- Anadir comentarios a cada disco.
- Ver comentarios por disco.
- Editar comentarios.
- Eliminar discos y comentarios.

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
|-- docker-compose.yml
|-- start.sh
`-- steps
    `-- paso1.md
```

## Como ejecutar

### Opcion principal
```bash
docker compose up --build
```

### Opcion alternativa
```bash
./start.sh
```

### En GitHub Codespaces
```bash
docker compose up --build
```

La configuracion de Codespaces incluida en el repositorio reenvia el puerto `8000` y prepara el entorno para usar Docker dentro del codespace.

## Acceso
- URL: `http://localhost:8000`
- Tiempo aproximado de arranque: `20-40 segundos`, segun si las imagenes ya existen localmente.

## Notas
- La base de datos persiste en el volumen `postgres_data`.
- La aplicacion espera automaticamente a que PostgreSQL este disponible antes de atender peticiones.
- La solucion esta pensada para poder ejecutarse en un entorno limpio con Docker, incluido GitHub Codespaces.

## Checklist de requisitos
- CRUD basico de tematica libre: cumplido con discos y comentarios, incluyendo crear, leer, actualizar y borrar.
- Base de datos persistente en contenedor independiente: cumplido con PostgreSQL y volumen Docker.
- Ejecucion en GitHub Codespaces nuevo: cubierta con configuracion `.devcontainer`.
- Arranque con un unico comando: `docker compose up --build` o `./start.sh`.
- README con uso, puerto, tiempo de arranque y funcionalidades: incluido.
- Repositorio privado: recuerda anadir al profesor `@amestevez` como colaborador de solo lectura.
