"""All inputs here are synthetic, including source=device validation cases."""

import json
from datetime import timedelta
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from test_manual_acquisition import manual_sample
from test_measurements import sample
from test_party_check_ins import body, post
from test_party_games import create_game
from test_party_games import party_world as party_world
from test_party_results import result_body

from kickbac.app import create_app
from kickbac.db import connect


@pytest.mark.parametrize("source", ["simulator", "device"])
def test_manual_retry_restart_expiry_conflicts_and_isolation(world, source):
    c, u, d, now, path = world
    sid = c.post("/v1/devices/one/sessions", headers=u["alice"], json={}).json()["id"]
    payload = {**manual_sample(sid), "source": source}
    assert (
        c.post("/v1/device/measurements", headers=d["two"], json=payload).status_code
        == 404
    )
    first = c.post("/v1/device/measurements", headers=d["one"], json=payload)
    assert first.status_code == 201
    now[0] += timedelta(seconds=70)
    app = create_app(c.app.state.settings, c.app.state.verifier, clock=lambda: now[0])
    with TestClient(app) as restarted:
        replay = restarted.post(
            "/v1/device/measurements", headers=d["one"], json=payload
        )
        assert replay.status_code == 200 and replay.content == first.content
        for change in [
            {"sample_duration_ms": 5001},
            {"raw": {"sensor": "mq3", "value": 1201, "unit": "adc_counts"}},
            {"source": "device" if source == "simulator" else "simulator"},
            {"measured_at": "2026-10-17T00:00:00Z"},
            {"session_id": str(uuid4())},
            {
                "breath_duration_ms": 2500,
                "acquisition_method": None,
                "sample_duration_ms": None,
            },
        ]:
            response = restarted.post(
                "/v1/device/measurements", headers=d["one"], json={**payload, **change}
            )
            assert response.status_code == 409
        assert (
            restarted.post(
                "/v1/device/measurements", headers=d["two"], json=payload
            ).status_code
            == 404
        )
        assert (
            restarted.post(
                "/v1/device/measurements",
                headers=d["one"],
                json={**payload, "measurement_id": str(uuid4())},
            ).status_code
            == 409
        )
        assert restarted.get("/v1/sessions/" + sid, headers=u["bob"]).status_code == 404
        assert restarted.get("/v1/measurements", headers=u["bob"]).json()["items"] == []
        assert (
            restarted.get("/v1/me/reading-summary", headers=u["bob"]).json()[
                "latest_measurement"
            ]
            is None
        )
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM measurements").fetchone()[0] == 1
        assert db.execute("SELECT payload FROM measurements").fetchone()[
            0
        ] == json.dumps(payload, sort_keys=True, separators=(",", ":"))


@pytest.mark.parametrize("state", ["expired", "cancelled"])
def test_manual_no_result_for_terminal_uncompleted_session(world, state):
    c, u, d, now, path = world
    sid = c.post("/v1/devices/one/sessions", headers=u["alice"], json={}).json()["id"]
    if state == "expired":
        now[0] += timedelta(seconds=60)
    else:
        c.post("/v1/sessions/" + sid + "/cancel", headers=u["alice"], json={})
    assert c.post(
        "/v1/device/measurements", headers=d["one"], json=manual_sample(sid)
    ).status_code == (410 if state == "expired" else 409)
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM measurements").fetchone()[0] == 0


@pytest.mark.parametrize(
    "change",
    [
        {"acquisition_method": None},
        {"acquisition_method": "unknown"},
        {"acquisition_method": True},
        {"acquisition_method": 1},
        {"sample_duration_ms": None},
        {"sample_duration_ms": True},
        {"sample_duration_ms": "5000"},
        {"sample_duration_ms": 5000.0},
        {"sample_duration_ms": 0},
        {"sample_duration_ms": 60001},
        {"breath_duration_ms": 1},
    ],
)
def test_invalid_manual_metadata_never_writes(world, change):
    c, u, d, _, path = world
    sid = c.post("/v1/devices/one/sessions", headers=u["alice"], json={}).json()["id"]
    response = c.post(
        "/v1/device/measurements",
        headers=d["one"],
        json={**manual_sample(sid), **change},
    )
    assert response.status_code == 422
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM measurements").fetchone()[0] == 0
        assert db.execute("SELECT status FROM sessions").fetchone()[0] == "ARMED"


