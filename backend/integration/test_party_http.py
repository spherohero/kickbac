"""Real loopback party/check-in/history acceptance with explicit synthetic identities.

Not live Auth0, iPhone NFC, physical breath acquisition or calibrated BAC evidence.
"""

import time
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from kickbac.app import create_app
from kickbac.auth import JWTVerifier
from kickbac.cli import provision_device
from kickbac.db import connect, initialize
from kickbac.settings import Settings
from kickbac.simulator import serve


def test_real_http_party_join_check_in_completion_retry_and_restart(tmp_path):
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    issuer, audience = "https://party-fixture.invalid/", "party-fixture"
    verifier = JWTVerifier(issuer, audience, lambda _: private.public_key())
    settings = Settings(tmp_path / "party-fixture.sqlite3")
    initialize(settings.db_path)
    secret_file = tmp_path / "fixture-device.secret"
    provision_device(settings.db_path, "party-fixture-unit", secret_file)
    device = {"Authorization": "Bearer " + secret_file.read_text().strip()}
    now = [datetime(2026, 10, 18, 6, tzinfo=UTC)]

    def credentials(name):
        token = jwt.encode(
            {
                "iss": issuer,
                "aud": audience,
                "sub": "party-fixture|" + name,
                "exp": int(time.time()) + 600,
            },
            private,
            algorithm="RS256",
        )
        return {"Authorization": "Bearer " + token}

    alice, bob, charlie = (credentials(name) for name in ("host", "member", "outsider"))

    def app():
        return create_app(settings, verifier=verifier, clock=lambda: now[0])

    def checked(client, method, path, headers, status=200, **kwargs):
        response = client.request(method, path, headers=headers, **kwargs)
        assert response.status_code == status
        return response.json()

    def sample(client):
        armed = checked(
            client, "POST", "/v1/devices/party-fixture-unit/sessions", bob, 201, json={}
        )
        body = {
            "measurement_id": str(uuid4()),
            "session_id": armed["id"],
            "raw": {"sensor": "mq3", "value": 1200, "unit": "adc_counts"},
            "breath_duration_ms": 2500,
            "source": "simulator",
            "measured_at": None,
        }
        reading = checked(
            client, "POST", "/v1/device/measurements", device, 201, json=body
        )
        assert (
            checked(client, "POST", "/v1/device/measurements", device, json=body)
            == reading
        )
        assert reading["source"] == "simulator"
        assert reading["estimated_bac_percent"] is None
        return reading

    with serve(app()) as client:
        party_body = {"party_id": str(uuid4()), "name": "Synthetic party fixture"}
        party = checked(client, "POST", "/v1/parties", alice, 201, json=party_body)
        party_id = party["party_id"]
        assert party_id == party_body["party_id"]
        assert checked(client, "POST", "/v1/parties", alice, json=party_body) == party

        # This is private fixture operator approval, not a phone/device bearer claim.
        from kickbac.cli import grant_party_device

        grant_party_device(settings.db_path, "party-fixture-unit", "party-fixture|host")
        checked(
            client,
            "PUT",
            f"/v1/parties/{party_id}/device",
            alice,
            json={"device_id": "party-fixture-unit"},
        )
        joined = checked(
            client,
            "POST",
            "/v1/parties/join",
            bob,
            json={"join_code": party["join_code"]},
        )
        joined_by_device = checked(
            client,
            "POST",
            "/v1/parties/join",
            bob,
            json={"device_id": "party-fixture-unit"},
        )
        assert joined_by_device == joined
        assert joined["party_id"] == party_id and joined["join_code"] is None
        assert checked(client, "GET", "/d/party-fixture-unit", {}) == {
            "device_id": "party-fixture-unit"
        }
        checked(client, "GET", f"/v1/parties/{party_id}", charlie, 404)

        # Party-assignment grants must not silently change legacy arming rights.
        outsider_session = checked(
            client,
            "POST",
            "/v1/devices/party-fixture-unit/sessions",
            charlie,
            201,
            json={},
        )
        checked(
            client,
            "POST",
            "/v1/sessions/" + outsider_session["id"] + "/cancel",
            charlie,
            json={},
        )
        ordinary = sample(client)
        now[0] += timedelta(seconds=1)
        game_body = {"game_instance_id": str(uuid4()), "game_id": "trivia"}
        game = checked(
            client, "POST", f"/v1/parties/{party_id}/games", alice, 201, json=game_body
        )
        assert game["device_id"] == "party-fixture-unit"
        measurement = sample(client)
        assert measurement["id"] != ordinary["id"]
        result_body = {
            "result_id": str(uuid4()),
            "game_id": "trivia",
            "score": 8,
            "outcome": "win",
            "data": {"correct_answers": 8, "questions": 10},
            "measurement_id": measurement["id"],
            "placement": 1,
        }
        result_path = f"/v1/party-games/{game['game_instance_id']}/results"
        accepted = checked(client, "POST", result_path, bob, 201, json=result_body)
        assert accepted["awarded_points"] == 10
        assert checked(client, "POST", result_path, bob, json=result_body) == accepted

        rich = checked(client, "GET", "/v1/me/game-history", bob)
        assert len(rich["items"]) == 1 and rich["has_more"] is False
        row = rich["items"][0]
        assert row["party"] == {
            "party_id": party_id,
            "name": party["name"],
            "created_at": party["created_at"],
        }
        assert row["game_instance_id"] == game["game_instance_id"]
        assert row["placement"] == 1 and row["measurement"] == measurement
        assert row["score"] == 8 and row["awarded_points"] == 10
        summary = checked(client, "GET", "/v1/me/reading-summary", bob)
        assert summary["saved_readings"] == 2
        assert {
            x["id"] for x in checked(client, "GET", "/v1/measurements", bob)["items"]
        } == {ordinary["id"], measurement["id"]}
        stats = checked(client, "GET", "/v1/me/stats", bob)
        assert (stats["total_points"], stats["games_played"], stats["wins"]) == (
            10,
            1,
            1,
        )
        assert checked(client, "GET", "/v1/me/game-history", alice)["items"] == []
        assert (
            checked(client, "GET", "/v1/me/reading-summary", alice)["saved_readings"]
            == 0
        )
        legacy_body = {
            k: result_body[k]
            for k in ("result_id", "game_id", "score", "outcome", "data")
        }
        checked(client, "POST", "/v1/me/game-results", bob, json=legacy_body)
        assert checked(client, "GET", "/v1/me/game-history", bob) == rich
        checked(client, "POST", f"/v1/parties/{party_id}/leave", bob, json={})
        checked(client, "POST", f"/v1/parties/{party_id}/close", alice, json={})
        assert checked(client, "POST", result_path, bob, json=result_body) == accepted

    with serve(app()) as client:
        assert checked(client, "POST", result_path, bob, json=result_body) == accepted
        assert checked(client, "GET", "/v1/me/game-history", bob) == rich
        assert checked(client, "GET", "/v1/me/reading-summary", bob) == summary
        assert checked(client, "GET", "/v1/me/stats", bob) == stats
        assert checked(client, "GET", "/v1/me/game-history", charlie)["items"] == []
        checked(client, "POST", result_path, charlie, 404, json=result_body)
        checked(client, "GET", f"/v1/parties/{party_id}", bob, 404)
        for route in (
            "/v1/me/game-history",
            "/v1/me/reading-summary",
            "/v1/me/parties",
        ):
            response = client.get(route)
            assert (
                response.status_code == 401
                and response.headers["cache-control"] == "no-store"
            )
    with connect(settings.db_path) as db:
        assert db.execute("SELECT COUNT(*) FROM game_results").fetchone()[0] == 1
        assert db.execute("SELECT COUNT(*) FROM measurements").fetchone()[0] == 2
        assert (
            db.execute("SELECT COUNT(*) FROM party_result_context").fetchone()[0] == 1
        )


@pytest.mark.parametrize(
    "method,path",
    [
        ("POST", "/v1/parties"),
        ("POST", "/v1/parties/join"),
        ("PUT", "/v1/parties/11111111-1111-4111-8111-111111111111/device"),
        ("POST", "/v1/parties/11111111-1111-4111-8111-111111111111/games"),
        ("POST", "/v1/party-games/11111111-1111-4111-8111-111111111111/results"),
    ],
)
def test_new_private_routes_bound_real_chunked_bodies_before_parsing(
    tmp_path, method, path
):
    settings = Settings(tmp_path / "chunked-fixture.sqlite3")
    initialize(settings.db_path)
    # No credentials needed: body bytes must be bounded before auth/JSON parsing.
    with serve(create_app(settings, verifier=lambda _: None)) as client:
        response = client.request(
            method,
            path,
            headers={"Content-Type": "application/json"},
            content=iter([b" " * 16384] * 3),
        )
        assert response.status_code == 413
        assert response.json()["error"]["code"] == "payload_too_large"
        assert response.headers["cache-control"] == "no-store"
