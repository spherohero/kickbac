from datetime import timedelta
from uuid import UUID, uuid4

import pytest
from test_party_games import party_world as party_world

from kickbac.db import connect


def body(**changes):
    return {"check_in_id": str(uuid4()), "device_id": "one", **changes}


def post(w, payload, user="bob", party=None):
    c, u, _, _, _, pid = w
    return c.post(
        f"/v1/parties/{party or pid}/check-ins", headers=u[user], json=payload
    )


@pytest.mark.parametrize(
    "case,expected",
    [
        ("exact", 200),
        ("changed", 409),
        ("foreign", 404),
        ("wrong_route", 404),
        ("historical_route", 409),
    ],
)
def test_retry_identity_before_current_state(party_world, case, expected):
    c, u, _, now, path, party = party_world
    payload = body()
    first = post(party_world, payload).json()
    other = str(uuid4())
    with connect(path) as db:
        db.execute("UPDATE sessions SET status='CANCELLED'")
        db.execute("UPDATE party_members SET left_at=?", (now[0].isoformat(),))
        db.execute(
            "UPDATE parties SET state='CLOSED',closed_at=?", (now[0].isoformat(),)
        )
        db.execute("DELETE FROM party_devices")
        if case == "historical_route":
            db.execute(
                "INSERT INTO parties VALUES (?,'auth0|bob','Other','JKLMNPQR',?,'OPEN',NULL)",
                (other, now[0].isoformat()),
            )
            db.execute(
                "INSERT INTO party_members VALUES (?,'auth0|bob',?,?)",
                (other, now[0].isoformat(), now[0].isoformat()),
            )
    payload["game_instance_id"] = None
    if case == "changed":
        payload["device_id"] = "two"
    r = post(
        party_world,
        payload,
        user="alice" if case == "foreign" else "bob",
        party=other if case in ("wrong_route", "historical_route") else party,
    )
    assert r.status_code == expected, r.text
    if expected == 200:
        first["session"]["status"] = "CANCELLED"
        assert r.json() == first
    elif expected == 409:
        assert r.json()["error"]["code"] == "idempotency_conflict"


@pytest.mark.parametrize(
    "case,expected,code",
    [
        ("nonmember", 404, "not_found"),
        ("left", 404, "not_found"),
        ("unknown_party", 404, "not_found"),
        ("closed", 409, "invalid_state"),
        ("unassigned", 404, "not_found"),
        ("wrong_device", 404, "not_found"),
        ("unknown_device", 404, "not_found"),
    ],
)
def test_new_attempt_requires_active_bound_party(party_world, case, expected, code):
    _, _, _, now, path, _ = party_world
    payload = body(
        device_id="two"
        if case == "wrong_device"
        else "missing"
        if case == "unknown_device"
        else "one"
    )
    with connect(path) as db:
        if case == "nonmember":
            db.execute("DELETE FROM party_members WHERE user_id='auth0|bob'")
        if case == "left":
            db.execute(
                "UPDATE party_members SET left_at=? WHERE user_id='auth0|bob'",
                (now[0].isoformat(),),
            )
        if case == "closed":
            db.execute(
                "UPDATE parties SET state='CLOSED',closed_at=?", (now[0].isoformat(),)
            )
        if case == "unassigned":
            db.execute("DELETE FROM party_devices")
    r = post(
        party_world, payload, party=str(uuid4()) if case == "unknown_party" else None
    )
    assert r.status_code == expected, r.text
    assert r.json()["error"]["code"] == code
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM sessions").fetchone()[0] == 0
        assert db.execute("SELECT COUNT(*) FROM party_check_ins").fetchone()[0] == 0


@pytest.mark.parametrize(
    "case,expected",
    [
        ("valid", 201),
        ("missing", 409),
        ("closed", 409),
        ("null_device", 409),
        ("device", 409),
        ("party", 409),
    ],
)
def test_game_snapshot_must_match(party_world, case, expected):
    from test_party_games import create_game

    _, _, _, now, path, _ = party_world
    game = create_game(party_world).json()["game_instance_id"]
    with connect(path) as db:
        if case == "closed":
            db.execute(
                "UPDATE party_games SET state='CLOSED',closed_at=?",
                (now[0].isoformat(),),
            )
        if case == "null_device":
            db.execute("UPDATE party_games SET device_id=NULL")
        if case == "device":
            db.execute("UPDATE party_games SET device_id='two'")
        if case == "party":
            other = str(uuid4())
            db.execute(
                "INSERT INTO parties VALUES (?,'other-host','Other','JKLMNPQR',?,'OPEN',NULL)",
                (other, now[0].isoformat()),
            )
            db.execute("UPDATE party_games SET party_id=?", (other,))
    r = post(
        party_world, body(game_instance_id=str(uuid4()) if case == "missing" else game)
    )
    assert r.status_code == expected, r.text
    if expected == 201:
        assert r.json()["game_instance_id"] == game
    else:
        assert r.json()["error"]["code"] == "invalid_state"


