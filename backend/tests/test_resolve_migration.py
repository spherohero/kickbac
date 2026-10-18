import sqlite3
from pathlib import Path
from uuid import uuid4

import pytest

from kickbac.db import check_schema, connect, initialize


def legacy(path, count=6):
    with connect(path) as db:
        for migration in sorted(
            (Path(__file__).parents[1] / "migrations").glob("00[1-6]_*.sql")
        ):
            db.executescript(migration.read_text())
        db.execute("INSERT INTO devices VALUES ('unit','private-hash',NULL)")
        db.execute(
            "INSERT INTO profiles VALUES ('owner','Kept',?,'time','time')",
            (b"\x00\xffprivate-avatar",),
        )
        db.execute(
            "INSERT INTO sessions VALUES ('session','unit','owner','COMPLETE','created','expires','done')"
        )
        db.execute(
            "INSERT INTO measurements VALUES ('reading','session','unit','owner','{}','received')"
        )
        db.execute(
            "INSERT INTO game_results VALUES ('result','owner','trivia',8,'win','{}',10,'completion_v1','client_reported','created')"
        )
        ids = [str(uuid4()) for _ in range(count)]
        for i, party_id in enumerate(ids):
            db.execute(
                "INSERT INTO parties VALUES (?, 'owner','Old',?,'time','OPEN',NULL)",
                (party_id, str(i)),
            )
            db.execute(
                "INSERT INTO party_members VALUES (?,'owner','time',NULL)", (party_id,)
            )
    return ids


@pytest.mark.parametrize("count", [6, 101])
def test_legacy_duplicates_are_readonly_conflicts_until_explicit_close(
    tmp_path, identity, count
):
    from fastapi.testclient import TestClient

    from kickbac.app import create_app
    from kickbac.auth import JWTVerifier
    from kickbac.settings import Settings

    path = tmp_path / "db"
    ids = legacy(path, count)
    initialize(path)
    private, token = identity
    verifier = JWTVerifier(
        "https://fixture.invalid/", "kickbac-api", lambda _: private.public_key()
    )
    owner = {"Authorization": "Bearer " + token(sub="owner")}
    foreign = {"Authorization": "Bearer " + token(sub="other")}
    with TestClient(create_app(Settings(path), verifier)) as c:
        with connect(path) as db:
            before = list(db.iterdump())
        r = c.get("/v1/me/parties/current", headers=owner)
        assert r.status_code == 409 and len(
            r.json()["error"]["current_parties"]
        ) == min(count, 100)
        assert r.json()["error"]["has_more"] == (count > 100)
        assert c.get("/v1/me/parties/current", headers=foreign).json() is None
        assert len(
            c.get("/v1/me/parties?limit=100", headers=owner).json()["items"]
        ) == min(count, 100)
        with connect(path) as db:
            assert list(db.iterdump()) == before
        for party_id in ids[:-1]:
            assert (
                c.post(
                    "/v1/parties/" + party_id + "/close", json={}, headers=owner
                ).status_code
                == 200
            )
        assert (
            c.get("/v1/me/parties/current", headers=owner).json()["party_id"] == ids[-1]
        )


def test_failed_seven_migration_rolls_back_ledger_and_preserves_six(tmp_path):
    path = tmp_path / "db"
    legacy(path)
    with connect(path) as db:
        db.execute(
            "CREATE TRIGGER party_member_one_open_insert AFTER INSERT ON devices BEGIN SELECT 1; END"
        )
        before = list(db.iterdump())
    with pytest.raises(sqlite3.OperationalError):
        initialize(path)
    with connect(path) as db:
        assert db.execute("PRAGMA user_version").fetchone()[0] == 6
        assert list(db.iterdump()) == before


