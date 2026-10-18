"""Existing private reading history is keyed to identity, not mutable profile data."""

from uuid import uuid4

from fastapi.testclient import TestClient
from test_profiles import picture

from kickbac.app import create_app
from kickbac.settings import Settings


def test_each_reading_survives_profile_creation_edits_and_relogin(world, identity):
    client, users, devices, _, path = world
    readings = []
    for value in (1200, 900):
        armed = client.post("/v1/devices/one/sessions", headers=users["alice"], json={})
        assert armed.status_code == 201
        result = client.post(
            "/v1/device/measurements",
            headers=devices["one"],
            json={
                "measurement_id": str(uuid4()),
                "session_id": armed.json()["id"],
                "raw": {"sensor": "mq3", "value": value, "unit": "adc_counts"},
                "breath_duration_ms": 2500,
                "source": "simulator",
                "measured_at": None,
            },
        )
        assert result.status_code == 201
        readings.append(result.json())
    before = client.get("/v1/measurements", headers=users["alice"]).json()
    assert {item["id"] for item in before["items"]} == {item["id"] for item in readings}
    assert all(item["estimated_bac_percent"] is None for item in before["items"])
    for name, photo in (("First Name", picture()), ("Edited Name", None)):
        assert (
            client.put(
                "/v1/me/profile",
                headers=users["alice"],
                json={"display_name": name, "profile_picture": photo},
            ).status_code
            == 200
        )
        assert client.get("/v1/measurements", headers=users["alice"]).json() == before
        game = client.post(
            "/v1/me/game-results",
            headers=users["alice"],
            json={
                "result_id": str(uuid4()),
                "game_id": "trivia",
                "score": 5,
                "outcome": "completed",
                "data": {},
            },
        )
        assert game.status_code == 201
        assert client.get("/v1/measurements", headers=users["alice"]).json() == before
    assert (
        client.get("/v1/me/stats", headers=users["alice"]).json()["total_points"] == 20
    )
    _, token = identity
    fresh = {"Authorization": "Bearer " + token(sub="auth0|alice")}
    with TestClient(create_app(Settings(path), client.app.state.verifier)) as restarted:
        assert restarted.get("/v1/measurements", headers=fresh).json() == before
        assert restarted.get("/v1/me/stats", headers=fresh).json()["total_points"] == 20
        assert (
            restarted.get("/v1/me/profile", headers=fresh).json()["display_name"]
            == "Edited Name"
        )
        assert (
            restarted.get("/v1/measurements", headers=users["bob"]).json()["items"]
            == []
        )
        for item in readings:
            assert (
                restarted.get(
                    "/v1/sessions/" + item["session_id"], headers=users["bob"]
                ).status_code
                == 404
            )
