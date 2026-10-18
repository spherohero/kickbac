import json
from uuid import uuid4


def test_private_body_parser_and_errors(world):
    from unittest.mock import patch as mock_patch

    from fastapi.testclient import TestClient

    c, users, _, _, _ = world
    paths = ["/v1/parties"]
    for path in paths:
        for content, expected in [
            (b"[" * 2000, 422),
            (b"\xff", 422),
            (b" " * 32769, 413),
        ]:
            r = c.post(path, content=content, headers=users["alice"])
            assert r.status_code == expected
            assert r.headers["cache-control"] == "no-store"
    for path in [
        "/v1/parties",
        "/v1/me/parties",
        "/v1/me/game-history",
        "/v1/party-games/x/close",
    ]:
        assert c.get(path).headers["cache-control"] == "no-store"
    with TestClient(c.app, raise_server_exceptions=False) as quiet:
        with mock_patch(
            "kickbac.parties.connect", side_effect=RuntimeError("private storage")
        ):
            r = quiet.get("/v1/me/parties", headers=users["alice"])
        assert r.status_code == 500
        assert r.headers["cache-control"] == "no-store"
        assert "private storage" not in r.text


def test_join_code_membership_leave_and_rejoin(world):
    c, users, _, _, _ = world
    p = c.post(
        "/v1/parties",
        json={"party_id": str(uuid4()), "name": "Friday"},
        headers=users["alice"],
    ).json()
    url = "/v1/parties/" + p["party_id"]
    body = {"join_code": "  " + p["join_code"].lower() + "  "}
    joined = c.post("/v1/parties/join", json=body, headers=users["bob"])
    assert joined.status_code == 200
    assert joined.json() == p | {"role": "member", "join_code": None, "member_count": 2}
    assert (
        c.post("/v1/parties/join", json=body, headers=users["bob"]).json()
        == joined.json()
    )
    assert c.get(url, headers=users["bob"]).json() == joined.json()
    for _ in range(2):
        assert c.post(url + "/leave", json={}, headers=users["bob"]).status_code == 200
    assert c.get(url, headers=users["bob"]).status_code == 404
    assert c.get("/v1/me/parties", headers=users["bob"]).json()["items"] == []
    assert c.post(url + "/leave", json={}, headers=users["alice"]).status_code == 409
    assert (
        c.post("/v1/parties/join", json=body, headers=users["bob"]).json()[
            "member_count"
        ]
        == 2
    )
    for bad in [
        {},
        {"join_code": p["join_code"], "device_id": "one"},
        {"join_code": None},
        {"device_id": 2},
        {"join_code": "bad"},
        {"device_id": "one", "user_id": "x"},
    ]:
        assert (
            c.post("/v1/parties/join", json=bad, headers=users["bob"]).status_code
            == 422
        )


def test_join_attempts_persist_failures_restart_and_exact_boundary(world):
    from datetime import timedelta

    from fastapi.testclient import TestClient

    from kickbac.app import create_app
    from kickbac.db import connect

    c, users, _, now, path = world
    p = c.post(
        "/v1/parties",
        json={"party_id": str(uuid4()), "name": "Friday"},
        headers=users["alice"],
    ).json()
    for _ in range(10):
        assert (
            c.post(
                "/v1/parties/join", json={"device_id": "missing"}, headers=users["bob"]
            ).status_code
            == 404
        )
    with connect(path) as db:
        assert (
            db.execute(
                "SELECT attempts FROM party_join_attempts WHERE user_id='auth0|bob'"
            ).fetchone()[0]
            == 10
        )
    app = create_app(c.app.state.settings, c.app.state.verifier, clock=lambda: now[0])
    with TestClient(app) as fresh:
        r = fresh.post(
            "/v1/parties/join", json={"join_code": p["join_code"]}, headers=users["bob"]
        )
        assert r.status_code == 429
        assert r.json()["error"]["code"] == "rate_limited"
        assert r.headers["retry-after"] == "60"
        now[0] += timedelta(seconds=59, microseconds=999999)
        assert (
            fresh.post(
                "/v1/parties/join", json={"device_id": "missing"}, headers=users["bob"]
            ).headers["retry-after"]
            == "1"
        )
        now[0] += timedelta(microseconds=1)
        assert (
            fresh.post(
                "/v1/parties/join",
                json={"join_code": p["join_code"]},
                headers=users["bob"],
            ).status_code
            == 200
        )
    with connect(path) as db:
        assert (
            db.execute(
                "SELECT attempts FROM party_join_attempts WHERE user_id='auth0|bob'"
            ).fetchone()[0]
            == 1
        )


