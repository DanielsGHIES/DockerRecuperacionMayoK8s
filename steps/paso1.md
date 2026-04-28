# Paso 1: Aplicacion multicontenedor con Docker

## Objetivo
Construir una aplicacion web multicontenedor para gestionar discos de musica y sus comentarios, cumpliendo los requisitos base de la practica con Docker.

## Solucion implementada
La entrega de este paso queda resuelta con:

- Un contenedor `backend` con Flask.
- Un contenedor `db` con PostgreSQL.
- Persistencia mediante volumen Docker.
- Arranque con un unico comando: `docker compose up --build`.
- Interfaz web sencilla para crear discos, listar discos, anadir comentarios y borrar elementos.
- Interfaz web sencilla para crear, leer, actualizar y borrar discos y comentarios.

## Funcionalidades cubiertas

### Discos
- Crear un disco indicando `nombre` y `grupo`.
- Ver el listado de discos guardados.
- Editar un disco.
- Eliminar un disco.

### Comentarios
- Anadir comentarios a cada disco.
- Ver los comentarios asociados a cada disco.
- Editar comentarios.
- Eliminar comentarios.

## Arquitectura

### Servicios
- `backend`: aplicacion Flask expuesta en el puerto `8000`.
- `db`: base de datos PostgreSQL con datos persistentes.

### Persistencia
- Volumen Docker `postgres_data` montado en `/var/lib/postgresql/data`.

### Estructura de datos

#### Tabla `discs`
- `id`
- `name`
- `artist`
- `created_at`

#### Tabla `comments`
- `id`
- `disc_id`
- `content`
- `created_at`

## Archivos clave
- `backend/app.py`: logica web y acceso a datos.
- `backend/templates/index.html`: interfaz HTML.
- `backend/static/styles.css`: estilos.
- `backend/Dockerfile`: imagen del backend.
- `backend/requirements.txt`: dependencias Python.
- `db/init.sql`: creacion de tablas.
- `docker-compose.yml`: orquestacion multicontenedor.
- `README.md`: instrucciones de uso.
- `start.sh`: arranque alternativo.

## Como ejecutar

### Opcion recomendada
```bash
docker compose up --build
```

### Opcion con script
```bash
./start.sh
```

## Comprobacion esperada
Cuando el stack arranca correctamente:

- PostgreSQL crea o reutiliza sus datos persistentes.
- Flask espera a que la base de datos este disponible.
- La aplicacion queda accesible en `http://localhost:8000`.

## Checklist de requisitos
- [x] Aplicacion CRUD basica sobre discos y comentarios.
- [x] Operaciones create, read, update y delete disponibles.
- [x] Arquitectura multicontenedor.
- [x] Base de datos persistente con volumen Docker.
- [x] Arranque con un unico comando.
- [x] README con instrucciones y descripcion.
- [x] Estructura preparada para ejecutarse en un entorno limpio y en GitHub Codespaces.

## Notas de entrega
- Se ha usado Flask por simplicidad y rapidez de despliegue.
- Se ha usado PostgreSQL como base de datos relacional persistente.
- La interfaz es intencionalmente sencilla para priorizar el cumplimiento funcional del paso 1.
- Si el repositorio se entrega como privado, hay que anadir a `@amestevez` como colaborador en lectura.