@pytest.mark.parametrize(
    "field", ["breath_duration_ms", "acquisition_method", "sample_duration_ms"]
)
def test_manual_required_fields_cannot_be_omitted(world, field):
    c, u, d, _, _ = world
    sid = c.post("/v1/devices/one/sessions", headers=u["alice"], json={}).json()["id"]
    payload = manual_sample(sid)
    del payload[field]
    assert (
        c.post("/v1/device/measurements", headers=d["one"], json=payload).status_code
        == 422
    )


@pytest.mark.parametrize("duration", [1, 60000])
def test_manual_strict_duration_boundaries(world, duration):
    c, u, d, _, _ = world
    sid = c.post("/v1/devices/one/sessions", headers=u["alice"], json={}).json()["id"]
    assert (
        c.post(
            "/v1/device/measurements",
            headers=d["one"],
            json={**manual_sample(sid), "sample_duration_ms": duration},
        ).status_code
        == 201
    )


def test_original_legacy_payload_and_response_survive_restart_byte_exact(world):
    c, u, d, now, path = world
    sid = c.post("/v1/devices/one/sessions", headers=u["alice"], json={}).json()["id"]
    payload = sample(sid)
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    # Seed the exact pre-change stored payload without invoking the new upload model.
    with connect(path) as db:
        db.execute(
            "INSERT INTO measurements VALUES (?,?,?,?,?,?)",
            (
                payload["measurement_id"],
                sid,
                "one",
                "auth0|alice",
                canonical,
                now[0].isoformat(),
            ),
        )
        db.execute(
            "UPDATE sessions SET status='COMPLETE',completed_at=? WHERE id=?",
            (now[0].isoformat(), sid),
        )
    expected = {
        "id": payload["measurement_id"],
        "session_id": sid,
        "device_id": "one",
        "raw": payload["raw"],
        "breath_duration_ms": 2500,
        "source": "simulator",
        "measured_at": None,
        "received_at": now[0].isoformat(),
        "estimated_bac_percent": None,
    }
    before = c.get("/v1/measurements", headers=u["alice"]).content
    assert c.get("/v1/measurements", headers=u["alice"]).json()["items"] == [expected]
    app = create_app(c.app.state.settings, c.app.state.verifier, clock=lambda: now[0])
    with TestClient(app) as restarted:
        for metadata in [{}, {"acquisition_method": None, "sample_duration_ms": None}]:
            response = restarted.post(
                "/v1/device/measurements",
                headers=d["one"],
                json={**payload, **metadata},
            )
            assert response.status_code == 200 and response.json() == expected
        assert restarted.get("/v1/measurements", headers=u["alice"]).content == before
    with connect(path) as db:
        assert db.execute("SELECT payload FROM measurements").fetchone()[0] == canonical
        assert db.execute("PRAGMA user_version").fetchone()[0] == 6


def test_manual_metadata_in_check_in_retry_history_and_rich_game_history(party_world):
    c, u, d, _, _, _ = party_world
    game = create_game(party_world).json()["game_instance_id"]
    check_in = body(game_instance_id=game)
    first = post(party_world, check_in)
    assert first.status_code == 201
    sid = first.json()["session"]["id"]
    payload = manual_sample(sid)
    response = c.post("/v1/device/measurements", headers=d["one"], json=payload)
    assert response.status_code == 201
    measurement = response.json()
    assert post(party_world, check_in).json()["session"]["measurement"] == measurement
    assert (
        c.get("/v1/me/check-ins", headers=u["bob"]).json()["items"][0]["session"][
            "measurement"
        ]
        == measurement
    )
    result = c.post(
        f"/v1/party-games/{game}/results",
        headers=u["bob"],
        json=result_body(measurement_id=measurement["id"]),
    )
    assert result.status_code == 201, result.text
    assert (
        c.get("/v1/me/game-history", headers=u["bob"]).json()["items"][0]["measurement"]
        == measurement
    )
    assert c.get("/v1/me/check-ins", headers=u["alice"]).json()["items"] == []
    assert c.get("/v1/me/game-history", headers=u["alice"]).json()["items"] == []