def test_host_close_releases_binding_and_closes_game_atomically(world):
    from kickbac.db import connect

    c, users, _, now, path = world
    body = {"party_id": str(uuid4()), "name": "Friday"}
    p = c.post("/v1/parties", json=body, headers=users["alice"]).json()
    url = "/v1/parties/" + p["party_id"]
    c.post("/v1/parties/join", json={"join_code": p["join_code"]}, headers=users["bob"])
    with connect(path) as db:
        db.execute("INSERT INTO party_devices VALUES (?, 'one')", (p["party_id"],))
        db.execute(
            "INSERT INTO party_games VALUES (?,?,'trivia','one',?,'OPEN',NULL)",
            (str(uuid4()), p["party_id"], now[0].isoformat()),
        )
    assert c.post(url + "/close", json={}, headers=users["bob"]).status_code == 404
    closed = c.post(url + "/close", json={}, headers=users["alice"])
    assert closed.status_code == 200
    assert closed.json()["state"] == "CLOSED"
    assert closed.json()["join_code"] is None
    assert closed.json()["device_id"] is None
    assert (
        c.post(url + "/close", json={}, headers=users["alice"]).json() == closed.json()
    )
    assert c.post("/v1/parties", json=body, headers=users["alice"]).status_code == 200
    assert (
        c.post(
            "/v1/parties/join", json={"join_code": p["join_code"]}, headers=users["bob"]
        ).status_code
        == 404
    )
    assert (
        c.get("/v1/me/parties", headers=users["bob"]).json()["items"][0]["state"]
        == "CLOSED"
    )
    with connect(path) as db:
        game = db.execute("SELECT state,closed_at FROM party_games").fetchone()
        assert tuple(game) == ("CLOSED", now[0].isoformat())
        assert db.execute("SELECT COUNT(*) FROM party_devices").fetchone()[0] == 0


def test_create_own_read_and_list(world):
    client, users, _, _, _ = world
    party_id = str(uuid4())
    body = {"party_id": party_id, "name": "  Friday  "}
    result = client.post("/v1/parties", json=body, headers=users["alice"])
    assert result.status_code == 201
    party = result.json()
    assert party == {
        "party_id": party_id,
        "name": "Friday",
        "created_at": "2026-10-17T00:00:00+00:00",
        "state": "OPEN",
        "closed_at": None,
        "role": "host",
        "member_count": 1,
        "device_id": None,
        "join_code": party["join_code"],
    }
    assert len(party["join_code"]) == 8
    assert client.get(f"/v1/parties/{party_id}", headers=users["alice"]).json() == party
    assert client.get("/v1/me/parties", headers=users["alice"]).json() == {
        "items": [party],
        "limit": 50,
        "offset": 0,
        "has_more": False,
    }
    assert (
        client.get(f"/v1/parties/{party_id}", headers=users["bob"]).status_code == 404
    )
    assert client.get("/v1/me/parties", headers=users["bob"]).json()["items"] == []


def test_create_idempotency_and_strict_validation(world):
    c, users, _, _, _ = world
    body = {"party_id": str(uuid4()), "name": " Friday "}
    first = c.post("/v1/parties", json=body, headers=users["alice"])
    replay = c.post("/v1/parties", json=body, headers=users["alice"])
    assert replay.status_code == 200
    assert replay.json() == first.json()
    assert c.post("/v1/parties", json=body, headers=users["bob"]).status_code == 404
    assert (
        c.post(
            "/v1/parties", json=body | {"name": "Changed"}, headers=users["alice"]
        ).status_code
        == 409
    )
    for change in [
        {"name": " "},
        {"name": "a" * 81},
        {"name": "a\x00b"},
        {"name": "\ud800"},
        {"name": 5},
        {"party_id": "bad"},
        {"extra": True},
    ]:
        assert (
            c.post(
                "/v1/parties", content=json.dumps(body | change), headers=users["alice"]
            ).status_code
            == 422
        )
    for query in ["limit=0", "limit=101", "offset=-1"]:
        assert (
            c.get("/v1/me/parties?" + query, headers=users["alice"]).status_code == 422
        )
    assert (
        c.get("/v1/me/parties?offset=" + "9" * 50, headers=users["alice"]).json()[
            "items"
        ]
        == []
    )
