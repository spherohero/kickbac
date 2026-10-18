"""Schema5 must add context without modifying any existing private records."""

import sqlite3
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from kickbac.app import create_app
from kickbac.db import check_schema, connect, initialize
from kickbac.settings import Settings

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
        assert db.execute("PRAGMA user_version").fetchone()[0] == 6
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


def populated_context(path):
    schema4_database(path)
    initialize(path)
    with connect(path) as db:
        db.execute("INSERT INTO devices VALUES ('two','other-fixture-hash',NULL)")
        for party, code in (("p", "ABCDEFGH"), ("p2", "JKLMNPQR")):
            db.execute(
                "INSERT INTO parties VALUES (?,'opaque-owner','Fixture',?,'created','OPEN',NULL)",
                (party, code),
            )
        db.execute(
            "INSERT INTO party_members VALUES ('p','opaque-owner','joined',NULL)"
        )
        db.execute("INSERT INTO device_party_hosts VALUES ('old','opaque-owner')")
        db.execute("INSERT INTO party_devices VALUES ('p','old')")
        db.execute(
            "INSERT INTO party_games VALUES ('g','p','trivia','old','created','OPEN',NULL)"
        )
        db.execute(
            "INSERT INTO party_games VALUES ('g2','p','trivia','old','created','CLOSED','done')"
        )
        db.execute(
            "INSERT INTO party_result_context VALUES ('r','g','opaque-owner','m',1)"
        )
        db.execute(
            "INSERT INTO party_join_attempts VALUES ('opaque-owner','created',3)"
        )
        db.execute(
            "INSERT INTO game_results VALUES ('r2','other-owner','trivia',0,'completed','{}',10,'completion_v1','client_reported','created')"
        )
        return {
            table: [tuple(row) for row in db.execute("SELECT * FROM " + table)]
            for table in (*OLD_TABLES, *sorted(PARTY_TABLES))
        }


def test_populated_party_context_survives_online_backup_and_app_restart(tmp_path):
    path, backup = tmp_path / "db", tmp_path / "backup"
    snapshot = populated_context(path)
    with connect(path) as source, connect(backup) as target:
        source.backup(target)
    check_schema(backup)
    with connect(backup) as db:
        assert db.execute("PRAGMA user_version").fetchone()[0] == 6
        assert db.execute("PRAGMA foreign_key_check").fetchall() == []
        for table, rows in snapshot.items():
            assert [tuple(row) for row in db.execute("SELECT * FROM " + table)] == rows
    with TestClient(
        create_app(Settings(backup), verifier=lambda _: "fixture")
    ) as client:
        assert client.get("/health").json() == {"status": "ok"}
    with connect(backup) as db:
        for table, rows in snapshot.items():
            assert [tuple(row) for row in db.execute("SELECT * FROM " + table)] == rows


def test_schema5_declares_membership_game_order_and_open_game_indexes(tmp_path):
    path = tmp_path / "db"
    initialize(path)
    with connect(path) as db:
        indexes = {
            row[0]: row[1]
            for row in db.execute(
                "SELECT name,sql FROM sqlite_master WHERE type='index' AND sql IS NOT NULL"
            )
        }
        assert set(indexes) >= {
            "party_members_owner",
            "party_games_order",
            "one_open_party_game",
        }
        assert "WHERE state='OPEN'" in indexes["one_open_party_game"]
        assert "UNIQUE" in indexes["one_open_party_game"]


@pytest.mark.parametrize(
    "statement",
    [
        "INSERT INTO parties VALUES ('duplicate','other','Different','ABCDEFGH','created','OPEN',NULL)",
        "INSERT INTO party_devices VALUES ('p2','old')",
        "INSERT INTO party_devices VALUES ('p','two')",
        "INSERT INTO party_games VALUES ('g3','p','trivia',NULL,'created','OPEN',NULL)",
        "INSERT INTO party_result_context VALUES ('r2','g','opaque-owner',NULL,NULL)",
        "INSERT INTO party_result_context VALUES ('r2','g2','other-owner','m',NULL)",
    ],
)
def test_schema5_rejects_duplicate_codes_bindings_games_completions_and_links(
    tmp_path, statement
):
    path = tmp_path / "db"
    snapshot = populated_context(path)
    with connect(path) as db:
        with pytest.raises(sqlite3.IntegrityError, match="UNIQUE"):
            db.execute(statement)
        for table in PARTY_TABLES:
            assert [
                tuple(row) for row in db.execute("SELECT * FROM " + table)
            ] == snapshot[table]


@pytest.mark.parametrize(
    "statement",
    [
        "INSERT INTO party_members VALUES ('missing','user','joined',NULL)",
        "INSERT INTO device_party_hosts VALUES ('missing','user')",
        "INSERT INTO party_devices VALUES ('missing','two')",
        "INSERT INTO party_devices VALUES ('p2','missing')",
        "INSERT INTO party_games VALUES ('g3','missing','trivia',NULL,'created','OPEN',NULL)",
        "INSERT INTO party_games VALUES ('g3','p2','trivia','missing','created','OPEN',NULL)",
        "INSERT INTO party_result_context VALUES ('missing','g2','other-owner',NULL,NULL)",
        "INSERT INTO party_result_context VALUES ('r2','missing','other-owner',NULL,NULL)",
        "INSERT INTO party_result_context VALUES ('r2','g2','other-owner','missing',NULL)",
    ],
)
def test_schema5_rejects_orphan_references(tmp_path, statement):
    path = tmp_path / "db"
    populated_context(path)
    with connect(path) as db:
        with pytest.raises(sqlite3.IntegrityError, match="FOREIGN KEY"):
            db.execute(statement)
        assert db.execute("PRAGMA foreign_key_check").fetchall() == []
