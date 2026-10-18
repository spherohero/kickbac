import sqlite3
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from test_app_readings import reading
from test_resolve_migration import legacy, snapshot

from kickbac.app import create_app
from kickbac.db import check_schema, connect, initialize
from kickbac.settings import Settings


@pytest.mark.parametrize(
    "table,columns",
    [
        (
            "app_readings",
            [
                "reading_id",
                "user_id",
                "value",
                "recorded_at",
                "duration_ms",
                "source",
                "received_at",
            ],
        ),
        ("app_reading_save_windows", ["user_id", "window_started", "accepted"]),
    ],
)
def test_startup_checks_all_app_columns(tmp_path, table, columns):
    for missing in [None, *columns]:
        path = tmp_path / str(missing)
        initialize(path)
        with connect(path) as db:
            db.execute("DROP TABLE " + table)
            if missing:
                db.execute(
                    "CREATE TABLE "
                    + table
                    + " ("
                    + ",".join(c + " TEXT" for c in columns if c != missing)
                    + ")"
                )
        with pytest.raises(sqlite3.OperationalError):
            check_schema(path)


def test_failed_eight_migration_is_atomic(tmp_path):
    path = tmp_path / "old"
    legacy(path)
    with connect(path) as db:
        db.executescript(
            (Path(__file__).parents[1] / "migrations/007_party_resolve.sql").read_text()
        )
        db.execute("CREATE INDEX app_readings_owner_order ON profiles(user_id)")
        before = snapshot(db)
    with pytest.raises(sqlite3.OperationalError):
        initialize(path)
    with connect(path) as db:
        assert db.execute("PRAGMA user_version").fetchone()[0] == 7
        assert snapshot(db) == before


def test_complete_schema_backup_fixture_has_rows_in_every_table(tmp_path):
    from test_parties_migration import populated_context

    path, target = tmp_path / "full", tmp_path / "restored"
    populated_context(path)
    with connect(path) as db:
        db.execute(
            "INSERT INTO party_resolve_requests VALUES ('request','opaque-owner','old','Fixture','p','joined')"
        )
        db.execute(
            "INSERT INTO party_check_ins VALUES ('check','s','p','g','opaque-owner','old')"
        )
        db.execute(
            "INSERT INTO app_readings VALUES ('app','opaque-owner',0.5,'2026-01-01T00:00:00+00:00',1,'app_generated','received')"
        )
        db.execute("INSERT INTO app_reading_save_windows VALUES ('opaque-owner',1,1)")
    with connect(path) as db, connect(target) as backup:
        expected = snapshot(db)
        assert all(expected[1].values())
        db.backup(backup)
    check_schema(target)
    with connect(target) as db:
        assert snapshot(db) == expected
        assert db.execute("PRAGMA foreign_key_check").fetchall() == []
    with TestClient(
        create_app(Settings(target), verifier=lambda _: "unused")
    ) as client:
        assert client.get("/health").status_code == 200


def test_populated_seven_upgrade_preserves_every_object_row_blob_hash(tmp_path):
    path = tmp_path / "old"
    legacy(path)
    with connect(path) as db:
        db.executescript(
            (Path(__file__).parents[1] / "migrations/007_party_resolve.sql").read_text()
        )
        before_objects, before_rows = snapshot(db)
    with pytest.raises(RuntimeError):
        check_schema(path)
    initialize(path)
    initialize(path)
    check_schema(path)
    with connect(path) as db:
        objects, rows = snapshot(db)
        assert all(o in objects for o in before_objects)
        assert all(rows[k] == v for k, v in before_rows.items())
        assert db.execute("PRAGMA user_version").fetchone()[0] == 8
        assert rows["app_readings"] == rows["app_reading_save_windows"] == []


def test_populated_backup_restart_and_old_ledgers_unchanged(world, tmp_path):
    c, users, _, now, path = world
    with connect(path) as db:
        old_objects, old_rows = snapshot(db)
    body = reading()
    accepted = c.post("/v1/me/app-readings", headers=users["alice"], json=body).json()
    target = tmp_path / "backup"
    with connect(path) as db:
        objects, rows = snapshot(db)
        assert objects == old_objects
        for k, v in old_rows.items():
            if not k.startswith("app_reading"):
                assert rows[k] == v
        expected = snapshot(db)
        with connect(target) as backup:
            db.backup(backup)
    check_schema(target)
    with connect(target) as db:
        assert snapshot(db) == expected
        assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        assert not db.execute("PRAGMA foreign_key_check").fetchall()
        with pytest.raises(sqlite3.IntegrityError):
            db.execute("INSERT INTO app_readings SELECT * FROM app_readings")
        with pytest.raises(sqlite3.IntegrityError):
            db.execute("UPDATE app_readings SET source='device'")
        with pytest.raises(sqlite3.IntegrityError):
            db.execute("UPDATE app_reading_save_windows SET accepted=61")
    with TestClient(
        create_app(Settings(target), c.app.state.verifier, clock=lambda: now[0])
    ) as fresh:
        r = fresh.post("/v1/me/app-readings", headers=users["alice"], json=body)
        assert r.status_code == 200 and r.json() == accepted
        assert (
            fresh.get("/v1/me/app-reading-summary", headers=users["alice"]).json()[
                "latest_reading"
            ]
            == accepted
        )


def test_summary_uses_one_readonly_snapshot(world, monkeypatch):
    import kickbac.app_readings as module

    c, users, _, _, path = world
    first = c.post("/v1/me/app-readings", headers=users["alice"], json=reading()).json()
    with connect(path) as db:
        db.execute("PRAGMA journal_mode=WAL")
    real_connect = module.connect
    statements = []

    class SnapshotConnection:
        def __enter__(self):
            self.db = real_connect(path)
            return self

        def __exit__(self, *args):
            self.db.close()

        def execute(self, sql, args=()):
            statements.append(sql)
            result = self.db.execute(sql, args)
            if sql.startswith("SELECT COUNT"):
                # Count has fixed the read snapshot; another connection commits newer data.
                with real_connect(path) as writer:
                    body = reading()
                    writer.execute(
                        "INSERT INTO app_readings VALUES (?,?,?,?,?,?,?)",
                        (
                            body["reading_id"],
                            "auth0|alice",
                            0.9,
                            "2099-01-01T00:00:00+00:00",
                            1,
                            "app_generated",
                            "now",
                        ),
                    )
            return result

    monkeypatch.setattr(module, "connect", lambda _: SnapshotConnection())
    r = c.get("/v1/me/app-reading-summary", headers=users["alice"])
    assert r.json()["saved_readings"] == 1
    assert r.json()["latest_reading"] == first
    assert statements[:2] == ["PRAGMA query_only=ON", "BEGIN"]
