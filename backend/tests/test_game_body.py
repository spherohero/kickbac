import asyncio
import json

import pytest
from fastapi.testclient import TestClient
from starlette.responses import Response
from test_games import result

from kickbac.db import connect
from kickbac.profile_body import ProfileBodyLimit


@pytest.mark.parametrize("path", ["/v1/me/game-results", "/v1/me/stats"])
def test_private_cache_on_success_auth_validation_and_internal_errors(world, path):
    c, users, _, _, db_path = world
    for response in [
        c.get(path, headers=users["alice"]),
        c.get(path),
        c.get(path + "?limit=0", headers=users["alice"]),
    ]:
        assert response.headers.get("cache-control") == "no-store"
    with TestClient(c.app, raise_server_exceptions=False) as safe:
        with connect(db_path) as db:
            db.execute("DROP TABLE game_results")
        response = safe.get(path, headers=users["alice"])
    assert response.status_code == 500
    assert response.headers.get("cache-control") == "no-store"
    assert response.json() == {
        "error": {"code": "internal_error", "message": "Internal server error."}
    }


@pytest.mark.parametrize(
    "length",
    [None, b"1", b"32769", b"9" * 10000],
    ids=["missing", "false", "oversize", "huge"],
)
def test_game_stream_cap_even_missing_or_lying_content_length(length):
    messages = []
    forwarded = []
    chunks = iter(
        [
            {"type": "http.request", "body": b"x" * 17000, "more_body": True},
            {"type": "http.request", "body": b"x" * 17000, "more_body": False},
        ]
    )

    async def receive():
        return next(chunks)

    async def send(message):
        messages.append(message)

    async def inner(scope, receive, send):
        forwarded.append(True)
        await Response()(scope, receive, send)

    scope = {
        "type": "http",
        "path": "/v1/me/game-results",
        "method": "POST",
        "headers": [] if length is None else [(b"content-length", length)],
    }
    asyncio.run(ProfileBodyLimit(inner)(scope, receive, send))
    assert not forwarded
    assert messages[0]["status"] == 413
    assert (b"cache-control", b"no-store") in messages[0]["headers"]
    assert json.loads(messages[1]["body"])["error"]["code"] == "payload_too_large"


def test_game_body_boundary_and_generic_bad_json(world):
    c, users, *_ = world
    valid = json.dumps(result()).encode()
    response = c.post(
        "/v1/me/game-results",
        headers={**users["alice"], "Content-Type": "application/json"},
        content=valid + b" " * (32768 - len(valid)),
    )
    assert response.status_code == 201
    too_big = c.post(
        "/v1/me/game-results", headers=users["alice"], content=b"x" * 32769
    )
    assert too_big.status_code == 413
    assert too_big.headers.get("cache-control") == "no-store"
    invalid = c.post(
        "/v1/me/game-results",
        headers=users["alice"],
        content=b'{"private-invalid-marker":',
    )
    assert invalid.status_code == 422
    assert invalid.headers.get("cache-control") == "no-store"
    assert "private-invalid-marker" not in invalid.text


def test_result_storage_error_cache_and_rollback(world):
    c, users, _, _, path = world
    with connect(path) as db:
        db.execute(
            "CREATE TRIGGER fail_result AFTER INSERT ON game_results BEGIN SELECT RAISE(ABORT,'private-db-marker'); END"
        )
    with TestClient(c.app, raise_server_exceptions=False) as safe:
        response = safe.post(
            "/v1/me/game-results", headers=users["alice"], json=result()
        )
    assert response.status_code == 500
    assert response.headers.get("cache-control") == "no-store"
    assert "private-db-marker" not in response.text
    assert c.get("/v1/me/stats", headers=users["alice"]).json()["total_points"] == 0
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM game_results").fetchone()[0] == 0
