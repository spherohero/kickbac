from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from threading import Barrier

import pytest
from fastapi.testclient import TestClient
from test_games import result

from kickbac.app import create_app
from kickbac.db import connect
from kickbac.settings import Settings


@pytest.mark.parametrize(
    "method,path",
    [
        ("POST", "/v1/me/game-results"),
        ("GET", "/v1/me/game-results"),
        ("GET", "/v1/me/stats"),
    ],
)
@pytest.mark.parametrize(
    "credential", ["missing", "invalid", "device", "expired", "wrong_audience", "m2m"]
)
def test_games_require_user_access_token(world, identity, method, path, credential):
    c, _, devices, _, db_path = world
    _, token = identity
    headers = {
        "missing": {},
        "invalid": {"Authorization": "Bearer invalid"},
        "device": devices["one"],
        "expired": {"Authorization": "Bearer " + token(exp=1)},
        "wrong_audience": {"Authorization": "Bearer " + token(aud="other")},
        "m2m": {"Authorization": "Bearer " + token(gty="client-credentials")},
    }[credential]
    response = c.request(
        method,
        path,
        headers=headers,
        **({"json": result()} if method == "POST" else {}),
    )
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"
    assert response.headers["cache-control"] == "no-store"
    with connect(db_path) as db:
        assert db.execute("SELECT COUNT(*) FROM game_results").fetchone()[0] == 0


@pytest.mark.parametrize(
    "method,path",
    [
        ("POST", "/v1/me/game-results"),
        ("GET", "/v1/me/game-results"),
        ("GET", "/v1/me/stats"),
    ],
)
def test_identity_provider_outage_is_503_and_private(world, method, path):
    from kickbac.errors import fail

    c, users, *_ = world

    def unavailable(token):
        fail(503, "auth_unavailable")

    c.app.state.verifier = unavailable
    response = c.request(
        method,
        path,
        headers=users["alice"],
        **({"json": result()} if method == "POST" else {}),
    )
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "auth_unavailable"
    assert response.headers["cache-control"] == "no-store"


def test_result_creation_uses_server_utc_and_invalid_clock_rolls_back(world):
    from datetime import UTC, datetime, timezone

    c, users, _, now, path = world
    now[0] = datetime(2026, 10, 17, 12, 30, tzinfo=timezone(timedelta(hours=-4)))
    created = c.post("/v1/me/game-results", headers=users["alice"], json=result())
    assert created.status_code == 201
    assert created.json()["created_at"] == now[0].astimezone(UTC).isoformat()
    now[0] = datetime(2026, 10, 17)
    with TestClient(c.app, raise_server_exceptions=False) as safe:
        rejected = safe.post(
            "/v1/me/game-results", headers=users["alice"], json=result()
        )
    assert rejected.status_code == 500
    assert rejected.headers["cache-control"] == "no-store"
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM game_results").fetchone()[0] == 1


@pytest.mark.parametrize(
    "changes",
    [
        {"game_id": "pictionary"},
        {"score": 21},
        {"outcome": "draw"},
        {"data": {"round": 2}},
    ],
)
def test_immutable_id_rejects_changed_accepted_fields_and_hides_foreign_owner(
    world, changes
):
    c, users, *_ = world
    body = result()
    original = c.post("/v1/me/game-results", headers=users["alice"], json=body)
    assert original.status_code == 201
    for owner, status, code in [
        ("alice", 409, "idempotency_conflict"),
        ("bob", 404, "not_found"),
    ]:
        response = c.post(
            "/v1/me/game-results", headers=users[owner], json={**body, **changes}
        )
        assert response.status_code == status
        assert response.json()["error"]["code"] == code
        assert response.headers["cache-control"] == "no-store"
        assert "auth0|alice" not in response.text
    assert c.get("/v1/me/game-results", headers=users["alice"]).json()["items"] == [
        original.json()
    ]
    assert c.get("/v1/me/stats", headers=users["bob"]).json()["total_points"] == 0


def test_canonical_replay_preserves_timestamp_and_uuid(world):
    c, users, _, now, _ = world
    body = result(data={"z": {"b": 1, "a": 2}, "a": "😀"})
    first = c.post("/v1/me/game-results", headers=users["alice"], json=body)
    assert first.status_code == 201
    now[0] += timedelta(days=1)
    retry = {
        **body,
        "result_id": body["result_id"].upper(),
        "data": {"a": "😀", "z": {"a": 2, "b": 1}},
    }
    replay = c.post("/v1/me/game-results", headers=users["alice"], json=retry)
    assert replay.status_code == 200
    assert replay.json() == first.json()


