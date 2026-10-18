from uuid import uuid4

import pytest
from test_party_games import create_game
from test_party_games import party_world as party_world
from test_party_results import result_body, seed_measurement

from kickbac.db import connect


def test_matching_context_result_retry_precedes_lifecycle_checks(party_world):
    c, u, _, now, path, party = party_world
    game = create_game(party_world).json()["game_instance_id"]
    mid = seed_measurement(party_world)
    with connect(path) as db:
        sid = db.execute(
            "SELECT session_id FROM measurements WHERE id=?", (mid,)
        ).fetchone()[0]
        db.execute(
            "INSERT INTO party_check_ins VALUES (?,?,?,?,?,?)",
            (str(uuid4()), sid, party, game, "auth0|bob", "one"),
        )
    payload = result_body(measurement_id=mid)
    url = f"/v1/party-games/{game}/results"
    first = c.post(url, headers=u["bob"], json=payload)
    assert first.status_code == 201, first.text
    c.post(f"/v1/party-games/{game}/close", headers=u["alice"], json={})
    c.post(f"/v1/parties/{party}/leave", headers=u["bob"], json={})
    r = c.post(url, headers=u["bob"], json=payload)
    assert r.status_code == 200, r.text
    assert r.json() == first.json()
    with connect(path) as db:
        assert db.execute(
            "SELECT COUNT(*),SUM(awarded_points) FROM game_results"
        ).fetchone()[:] == (1, 10)


@pytest.mark.parametrize("context", ["party_only", "other_game", "other_party"])
def test_measurement_cannot_cross_check_in_context(party_world, context):
    c, u, _, now, path, party = party_world
    game = create_game(party_world).json()["game_instance_id"]
    mid = seed_measurement(party_world)
    with connect(path) as db:
        sid = db.execute(
            "SELECT session_id FROM measurements WHERE id=?", (mid,)
        ).fetchone()[0]
        linked_game = None
        if context == "other_game":
            linked_game = str(uuid4())
            db.execute(
                "INSERT INTO party_games VALUES (?,?,'trivia','one',?,'CLOSED',?)",
                (linked_game, party, now[0].isoformat(), now[0].isoformat()),
            )
        if context == "other_party":
            party = str(uuid4())
            db.execute(
                "INSERT INTO parties VALUES (?,'auth0|alice','Other','JKLMNPQR',?,'OPEN',NULL)",
                (party, now[0].isoformat()),
            )
        db.execute(
            "INSERT INTO party_check_ins VALUES (?,?,?,?,?,?)",
            (str(uuid4()), sid, party, linked_game, "auth0|bob", "one"),
        )
    r = c.post(
        f"/v1/party-games/{game}/results",
        headers=u["bob"],
        json=result_body(measurement_id=mid),
    )
    assert r.status_code == 422, r.text
    assert r.json()["error"]["code"] == "validation_error"
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM game_results").fetchone()[0] == 0
