"""Actual backend HTTP bytes -> current C++ firmware decoder; no hardware.

Run explicitly after installing the pinned firmware JSON headers:
    uv run --locked pytest -q integration/test_firmware_wire.py
Identity and sensor data are isolated fixtures, never production Auth0 or ADC.
"""

import os
import subprocess
import time
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from kickbac.app import create_app
from kickbac.auth import JWTVerifier
from kickbac.cli import provision_device
from kickbac.db import initialize
from kickbac.settings import Settings
from kickbac.simulator import serve


@pytest.fixture(scope="session")
def decoder(tmp_path_factory):
    root = Path(__file__).resolve().parents[2]
    headers = Path(
        os.environ.get(
            "ARDUINOJSON_INCLUDE",
            root / "firmware/.pio/libdeps/xiao_device/ArduinoJson/src",
        )
    )
    assert (headers / "ArduinoJson.h").is_file(), (
        "Install pinned ArduinoJson via the documented PlatformIO pkg command "
        "or set ARDUINOJSON_INCLUDE to those headers. No skip/fake decoder fallback."
    )
    firmware_headers = Path(
        os.environ.get("KICKBAC_FIRMWARE_HEADER_DIR", root / "firmware/include")
    )
    executable = tmp_path_factory.mktemp("firmware-decoder") / "decode.exe"
    subprocess.run(
        [
            os.environ.get("CXX", "g++"),
            "-std=c++11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-Wconversion",
            "-Wshadow",
            "-pedantic",
            "-fno-exceptions",
            "-fno-rtti",
            "-I",
            str(headers),
            "-I",
            str(firmware_headers),
            str(Path(__file__).with_name("firmware_decoder.cpp")),
            "-o",
            str(executable),
        ],
        check=True,
        capture_output=True,
        timeout=60,
    )

    def decode(mode, response):
        result = subprocess.run(
            [str(executable), mode, str(response.status_code)],
            input=response.content,
            capture_output=True,
            check=True,
            timeout=5,
        )
        assert not result.stderr
        return result.stdout.decode().strip()

    return decode


