from uuid import uuid4


def resolve(c, users, who="alice", device="one", **extra):
    return c.post(
        "/v1/parties/resolve",
        json={"request_id": str(uuid4()), "device_id": device, **extra},
        headers=users[who],
    )


def test_resolve_joins_busy_assigned_party_and_never_renames(world):
    from kickbac.db import connect

    c, users, _, _, path = world
    first = resolve(c, users, name="Original").json()["party"]
    armed = c.post("/v1/devices/one/sessions", json={}, headers=users["alice"])
    assert armed.status_code == 201
    with connect(path) as db:
        before = [tuple(r) for r in db.execute("SELECT * FROM sessions")]
    joined = resolve(c, users, "bob", name="Different")
    assert joined.status_code == 200
    assert joined.json()["action"] == "joined"
    assert joined.json()["party"] == first | {
        "role": "member",
        "join_code": None,
        "member_count": 2,
    }
    assert resolve(c, users).json()["action"] == "joined"
    with connect(path) as db:
        assert [tuple(r) for r in db.execute("SELECT * FROM sessions")] == before


def test_global_active_policy_and_current_read(world):
    c, users, *_ = world
    assert c.get("/v1/me/parties/current", headers=users["alice"]).json() is None
    p = resolve(c, users).json()["party"]
    assert c.get("/v1/me/parties/current", headers=users["alice"]).json() == p
    q = resolve(c, users, "bob", "two").json()["party"]
    for result in [
        resolve(c, users, device="two"),
        c.post(
            "/v1/parties",
            json={"party_id": str(uuid4()), "name": "Other"},
            headers=users["alice"],
        ),
        c.post(
            "/v1/parties/join",
            json={"join_code": q["join_code"]},
            headers=users["alice"],
        ),
        c.post("/v1/parties/join", json={"device_id": "two"}, headers=users["alice"]),
    ]:
        assert result.status_code == 409
        assert result.json()["error"]["code"] == "active_party_conflict"
        assert result.json()["error"]["current_parties"] == [p]
        assert q["join_code"] not in result.text
    assert (
        c.post(
            "/v1/parties/join", json={"device_id": "one"}, headers=users["alice"]
        ).status_code
        == 200
    )
    assert (
        c.post(
            "/v1/parties/" + p["party_id"] + "/close", json={}, headers=users["alice"]
        ).status_code
        == 200
    )
    assert c.get("/v1/me/parties/current", headers=users["alice"]).json() is None
    assert resolve(c, users, device="two").status_code == 200


def test_resolve_retry_privacy_late_close_leave_and_restart(world):
    from fastapi.testclient import TestClient

    from kickbac.app import create_app
    from kickbac.db import connect

    c, users, _, now, path = world
    body = {"request_id": str(uuid4()), "device_id": "one", "name": " First "}
    created = c.post("/v1/parties/resolve", json=body, headers=users["alice"]).json()
    p = created["party"]
    assert (
        c.post("/v1/parties/resolve", json=body, headers=users["bob"]).status_code
        == 404
    )
    for changed in [{"name": "Other"}, {"device_id": "two"}]:
        r = c.post("/v1/parties/resolve", json=body | changed, headers=users["alice"])
        assert (
            r.status_code == 409 and r.json()["error"]["code"] == "idempotency_conflict"
        )
    joined_body = {"request_id": str(uuid4()), "device_id": "one"}
    joined = c.post(
        "/v1/parties/resolve", json=joined_body, headers=users["bob"]
    ).json()
    c.post("/v1/parties/" + p["party_id"] + "/leave", json={}, headers=users["bob"])
    assert (
        c.post("/v1/parties/resolve", json=joined_body, headers=users["bob"]).json()[
            "action"
        ]
        == joined["action"]
    )
    assert (
        c.get("/v1/parties/" + p["party_id"], headers=users["bob"]).status_code == 404
    )
    closed = c.post(
        "/v1/parties/" + p["party_id"] + "/close", json={}, headers=users["alice"]
    ).json()
    newer = resolve(c, users).json()["party"]
    assert newer["party_id"] != p["party_id"] and newer["join_code"] != p["join_code"]
    with TestClient(
        create_app(c.app.state.settings, c.app.state.verifier, clock=lambda: now[0])
    ) as fresh:
        r = fresh.post("/v1/parties/resolve", json=body, headers=users["alice"])
        assert r.status_code == 200 and r.json() == {
            "action": "created",
            "party": closed,
        }
        assert (
            fresh.get("/v1/me/parties/current", headers=users["alice"]).json() == newer
        )
    with connect(path) as db:
        assert (
            db.execute(
                "SELECT left_at FROM party_members WHERE party_id=? AND user_id='auth0|bob'",
                (p["party_id"],),
            ).fetchone()[0]
            is not None
        )
        assert db.execute("SELECT COUNT(*) FROM parties").fetchone()[0] == 2


