import json
from datetime import timedelta
from uuid import uuid4

import pytest
from test_party_games import create_game
from test_party_games import party_world as party_world

from kickbac.db import connect


def result_body(**changes):
    return {
        "result_id": str(uuid4()),
        "game_id": "trivia",
        "score": 8,
        "outcome": "win",
        "data": {"a": 1},
        **changes,
    }


@pytest.mark.parametrize(
    "change", [None, "score", "data", "placement", "game", "foreign", "generic"]
)
def test_result_id_replay_checks_complete_context(party_world, change):
    c, u, _, now, path, _ = party_world
    game = create_game(party_world).json()["game_instance_id"]
    url = f"/v1/party-games/{game}/results"
    body = result_body()
    first = c.post(
        "/v1/me/game-results" if change == "generic" else url,
        headers=u["bob"],
        json=body,
    )
    assert first.status_code == 201
    actor = "bob"
    expected = 200 if change is None else 409
    if change == "score":
        body["score"] = 9
    if change == "data":
        body["data"] = {"a": 2}
    if change == "placement":
        body["placement"] = 1
    if change == "game":
        url = f"/v1/party-games/{uuid4()}/results"
        expected = 404
    if change == "foreign":
        actor = "alice"
        expected = 404
    with connect(path) as db:
        db.execute(
            "UPDATE party_members SET left_at=? WHERE user_id='auth0|bob'",
            (now[0].isoformat(),),
        )
        db.execute(
            "UPDATE parties SET state='CLOSED',closed_at=?", (now[0].isoformat(),)
        )
        db.execute(
            "UPDATE party_games SET state='CLOSED',closed_at=?", (now[0].isoformat(),)
        )
    if change is None:
        body.update(measurement_id=None, placement=None)
    r = c.post(url, headers=u[actor], json=body)
    assert r.status_code == expected, r.text
    if expected == 200:
        assert r.json() == first.json()


@pytest.mark.parametrize(
    "case,expected",
    [
        ("left", 404),
        ("closed_game", 409),
        ("closed_party", 409),
        ("mismatch", 422),
        ("duplicate", 409),
    ],
)
def test_new_completion_requires_eligible_instance(party_world, case, expected):
    c, u, _, now, path, _ = party_world
    game = create_game(party_world).json()["game_instance_id"]
    url = f"/v1/party-games/{game}/results"
    body = result_body()
    if case == "duplicate":
        assert c.post(url, headers=u["bob"], json=result_body()).status_code == 201
    with connect(path) as db:
        if case == "left":
            db.execute(
                "UPDATE party_members SET left_at=? WHERE user_id='auth0|bob'",
                (now[0].isoformat(),),
            )
        if case == "closed_game":
            db.execute(
                "UPDATE party_games SET state='CLOSED',closed_at=?",
                (now[0].isoformat(),),
            )
        if case == "closed_party":
            db.execute(
                "UPDATE parties SET state='CLOSED',closed_at=?", (now[0].isoformat(),)
            )
    if case == "mismatch":
        body["game_id"] = "pictionary"
    r = c.post(url, headers=u["bob"], json=body)
    assert r.status_code == expected, r.text
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM game_results").fetchone()[0] == (
            case == "duplicate"
        )


def seed_measurement(w, *, user="bob", device="one", session_delta=0, received_delta=0):
    _, _, _, now, path, _ = w
    mid, sid = str(uuid4()), str(uuid4())
    stamp = now[0].isoformat()
    payload = {
        "measurement_id": mid,
        "session_id": sid,
        "raw": {"sensor": "mq3", "value": 1200, "unit": "adc_counts"},
        "breath_duration_ms": 2500,
        "source": "simulator",
        "measured_at": None,
    }
    with connect(path) as db:
        db.execute(
            "INSERT INTO sessions VALUES (?,?,?,'COMPLETE',?,?,?)",
            (
                sid,
                device,
                "auth0|" + user,
                (now[0] + timedelta(seconds=session_delta)).isoformat(),
                stamp,
                stamp,
            ),
        )
        db.execute(
            "INSERT INTO measurements VALUES (?,?,?,?,?,?)",
            (
                mid,
                sid,
                device,
                "auth0|" + user,
                json.dumps(payload),
                (now[0] + timedelta(seconds=received_delta)).isoformat(),
            ),
        )
    return mid


@pytest.mark.parametrize(
    "case,expected",
    [
        ("valid", 201),
        ("foreign", 404),
        ("unknown", 404),
        ("device", 422),
        ("old", 422),
        ("future", 422),
        ("unbound", 422),
    ],
)
def test_measurement_link_requires_owned_compatible_check(party_world, case, expected):
    c, u, _, _, path, _ = party_world
    if case == "unbound":
        with connect(path) as db:
            db.execute("DELETE FROM party_devices")
    game = create_game(party_world).json()["game_instance_id"]
    mid = seed_measurement(
        party_world,
        user="alice" if case == "foreign" else "bob",
        device="two" if case == "device" else "one",
        session_delta=-1 if case == "old" else 0,
        received_delta=1 if case == "future" else 0,
    )
    body = result_body(measurement_id=str(uuid4()) if case == "unknown" else mid)
    r = c.post(f"/v1/party-games/{game}/results", headers=u["bob"], json=body)
    assert r.status_code == expected, r.text
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM game_results").fetchone()[0] == (
            expected == 201
        )
        assert db.execute("SELECT COUNT(*) FROM measurements").fetchone()[0] == 1