@pytest.mark.parametrize("microseconds", [0, 123456])
def test_real_http_device_lifecycle_decodes_in_current_firmware(
    tmp_path, decoder, microseconds
):
    """Actual serializations, both timestamp forms, lifecycle and persisted retry."""
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    verifier = JWTVerifier(
        "https://wire-fixture.invalid/",
        "wire-fixture",
        lambda token: private.public_key(),
    )
    settings = Settings(tmp_path / "wire.sqlite3")
    initialize(settings.db_path)
    devices = {}
    for device_id in ("kb-demo-01", "wire-other"):
        secret = tmp_path / (device_id + ".secret")
        provision_device(settings.db_path, device_id, secret)
        devices[device_id] = {"Authorization": "Bearer " + secret.read_text().strip()}
    users = {}
    for subject in ("wire-fixture|alice", "wire-fixture|bob"):
        token = jwt.encode(
            {
                "iss": "https://wire-fixture.invalid/",
                "aud": "wire-fixture",
                "sub": subject,
                "exp": int(time.time()) + 300,
            },
            private,
            algorithm="RS256",
        )
        users[subject] = {"Authorization": "Bearer " + token}
    alice, bob = users.values()
    device = devices["kb-demo-01"]
    now = [datetime(2026, 10, 18, 2, 0, 0, microseconds, tzinfo=UTC)]

    def app():
        return create_app(settings, verifier=verifier, clock=lambda: now[0])

    def wire(client, mode, expected, headers):
        response = client.request(
            "POST" if mode == "heartbeat" else "GET",
            "/v1/device/heartbeat" if mode == "heartbeat" else "/v1/device/session",
            headers=headers,
            **({"json": {}} if mode == "heartbeat" else {}),
        )
        assert response.status_code == 200
        assert response.headers["content-type"].startswith("application/json")
        # Matches device_probe.cpp's getSize/readBytes acceptance requirements.
        assert 1 <= len(response.content) <= 768
        assert int(response.headers["content-length"]) == len(response.content)
        assert b"\0" not in response.content
        assert "transfer-encoding" not in response.headers
        assert decoder(mode, response) == expected
        body = response.json()
        assert body["device_id"] == "kb-demo-01"
        if mode == "poll":
            assert set(body) == {"device_id", "active_session"}
            if body["active_session"] is not None:
                assert set(body["active_session"]) == {
                    "id",
                    "device_id",
                    "status",
                    "expires_at",
                }
        else:
            assert set(body) == {"device_id", "online", "last_seen_at"}
            assert body["last_seen_at"] == now[0].isoformat()
        return body

    def arm(client):
        response = client.post(
            "/v1/devices/kb-demo-01/sessions", headers=alice, json={}
        )
        assert response.status_code == 201
        session = response.json()
        retry = client.post("/v1/devices/kb-demo-01/sessions", headers=alice, json={})
        assert retry.status_code == 200 and retry.json() == session
        assert (
            client.post(
                "/v1/devices/kb-demo-01/sessions", headers=bob, json={}
            ).status_code
            == 409
        )
        assert (
            client.get("/v1/sessions/" + session["id"], headers=bob).status_code == 404
        )
        poll = wire(client, "poll", "ARMED", device)
        assert poll["active_session"]["id"] == session["id"]
        assert poll["active_session"]["expires_at"] == session["expires_at"]
        return session

    with serve(app()) as client:
        for mode, method, route in (
            ("heartbeat", "POST", "/v1/device/heartbeat"),
            ("poll", "GET", "/v1/device/session"),
        ):
            for headers in ({}, alice, {"Authorization": "Bearer invalid-fixture"}):
                response = client.request(
                    method,
                    route,
                    headers=headers,
                    **({"json": {}} if method == "POST" else {}),
                )
                assert response.status_code == 401
                assert decoder(mode, response) == "INVALID"
            foreign_device = client.request(
                method,
                route,
                headers=devices["wire-other"],
                **({"json": {}} if method == "POST" else {}),
            )
            assert foreign_device.status_code == 200
            assert decoder(mode, foreign_device) == "INVALID"
        wire(client, "heartbeat", "HEARTBEAT_OK", device)
        wire(client, "poll", "IDLE", device)
        cancelled = arm(client)
        assert (
            client.post(
                "/v1/sessions/" + cancelled["id"] + "/cancel", headers=alice, json={}
            ).status_code
            == 200
        )
        wire(client, "poll", "IDLE", device)
        expired = arm(client)
        now[0] = datetime.fromisoformat(expired["expires_at"])
        wire(client, "poll", "IDLE", device)
        assert (
            client.get("/v1/sessions/" + expired["id"], headers=alice).json()["status"]
            == "EXPIRED"
        )
        completed = arm(client)
        sampling = "/v1/device/sessions/" + completed["id"] + "/sampling"
        assert (
            client.post(sampling, headers=devices["wire-other"], json={}).status_code
            == 404
        )
        assert client.post(sampling, headers=device, json={}).status_code == 200
        wire(client, "poll", "SAMPLING", device)
        now[0] += timedelta(seconds=1)
        wire(client, "heartbeat", "HEARTBEAT_OK", device)
        # Explicit simulated sensor fixture; not physical acquisition/duration evidence.
        payload = {
            "measurement_id": str(uuid4()),
            "session_id": completed["id"],
            "raw": {"sensor": "mq3", "value": 1200, "unit": "adc_counts"},
            "breath_duration_ms": 2500,
            "source": "simulator",
            "measured_at": None,
        }
        accepted = client.post("/v1/device/measurements", headers=device, json=payload)
        assert accepted.status_code == 201
        measurement = accepted.json()
        assert measurement["estimated_bac_percent"] is None
        replay = client.post("/v1/device/measurements", headers=device, json=payload)
        assert replay.status_code == 200 and replay.json() == measurement
        wire(client, "poll", "IDLE", device)

    with serve(app()) as client:
        wire(client, "heartbeat", "HEARTBEAT_OK", device)
        wire(client, "poll", "IDLE", device)
        replay = client.post("/v1/device/measurements", headers=device, json=payload)
        assert replay.status_code == 200 and replay.json() == measurement
        own = client.get("/v1/measurements", headers=alice)
        assert own.status_code == 200 and own.json()["items"] == [measurement]
        assert client.get("/v1/measurements", headers=bob).json()["items"] == []
        assert (
            client.get("/v1/sessions/" + completed["id"], headers=alice).json()[
                "status"
            ]
            == "COMPLETE"
        )
