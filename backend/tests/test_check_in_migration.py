import sqlite3
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from test_parties_migration import schema4_database

from kickbac.app import create_app
from kickbac.db import check_schema, connect, initialize
from kickbac.settings import Settings


def schema5(path):
    schema4_database(path)
    with connect(path) as db:
        db.executescript(
            (Path(__file__).parent.parent / "migrations/005_parties.sql").read_text()
        )
        db.execute(
            "INSERT INTO parties VALUES ('p','opaque-owner','Fixture','ABCDEFGH','created','OPEN',NULL)"
        )
        db.execute(
            "INSERT INTO party_members VALUES ('p','opaque-owner','created',NULL)"
        )
        db.execute("INSERT INTO party_devices VALUES ('p','old')")
        db.execute(
            "INSERT INTO party_games VALUES ('g','p','trivia','old','created','OPEN',NULL)"
        )


def snapshot(db):
    return {
        r[0]: (r[1], [tuple(x) for x in db.execute("SELECT * FROM " + r[0])])
        for r in db.execute(
            "SELECT name,sql FROM sqlite_master WHERE type='table'"
        ).fetchall()
    }


def test_failed006_rolls_back_all_schema_and_rows(tmp_path):
    path = tmp_path / "db"
    schema5(path)
    with connect(path) as db:
        db.execute("CREATE INDEX party_check_ins_owner_history ON profiles(user_id)")
        before = list(db.iterdump())
    with pytest.raises(sqlite3.OperationalError):
        initialize(path)
    with connect(path) as db:
        assert db.execute("PRAGMA user_version").fetchone()[0] == 5
        assert list(db.iterdump()) == before


def test_schema_check_requires_context(tmp_path):
    path = tmp_path / "db"
    initialize(path)
    with connect(path) as db:
        db.execute("DROP TABLE party_check_ins")
    with pytest.raises(sqlite3.OperationalError):
        check_schema(path)


@pytest.mark.parametrize(
    "field", ["session_id", "party_id", "game_instance_id", "device_id"]
)
def test_each_new_foreign_key_rejects_orphans(tmp_path, field):
    path = tmp_path / "db"
    schema5(path)
    initialize(path)
    values = {
        "check_in_id": "c",
        "session_id": "s",
        "party_id": "p",
        "game_instance_id": "g",
        "user_id": "opaque-owner",
        "device_id": "old",
    }
    values[field] = "missing"
    with connect(path) as db:
        with pytest.raises(sqlite3.IntegrityError, match="FOREIGN KEY"):
            db.execute(
                "INSERT INTO party_check_ins VALUES (?,?,?,?,?,?)",
                tuple(values.values()),
            )
        assert db.execute("SELECT COUNT(*) FROM party_check_ins").fetchone()[0] == 0


def test_null_game_and_unique_session_constraints(tmp_path):
    path = tmp_path / "db"
    schema5(path)
    initialize(path)
    with connect(path) as db:
        db.execute(
            "INSERT INTO party_check_ins VALUES ('c','s','p',NULL,'opaque-owner','old')"
        )
        with pytest.raises(sqlite3.IntegrityError, match="UNIQUE"):
            db.execute(
                "INSERT INTO party_check_ins VALUES ('c2','s','p',NULL,'opaque-owner','old')"
            )
        db.execute(
            "INSERT INTO sessions VALUES ('s2','old','opaque-owner','COMPLETE','created','expires','done')"
        )
        with pytest.raises(sqlite3.IntegrityError, match="UNIQUE"):
            db.execute(
                "INSERT INTO party_check_ins VALUES ('c','s2','p',NULL,'opaque-owner','old')"
            )


def test_populated5_upgrade_repeat_backup_restart(tmp_path):
    path = tmp_path / "db"
    schema5(path)
    with connect(path) as db:
        before = snapshot(db)
    initialize(path)
    initialize(path)
    with connect(path) as db:
        assert db.execute("PRAGMA user_version").fetchone()[0] == 8
        assert all(snapshot(db)[t] == v for t, v in before.items())
        db.execute(
            "INSERT INTO party_check_ins VALUES ('c','s','p','g','opaque-owner','old')"
        )
    backup = tmp_path / "backup"
    with connect(path) as db, connect(backup) as target:
        expected = snapshot(db)
        db.backup(target)
    check_schema(backup)
    with TestClient(
        create_app(Settings(backup), verifier=lambda _: "fixture")
    ) as client:
        assert client.get("/health").status_code == 200
    with connect(backup) as db:
        assert snapshot(db) == expected
        assert db.execute("PRAGMA foreign_key_check").fetchall() == []
        assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        assert "party_check_ins_owner_history" in {
            r[1] for r in db.execute("PRAGMA index_list(party_check_ins)")
        }
        for values in [
            ("c", "s", "p", "g", "opaque-owner", "old"),
            ("c2", "s", "p", None, "opaque-owner", "old"),
            ("c2", "missing", "p", None, "opaque-owner", "old"),
            ("c2", "s", "missing", None, "opaque-owner", "old"),
            ("c2", "s", "p", "missing", "opaque-owner", "old"),
            ("c2", "s", "p", None, "opaque-owner", "missing"),
        ]:
            with pytest.raises(sqlite3.IntegrityError):
                db.execute("INSERT INTO party_check_ins VALUES (?,?,?,?,?,?)", values)
