import time
from datetime import UTC, datetime

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from kickbac.app import create_app
from kickbac.auth import JWTVerifier
from kickbac.cli import provision_device
from kickbac.db import initialize
from kickbac.settings import Settings


@pytest.fixture
def identity():
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    def token(**overrides):
        payload = {
            "iss": "https://fixture.invalid/",
            "aud": "kickbac-api",
            "sub": "auth0|alice",
            "exp": int(time.time()) + 300,
        }
        payload.update(overrides)
        return jwt.encode(payload, private, algorithm="RS256", headers={"typ": "JWT"})

    return private, token


@pytest.fixture
def world(tmp_path, identity):
    private, token = identity
    path = tmp_path / "db"
    initialize(path)
    device_headers = {}
    for device in ["one", "two"]:
        target = tmp_path / (device + ".secret")
        provision_device(path, device, target)
        device_headers[device] = {
            "Authorization": "Bearer " + target.read_text().strip()
        }
    now = [datetime(2026, 10, 17, tzinfo=UTC)]
    verifier = JWTVerifier(
        "https://fixture.invalid/", "kickbac-api", lambda t: private.public_key()
    )
    app = create_app(Settings(path), verifier, clock=lambda: now[0])
    with TestClient(app) as client:
        yield (
            client,
            {
                u: {"Authorization": "Bearer " + token(sub="auth0|" + u)}
                for u in ["alice", "bob"]
            },
            device_headers,
            now,
            path,
        )