def test_resolve_rejects_unknown_busy_invalid_and_rolls_back(world):
    import json
    from datetime import timedelta

    from fastapi.testclient import TestClient

    from kickbac.db import connect

    c, users, devices, now, path = world
    assert resolve(c, users, device="unknown").status_code == 404
    assert (
        c.post("/v1/devices/one/sessions", json={}, headers=users["alice"]).status_code
        == 201
    )
    r = resolve(c, users)
    assert r.status_code == 409 and r.json()["error"]["code"] == "device_busy"
    # SAMPLING is equally fenced; no arm expiry or measurement is changed.
    with connect(path) as db:
        db.execute("UPDATE sessions SET status='SAMPLING' WHERE device_id='one'")
        sampling = [tuple(row) for row in db.execute("SELECT * FROM sessions")]
    assert resolve(c, users).json()["error"]["code"] == "device_busy"
    with connect(path) as db:
        assert [tuple(row) for row in db.execute("SELECT * FROM sessions")] == sampling
    base = {"request_id": str(uuid4()), "device_id": "two"}
    for change in [
        {"name": None},
        {"name": " "},
        {"name": "a\n"},
        {"name": "\ud800"},
        {"name": "a" * 81},
        {"name": 1},
        {"device_id": " a"},
        {"request_id": "bad"},
        {"extra": True},
    ]:
        r = c.post(
            "/v1/parties/resolve",
            content=json.dumps(base | change),
            headers=users["alice"] | {"Content-Type": "application/json"},
        )
        assert r.status_code == 422 and r.headers["cache-control"] == "no-store"
    for raw, code in [(b"[" * 2000, 422), (b"\xff", 422), (b" " * 32769, 413)]:
        r = c.post(
            "/v1/parties/resolve",
            content=raw,
            headers=users["alice"] | {"Content-Type": "application/json"},
        )
        assert r.status_code == code and r.headers["cache-control"] == "no-store"
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM parties").fetchone()[0] == 0
        db.execute(
            "CREATE TRIGGER reject_resolve BEFORE INSERT ON party_resolve_requests BEGIN SELECT RAISE(ABORT,'private-marker'); END"
        )
    with TestClient(c.app, raise_server_exceptions=False) as quiet:
        assert resolve(quiet, users, device="two").status_code == 500
    with connect(path) as db:
        for table in [
            "parties",
            "party_members",
            "party_devices",
            "party_resolve_requests",
        ]:
            assert db.execute("SELECT COUNT(*) FROM " + table).fetchone()[0] == 0
    now[0] += timedelta(seconds=60)
    with connect(path) as db:
        db.execute("DROP TRIGGER reject_resolve")
    assert resolve(c, users).status_code == 201


def test_resolve_serializes_same_device_phones_and_same_phone_devices(world):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier

    from kickbac.db import connect

    c, users, _, _, path = world
    barrier = Barrier(2)

    def attempt(who):
        barrier.wait(timeout=10)
        return resolve(c, users, who)

    with ThreadPoolExecutor(2) as pool:
        results = list(pool.map(attempt, ["alice", "bob"]))
    assert sorted(r.status_code for r in results) == [200, 201]
    assert len({r.json()["party"]["party_id"] for r in results}) == 1
    host = "alice" if results[0].status_code == 201 else "bob"
    p = results[0].json()["party"]
    c.post("/v1/parties/" + p["party_id"] + "/close", json={}, headers=users[host])
    barrier = Barrier(2)

    def claim(device):
        barrier.wait(timeout=10)
        return resolve(c, users, device=device)

    with ThreadPoolExecutor(2) as pool:
        results = list(pool.map(claim, ["one", "two"]))
    assert sorted(r.status_code for r in results) == [201, 409]
    with connect(path) as db:
        assert (
            db.execute("SELECT COUNT(*) FROM parties WHERE state='OPEN'").fetchone()[0]
            == 1
        )
        assert db.execute("SELECT COUNT(*) FROM party_devices").fetchone()[0] == 1


def test_resolve_creates_bound_party_without_grant_and_replays(world):
    from kickbac.db import connect

    c, users, _, _, path = world
    body = {"request_id": str(uuid4()), "device_id": "one"}
    first = c.post("/v1/parties/resolve", json=body, headers=users["alice"])
    assert first.status_code == 201
    p = first.json()["party"]
    assert first.json()["action"] == "created"
    assert p["device_id"] == "one" and p["name"] == "Party" and p["role"] == "host"
    replay = c.post(
        "/v1/parties/resolve", json=body | {"name": "Party"}, headers=users["alice"]
    )
    assert replay.status_code == 200 and replay.json() == first.json()
    with connect(path) as db:
        assert (
            db.execute("SELECT COUNT(*) FROM party_resolve_requests").fetchone()[0] == 1
        )
        assert db.execute("SELECT COUNT(*) FROM device_party_hosts").fetchone()[0] == 0
        assert db.execute("SELECT COUNT(*) FROM sessions").fetchone()[0] == 0
