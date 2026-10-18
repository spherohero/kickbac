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


def test_operator_grant_requires_registered_device_and_opaque_subject(
    world, monkeypatch, capsys
):
    import pytest

    from kickbac import cli
    from kickbac.db import connect

    c, _, _, _, path = world
    grant = getattr(cli, "grant_party_device", None)
    assert callable(grant)
    for subject in ["", "   "]:
        with pytest.raises(ValueError):
            grant(path, "one", subject)
    with pytest.raises(ValueError):
        grant(path, "unknown", "opaque")
    grant(path, "one", "opaque-no-provider-prefix")
    grant(path, "one", "opaque-no-provider-prefix")
    monkeypatch.setattr(cli.Settings, "from_env", lambda: c.app.state.settings)
    monkeypatch.setattr(
        "sys.argv",
        ["kickbac", "grant-party-device", "two", "opaque-no-provider-prefix"],
    )
    cli.main()
    assert capsys.readouterr().out == "Party device assignment permission granted.\n"
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM device_party_hosts").fetchone()[0] == 2
        assert db.execute("SELECT COUNT(*) FROM sessions").fetchone()[0] == 0


def test_host_granted_binding_reassignment_and_device_join(world, identity):
    from kickbac.cli import grant_party_device

    c, users, _, _, path = world

    users["carol"] = {"Authorization": "Bearer " + identity[1](sub="auth0|carol")}

    def create(who):
        return c.post(
            "/v1/parties",
            json={"party_id": str(uuid4()), "name": "Friday"},
            headers=users[who],
        ).json()

    p, q = create("alice"), create("carol")
    url = "/v1/parties/" + p["party_id"] + "/device"
    assert (
        c.put(url, json={"device_id": "one"}, headers=users["alice"]).status_code == 404
    )
    grant_party_device(path, "one", "auth0|alice")
    grant_party_device(path, "two", "auth0|alice")
    grant_party_device(path, "one", "auth0|carol")
    bound = c.put(url, json={"device_id": "one"}, headers=users["alice"])
    assert bound.status_code == 200
    assert bound.json()["device_id"] == "one"
    assert (
        c.put(url, json={"device_id": "one"}, headers=users["alice"]).json()
        == bound.json()
    )
    joined = c.post("/v1/parties/join", json={"device_id": "one"}, headers=users["bob"])
    assert joined.status_code == 200
    assert joined.json()["party_id"] == p["party_id"]
    assert (
        c.put(url, json={"device_id": "two"}, headers=users["bob"]).status_code == 404
    )
    conflict = c.put(
        "/v1/parties/" + q["party_id"] + "/device",
        json={"device_id": "one"},
        headers=users["carol"],
    )
    assert conflict.status_code == 409
    assert conflict.json()["error"]["code"] == "device_assigned"
    assert (
        c.put(url, json={"device_id": "two"}, headers=users["alice"]).json()[
            "device_id"
        ]
        == "two"
    )
    assert (
        c.post(
            "/v1/parties/join", json={"device_id": "one"}, headers=users["bob"]
        ).status_code
        == 404
    )
    assert c.get("/d/two").json() == {"device_id": "two"}
    for _ in range(2):
        assert c.delete(url, headers=users["alice"]).json()["device_id"] is None