@pytest.mark.parametrize("different", [False, True])
def test_concurrent_posts_award_once(world, different):
    c, users, _, _, path = world
    body = result()
    count = 6
    gate = Barrier(count)

    def post(index):
        gate.wait(timeout=10)
        return c.post(
            "/v1/me/game-results",
            headers=users["alice"],
            json={**body, "score": index if different else 20},
        )

    with ThreadPoolExecutor(count) as pool:
        responses = list(pool.map(post, range(count)))
    codes = sorted(response.status_code for response in responses)
    assert codes == (
        [201] + [409] * (count - 1) if different else [200] * (count - 1) + [201]
    )
    successes = [r.json() for r in responses if r.status_code < 300]
    assert all(row == successes[0] for row in successes)
    with connect(path) as db:
        row = db.execute(
            "SELECT COUNT(*),SUM(awarded_points) FROM game_results"
        ).fetchone()
        assert tuple(row) == (1, 10)
    assert c.get("/v1/me/stats", headers=users["alice"]).json()["total_points"] == 10


def test_stats_aggregate_per_game_without_profile_or_phone_linking(world, identity):
    c, users, _, _, path = world
    for game, score, outcome in [
        ("trivia", 30, "win"),
        ("trivia", 100, "loss"),
        ("pictionary", 3, "draw"),
        ("boggle", 2, "completed"),
    ]:
        assert (
            c.post(
                "/v1/me/game-results",
                headers=users["alice"],
                json=result(game_id=game, score=score, outcome=outcome),
            ).status_code
            == 201
        )
    expected = {
        "user_id": "auth0|alice",
        "total_points": 40,
        "games_played": 4,
        "wins": 1,
        "per_game": [
            {
                "game_id": "boggle",
                "total_points": 10,
                "games_played": 1,
                "wins": 0,
                "best_score": 2,
            },
            {
                "game_id": "pictionary",
                "total_points": 10,
                "games_played": 1,
                "wins": 0,
                "best_score": 3,
            },
            {
                "game_id": "trivia",
                "total_points": 20,
                "games_played": 2,
                "wins": 1,
                "best_score": 100,
            },
        ],
    }
    assert c.get("/v1/me/stats", headers=users["alice"]).json() == expected
    _, token = identity

    def same_phone(sub):
        return {
            "Authorization": "Bearer " + token(sub=sub, phone_number="+15500000000")
        }

    assert c.get("/v1/me/stats", headers=same_phone("auth0|alice")).json() == expected
    assert (
        c.get("/v1/me/stats", headers=same_phone("sms|different")).json()[
            "total_points"
        ]
        == 0
    )
    assert (
        c.put(
            "/v1/me/profile",
            headers=users["alice"],
            json={"display_name": "Edited", "profile_picture": None},
        ).status_code
        == 200
    )
    assert (
        c.put(
            "/v1/me/profile",
            headers=users["alice"],
            json={
                "display_name": "Edited",
                "profile_picture": None,
                "total_points": 9999,
            },
        ).status_code
        == 422
    )
    with TestClient(create_app(Settings(path), c.app.state.verifier)) as restarted:
        assert (
            restarted.get("/v1/me/stats", headers=same_phone("auth0|alice")).json()
            == expected
        )
        assert (
            len(
                restarted.get(
                    "/v1/me/game-results", headers=same_phone("auth0|alice")
                ).json()["items"]
            )
            == 4
        )


def test_readonly_game_gets_and_posts_do_not_mutate_other_domains(world, monkeypatch):
    import kickbac.games as games

    c, users, _, now, path = world
    assert (
        c.put(
            "/v1/me/profile",
            headers=users["alice"],
            json={"display_name": "Kept", "profile_picture": None},
        ).status_code
        == 200
    )
    assert (
        c.post("/v1/devices/one/sessions", headers=users["alice"], json={}).status_code
        == 201
    )
    now[0] += timedelta(seconds=61)
    with connect(path) as db:
        before = {
            table: [tuple(row) for row in db.execute("SELECT * FROM " + table)]
            for table in ["devices", "profiles", "sessions", "measurements"]
        }
    assert (
        c.post("/v1/me/game-results", headers=users["alice"], json=result()).status_code
        == 201
    )
    with connect(path) as db:
        for table, rows in before.items():
            assert [tuple(row) for row in db.execute("SELECT * FROM " + table)] == rows
        dump = list(db.iterdump())
    real_connect = games.connect

    def readonly(path):
        db = real_connect(path)
        # No write opcode may be authorized, including session-expiry writes.
        import sqlite3

        db.set_authorizer(
            lambda action, *args: (
                sqlite3.SQLITE_DENY
                if action
                in (sqlite3.SQLITE_INSERT, sqlite3.SQLITE_UPDATE, sqlite3.SQLITE_DELETE)
                else sqlite3.SQLITE_OK
            )
        )
        return db

    monkeypatch.setattr(games, "connect", readonly)
    for owner in ("alice", "bob"):
        for endpoint in ("/v1/me/game-results", "/v1/me/stats"):
            assert c.get(endpoint, headers=users[owner]).status_code == 200
    with connect(path) as db:
        assert list(db.iterdump()) == dump
