import sqlite3

from fastapi.testclient import TestClient


def test_explicit_migration_health_and_restart(tmp_path):
    from kickbac.app import create_app
    from kickbac.db import initialize
    from kickbac.settings import Settings

    path = tmp_path / "persistent.sqlite3"
    initialize(path)
    initialize(path)
    with sqlite3.connect(path) as db:
        assert db.execute("PRAGMA user_version").fetchone()[0] == 4
        assert {r[1] for r in db.execute("PRAGMA table_info(devices)")} == {
            "id",
            "credential_hash",
            "last_seen_at",
        }
        db.execute("INSERT INTO devices(id,credential_hash) VALUES ('unit','hash')")
    for _ in range(2):
        with TestClient(
            create_app(Settings(db_path=path), verifier=lambda t: "test")
        ) as client:
            assert client.get("/health").json() == {"status": "ok"}
    with sqlite3.connect(path) as db:
        assert db.execute("SELECT id FROM devices").fetchone()[0] == "unit"
