from uuid import uuid4

from test_party_games import create_game
from test_party_games import party_world as party_world
from test_party_results import result_body, seed_measurement

from kickbac.db import connect


def test_all_history_paginates_legacy_and_parties_after_leave(party_world):
    c, u, _, now, path, party = party_world
    game = create_game(party_world).json()["game_instance_id"]
    party_result = c.post(
        f"/v1/party-games/{game}/results", headers=u["bob"], json=result_body()
    ).json()
    generic = c.post(
        "/v1/me/game-results",
        headers=u["bob"],
        json=result_body(
            data={"party_id": party, "game_instance_id": game, "placement": 1}
        ),
    ).json()
    c.post("/v1/me/game-results", headers=u["alice"], json=result_body())
    second_party = str(uuid4())
    with connect(path) as db:
        db.execute(
            "INSERT INTO parties VALUES (?,'auth0|alice','Same name','BCDEFGHJ',?,'OPEN',NULL)",
            (second_party, now[0].isoformat()),
        )
        db.execute(
            "INSERT INTO party_members VALUES (?,?,?,NULL)",
            (second_party, "auth0|bob", now[0].isoformat()),
        )
    second_game = c.post(
        f"/v1/parties/{second_party}/games",
        headers=u["alice"],
        json={"game_instance_id": str(uuid4()), "game_id": "trivia"},
    ).json()["game_instance_id"]
    second = c.post(
        f"/v1/party-games/{second_game}/results", headers=u["bob"], json=result_body()
    ).json()
    with connect(path) as db:
        db.execute(
            "UPDATE party_members SET left_at=? WHERE user_id='auth0|bob'",
            (now[0].isoformat(),),
        )
        db.execute(
            "UPDATE parties SET state='CLOSED',closed_at=?", (now[0].isoformat(),)
        )
    expected = sorted(
        [party_result, generic, second], key=lambda row: row["result_id"], reverse=True
    )
    actual = []
    for offset in range(3):
        r = c.get(
            "/v1/me/game-history",
            headers=u["bob"],
            params={"limit": 1, "offset": offset},
        )
        assert r.status_code == 200
        body = r.json()
        assert body["has_more"] == (offset < 2)
        row = body["items"][0]
        assert {key: row[key] for key in expected[offset]} == expected[offset]
        if row["result_id"] == generic["result_id"]:
            assert all(
                row[key] is None
                for key in ["party", "game_instance_id", "placement", "measurement"]
            )
        else:
            assert row["party"] == {
                "party_id": party
                if row["result_id"] == party_result["result_id"]
                else second_party,
                "name": "Same name",
                "created_at": now[0].isoformat(),
            }
            assert row["measurement"] is None
        actual.append(row)
    assert len(actual) == 3
    assert c.get(
        "/v1/me/game-history", headers=u["bob"], params={"offset": 10**50}
    ).json() == {"items": [], "limit": 50, "offset": 10**50, "has_more": False}
    for params in [{"limit": 0}, {"limit": 101}, {"offset": -1}]:
        assert (
            c.get("/v1/me/game-history", headers=u["bob"], params=params).status_code
            == 422
        )


def test_rich_history_includes_private_party_and_existing_measurement(party_world):
    c, u, _, _, _, party = party_world
    game = create_game(party_world).json()["game_instance_id"]
    mid = seed_measurement(party_world)
    r = c.post(
        f"/v1/party-games/{game}/results",
        headers=u["bob"],
        json=result_body(measurement_id=mid, placement=1),
    )
    assert r.status_code == 201
    measurement = c.get("/v1/measurements", headers=u["bob"]).json()["items"][0]
    expected = {
        **r.json(),
        "party": {
            "party_id": party,
            "name": "Same name",
            "created_at": party_world[3][0].isoformat(),
        },
        "game_instance_id": game,
        "placement": 1,
        "measurement": measurement,
    }
    history = c.get("/v1/me/game-history", headers=u["bob"])
    assert history.status_code == 200, history.text
    assert history.json() == {
        "items": [expected],
        "limit": 50,
        "offset": 0,
        "has_more": False,
    }
    assert measurement["estimated_bac_percent"] is None
    assert c.get("/v1/me/game-history", headers=u["alice"]).json()["items"] == []
