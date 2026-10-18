import sqlite3
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from kickbac.app import create_app
from kickbac.db import check_schema, connect, initialize
from kickbac.settings import Settings


@pytest.mark.parametrize("version", [0, 1, 2])
def test_upgrade_to_three_preserves_every_old_row_and_is_repeatable(tmp_path, version):
    path = tmp_path / "db"
    migrations = Path(__file__).parent.parent / "migrations"
    old = {}
    with connect(path) as db:
        for migration in sorted(migrations.glob("*.sql"))[:version]:
            db.executescript(migration.read_text())
        if version >= 1:
            db.execute("INSERT INTO devices VALUES ('existing','private-hash','seen')")
        if version >= 2:
            db.execute(
                "INSERT INTO sessions VALUES ('s','existing','auth0|alice','COMPLETE','created','expires','done')"
            )
            db.execute(
                "INSERT INTO measurements VALUES ('m','s','existing','auth0|alice','{}','received')"
            )
        tables = ["devices", "sessions", "measurements"][
            : (0 if version == 0 else 1 if version == 1 else 3)
        ]
        for table in tables:
            old[table] = [tuple(row) for row in db.execute(f"SELECT * FROM {table}")]
    with pytest.raises(RuntimeError, match="schema"):
        check_schema(path)
    initialize(path)
    initialize(path)
    check_schema(path)
    with connect(path) as db:
        assert db.execute("PRAGMA user_version").fetchone()[0] == 3
        for table, rows in old.items():
            assert [tuple(row) for row in db.execute(f"SELECT * FROM {table}")] == rows
        assert {row[1] for row in db.execute("PRAGMA table_info(profiles)")} == {
            "user_id",
            "display_name",
            "profile_picture",
            "created_at",
            "updated_at",
        }
        assert db.execute("SELECT count(*) FROM profiles").fetchone()[0] == 0


@pytest.mark.parametrize("version", [0, 1, 2, 4])
def test_startup_refuses_wrong_version_without_upgrade(tmp_path, version):
    path = tmp_path / "db"
    initialize(path)
    with connect(path) as db:
        db.execute(f"PRAGMA user_version={version}")
    with (
        pytest.raises(RuntimeError, match="schema"),
        TestClient(create_app(Settings(path), lambda token: "fixture")),
    ):
        pass
    with connect(path) as db:
        assert db.execute("PRAGMA user_version").fetchone()[0] == version


@pytest.mark.parametrize(
    "column",
    ["user_id", "display_name", "profile_picture", "created_at", "updated_at", "table"],
)
def test_startup_refuses_missing_profile_table_or_column(tmp_path, column):
    path = tmp_path / "db"
    initialize(path)
    with connect(path) as db:
        # Corrupt only this isolated test database, never a user database.
        db.execute("DROP TABLE profiles")
        if column != "table":
            cols = [
                c
                for c in [
                    "user_id",
                    "display_name",
                    "profile_picture",
                    "created_at",
                    "updated_at",
                ]
                if c != column
            ]
            db.execute(
                "CREATE TABLE profiles (" + ",".join(c + " TEXT" for c in cols) + ")"
            )
    with (
        pytest.raises(sqlite3.OperationalError),
        TestClient(create_app(Settings(path), lambda token: "fixture")),
    ):
        pass


def test_backup_contains_profile_blob(world, tmp_path):
    c, users, _, _, path = world
    from test_profiles import picture

    response = c.put(
        "/v1/me/profile",
        headers=users["alice"],
        json={"display_name": "Alice", "profile_picture": picture()},
    )
    assert response.status_code == 200
    backup = tmp_path / "backup.db"
    with connect(path) as source, connect(backup) as target:
        source.backup(target)
    with TestClient(create_app(Settings(backup), c.app.state.verifier)) as restored:
        assert (
            restored.get("/v1/me/profile", headers=users["alice"]).json()
            == response.json()
        )
