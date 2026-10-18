import sqlite3
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Barrier

import pytest

from kickbac.db import check_schema, connect, initialize


def test_concurrent_armers_one_winner(world):
    c, u, _, _, path = world
    gate = Barrier(2)

    def arm(user):
        gate.wait(timeout=5)
        return c.post("/v1/devices/one/sessions", headers=u[user], json={}).status_code

    with ThreadPoolExecutor(2) as pool:
        assert sorted(pool.map(arm, ["alice", "bob"])) == [201, 409]
    with connect(path) as db:
        assert (
            db.execute("SELECT count(*) FROM sessions WHERE status='ARMED'").fetchone()[
                0
            ]
            == 1
        )


@pytest.mark.parametrize("route", ["/v1/devices/one/sessions", "/v1/device/heartbeat"])
def test_empty_bodies_reject_unknown_fields(world, route):
    c, u, d, _, _ = world
    response = c.post(
        route,
        headers=d["one"] if "/device/" in route else u["alice"],
        json={"user_id": "secret-marker"},
    )
    assert response.status_code == 422 and "secret-marker" not in response.text
    assert response.json()["error"]["code"] == "validation_error"


def test_upgrade_schema_one_preserves_devices_and_constraints(tmp_path):
    path = tmp_path / "db"
    with sqlite3.connect(path) as db:
        db.executescript(
            (Path(__file__).parent.parent / "migrations/001_initial.sql").read_text()
        )
        db.execute("INSERT INTO devices(id,credential_hash) VALUES ('existing','hash')")
    with pytest.raises(RuntimeError, match="schema"):
        check_schema(path)
    initialize(path)
    initialize(path)
    check_schema(path)
    with connect(path) as db:
        assert db.execute("PRAGMA user_version").fetchone()[0] == 5
        assert db.execute("SELECT id FROM devices").fetchone()[0] == "existing"
        for sid in ["first", "second"]:
            if sid == "first":
                db.execute(
                    "INSERT INTO sessions VALUES (?,'existing','alice','ARMED','created','expires',NULL)",
                    (sid,),
                )
            else:
                with pytest.raises(sqlite3.IntegrityError):
                    db.execute(
                        "INSERT INTO sessions VALUES (?,'existing','bob','SAMPLING','created','expires',NULL)",
                        (sid,),
                    )
