import sqlite3
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from test_games import result

from kickbac.app import create_app
from kickbac.db import check_schema, connect, initialize
from kickbac.settings import Settings

COLUMNS = [
    "result_id",
    "user_id",
    "game_id",
    "score",
    "outcome",
    "data",
    "awarded_points",
    "scoring_policy",
    "source",
    "created_at",
]


@pytest.mark.parametrize("version", [0, 1, 2, 3])
def test_upgrade_every_supported_old_schema_preserves_all_bytes(tmp_path, version):
    path = tmp_path / "db"
    migrations = Path(__file__).parent.parent / "migrations"
    tables = []
    with connect(path) as db:
        for migration in sorted(migrations.glob("*.sql"))[:version]:
            db.executescript(migration.read_text())
        if version >= 1:
            db.execute(
                "INSERT INTO devices VALUES ('old','credential-bytes','old-seen')"
            )
            tables.append("devices")
        if version >= 2:
            db.execute(
                "INSERT INTO sessions VALUES ('old-session','old','sms|old','COMPLETE','created','expires','completed')"
            )
            db.execute(
                "INSERT INTO measurements VALUES ('old-reading','old-session','old','sms|old','{\"raw\":1}','received')"
            )
            tables += ["sessions", "measurements"]
        if version >= 3:
            db.execute(
                "INSERT INTO profiles VALUES ('sms|old','Kept 😀',?,'created','updated')",
                (b"\x00\xff\xfeavatar-bytes",),
            )
            tables.append("profiles")
        snapshot = {
            table: [tuple(row) for row in db.execute("SELECT * FROM " + table)]
            for table in tables
        }
    with pytest.raises(RuntimeError, match="schema"):
        check_schema(path)
    initialize(path)
    initialize(path)
    check_schema(path)
    with connect(path) as db:
        assert db.execute("PRAGMA user_version").fetchone()[0] == 6
        assert db.execute("SELECT COUNT(*) FROM game_results").fetchone()[0] == 0
        for table, rows in snapshot.items():
            assert [tuple(row) for row in db.execute("SELECT * FROM " + table)] == rows


@pytest.mark.parametrize("missing", ["table", *COLUMNS])
def test_startup_refuses_missing_game_table_or_any_column(tmp_path, missing):
    path = tmp_path / "db"
    initialize(path)
    with connect(path) as db:
        db.execute("DROP TABLE game_results")
        if missing != "table":
            db.execute(
                "CREATE TABLE game_results ("
                + ",".join(c + " TEXT" for c in COLUMNS if c != missing)
                + ")"
            )
    with (
        pytest.raises(sqlite3.OperationalError),
        TestClient(create_app(Settings(path), lambda token: "unused")),
    ):
        pass


def test_backup_restart_keeps_game_ledger_stats_profiles_and_replay(world, tmp_path):
    c, users, _, _, path = world
    assert (
        c.put(
            "/v1/me/profile",
            headers=users["alice"],
            json={"display_name": "Kept", "profile_picture": None},
        ).status_code
        == 200
    )
    body = result()
    first = c.post("/v1/me/game-results", headers=users["alice"], json=body)
    assert first.status_code == 201
    expected = c.get("/v1/me/stats", headers=users["alice"]).json()
    target = tmp_path / "backup.db"
    with connect(path) as db, connect(target) as backup:
        db.backup(backup)
    for database in (path, target):
        with TestClient(
            create_app(Settings(database), c.app.state.verifier)
        ) as restarted:
            assert (
                restarted.get("/v1/me/stats", headers=users["alice"]).json() == expected
            )
            assert restarted.get("/v1/me/game-results", headers=users["alice"]).json()[
                "items"
            ] == [first.json()]
            assert (
                restarted.get("/v1/me/profile", headers=users["alice"]).json()[
                    "display_name"
                ]
                == "Kept"
            )
            retry = restarted.post(
                "/v1/me/game-results", headers=users["alice"], json=body
            )
            assert retry.status_code == 200 and retry.json() == first.json()


def test_failed_game_migration_rolls_back_version_and_new_table(tmp_path):
    path = tmp_path / "db"
    migrations = Path(__file__).parent.parent / "migrations"
    with connect(path) as db:
        for migration in sorted(migrations.glob("*.sql"))[:3]:
            db.executescript(migration.read_text())
        # An incompatible preexisting index name makes migration 004 fail mid-script.
        db.execute("CREATE INDEX game_results_owner_order ON profiles(user_id)")
        before = list(db.iterdump())
    with pytest.raises(sqlite3.OperationalError):
        initialize(path)
    with connect(path) as db:
        assert db.execute("PRAGMA user_version").fetchone()[0] == 3
        assert list(db.iterdump()) == before
