"""Real HTTP App reading persistence: generated records, not device/BAC evidence."""

import time
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from threading import Barrier
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


class PrivateWorld(tuple):
    def __repr__(self):
        return "<isolated App HTTP fixture; credentials withheld>"


@pytest.fixture
def app_world(tmp_path):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    issuer, audience = "https://app-http-fixture.invalid/", "app-http-fixture"
    settings = Settings(tmp_path / "app-http.sqlite3")
    initialize(settings.db_path)
    verifier = JWTVerifier(issuer, audience, lambda _: key.public_key())
    users = []
    for sub in ("app-fixture|owner", "app-fixture|foreign"):
        token = jwt.encode(
            {"iss": issuer, "aud": audience, "sub": sub, "exp": int(time.time()) + 600},
            key,
            algorithm="RS256",
        )
        users.append({"Authorization": "Bearer " + token})
    secret = tmp_path / "app-fixture-device.secret"
    provision_device(settings.db_path, "app-fixture-unit", secret)
    device = {"Authorization": "Bearer " + secret.read_text().strip()}
    now = [datetime.now(UTC)]

    def app():
        return create_app(settings, verifier=verifier, clock=lambda: now[0])

    return PrivateWorld((settings, users, device, now, app))


def checked(client, method, path, headers, status=200, **kwargs):
    response = client.request(method, path, headers=headers, **kwargs)
    assert response.status_code == status, (
        method,
        path,
        response.status_code,
        response.text,
    )
    assert response.headers.get("Cache-Control") == "no-store"
    return response.json()


def sample(**changes):
    return {
        "reading_id": str(uuid4()),
        "value": 0.08,
        "recorded_at": "2026-10-18T09:31:50.331196Z",
        "duration_ms": 2500,
        "source": "app_generated",
        **changes,
    }


def test_real_http_app_save_retry_private_pages_summary_and_restart(app_world):
    settings, (owner, foreign), device, now, app = app_world
    body = sample()
    with serve(app()) as client:
        receipt = checked(client, "POST", "/v1/me/app-readings", owner, 201, json=body)
        assert (
            receipt["reading_id"] == body["reading_id"]
            and receipt["source"] == "app_generated"
        )
        assert receipt["value"] == 0.08 and receipt["duration_ms"] == 2500
        assert receipt["recorded_at"] == "2026-10-18T09:31:50.331196+00:00"
        assert datetime.fromisoformat(receipt["received_at"]) == now[0]
        # Canonical timezone offset, same local UUID, original immutable receipt.
        canonical = {**body, "recorded_at": "2026-10-18T05:31:50.331196-04:00"}
        assert (
            checked(client, "POST", "/v1/me/app-readings", owner, json=canonical)
            == receipt
        )
        checked(
            client,
            "POST",
            "/v1/me/app-readings",
            owner,
            409,
            json={**body, "value": 0.09},
        )
        checked(client, "POST", "/v1/me/app-readings", foreign, 404, json=body)
        checked(client, "POST", "/v1/me/app-readings", device, 401, json=body)
        checked(client, "POST", "/v1/me/app-readings", {}, 401, json=body)
        for changes in (
            {"value": True},
            {"value": "0.08"},
            {"value": 1.01},
            {"duration_ms": 0},
            {"duration_ms": True},
            {"recorded_at": "2026-10-18T09:31:50"},
            {"source": "device"},
            {"user_id": "other"},
        ):
            checked(
                client,
                "POST",
                "/v1/me/app-readings",
                owner,
                422,
                json=sample(**changes),
            )
        for invalid in (b'{"value":NaN}', b'{"value":Infinity}', b"\xff", b"{"):
            response = client.post(
                "/v1/me/app-readings",
                headers={**owner, "Content-Type": "application/json"},
                content=invalid,
            )
            assert (
                response.status_code == 422
                and response.headers["Cache-Control"] == "no-store"
            )
        huge = client.post(
            "/v1/me/app-readings",
            headers={**owner, "Content-Type": "application/json"},
            content=b"{" + b" " * 32768 + b"}",
        )
        assert huge.status_code == 413 and huge.headers["Cache-Control"] == "no-store"
        second_body = sample(recorded_at="2026-10-18T09:31:51Z", value=0.04)
        second = checked(
            client, "POST", "/v1/me/app-readings", owner, 201, json=second_body
        )
        page = checked(client, "GET", "/v1/me/app-readings?limit=1&offset=0", owner)
        assert page == {"items": [second], "limit": 1, "offset": 0, "has_more": True}
        assert checked(client, "GET", "/v1/me/app-readings?limit=1&offset=1", owner)[
            "items"
        ] == [receipt]
        assert (
            checked(client, "GET", "/v1/me/app-readings?offset=" + str(2**100), owner)[
                "items"
            ]
            == []
        )
        assert checked(client, "GET", "/v1/me/app-readings", foreign)["items"] == []
        summary = checked(client, "GET", "/v1/me/app-reading-summary", owner)
        assert summary == {
            "user_id": receipt["user_id"],
            "source": "app_generated",
            "saved_readings": 2,
            "latest_reading": second,
        }
        assert client.get("/v1/measurements", headers=owner).json()["items"] == []
        assert (
            client.get("/v1/me/reading-summary", headers=owner).json()["saved_readings"]
            == 0
        )
        assert client.get("/v1/me/stats", headers=owner).json()["total_points"] == 0
    with serve(app()) as client:
        assert (
            checked(client, "POST", "/v1/me/app-readings", owner, json=body) == receipt
        )
        assert checked(client, "GET", "/v1/me/app-readings", owner)["items"] == [
            second,
            receipt,
        ]
        assert checked(client, "GET", "/v1/me/app-reading-summary", owner) == summary
    with connect(settings.db_path) as db:
        assert db.execute("SELECT count(*) FROM measurements").fetchone()[0] == 0
        assert db.execute("SELECT count(*) FROM sessions").fetchone()[0] == 0
        assert db.execute("SELECT count(*) FROM game_results").fetchone()[0] == 0
        assert db.execute("SELECT count(*) FROM profiles").fetchone()[0] == 0


def test_real_http_app_concurrent_idempotency_and_persisted_rate_window(app_world):
    _, (owner, _), _, now, app = app_world
    first = sample()
    barrier = Barrier(2)
    with serve(app()) as client:

        def submit(_):
            barrier.wait(timeout=5)
            return client.post("/v1/me/app-readings", headers=owner, json=first)

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(submit, range(2)))
        assert sorted(r.status_code for r in results) == [200, 201]
        assert results[0].json() == results[1].json()
        for _ in range(59):
            checked(client, "POST", "/v1/me/app-readings", owner, 201, json=sample())
        response = client.post("/v1/me/app-readings", headers=owner, json=sample())
        assert (
            response.status_code == 429
            and 1 <= int(response.headers["Retry-After"]) <= 60
        )
        assert response.json()["error"]["code"] == "rate_limited"
        assert (
            checked(client, "POST", "/v1/me/app-readings", owner, json=first)
            == results[0].json()
        )
    with serve(app()) as client:
        response = client.post("/v1/me/app-readings", headers=owner, json=sample())
        assert response.status_code == 429
        now[0] += timedelta(seconds=60)
        checked(client, "POST", "/v1/me/app-readings", owner, 201, json=sample())
        assert (
            checked(client, "GET", "/v1/me/app-reading-summary", owner)[
                "saved_readings"
            ]
            == 61
        )
