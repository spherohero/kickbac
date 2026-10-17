import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from kickbac.app import create_app
from kickbac.db import initialize
from kickbac.settings import Settings


def test_production_fails_closed_without_auth0(tmp_path):
    initialize(tmp_path / "db")
    with (
        pytest.raises(RuntimeError, match="Auth0"),
        TestClient(create_app(Settings(tmp_path / "db"))),
    ):
        pass


def test_jwks_unavailable_is_503(tmp_path, identity):
    from kickbac.auth import JWTVerifier

    _, token = identity

    def unavailable(t):
        raise jwt.PyJWKClientConnectionError("unavailable")

    initialize(tmp_path / "db")
    verifier = JWTVerifier("https://fixture.invalid/", "kickbac-api", unavailable)
    with TestClient(create_app(Settings(tmp_path / "db"), verifier)) as client:
        response = client.get("/v1/me", headers={"Authorization": "Bearer " + token()})
        assert response.status_code == 503
        assert response.json()["error"]["code"] == "auth_unavailable"


def test_signed_access_token_identifies_user(tmp_path, identity):
    from kickbac.auth import JWTVerifier

    private, token = identity
    path = tmp_path / "db"
    initialize(path)
    verifier = JWTVerifier(
        "https://fixture.invalid/", "kickbac-api", lambda t: private.public_key()
    )
    with TestClient(create_app(Settings(path), verifier=verifier)) as client:
        response = client.get("/v1/me", headers={"Authorization": "Bearer " + token()})
        assert response.status_code == 200
        assert response.json() == {"user_id": "auth0|alice"}


@pytest.mark.parametrize(
    "kind",
    [
        "missing",
        "garbage",
        "expired",
        "issuer",
        "audience",
        "no_sub",
        "blank_sub",
        "unsigned",
        "signature",
        "id_token",
    ],
)
def test_invalid_auth_is_private_generic_401(tmp_path, identity, kind):
    from kickbac.auth import JWTVerifier

    private, token = identity
    initialize(tmp_path / "db")
    value = {
        "missing": "",
        "garbage": "not-a-token",
        "expired": token(exp=1),
        "issuer": token(iss="https://wrong.invalid/"),
        "audience": token(aud="wrong"),
        "no_sub": jwt.encode(
            {
                "iss": "https://fixture.invalid/",
                "aud": "kickbac-api",
                "exp": int(time.time()) + 300,
            },
            private,
            algorithm="RS256",
        ),
        "blank_sub": token(sub=""),
        "unsigned": jwt.encode({"sub": "alice"}, "", algorithm="none"),
        "signature": jwt.encode(
            {"sub": "alice"},
            rsa.generate_private_key(public_exponent=65537, key_size=2048),
            algorithm="RS256",
        ),
        "id_token": token(aud="native-client-id"),
    }[kind]
    verifier = JWTVerifier(
        "https://fixture.invalid/", "kickbac-api", lambda t: private.public_key()
    )
    with TestClient(create_app(Settings(tmp_path / "db"), verifier)) as client:
        headers = {"Authorization": "Bearer " + value} if value else {}
        response = client.get("/v1/me", headers=headers)
        assert response.status_code == 401
        assert response.headers["www-authenticate"] == "Bearer"
        assert response.json() == {
            "error": {
                "code": "unauthorized",
                "message": "Invalid or missing credentials.",
            }
        }
