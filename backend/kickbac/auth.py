import hashlib
import math
import re
from typing import Annotated

import jwt
from fastapi import Request, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .db import connect
from .errors import fail


class JWTVerifier:
    def __init__(self, issuer, audience, key_provider):
        self.issuer = issuer
        self.audience = audience
        self.key_provider = key_provider

    def __call__(self, token):
        try:
            if jwt.get_unverified_header(token).get("alg") != "RS256":
                fail(401, "unauthorized")
            # Parse before network IO; never trust unverified claims.
            unverified = jwt.decode(token, options={"verify_signature": False})
            expiry = unverified.get("exp")
            if (
                isinstance(expiry, bool)
                or not isinstance(expiry, (int, float))
                or (isinstance(expiry, float) and not math.isfinite(expiry))
            ):
                fail(401, "unauthorized")
            claims = jwt.decode(
                token,
                self.key_provider(token),
                algorithms=["RS256"],
                issuer=self.issuer,
                audience=self.audience,
                options={"require": ["iss", "aud", "exp", "sub"]},
            )
            if not isinstance(claims["sub"], str) or not claims["sub"].strip():
                fail(401, "unauthorized")
            if claims.get("gty") == "client-credentials" or claims["sub"].endswith(
                "@clients"
            ):
                fail(401, "unauthorized")
            return claims["sub"]
        except jwt.PyJWKClientConnectionError:
            fail(503, "auth_unavailable")
        except (jwt.InvalidTokenError, jwt.PyJWKClientError):
            fail(401, "unauthorized")


def auth0_verifier(settings):
    label = r"[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"
    if (
        not re.fullmatch(rf"{label}(?:\.{label})+", settings.auth0_domain)
        or len(settings.auth0_domain) > 253
        or not settings.auth0_audience.strip()
    ):
        raise RuntimeError("Auth0 domain and API audience must be configured")
    issuer = "https://" + settings.auth0_domain + "/"
    client = jwt.PyJWKClient(
        issuer + ".well-known/jwks.json", cache_keys=True, lifespan=300, timeout=5
    )
    return JWTVerifier(
        issuer,
        settings.auth0_audience,
        lambda t: client.get_signing_key_from_jwt(t).key,
    )


def bearer_token(request: Request):
    match = re.fullmatch(
        r"(?i:Bearer) ([^\s]+)", request.headers.get("Authorization", "")
    )
    if not match:
        fail(401, "unauthorized")
    return match[1]


user_scheme = HTTPBearer(
    scheme_name="UserAccessToken",
    auto_error=False,
    description="Auth0 RS256 user-delegated API access token (not an ID/M2M token).",
)
device_scheme = HTTPBearer(
    scheme_name="DeviceCredential",
    auto_error=False,
    description="Privately provisioned per-device credential; never a user JWT.",
)


def user_subject(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Security(user_scheme)],
):
    return request.app.state.verifier(bearer_token(request))


def device_identity(
    request: Request,
    credentials: Annotated[
        HTTPAuthorizationCredentials | None, Security(device_scheme)
    ],
):
    digest = hashlib.sha256(bearer_token(request).encode()).hexdigest()
    with connect(request.app.state.settings.db_path) as db:
        row = db.execute(
            "SELECT id FROM devices WHERE credential_hash=?", (digest,)
        ).fetchone()
    if row is None:
        fail(401, "unauthorized")
    return row["id"]
