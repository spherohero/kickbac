from uuid import uuid4

import pytest

from kickbac.db import connect


@pytest.fixture
def party_world(world):
    import importlib.util

    client, users, devices, now, path = world
    if importlib.util.find_spec("kickbac.party_games"):
        from kickbac.party_games import router

        client.app.include_router(router)
    party = str(uuid4())
    with connect(path) as db:
        db.execute(
            "INSERT INTO parties VALUES (?, 'auth0|alice', 'Same name', 'ABCDEFGH', ?, 'OPEN', NULL)",
            (party, now[0].isoformat()),
        )
        for user in ["alice", "bob"]:
            db.execute(
                "INSERT INTO party_members VALUES (?,?,?,NULL)",
                (party, "auth0|" + user, now[0].isoformat()),
            )
        db.execute("INSERT INTO party_devices VALUES (?, 'one')", (party,))
    return (*world, party)


def create_game(w, **changes):
    client, users, _, _, _, party = w
    body = {"game_instance_id": str(uuid4()), "game_id": "trivia", **changes}
    return client.post(f"/v1/parties/{party}/games", headers=users["alice"], json=body)


@pytest.mark.parametrize(
    "case,expected",
    [
        ("member", 404),
        ("missing", 404),
        ("retry", 200),
        ("changed", 409),
        ("closed_retry", 200),
        ("second", 409),
        ("foreign", 404),
        ("closed_new", 409),
    ],
)
def test_creation_authority_and_idempotency(party_world, case, expected):
    c, u, _, now, path, party = party_world
    first = create_game(party_world).json()
    body = {"game_instance_id": first["game_instance_id"], "game_id": "trivia"}
    actor = "alice"
    if case == "member":
        actor = "bob"
    if case == "changed":
        body["game_id"] = "pictionary"
    if case in ("second", "closed_new"):
        body["game_instance_id"] = str(uuid4())
    with connect(path) as db:
        if case in ("closed_retry", "closed_new"):
            db.execute(
                "UPDATE parties SET state='CLOSED',closed_at=?", (now[0].isoformat(),)
            )
            db.execute("UPDATE party_devices SET device_id='two'")
        if case == "foreign":
            db.execute("UPDATE parties SET host_user_id='auth0|bob'")
    if case == "missing":
        party = str(uuid4())
    r = c.post(f"/v1/parties/{party}/games", headers=u[actor], json=body)
    assert r.status_code == expected, r.text
    if expected == 200:
        assert r.json() == first


def test_host_close_is_idempotent(party_world):
    c, u, *_ = party_world
    game = create_game(party_world).json()["game_instance_id"]
    url = f"/v1/party-games/{game}/close"
    assert c.post(url, headers=u["bob"], json={}).status_code == 404
    first = c.post(url, headers=u["alice"], json={})
    assert first.status_code == 200
    assert first.json()["state"] == "CLOSED"
    assert c.post(url, headers=u["alice"], json={}).json() == first.json()
    assert create_game(party_world).status_code == 201


def test_instance_list_private_stable_pagination(party_world):
    c, u, _, now, path, party = party_world
    first = create_game(party_world).json()
    first = c.post(
        f"/v1/party-games/{first['game_instance_id']}/close",
        headers=u["alice"],
        json={},
    ).json()
    second = create_game(party_world).json()
    url = f"/v1/parties/{party}/games"
    rows = sorted([first, second], key=lambda x: x["game_instance_id"], reverse=True)
    for offset in [0, 1, 10**40]:
        r = c.get(url, headers=u["bob"], params={"limit": 1, "offset": offset})
        assert r.status_code == 200
        assert r.json() == {
            "items": rows[offset : offset + 1],
            "limit": 1,
            "offset": offset,
            "has_more": offset == 0,
        }
    assert c.get(url, headers=u["bob"], params={"limit": 101}).status_code == 422
    with connect(path) as db:
        db.execute(
            "UPDATE party_members SET left_at=? WHERE user_id='auth0|bob'",
            (now[0].isoformat(),),
        )
    assert c.get(url, headers=u["bob"]).status_code == 404


def test_new_router_documents_typed_replays_and_payload_limit(party_world):
    schema = party_world[0].app.openapi()
    for path in [
        "/v1/parties/{party_id}/games",
        "/v1/party-games/{game_instance_id}/results",
    ]:
        responses = schema["paths"][path]["post"]["responses"]
        assert (
            responses["200"]["content"]["application/json"]["schema"]
            == responses["201"]["content"]["application/json"]["schema"]
        )
        assert responses["413"]["content"]["application/json"]["schema"][
            "$ref"
        ].endswith("/ErrorEnvelope")
        assert "429" not in responses


def test_create_instance_snapshots_device(party_world):
    response = create_game(party_world)
    assert response.status_code == 201, response.text
    assert response.json() == {
        "game_instance_id": response.json()["game_instance_id"],
        "party_id": party_world[-1],
        "game_id": "trivia",
        "device_id": "one",
        "created_at": party_world[3][0].isoformat(),
        "state": "OPEN",
        "closed_at": None,
    }