def test_resolve_ledger_survives_full_backup_restart_and_constraints(world, tmp_path):
    from fastapi.testclient import TestClient

    from kickbac.app import create_app
    from kickbac.settings import Settings

    c, users, _, now, path = world
    body = {"request_id": str(uuid4()), "device_id": "one"}
    accepted = c.post("/v1/parties/resolve", json=body, headers=users["alice"]).json()
    backup = tmp_path / "backup"
    with connect(path) as source, connect(backup) as target:
        expected = snapshot(source)
        source.backup(target)
    check_schema(backup)
    with connect(backup) as db:
        assert snapshot(db) == expected
        assert db.execute("PRAGMA foreign_key_check").fetchall() == []
        assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        for device, party, action, expected_error in [
            ("missing", accepted["party"]["party_id"], "joined", "FOREIGN KEY"),
            ("one", "missing", "joined", "FOREIGN KEY"),
            ("one", accepted["party"]["party_id"], "invalid", "CHECK"),
        ]:
            with pytest.raises(sqlite3.IntegrityError, match=expected_error):
                db.execute(
                    "INSERT INTO party_resolve_requests VALUES (?,'owner',?,'Party',?,?)",
                    (str(uuid4()), device, party, action),
                )
        with pytest.raises(sqlite3.IntegrityError, match="UNIQUE"):
            db.execute(
                "INSERT INTO party_resolve_requests SELECT * FROM party_resolve_requests"
            )
    with TestClient(
        create_app(Settings(backup), c.app.state.verifier, clock=lambda: now[0])
    ) as fresh:
        r = fresh.post("/v1/parties/resolve", json=body, headers=users["alice"])
        assert r.status_code == 200 and r.json() == accepted


def test_sql_replace_cannot_reopen_a_closed_party_with_conflicting_members(world):
    c, users, _, _, path = world
    body = {"request_id": str(uuid4()), "device_id": "one"}
    p = c.post("/v1/parties/resolve", json=body, headers=users["alice"]).json()["party"]
    c.post("/v1/parties/join", json={"device_id": "one"}, headers=users["bob"])
    c.post("/v1/parties/" + p["party_id"] + "/close", json={}, headers=users["alice"])
    c.post(
        "/v1/parties/resolve",
        json={"request_id": str(uuid4()), "device_id": "two"},
        headers=users["bob"],
    )
    with connect(path) as db:
        before = snapshot(db)
        with pytest.raises(sqlite3.IntegrityError, match="active_party_conflict"):
            db.execute(
                "INSERT OR REPLACE INTO parties VALUES (?,'auth0|alice','Old',?,'time','OPEN',NULL)",
                (p["party_id"], p["join_code"]),
            )
        assert snapshot(db) == before


def snapshot(db):
    objects = [
        tuple(r)
        for r in db.execute(
            "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY name"
        )
    ]
    rows = {
        r[1]: [
            tuple(v) for v in db.execute('SELECT * FROM "' + r[1] + '" ORDER BY rowid')
        ]
        for r in objects
        if r[0] == "table"
    }
    return objects, rows


def test_populated_six_upgrade_preserves_duplicates_and_guards_future_writes(tmp_path):
    path = tmp_path / "legacy.db"
    ids = legacy(path)
    with connect(path) as db:
        old_objects, old_rows = snapshot(db)
    initialize(path)
    initialize(path)
    check_schema(path)
    with connect(path) as db:
        objects, rows = snapshot(db)
        assert all(obj in objects for obj in old_objects)
        assert all(rows[k] == v for k, v in old_rows.items())
        assert db.execute("PRAGMA user_version").fetchone()[0] == 7
        with pytest.raises(sqlite3.IntegrityError, match="active_party_conflict"):
            db.execute(
                "INSERT INTO parties VALUES (?, 'owner','New','new','time','OPEN',NULL)",
                (str(uuid4()),),
            )
        db.execute(
            "INSERT INTO parties VALUES ('other','other','Other','other','time','OPEN',NULL)"
        )
        with pytest.raises(sqlite3.IntegrityError, match="active_party_conflict"):
            db.execute("INSERT INTO party_members VALUES ('other','owner','time',NULL)")
        db.execute("INSERT INTO party_members VALUES ('other','owner','time','left')")
        with pytest.raises(sqlite3.IntegrityError, match="active_party_conflict"):
            db.execute("UPDATE party_members SET left_at=NULL WHERE party_id='other'")
        for party_id in ids:
            db.execute(
                "UPDATE parties SET state='CLOSED',closed_at='closed' WHERE party_id=?",
                (party_id,),
            )
        db.execute("UPDATE party_members SET left_at=NULL WHERE party_id='other'")
        with pytest.raises(sqlite3.IntegrityError, match="active_party_conflict"):
            db.execute(
                "UPDATE parties SET state='OPEN',closed_at=NULL WHERE party_id=?",
                (ids[0],),
            )