def test_binding_close_busy_sessions_expiry_and_unchanged_legacy_arm(world):
    from datetime import timedelta

    from kickbac.cli import grant_party_device
    from kickbac.db import connect

    c, users, _, now, path = world
    p = c.post(
        "/v1/parties",
        json={"party_id": str(uuid4()), "name": "Friday"},
        headers=users["alice"],
    ).json()
    url = "/v1/parties/" + p["party_id"]
    for device in ["one", "two"]:
        grant_party_device(path, device, "auth0|alice")
    assert (
        c.put(
            url + "/device", json={"device_id": "one"}, headers=users["alice"]
        ).status_code
        == 200
    )
    # Nonmember arming remains valid, even for an assigned unit.
    assert (
        c.post("/v1/devices/one/sessions", json={}, headers=users["bob"]).status_code
        == 201
    )
    for method, suffix, body in [
        ("put", "/device", {"device_id": "two"}),
        ("delete", "/device", None),
        ("post", "/close", {}),
    ]:
        r = c.request(method, url + suffix, json=body, headers=users["alice"])
        assert r.status_code == 409
        assert r.json()["error"]["code"] == "device_busy"
    with connect(path) as db:
        assert db.execute("SELECT device_id FROM party_devices").fetchone()[0] == "one"
        assert db.execute("SELECT state FROM parties").fetchone()[0] == "OPEN"
    # Identical binding retry is not a transition and remains idempotent while busy.
    assert (
        c.put(
            url + "/device", json={"device_id": "one"}, headers=users["alice"]
        ).status_code
        == 200
    )
    now[0] += timedelta(seconds=60)
    assert (
        c.put(
            url + "/device", json={"device_id": "two"}, headers=users["alice"]
        ).status_code
        == 200
    )
    with connect(path) as db:
        assert db.execute("SELECT status FROM sessions").fetchone()[0] == "ARMED"
    assert (
        c.post("/v1/devices/one/sessions", json={}, headers=users["bob"]).status_code
        == 201
    )
    assert (
        c.put(
            url + "/device", json={"device_id": "one"}, headers=users["alice"]
        ).status_code
        == 409
    )
    assert c.post(url + "/close", json={}, headers=users["alice"]).status_code == 200


def test_random_join_code_collision_retries_without_partial_party(world, monkeypatch):
    from kickbac import parties

    c, users, _, _, _ = world
    chars = iter("A" * 16 + "B" * 8)
    monkeypatch.setattr(parties.secrets, "choice", lambda alphabet: next(chars))
    for code in ["AAAAAAAA", "BBBBBBBB"]:
        r = c.post(
            "/v1/parties",
            json={"party_id": str(uuid4()), "name": "Friday"},
            headers=users["alice"],
        )
        assert r.status_code == 201
        assert r.json()["join_code"] == code
        assert (
            c.post(
                "/v1/parties/" + r.json()["party_id"] + "/close",
                json={},
                headers=users["alice"],
            ).status_code
            == 200
        )
    assert len(c.get("/v1/me/parties", headers=users["alice"]).json()["items"]) == 2


def test_concurrent_assignment_and_join_close_are_serializable(world, identity):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier

    from kickbac.cli import grant_party_device
    from kickbac.db import connect

    c, users, _, _, path = world
    users["carol"] = {"Authorization": "Bearer " + identity[1](sub="auth0|carol")}
    parties = [
        c.post(
            "/v1/parties",
            json={"party_id": str(uuid4()), "name": "Friday"},
            headers=users[who],
        ).json()
        for who in ["alice", "carol"]
    ]
    grant_party_device(path, "one", "auth0|alice")
    barrier = Barrier(2)

    grant_party_device(path, "one", "auth0|carol")

    def assign(p):
        barrier.wait(timeout=5)
        return c.put(
            "/v1/parties/" + p["party_id"] + "/device",
            json={"device_id": "one"},
            headers=users["alice" if p == parties[0] else "carol"],
        )

    with ThreadPoolExecutor(2) as pool:
        results = list(pool.map(assign, parties))
    assert sorted(r.status_code for r in results) == [200, 409]
    p = results[0].json() if results[0].status_code == 200 else results[1].json()
    barrier = Barrier(2)

    def mutate(action):
        barrier.wait(timeout=5)
        if action == "join":
            return c.post(
                "/v1/parties/join", json={"device_id": "one"}, headers=users["bob"]
            )
        return c.post(
            "/v1/parties/" + p["party_id"] + "/close",
            json={},
            headers=users[
                "alice" if p["party_id"] == parties[0]["party_id"] else "carol"
            ],
        )

    with ThreadPoolExecutor(2) as pool:
        joined, closed = list(pool.map(mutate, ["join", "close"]))
    assert joined.status_code in (200, 404)
    assert closed.status_code == 200
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM party_devices").fetchone()[0] == 0
        count = db.execute(
            "SELECT COUNT(*) FROM party_members WHERE party_id=? AND user_id='auth0|bob'",
            (p["party_id"],),
        ).fetchone()[0]
        assert count == (1 if joined.status_code == 200 else 0)


