"""Schema5 must add context without modifying any existing private records."""

import sqlite3
from pathlib import Path

import pytest

from kickbac.db import check_schema, connect, initialize

OLD_TABLES = ("devices", "sessions", "measurements", "profiles", "game_results")
PARTY_TABLES = {
    "parties",
    "party_members",
    "device_party_hosts",
    "party_devices",
    "party_games",
    "party_result_context",
    "party_join_attempts",
}


def schema4_database(path):
    migrations = Path(__file__).parent.parent / "migrations"
    with connect(path) as db:
        for migration in sorted(migrations.glob("*.sql"))[:4]:
            db.executescript(migration.read_text())
        db.execute("INSERT INTO devices VALUES ('old','private-fixture-hash','seen')")
        db.execute(
            "INSERT INTO sessions VALUES ('s','old','opaque-owner','COMPLETE','created','expires','done')"
        )
        db.execute(
            "INSERT INTO measurements VALUES ('m','s','old','opaque-owner','{}','received')"
        )
        db.execute(
            "INSERT INTO profiles VALUES ('opaque-owner','Kept 😀',?,'created','updated')",
            (b"\x00\xffprivate-avatar-fixture",),
        )
        db.execute(
            "INSERT INTO game_results VALUES ('r','opaque-owner','trivia',8,'win','{}',10,'completion_v1','client_reported','created')"
        )
        return {
            table: {
                "rows": [tuple(row) for row in db.execute("SELECT * FROM " + table)],
                "sql": db.execute(
                    "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                    (table,),
                ).fetchone()[0],
            }
            for table in OLD_TABLES
        }


def test_populated_schema4_upgrade_is_additive_repeatable_and_backup_safe(tmp_path):
    path = tmp_path / "db"
    before = schema4_database(path)
    initialize(path)
    initialize(path)
    with connect(path) as db:
        assert db.execute("PRAGMA user_version").fetchone()[0] == 5
        tables = {
            row[0]
            for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")
        }
        assert tables >= PARTY_TABLES
        for table, snapshot in before.items():
            assert [
                tuple(row) for row in db.execute("SELECT * FROM " + table)
            ] == snapshot["rows"]
            assert (
                db.execute(
                    "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                    (table,),
                ).fetchone()[0]
                == snapshot["sql"]
            )
        assert db.execute("PRAGMA foreign_key_check").fetchall() == []
        assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        backup = tmp_path / "backup"
        with connect(backup) as target:
            db.backup(target)
    check_schema(path)
    check_schema(backup)
    with connect(backup) as db:
        for table, snapshot in before.items():
            assert [
                tuple(row) for row in db.execute("SELECT * FROM " + table)
            ] == snapshot["rows"]


def test_failed_schema5_migration_rolls_back_every_new_table(tmp_path):
    path = tmp_path / "db"
    schema4_database(path)
    with connect(path) as db:
        db.execute("CREATE INDEX party_members_owner ON profiles(user_id)")
        before = list(db.iterdump())
    with pytest.raises(sqlite3.OperationalError):
        initialize(path)
    with connect(path) as db:
        assert db.execute("PRAGMA user_version").fetchone()[0] == 4
        assert list(db.iterdump()) == before


@pytest.mark.parametrize("table", sorted(PARTY_TABLES))
def test_startup_checks_each_new_context_table(tmp_path, table):
    path = tmp_path / "db"
    initialize(path)
    with connect(path) as db:
        db.execute("PRAGMA foreign_keys=OFF")
        db.execute("DROP TABLE " + table)
    with pytest.raises(sqlite3.OperationalError):
        check_schema(path)