@pytest.mark.parametrize("kind", ["ordinary_own", "check_in_own", "ordinary_foreign"])
def test_any_active_session_busy_without_consuming_id(party_world, kind):
    c, u, _, _, path, _ = party_world
    if kind == "check_in_own":
        first = post(party_world, body()).json()["session"]
    else:
        first = c.post(
            "/v1/devices/one/sessions",
            headers=u["alice" if kind == "ordinary_foreign" else "bob"],
            json={},
        ).json()
    payload = body()
    r = post(party_world, payload)
    assert r.status_code == 409, r.text
    assert r.json()["error"]["code"] == "device_busy"
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM sessions").fetchone()[0] == 1
    c.post(
        f"/v1/sessions/{first['id']}/cancel",
        headers=u["alice" if kind == "ordinary_foreign" else "bob"],
        json={},
    )
    assert post(party_world, payload).status_code == 201


@pytest.mark.parametrize("value", ["", "bad slug", "a/b", "a" * 65, True, 12, None])
def test_strict_device_slug(party_world, value):
    r = post(party_world, body(device_id=value))
    assert r.status_code == 422, r.text


def test_upload_after_leave_and_game_close_private_history_current_state(party_world):
    from test_party_games import create_game

    c, u, d, now, path, party = party_world
    game = create_game(party_world).json()["game_instance_id"]
    payload = body(game_instance_id=game)
    first = post(party_world, payload).json()
    sid = first["session"]["id"]
    assert (
        c.post(f"/v1/party-games/{game}/close", headers=u["alice"], json={}).status_code
        == 200
    )
    assert (
        c.post(f"/v1/parties/{party}/leave", headers=u["bob"], json={}).status_code
        == 200
    )
    upload = {
        "measurement_id": str(uuid4()),
        "session_id": sid,
        "raw": {"sensor": "mq3", "value": 1200, "unit": "adc_counts"},
        "breath_duration_ms": 2500,
        "source": "simulator",
        "measured_at": None,
    }
    r = c.post("/v1/device/measurements", headers=d["one"], json=upload)
    assert r.status_code == 201, r.text
    replay = post(party_world, payload)
    assert replay.status_code == 200, replay.text
    assert replay.json()["session"]["status"] == "COMPLETE"
    assert replay.json()["session"]["measurement"] == r.json()
    with connect(path) as db:
        before = list(db.iterdump())
    history = c.get("/v1/me/check-ins", headers=u["bob"])
    assert history.status_code == 200, history.text
    assert history.headers["cache-control"] == "no-store"
    assert history.json() == {
        "items": [replay.json()],
        "limit": 50,
        "offset": 0,
        "has_more": False,
    }
    assert c.get("/v1/me/check-ins", headers=u["alice"]).json()["items"] == []
    with connect(path) as db:
        assert list(db.iterdump()) == before


def test_check_in_openapi_explicit_typed_statuses(world):
    spec = world[0].get("/openapi.json").json()
    op = spec["paths"]["/v1/parties/{party_id}/check-ins"]["post"]
    for status, model in [
        ("200", "CheckInResponse"),
        ("201", "CheckInResponse"),
        ("413", "ErrorEnvelope"),
        ("422", "ErrorEnvelope"),
    ]:
        assert op["responses"][status]["content"]["application/json"]["schema"] == {
            "$ref": "#/components/schemas/" + model
        }


def test_create_atomic_owned_session_and_unchanged_poll(party_world):
    c, u, d, now, path, party = party_world
    calls = []

    def clock():
        calls.append(1)
        return now[0]

    c.app.state.clock = clock
    payload = body()
    r = post(party_world, payload)
    assert r.status_code == 201, r.text
    assert len(calls) == 1
    result = r.json()
    session = result["session"]
    UUID(session["id"])
    assert result == {
        "check_in_id": payload["check_in_id"],
        "party_id": party,
        "game_instance_id": None,
        "session": session,
    }
    assert session == {
        "id": session["id"],
        "device_id": "one",
        "user_id": "auth0|bob",
        "status": "ARMED",
        "created_at": now[0].isoformat(),
        "expires_at": (now[0] + timedelta(seconds=60)).isoformat(),
        "completed_at": None,
        "measurement": None,
    }
    assert r.headers["cache-control"] == "no-store"
    poll = c.get("/v1/device/session", headers=d["one"]).json()
    assert poll["active_session"] == {
        k: session[k] for k in ["id", "device_id", "status", "expires_at"]
    }
    with connect(path) as db:
        assert tuple(db.execute("SELECT * FROM party_check_ins").fetchone()) == (
            payload["check_in_id"],
            session["id"],
            party,
            None,
            "auth0|bob",
            "one",
        )
        assert db.execute("SELECT COUNT(*) FROM game_results").fetchone()[0] == 0
