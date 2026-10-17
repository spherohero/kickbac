"""Explicit, isolated OIDC + sensor fixtures over real loopback HTTP.

Never imported by normal application startup. No live Auth0 authentication or
hardware sensing is claimed, and no credential is displayed.
"""

import json
import os
import socket
import threading
import time
from contextlib import contextmanager
from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import uuid4

import httpx
import jwt
import uvicorn
from cryptography.hazmat.primitives.asymmetric import rsa

from .app import create_app
from .auth import JWTVerifier
from .cli import provision_device
from .db import connect, initialize
from .settings import Settings


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


@contextmanager
def serve(app):
    """Bind once to an OS-selected loopback port; bound all waits/shutdowns."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        origin = f"http://127.0.0.1:{listener.getsockname()[1]}"
        server = uvicorn.Server(
            uvicorn.Config(
                app, log_level="warning", access_log=False, timeout_graceful_shutdown=3
            )
        )
        errors = []

        def run():
            try:
                server.run(sockets=[listener])
            except (SystemExit, OSError, RuntimeError) as error:
                errors.append(type(error).__name__)

        worker = threading.Thread(target=run, daemon=True)
        worker.start()
        try:
            deadline = time.monotonic() + 8
            while not server.started:
                require(
                    worker.is_alive() and not errors, "Simulator server failed to start"
                )
                require(time.monotonic() < deadline, "Simulator startup timeout")
                time.sleep(0.02)
            print("Real HTTP fixture server: " + origin, flush=True)
            with httpx.Client(base_url=origin, timeout=3, trust_env=False) as client:
                require(client.get("/health").status_code == 200, "Readiness failed")
                yield client
        finally:
            server.should_exit = True
            worker.join(timeout=8)
            if worker.is_alive():
                server.force_exit = True
                worker.join(timeout=2)
            require(not worker.is_alive(), "Simulator shutdown timeout")
        require(not errors, "Simulator server failed")


def request(client, method, path, expected=200, headers=None, **kwargs):
    response = client.request(method, path, headers=headers, **kwargs)
    require(
        response.status_code == expected,
        f"{method} {path}: expected {expected}, got {response.status_code}",
    )
    return response.json()


def main():
    print("SIMULATED OIDC: ephemeral local RSA identity fixture, NOT live Auth0 login.")
    print("SIMULATED SENSOR: MQ-3 ADC fixture, NOT measured BAC or hardware data.")
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    issuer, audience = "https://simulator.invalid/", "kickbac-simulator"
    verifier = JWTVerifier(issuer, audience, lambda token: private.public_key())

    def user(subject):
        token = jwt.encode(
            {
                "iss": issuer,
                "aud": audience,
                "sub": subject,
                "exp": int(time.time()) + 300,
            },
            private,
            algorithm="RS256",
        )
        return {"Authorization": "Bearer " + token}

    alice, bob = user("simulated|alice"), user("simulated|bob")
    with TemporaryDirectory(
        prefix="kickbac-simulator-", dir=os.environ.get("TMPDIR") or None
    ) as temporary:
        root = Path(temporary)
        settings = Settings(root / "fixture.sqlite3")
        initialize(settings.db_path)
        devices = {}
        for device_id in ["sim-one", "sim-two"]:
            target = root / (device_id + ".secret")
            provision_device(settings.db_path, device_id, target)
            devices[device_id] = {
                "Authorization": "Bearer " + target.read_text().strip()
            }
        device = devices["sim-one"]
        with serve(create_app(settings, verifier=verifier)) as client:
            me = request(client, "GET", "/v1/me", headers=alice)
            require(
                me == {"user_id": "simulated|alice"}, "Identity verification failed"
            )
            require(
                request(client, "GET", "/d/sim-one") == {"device_id": "sim-one"},
                "Resolution failed",
            )
            availability = request(client, "GET", "/v1/devices/sim-one", headers=alice)
            require(
                availability["state"] == "AVAILABLE" and not availability["online"],
                "Initial availability failed",
            )
            require(
                request(
                    client, "POST", "/v1/device/heartbeat", headers=device, json={}
                )["online"],
                "Heartbeat failed",
            )
            session = request(
                client, "POST", "/v1/devices/sim-one/sessions", 201, alice, json={}
            )
            sid = session["id"]
            require(
                request(
                    client,
                    "POST",
                    "/v1/devices/sim-one/sessions",
                    headers=alice,
                    json={},
                )
                == session,
                "Arm retry changed session",
            )
            require(
                request(client, "GET", "/v1/device/session", headers=device)[
                    "active_session"
                ]["id"]
                == sid,
                "Polling failed",
            )
            sampling = request(
                client,
                "POST",
                "/v1/device/sessions/" + sid + "/sampling",
                headers=device,
                json={},
            )
            require(
                sampling["status"] == "SAMPLING" and "user_id" not in sampling,
                "Sampling/device privacy failed",
            )
            payload = {
                "measurement_id": str(uuid4()),
                "session_id": sid,
                "raw": {"sensor": "mq3", "value": 1200, "unit": "adc_counts"},
                "breath_duration_ms": 2500,
                "source": "simulator",
                "measured_at": None,
            }
            measurement = request(
                client, "POST", "/v1/device/measurements", 201, device, json=payload
            )
            require(
                request(
                    client,
                    "POST",
                    "/v1/device/measurements",
                    headers=device,
                    json=payload,
                )
                == measurement,
                "Replay changed result",
            )
            request(
                client,
                "POST",
                "/v1/device/measurements",
                409,
                device,
                json={**payload, "measurement_id": str(uuid4())},
            )
            request(
                client,
                "POST",
                "/v1/device/measurements",
                404,
                devices["sim-two"],
                json=payload,
            )
            complete = request(client, "GET", "/v1/sessions/" + sid, headers=alice)
            require(
                complete["status"] == "COMPLETE"
                and complete["measurement"] == measurement,
                "Session did not complete",
            )
            request(client, "GET", "/v1/sessions/" + sid, 404, bob)
            require(
                request(client, "GET", "/v1/measurements", headers=bob)["items"] == [],
                "Foreign history was exposed",
            )
            history = request(client, "GET", "/v1/measurements", headers=alice)
            require(
                history["items"] == [measurement] and not history["has_more"],
                "History mismatch",
            )
            require(
                request(client, "GET", "/v1/device/session", headers=device)[
                    "active_session"
                ]
                is None,
                "Completed session still active",
            )
        # A new app + server + TCP listener must recover the persisted result.
        with serve(create_app(settings, verifier=verifier)) as client:
            require(
                request(client, "GET", "/v1/sessions/" + sid, headers=alice)
                == complete,
                "Restart lost session",
            )
            require(
                request(client, "GET", "/v1/measurements", headers=alice) == history,
                "Restart lost history",
            )
            require(
                request(
                    client,
                    "POST",
                    "/v1/device/measurements",
                    headers=device,
                    json=payload,
                )
                == measurement,
                "Restart broke idempotency",
            )
        with connect(settings.db_path) as db:
            count = db.execute("SELECT count(*) FROM measurements").fetchone()[0]
            duplicate_rows = db.execute(
                "SELECT count(*) FROM (SELECT session_id FROM measurements GROUP BY session_id HAVING count(*)>1)"
            ).fetchone()[0]
        require(count == 1 and duplicate_rows == 0, "Unexpected duplicate results")
    print(
        json.dumps(
            {
                "status": "SIMULATOR_OK",
                "transport": "real HTTP loopback",
                "session_status": "COMPLETE",
                "measurements": count,
                "duplicate_rows": duplicate_rows,
                "foreign_owner_status": 404,
                "restart": "ok",
            }
        )
    )


if __name__ == "__main__":
    main()
