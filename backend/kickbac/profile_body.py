from starlette.responses import JSONResponse

from .errors import MESSAGES, is_party_private

PROFILE_BODY_LIMIT = 1024 * 1024
GAME_BODY_LIMIT = 32768
PRIVATE_BODY_POLICIES = {
    "/v1/me/app-readings": ("POST", GAME_BODY_LIMIT),
    "/v1/me/app-reading-summary": (None, 0),
    "/v1/me/profile": ("PUT", PROFILE_BODY_LIMIT),
    "/v1/me/game-results": ("POST", GAME_BODY_LIMIT),
    "/v1/me/stats": (None, 0),
    "/v1/me/reading-summary": (None, 0),
}


class ProfileBodyLimit:
    """Bound bytes before JSON parsing, regardless of Content-Length/chunking."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        policy = PRIVATE_BODY_POLICIES.get(scope["path"].rstrip("/"))
        if is_party_private(scope["path"]):
            policy = (
                scope["method"] if scope["method"] in {"POST", "PUT"} else None,
                GAME_BODY_LIMIT,
            )
        if policy is None:
            return await self.app(scope, receive, send)
        method, body_limit = policy

        async def private_send(message):
            if message["type"] == "http.response.start":
                headers = [
                    (k, v)
                    for k, v in message.get("headers", [])
                    if k.lower() != b"cache-control"
                ]
                message = {
                    **message,
                    "headers": headers + [(b"cache-control", b"no-store")],
                }
            await send(message)

        async def too_large():
            response = JSONResponse(
                {
                    "error": {
                        "code": "payload_too_large",
                        "message": MESSAGES["payload_too_large"],
                    }
                },
                status_code=413,
            )
            await response(scope, receive, private_send)

        if scope["method"] != method:
            return await self.app(scope, receive, private_send)
        for key, value in scope.get("headers", []):
            if key.lower() == b"content-length" and value.isdigit():
                # Compare as decimal text, avoiding unbounded int conversion.
                length = value.lstrip(b"0") or b"0"
                limit = str(body_limit).encode("ascii")
                if len(length) > len(limit) or (
                    len(length) == len(limit) and length > limit
                ):
                    return await too_large()
        body = bytearray()
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            if len(body) + len(chunk) > body_limit:
                return await too_large()
            body.extend(chunk)
            if not message.get("more_body", False):
                break

        async def buffered_receive():
            return {"type": "http.request", "body": bytes(body), "more_body": False}

        await self.app(scope, buffered_receive, private_send)
