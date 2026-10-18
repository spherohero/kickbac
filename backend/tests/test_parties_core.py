import json
from uuid import uuid4


def test_private_body_parser_and_errors(world):
    from fastapi.testclient import TestClient
    from unittest.mock import patch as mock_patch

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