def test_measurement_cannot_reward_another_game(party_world):
    c, u, *_ = party_world
    game = create_game(party_world).json()["game_instance_id"]
    mid = seed_measurement(party_world)
    assert (
        c.post(
            f"/v1/party-games/{game}/results",
            headers=u["bob"],
            json=result_body(measurement_id=mid),
        ).status_code
        == 201
    )
    c.post(f"/v1/party-games/{game}/close", headers=u["alice"], json={})
    second = create_game(party_world).json()["game_instance_id"]
    r = c.post(
        f"/v1/party-games/{second}/results",
        headers=u["bob"],
        json=result_body(measurement_id=mid),
    )
    assert r.status_code == 409, r.text
    assert r.json()["error"]["code"] == "idempotency_conflict"
    foreign = c.post(
        f"/v1/party-games/{second}/results",
        headers=u["alice"],
        json=result_body(measurement_id=mid),
    )
    assert foreign.status_code == 404, foreign.text


@pytest.mark.parametrize("mode", ["identical", "changed", "new_id"])
def test_concurrent_completion_awards_once(party_world, mode):
    from concurrent.futures import ThreadPoolExecutor

    c, u, _, _, path, _ = party_world
    game = create_game(party_world).json()["game_instance_id"]
    url = f"/v1/party-games/{game}/results"
    first = result_body()
    second = {**first}
    if mode == "changed":
        second["score"] = 9
    if mode == "new_id":
        second["result_id"] = str(uuid4())
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(
            pool.map(
                lambda body: c.post(url, headers=u["bob"], json=body), [first, second]
            )
        )
    assert sorted(r.status_code for r in responses) == (
        [200, 201] if mode == "identical" else [201, 409]
    )
    with connect(path) as db:
        assert db.execute(
            "SELECT COUNT(*),SUM(awarded_points) FROM game_results"
        ).fetchone()[:] == (1, 10)
        assert (
            db.execute("SELECT COUNT(*) FROM party_result_context").fetchone()[0] == 1
        )


def test_context_failure_rolls_back_ledger(party_world):
    import sqlite3

    c, u, _, _, path, _ = party_world
    game = create_game(party_world).json()["game_instance_id"]
    with connect(path) as db:
        db.execute(
            "CREATE TRIGGER fail_context BEFORE INSERT ON party_result_context BEGIN SELECT RAISE(ABORT,'synthetic failure'); END"
        )
    with pytest.raises(sqlite3.IntegrityError, match="synthetic failure"):
        c.post(f"/v1/party-games/{game}/results", headers=u["bob"], json=result_body())
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM game_results").fetchone()[0] == 0
        assert (
            db.execute("SELECT COUNT(*) FROM party_result_context").fetchone()[0] == 0
        )


@pytest.mark.parametrize(
    "field,value",
    [
        ("placement", True),
        ("placement", 1.5),
        ("placement", "1"),
        ("placement", 0),
        ("placement", 10001),
        ("measurement_id", "bad"),
        ("owner", "bob"),
        ("score", True),
        ("game_id", 123),
    ],
)
def test_strict_result_validation(party_world, field, value):
    c, u, *_ = party_world
    game = create_game(party_world).json()["game_instance_id"]
    assert (
        c.post(
            f"/v1/party-games/{game}/results",
            headers=u["bob"],
            json=result_body(**{field: value}),
        ).status_code
        == 422
    )


def test_replay_survives_app_restart(party_world):
    from fastapi.testclient import TestClient

    from kickbac.app import create_app
    from kickbac.settings import Settings

    c, u, _, now, path, _ = party_world
    game = create_game(party_world).json()["game_instance_id"]
    body = result_body(measurement_id=seed_measurement(party_world))
    url = f"/v1/party-games/{game}/results"
    first = c.post(url, headers=u["bob"], json=body)
    c.post(f"/v1/party-games/{game}/close", headers=u["alice"], json={})
    with connect(path) as db:
        db.execute(
            "UPDATE party_members SET left_at=? WHERE user_id='auth0|bob'",
            (now[0].isoformat(),),
        )
    app = create_app(Settings(path), c.app.state.verifier, clock=lambda: now[0])
    with TestClient(app) as restarted:
        replay = restarted.post(url, headers=u["bob"], json=body)
        assert replay.status_code == 200, replay.text
        assert replay.json() == first.json()


def test_generic_uuid_cannot_probe_foreign_game(party_world):
    c, u, _, now, path, _ = party_world
    game = create_game(party_world).json()["game_instance_id"]
    body = result_body()
    assert c.post("/v1/me/game-results", headers=u["bob"], json=body).status_code == 201
    with connect(path) as db:
        db.execute("DELETE FROM party_members WHERE user_id='auth0|bob'")
    assert (
        c.post(
            f"/v1/party-games/{game}/results", headers=u["bob"], json=body
        ).status_code
        == 404
    )


def test_completion_writes_ledger_and_context(party_world):
    c, u, _, _, path, _ = party_world
    game = create_game(party_world).json()["game_instance_id"]
    body = result_body(placement=1)
    r = c.post(f"/v1/party-games/{game}/results", headers=u["bob"], json=body)
    assert r.status_code == 201, r.text
    assert r.json() == {
        k: v
        for k, v in {
            **body,
            "user_id": "auth0|bob",
            "awarded_points": 10,
            "scoring_policy": "completion_v1",
            "source": "client_reported",
            "created_at": party_world[3][0].isoformat(),
        }.items()
        if k != "placement"
    }
    with connect(path) as db:
        row = db.execute("SELECT * FROM party_result_context").fetchone()
        assert dict(row) == {
            "result_id": body["result_id"],
            "game_instance_id": game,
            "user_id": "auth0|bob",
            "measurement_id": None,
            "placement": 1,
        }
    assert c.get("/v1/me/stats", headers=u["bob"]).json()["total_points"] == 10
    assert c.get("/v1/me/game-results", headers=u["bob"]).json()["items"] == [r.json()]
