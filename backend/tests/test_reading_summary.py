"""Private SQL reading totals do not depend on profiles or loaded history pages."""

import sqlite3
from datetime import timedelta
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient

from kickbac.app import create_app
from kickbac.db import connect
from kickbac.settings import Settings

SUMMARY = "/v1/me/reading-summary"


def upload(client, user, device, measurement_id, measured_at=None):
    armed = client.post("/v1/devices/one/sessions", headers=user, json={})
    assert armed.status_code == 201
    body = {
        "measurement_id": str(measurement_id),
        "session_id": armed.json()["id"],
        "raw": {"sensor": "mq3", "value": 1200, "unit": "adc_counts"},
        "breath_duration_ms": 2500,
        "source": "simulator",
        "measured_at": measured_at,
    }
    response = client.post("/v1/device/measurements", headers=device, json=body)
    assert response.status_code == 201
    replay = client.post("/v1/device/measurements", headers=device, json=body)
    assert replay.status_code == 200
    assert replay.json() == response.json()
    return response.json()


def test_summary_counts_all_owned_uploads_before_profile_with_receipt_order(
    world, identity
):
    client, users, devices, now, path = world
    # Same receipt time: ID, not acquisition time or upload order, breaks ties.
    high = upload(client, users["alice"], devices["one"], UUID(int=2))
    upload(client, users["alice"], devices["one"], UUID(int=1), "2030-01-01T00:00:00Z")
    expected = {
        "user_id": "auth0|alice",
        "saved_readings": 2,
        "latest_measurement": high,
    }
    assert client.get(SUMMARY, headers=users["alice"]).json() == expected
    assert high["estimated_bac_percent"] is None
    assert client.get("/v1/measurements?limit=1", headers=users["alice"]).json()[
        "has_more"
    ]
    assert (
        client.get(
            SUMMARY + "?limit=0&offset=999&user_id=auth0|bob", headers=users["alice"]
        ).json()
        == expected
    )
    now[0] += timedelta(seconds=1)
    latest = upload(client, users["alice"], devices["one"], UUID(int=0))
    expected.update(saved_readings=3, latest_measurement=latest)
    foreign = upload(client, users["bob"], devices["one"], uuid4())
    assert client.get(SUMMARY, headers=users["alice"]).json() == expected
    assert client.get(SUMMARY, headers=users["bob"]).json() == {
        "user_id": "auth0|bob",
        "saved_readings": 1,
        "latest_measurement": foreign,
    }
    for name in ("First", "Edited"):
        assert (
            client.put(
                "/v1/me/profile",
                headers=users["alice"],
                json={"display_name": name, "profile_picture": None},
            ).status_code
            == 200
        )
        assert client.get(SUMMARY, headers=users["alice"]).json() == expected
    # Game completion changes points, not reading count or latest reading.
    assert (
        client.post(
            "/v1/me/game-results",
            headers=users["alice"],
            json={
                "result_id": str(uuid4()),
                "game_id": "trivia",
                "score": 1,
                "outcome": "completed",
                "data": {},
            },
        ).status_code
        == 201
    )
    _, token = identity
    fresh = {"Authorization": "Bearer " + token(sub="auth0|alice")}
    with TestClient(create_app(Settings(path), client.app.state.verifier)) as restarted:
        assert restarted.get(SUMMARY, headers=fresh).json() == expected
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM measurements").fetchone()[0] == 4


@pytest.mark.parametrize("authenticated", [True, False])
def test_summary_success_and_auth_errors_are_private(world, authenticated):
    client, users, _, _, _ = world
    response = client.get(SUMMARY, headers=users["alice"] if authenticated else {})
    assert response.status_code == (200 if authenticated else 401)
    assert response.headers.get("cache-control") == "no-store"
    if not authenticated:
        assert response.json()["error"]["code"] == "unauthorized"
        assert response.headers["www-authenticate"] == "Bearer"


def test_summary_storage_failure_is_private(world, monkeypatch):
    client, users, _, _, _ = world

    def broken_connect(path):
        raise sqlite3.OperationalError("fixture storage failure")

    monkeypatch.setattr("kickbac.measurements.connect", broken_connect)
    with TestClient(client.app, raise_server_exceptions=False) as failing:
        response = failing.get(SUMMARY, headers=users["alice"])
    assert response.status_code == 500
    assert response.json()["error"]["code"] == "internal_error"
    assert response.headers.get("cache-control") == "no-store"


def test_summary_does_not_write_or_expire_sessions(world, monkeypatch):
    client, users, _, now, path = world
    assert (
        client.post(
            "/v1/devices/one/sessions", headers=users["alice"], json={}
        ).status_code
        == 201
    )
    now[0] += timedelta(seconds=61)
    with connect(path) as db:
        before = list(db.iterdump())
    connections = []
    statements = []

    def tracked_connect(path):
        db = connect(path)
        db.set_trace_callback(statements.append)
        connections.append(db)
        return db

    monkeypatch.setattr("kickbac.measurements.connect", tracked_connect)
    assert client.get(SUMMARY, headers=users["alice"]).status_code == 200
    with connect(path) as db:
        assert list(db.iterdump()) == before
    assert "PRAGMA query_only=ON" in statements
    assert len(connections) == 1
    with pytest.raises(sqlite3.ProgrammingError):
        connections[0].execute("SELECT 1")


def test_summary_openapi_is_typed_authenticated_and_bodyless(world):
    client, *_ = world
    spec = client.get("/openapi.json").json()
    operation = spec["paths"][SUMMARY]["get"]
    assert "requestBody" not in operation
    assert operation["security"] == [{"UserAccessToken": []}]
    assert operation["responses"]["200"]["content"]["application/json"]["schema"] == {
        "$ref": "#/components/schemas/ReadingSummaryResponse"
    }
    model = spec["components"]["schemas"]["ReadingSummaryResponse"]
    assert set(model["required"]) == {"user_id", "saved_readings", "latest_measurement"}
    assert model["properties"]["latest_measurement"]["anyOf"] == [
        {"$ref": "#/components/schemas/MeasurementResponse"},
        {"type": "null"},
    ]


def test_empty_reading_summary(world):
    client, users, _, _, _ = world
    response = client.get("/v1/me/reading-summary", headers=users["alice"])
    assert response.status_code == 200
    assert response.json() == {
        "user_id": "auth0|alice",
        "saved_readings": 0,
        "latest_measurement": None,
    }