def test_party_openapi_documents_bounded_writes_and_join_rate_limit(world):
    c, *_ = world
    spec = c.get("/openapi.json").json()
    for path, method in [
        ("/v1/parties", "post"),
        ("/v1/parties/join", "post"),
        ("/v1/parties/{party_id}/device", "put"),
    ]:
        responses = spec["paths"][path][method]["responses"]
        assert (
            responses["413"]["content"]["application/json"]["schema"]["$ref"]
            == "#/components/schemas/ErrorEnvelope"
        )
    join = spec["paths"]["/v1/parties/join"]["post"]["responses"]
    assert "Retry-After" in join["429"]["headers"]
    assert (
        join["429"]["content"]["application/json"]["schema"]["$ref"]
        == "#/components/schemas/ErrorEnvelope"
    )


def test_private_prefix_stream_cap_ignores_false_length():
    import asyncio

    from kickbac.profile_body import ProfileBodyLimit

    for path in [
        "/v1/parties",
        "/v1/parties/x/device",
        "/v1/party-games/x/results",
        "/v1/me/parties",
        "/v1/me/game-history",
    ]:
        for method in ["POST", "PUT"]:
            for length in [None, b"1"]:
                messages = []
                chunks = iter(
                    [
                        {
                            "type": "http.request",
                            "body": b"x" * 17000,
                            "more_body": True,
                        },
                        {
                            "type": "http.request",
                            "body": b"x" * 17000,
                            "more_body": False,
                        },
                    ]
                )

                async def receive(chunks=chunks):
                    return next(chunks)

                async def send(message, messages=messages):
                    messages.append(message)

                async def inner(scope, receive, send):
                    raise AssertionError("Oversize body reached parser")

                scope = {
                    "type": "http",
                    "path": path,
                    "method": method,
                    "headers": [] if length is None else [(b"content-length", length)],
                }
                asyncio.run(ProfileBodyLimit(inner)(scope, receive, send))
                assert messages[0]["status"] == 413
                assert (b"cache-control", b"no-store") in messages[0]["headers"]


def test_party_reads_are_readonly_ordered_paginated_and_join_failures_rollback(world):
    from datetime import timedelta

    from fastapi.testclient import TestClient

    from kickbac.db import connect

    c, users, _, now, path = world
    ids = [str(uuid4()) for _ in range(3)]
    for party_id in ids:
        assert (
            c.post(
                "/v1/parties",
                json={"party_id": party_id, "name": "Friday"},
                headers=users["alice"],
            ).status_code
            == 201
        )
        if party_id != ids[-1]:
            assert (
                c.post(
                    "/v1/parties/" + party_id + "/close",
                    json={},
                    headers=users["alice"],
                ).status_code
                == 200
            )
    p = c.get("/v1/parties/" + ids[-1], headers=users["alice"]).json()
    c.post("/v1/devices/one/sessions", json={}, headers=users["alice"])
    now[0] += timedelta(seconds=60)
    with connect(path) as db:
        before = list(db.iterdump())
    page = c.get("/v1/me/parties?limit=1&offset=1", headers=users["alice"]).json()
    assert [r["party_id"] for r in page["items"]] == sorted(ids, reverse=True)[1:2]
    assert page["has_more"] is True
    assert c.get("/v1/parties/" + ids[0], headers=users["alice"]).status_code == 200
    with connect(path) as db:
        assert list(db.iterdump()) == before
        db.execute(
            "CREATE TRIGGER reject_join AFTER INSERT ON party_members BEGIN SELECT RAISE(ABORT,'private-marker'); END"
        )
    with TestClient(c.app, raise_server_exceptions=False) as quiet:
        r = quiet.post(
            "/v1/parties/join", json={"join_code": p["join_code"]}, headers=users["bob"]
        )
    assert r.status_code == 500
    assert r.headers["cache-control"] == "no-store"
    with connect(path) as db:
        assert (
            db.execute(
                "SELECT COUNT(*) FROM party_members WHERE user_id='auth0|bob'"
            ).fetchone()[0]
            == 0
        )
        assert (
            db.execute(
                "SELECT attempts FROM party_join_attempts WHERE user_id='auth0|bob'"
            ).fetchone()[0]
            == 1
        )


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
