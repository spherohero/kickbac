import sqlite3
from contextlib import contextmanager
from pathlib import Path


class ClosingConnection(sqlite3.Connection):
    def __exit__(self, *args):
        try:
            return super().__exit__(*args)
        finally:
            self.close()


def connect(path):
    db = sqlite3.connect(path, timeout=10, factory=ClosingConnection)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys=ON")
    return db


def initialize(path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with connect(path) as db:
        version = db.execute("PRAGMA user_version").fetchone()[0]
        if version not in (0, 1, 2, 3, 4):
            raise RuntimeError("Unsupported database schema")
        migrations = [
            "001_initial.sql",
            "002_sessions_measurements.sql",
            "003_profiles.sql",
            "004_game_results.sql",
        ]
        for migration in migrations[version:]:
            sql = (Path(__file__).parent.parent / "migrations" / migration).read_text()
            db.executescript("BEGIN IMMEDIATE;\n" + sql + "\nCOMMIT;")


def check_schema(path):
    if not Path(path).is_file():
        raise RuntimeError("Initialize database with python -m kickbac.cli init-db")
    with connect(path) as db:
        if db.execute("PRAGMA user_version").fetchone()[0] != 4:
            raise RuntimeError("Database schema is not initialized")
        db.execute("SELECT id,credential_hash,last_seen_at FROM devices LIMIT 0")
        db.execute(
            "SELECT user_id,display_name,profile_picture,created_at,updated_at FROM profiles LIMIT 0"
        )
        db.execute(
            "SELECT id,device_id,user_id,status,created_at,expires_at,completed_at FROM sessions LIMIT 0"
        )
        db.execute(
            "SELECT id,session_id,device_id,user_id,payload,received_at FROM measurements LIMIT 0"
        )
        db.execute(
            "SELECT result_id,user_id,game_id,score,outcome,data,awarded_points,"
            "scoring_policy,source,created_at FROM game_results LIMIT 0"
        )


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
