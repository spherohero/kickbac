import json

import pytest
from test_games import result

from kickbac.db import connect


@pytest.mark.parametrize(
    "changes",
    [
        {"score": True},
        {"score": 1.0},
        {"score": "2"},
        {"score": -1},
        {"score": 1000001},
        {"game_id": True},
        {"game_id": ""},
        {"game_id": "Trivia"},
        {"game_id": "a" * 65},
        {"game_id": "a\n"},
        {"game_id": "a.b"},
        {"result_id": "not-a-uuid"},
        {"outcome": "winner"},
        {"data": None},
        {"data": []},
        {"user_id": "auth0|bob"},
        {"awarded_points": 500},
        {"phone": "+15500000000"},
        {"source": "verified"},
        {"scoring_policy": "other"},
        {"created_at": "2000-01-01T00:00:00Z"},
    ],
)
def test_reject_invalid_fields_before_storage(world, changes):
    c, users, _, _, path = world
    response = c.post(
        "/v1/me/game-results", headers=users["alice"], json=result(**changes)
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM game_results").fetchone()[0] == 0


@pytest.mark.parametrize("field", ["result_id", "game_id", "score", "outcome", "data"])
def test_all_fields_required(world, field):
    c, users, *_ = world
    body = result()
    del body[field]
    assert (
        c.post("/v1/me/game-results", headers=users["alice"], json=body).status_code
        == 422
    )


@pytest.mark.parametrize(
    "data",
    [
        {"": 1},
        {"k" * 65: 1},
        {"a": "x" * 513},
        {"a": list(range(65))},
        {"a": {"b": {"c": {"d": {"e": 1}}}}},
        {str(i): i for i in range(128)},
        {"a": 1000000000001},
        {"a": -1000000000001},
        {"a": 1e100},
        {"a": float("nan")},
        {"a": float("inf")},
        {"a": float("-inf")},
        {"a": "\ud800"},
        {"\udfff": 1},
    ],
)
def test_reject_invalid_json_data(world, data):
    c, users, *_ = world
    # JSON's non-standard NaN/Infinity are deliberately sent as raw bytes.
    response = c.post(
        "/v1/me/game-results",
        headers={**users["alice"], "Content-Type": "application/json"},
        content=json.dumps(result(data=data)),
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


@pytest.mark.parametrize(
    "data", [{1: "not-string"}, {"a": (1, 2)}, {"a": {1, 2}}, {"a": b"bytes"}]
)
def test_python_model_rejects_non_json_without_coercion(data):
    from pydantic import ValidationError

    from kickbac.games import GameResultPut

    with pytest.raises(ValidationError):
        GameResultPut(**result(data=data))


@pytest.mark.parametrize(
    "data",
    [
        {"k" * 64: "x" * 512},
        {"a": list(range(64))},
        {"a": {"b": {"c": {"d": 1}}}},
        {str(i): i for i in range(127)},
        {"a": 1e12, "b": -1e12, "c": False},
    ],
)
def test_accept_json_boundary_values(world, data):
    c, users, *_ = world
    response = c.post(
        "/v1/me/game-results",
        headers=users["alice"],
        json=result(data=data, score=1000000, game_id="a" * 64),
    )
    assert response.status_code == 201
    assert response.json()["data"] == data


def test_data_byte_cap_is_canonical_utf8_and_size_errors_are_413(world):
    c, users, *_ = world
    # Seven full strings and one shorter value yield exactly 4096 canonical bytes.
    data = {str(i): "x" * 512 for i in range(7)}
    data["7"] = "x" * (
        4096
        - len(
            json.dumps(
                {**data, "7": ""}, sort_keys=True, separators=(",", ":")
            ).encode()
        )
    )
    assert len(json.dumps(data, sort_keys=True, separators=(",", ":")).encode()) == 4096
    assert (
        c.post(
            "/v1/me/game-results", headers=users["alice"], json=result(data=data)
        ).status_code
        == 201
    )
    data["7"] += "x"
    response = c.post(
        "/v1/me/game-results", headers=users["alice"], json=result(data=data)
    )
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "payload_too_large"
    unicode_data = {str(i): "😀" * 256 for i in range(4)}
    assert (
        c.post(
            "/v1/me/game-results",
            headers=users["alice"],
            json=result(data=unicode_data),
        ).status_code
        == 413
    )


def test_valid_minimum_score_and_future_game(world):
    c, users, *_ = world
    response = c.post(
        "/v1/me/game-results",
        headers=users["alice"],
        json=result(score=0, game_id="future_game-2", outcome="completed"),
    )
    assert response.status_code == 201
    assert response.json()["awarded_points"] == 10


@pytest.mark.parametrize(
    "raw",
    [
        b'{"result_id":"00000000-0000-0000-0000-000000000001","game_id":"trivia","score":1,"outcome":"win","data":{"a":'
        + b"[" * 2000
        + b"0"
        + b"]" * 2000
        + b"}}",
        b'{"data":{"a":' + b"9" * 5000 + b"}}",
        b'{"data":{"a":"\xff"}}',
    ],
    ids=["parser-depth", "huge-integer", "invalid-utf8"],
)
def test_pathological_raw_json_is_generic_validation_error(world, raw):
    c, users, *_ = world
    response = c.post(
        "/v1/me/game-results",
        headers={**users["alice"], "Content-Type": "application/json"},
        content=raw,
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"
