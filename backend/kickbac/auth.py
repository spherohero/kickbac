import re

import jwt
from fastapi import Request

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
            jwt.decode(token, options={"verify_signature": False})
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


def user_subject(request: Request):
    return request.app.state.verifier(bearer_token(request))
