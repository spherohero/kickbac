import sqlite3
from contextlib import contextmanager
from pathlib import Path


def connect(path):
    db = sqlite3.connect(path, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys=ON")
    return db


def initialize(path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with connect(path) as db:
        version = db.execute("PRAGMA user_version").fetchone()[0]
        if version == 0:
            sql = (
                Path(__file__).parent.parent / "migrations/001_initial.sql"
            ).read_text()
            db.executescript("BEGIN IMMEDIATE;\n" + sql + "\nCOMMIT;")
        elif version != 1:
            raise RuntimeError("Unsupported database schema")


def check_schema(path):
    if not Path(path).is_file():
        raise RuntimeError("Initialize database with python -m kickbac.cli init-db")
    with connect(path) as db:
        if db.execute("PRAGMA user_version").fetchone()[0] != 1:
            raise RuntimeError("Database schema is not initialized")
        db.execute("SELECT id,credential_hash,last_seen_at FROM devices LIMIT 0")


@contextmanager
def transaction(path):
    db = connect(path)
    try:
        db.execute("BEGIN IMMEDIATE")
        yield db
        db.commit()
    except BaseException:
        db.rollback()
        raise
    finally:
        db.close()
