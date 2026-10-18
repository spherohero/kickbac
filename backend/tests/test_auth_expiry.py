import time

import jwt
import pytest
from fastapi import HTTPException

from kickbac.auth import JWTVerifier


@pytest.mark.parametrize(
    "expiry", [None, True, "9999999999", float("inf"), float("nan")]
)
def test_invalid_expiry_is_generic_401(identity, expiry):
    private, token = identity
    verifier = JWTVerifier(
        "https://fixture.invalid/", "kickbac-api", lambda t: private.public_key()
    )
    with pytest.raises(HTTPException) as error:
        verifier(token(exp=expiry))
    assert error.value.status_code == 401


def test_lowercase_bearer_supported(world):
    client, users, _, _, _ = world
    header = users["alice"]["Authorization"].replace("Bearer ", "bEaReR ")
    assert client.get("/v1/me", headers={"Authorization": header}).json() == {
        "user_id": "auth0|alice"
    }


def test_unmatched_jwk_is_401(identity):
    _, token = identity

    def missing(value):
        raise jwt.PyJWKClientError("private-provider-detail")

    with pytest.raises(HTTPException) as error:
        JWTVerifier("https://fixture.invalid/", "kickbac-api", missing)(
            token(exp=int(time.time()) + 60)
        )
    assert error.value.status_code == 401
