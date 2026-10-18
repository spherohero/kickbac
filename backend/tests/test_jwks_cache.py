import json
import time
from io import BytesIO
from types import SimpleNamespace
from urllib.error import URLError
from urllib.request import OpenerDirector

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from kickbac.app import create_app
from kickbac.db import initialize
from kickbac.settings import Settings


@pytest.fixture
def jwks_api(tmp_path, monkeypatch):
    # Freeze only PyJWT's cache clocks, not HTTP/asyncio or JWT expiry clocks.
    clock = SimpleNamespace(now=1000.0)
    cache_time = SimpleNamespace(monotonic=lambda: clock.now)
    for module in (jwt.api_jwk, jwt.jwk_set_cache, jwt.jwks_client):
        monkeypatch.setattr(module, "time", cache_time)

    keys = {
        kid: rsa.generate_private_key(public_exponent=65537, key_size=2048)
        for kid in ("old", "new")
    }
    public_keys = {
        kid: dict(
            json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(key.public_key())),
            kid=kid,
            use="sig",
            alg="RS256",
        )
        for kid, key in keys.items()
    }
    endpoint = SimpleNamespace(kids=["old"], unavailable=False, calls=[])

    def open_jwks(opener, request, *, timeout):
        assert request.full_url == "https://fixture.invalid/.well-known/jwks.json"
        assert timeout == 5
        endpoint.calls.append(request.full_url)
        if endpoint.unavailable:
            raise URLError("fixture JWKS unavailable")
        return BytesIO(
            json.dumps({"keys": [public_keys[kid] for kid in endpoint.kids]}).encode()
        )

    # Replace only urllib transport: real PyJWKClient fetching, JSON/JWK parsing,
    # key selection, caching and RS256 verification remain under test.
    monkeypatch.setattr(OpenerDirector, "open", open_jwks)
    path = tmp_path / "db"
    initialize(path)
    settings = Settings(
        path, auth0_domain="fixture.invalid", auth0_audience="kickbac-api"
    )

    def token(kid="old", **overrides):
        claims = {
            "iss": "https://fixture.invalid/",
            "aud": "kickbac-api",
            "sub": "auth0|alice",
            "exp": int(time.time()) + 3600,
        }
        claims.update(overrides)
        return jwt.encode(claims, keys[kid], algorithm="RS256", headers={"kid": kid})

    with TestClient(create_app(settings)) as client:

        def request(value=None):
            return client.get(
                "/v1/me",
                headers={"Authorization": "Bearer " + (value or token())},
            )

        yield SimpleNamespace(
            clock=clock, endpoint=endpoint, token=token, request=request
        )


def test_removed_cached_key_is_rejected_after_jwks_ttl(jwks_api):
    api = jwks_api
    old_token = api.token()
    assert api.request(old_token).status_code == 200
    assert len(api.endpoint.calls) == 1
    api.endpoint.kids = ["new"]
    api.clock.now += 301
    response = api.request(old_token)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"
    assert response.headers["www-authenticate"] == "Bearer"
    assert len(api.endpoint.calls) == 2


def test_jwks_set_is_cached_for_300_seconds(jwks_api):
    api = jwks_api
    assert api.request().json() == {"user_id": "auth0|alice"}
    api.endpoint.unavailable = True
    api.clock.now += 299
    assert api.request().status_code == 200
    assert len(api.endpoint.calls) == 1


def test_new_kid_rotation_refreshes_unexpired_jwks(jwks_api):
    api = jwks_api
    assert api.request().status_code == 200
    api.endpoint.kids = ["new"]
    # Beyond PyJWT's unknown-kid refresh cooldown, but within the set TTL.
    api.clock.now += 31
    assert api.request(api.token("new")).status_code == 200
    assert len(api.endpoint.calls) == 2
    assert api.request().status_code == 401


def test_unknown_kid_is_401(jwks_api):
    api = jwks_api
    assert api.request().status_code == 200
    api.clock.now += 31
    response = api.request(api.token("new"))
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"
    assert len(api.endpoint.calls) == 2


@pytest.mark.parametrize("warm_cache", [False, True])
def test_jwks_transport_failure_is_503_not_stale_key_fallback(jwks_api, warm_cache):
    api = jwks_api
    if warm_cache:
        assert api.request().status_code == 200
        api.clock.now += 301
    api.endpoint.unavailable = True
    response = api.request()
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "auth_unavailable"
    assert len(api.endpoint.calls) == (2 if warm_cache else 1)


@pytest.mark.parametrize("kind", ["garbage", "bad_payload", "bad_exp", "wrong_alg"])
def test_malformed_token_does_not_fetch_jwks(jwks_api, kind):
    api = jwks_api
    header = jwt.utils.base64url_encode(b'{"alg":"RS256","kid":"old"}').decode()
    token = {
        "garbage": "not-a-token",
        "bad_payload": header + ".bm90LWpzb24.c2ln",
        "bad_exp": api.token(exp="not-numeric"),
        "wrong_alg": jwt.encode({"exp": 1}, "", algorithm="none"),
    }[kind]
    api.endpoint.unavailable = True
    response = api.request(token)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"
    assert api.endpoint.calls == []
