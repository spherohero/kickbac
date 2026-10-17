import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa


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
