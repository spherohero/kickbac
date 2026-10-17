import jwt
import pytest
from fastapi.testclient import TestClient

from kickbac.app import create_app
from kickbac.auth import JWTVerifier, auth0_verifier
from kickbac.db import initialize
from kickbac.settings import Settings


@pytest.mark.parametrize(
    "claims", [{"gty": "client-credentials"}, {"sub": "machine@clients"}]
)
def test_machine_tokens_not_human_users(tmp_path, identity, claims):
    private, token = identity
    initialize(tmp_path / "db")
    verifier = JWTVerifier(
        "https://fixture.invalid/", "kickbac-api", lambda t: private.public_key()
    )
    with TestClient(create_app(Settings(tmp_path / "db"), verifier)) as client:
        response = client.get(
            "/v1/me", headers={"Authorization": "Bearer " + token(**claims)}
        )
    assert response.status_code == 401


@pytest.mark.parametrize(
    "header", ["raw", "Basic token", "Bearer", "Bearer ", "Bearer a b"]
)
def test_malformed_scheme_never_calls_verifier(tmp_path, identity, header):
    _, token = identity
    initialize(tmp_path / "db")
    calls = []

    def verify(value):
        calls.append(value)
        return "alice"

    with TestClient(create_app(Settings(tmp_path / "db"), verify)) as client:
        response = client.get(
            "/v1/me", headers={"Authorization": token() if header == "raw" else header}
        )
    assert response.status_code == 401
    assert calls == []


@pytest.mark.parametrize(
    "token", ["garbage", jwt.encode({"sub": "alice"}, "", algorithm="none")]
)
def test_obviously_invalid_jwt_never_fetches_keys(token):
    calls = []

    def key(value):
        calls.append(value)
        raise jwt.PyJWKClientConnectionError("offline")

    from fastapi import HTTPException

    with pytest.raises(HTTPException) as error:
        JWTVerifier("https://fixture.invalid/", "api", key)(token)
    assert error.value.status_code == 401
    assert calls == []


@pytest.mark.parametrize(
    "domain",
    [
        "https://example.com",
        "example.com/path",
        "example.com:443",
        "a..com",
        "-bad.com",
        "example.com?x",
        "",
    ],
)
def test_invalid_auth0_domain_rejected(domain):
    with pytest.raises(RuntimeError, match="Auth0"):
        auth0_verifier(Settings("unused", domain, "api"))
