from uuid import uuid4

import pytest


def result(**changes):
    return {
        "result_id": str(uuid4()),
        "game_id": "trivia",
        "score": 20,
        "outcome": "win",
        "data": {},
        **changes,
    }


def test_initial_stats_are_private_zeroes(world):
    c, users, *_ = world
    response = c.get("/v1/me/stats", headers=users["alice"])
    assert response.status_code == 200
    assert response.json() == {
        "user_id": "auth0|alice",
        "total_points": 0,
        "games_played": 0,
        "wins": 0,
        "per_game": [],
    }


def test_store_result_replay_and_derive_points(world):
    c, users, _, now, _ = world
    body = result(data={"rounds": [1, True, None, {"answer": "yes"}]})
    first = c.post("/v1/me/game-results", headers=users["alice"], json=body)
    assert first.status_code == 201
    assert first.json() == {
        **body,
        "user_id": "auth0|alice",
        "awarded_points": 10,
        "scoring_policy": "completion_v1",
        "source": "client_reported",
        "created_at": now[0].isoformat(),
    }
    replay = c.post("/v1/me/game-results", headers=users["alice"], json=body)
    assert replay.status_code == 200
    assert replay.json() == first.json()
    assert c.get("/v1/me/stats", headers=users["alice"]).json() == {
        "user_id": "auth0|alice",
        "total_points": 10,
        "games_played": 1,
        "wins": 1,
        "per_game": [
            {
                "game_id": "trivia",
                "total_points": 10,
                "games_played": 1,
                "wins": 1,
                "best_score": 20,
            }
        ],
    }


def test_list_private_filtered_stable_pages(world):
    c, users, *_ = world
    saved = []
    for game in ("trivia", "pictionary", "trivia"):
        response = c.post(
            "/v1/me/game-results", headers=users["alice"], json=result(game_id=game)
        )
        assert response.status_code == 201
        saved.append(response.json())
    expected = sorted(
        saved, key=lambda row: (row["created_at"], row["result_id"]), reverse=True
    )
    page = c.get("/v1/me/game-results?limit=2", headers=users["alice"])
    assert page.status_code == 200
    assert page.json() == {
        "items": expected[:2],
        "limit": 2,
        "offset": 0,
        "has_more": True,
    }
    assert c.get(
        "/v1/me/game-results?limit=2&offset=2", headers=users["alice"]
    ).json() == {"items": expected[2:], "limit": 2, "offset": 2, "has_more": False}
    assert c.get("/v1/me/game-results?game_id=trivia", headers=users["alice"]).json()[
        "items"
    ] == [row for row in expected if row["game_id"] == "trivia"]
    assert c.get("/v1/me/game-results", headers=users["bob"]).json() == {
        "items": [],
        "limit": 50,
        "offset": 0,
        "has_more": False,
    }


@pytest.mark.parametrize(
    "query",
    [
        "limit=0",
        "limit=101",
        "offset=-1",
        "limit=true",
        "game_id=Bad",
        "game_id=",
        "game_id=a%0A",
    ],
)
def test_list_rejects_bad_query(world, query):
    c, users, *_ = world
    assert (
        c.get("/v1/me/game-results?" + query, headers=users["alice"]).status_code == 422
    )


def test_offset_larger_than_sqlite_integer_range_is_empty(world):
    c, users, *_ = world
    offset = 10**100
    response = c.get(f"/v1/me/game-results?offset={offset}", headers=users["alice"])
    assert response.status_code == 200
    assert response.json() == {
        "items": [],
        "limit": 50,
        "offset": offset,
        "has_more": False,
    }
