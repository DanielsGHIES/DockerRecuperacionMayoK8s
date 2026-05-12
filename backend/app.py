import os
import time
from contextlib import closing

from flask import Flask, jsonify, redirect, render_template, request, url_for
import psycopg2
from psycopg2.extras import RealDictCursor


app = Flask(__name__)

DB_CONFIG = {
    "host": os.getenv("POSTGRES_HOST", "db"),
    "port": int(os.getenv("POSTGRES_PORT", "5432")),
    "dbname": os.getenv("POSTGRES_DB", "music_reviews"),
    "user": os.getenv("POSTGRES_USER", "music_user"),
    "password": os.getenv("POSTGRES_PASSWORD", "music_password"),
}


def get_connection():
    return psycopg2.connect(**DB_CONFIG)


def wait_for_database(max_attempts=20, delay=2):
    for attempt in range(1, max_attempts + 1):
        try:
            with closing(get_connection()) as connection:
                with connection.cursor() as cursor:
                    cursor.execute("SELECT 1;")
            return
        except psycopg2.OperationalError:
            if attempt == max_attempts:
                raise
            time.sleep(delay)


def ensure_schema():
    with closing(get_connection()) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS discs (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(150) NOT NULL,
                    artist VARCHAR(150) NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                """
            )
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS comments (
                    id SERIAL PRIMARY KEY,
                    disc_id INTEGER NOT NULL REFERENCES discs(id) ON DELETE CASCADE,
                    content TEXT NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                """
            )
        connection.commit()


def fetch_discs():
    with closing(get_connection()) as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                SELECT
                    d.id,
                    d.name,
                    d.artist,
                    d.created_at,
                    COUNT(c.id) AS comment_count
                FROM discs d
                LEFT JOIN comments c ON c.disc_id = d.id
                GROUP BY d.id
                ORDER BY d.created_at DESC, d.id DESC;
                """
            )
            discs = cursor.fetchall()

            cursor.execute(
                """
                SELECT id, disc_id, content, created_at
                FROM comments
                ORDER BY created_at DESC, id DESC;
                """
            )
            comments = cursor.fetchall()

    comments_by_disc = {}
    for comment in comments:
        comments_by_disc.setdefault(comment["disc_id"], []).append(comment)

    return discs, comments_by_disc


@app.route("/", methods=["GET"])
def index():
    discs, comments_by_disc = fetch_discs()
    return render_template("index.html", discs=discs, comments_by_disc=comments_by_disc)


@app.route("/stress", methods=["GET"])
def stress():
    seconds = min(float(request.args.get("seconds", "0.2")), 2.0)
    deadline = time.perf_counter() + seconds
    value = 0
    while time.perf_counter() < deadline:
        value = (value * 31 + 7) % 1000003

    return jsonify({"status": "ok", "seconds": seconds, "checksum": value})


@app.route("/discs", methods=["POST"])
def create_disc():
    name = request.form.get("name", "").strip()
    artist = request.form.get("artist", "").strip()
    if not name or not artist:
        return redirect(url_for("index"))

    with closing(get_connection()) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "INSERT INTO discs (name, artist) VALUES (%s, %s);",
                (name, artist),
            )
        connection.commit()

    return redirect(url_for("index"))


@app.route("/discs/<int:disc_id>/comments", methods=["POST"])
def create_comment(disc_id):
    content = request.form.get("content", "").strip()
    if not content:
        return redirect(url_for("index"))

    with closing(get_connection()) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "INSERT INTO comments (disc_id, content) VALUES (%s, %s);",
                (disc_id, content),
            )
        connection.commit()

    return redirect(url_for("index"))


@app.route("/discs/<int:disc_id>/delete", methods=["POST"])
def delete_disc(disc_id):
    with closing(get_connection()) as connection:
        with connection.cursor() as cursor:
            cursor.execute("DELETE FROM discs WHERE id = %s;", (disc_id,))
        connection.commit()

    return redirect(url_for("index"))


@app.route("/discs/<int:disc_id>/edit", methods=["POST"])
def edit_disc(disc_id):
    name = request.form.get("name", "").strip()
    artist = request.form.get("artist", "").strip()
    if not name or not artist:
        return redirect(url_for("index"))

    with closing(get_connection()) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "UPDATE discs SET name = %s, artist = %s WHERE id = %s;",
                (name, artist, disc_id),
            )
        connection.commit()

    return redirect(url_for("index"))


@app.route("/comments/<int:comment_id>/delete", methods=["POST"])
def delete_comment(comment_id):
    with closing(get_connection()) as connection:
        with connection.cursor() as cursor:
            cursor.execute("DELETE FROM comments WHERE id = %s;", (comment_id,))
        connection.commit()

    return redirect(url_for("index"))


@app.route("/comments/<int:comment_id>/edit", methods=["POST"])
def edit_comment(comment_id):
    content = request.form.get("content", "").strip()
    if not content:
        return redirect(url_for("index"))

    with closing(get_connection()) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "UPDATE comments SET content = %s WHERE id = %s;",
                (content, comment_id),
            )
        connection.commit()

    return redirect(url_for("index"))


wait_for_database()
ensure_schema()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=False)
