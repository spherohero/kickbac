from starlette.responses import JSONResponse

from .errors import MESSAGES

PROFILE_BODY_LIMIT = 1024 * 1024


class ProfileBodyLimit:
    """Bound bytes before JSON parsing, regardless of Content-Length/chunking."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope["path"].rstrip("/") != "/v1/me/profile":
            return await self.app(scope, receive, send)

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

        if scope["method"] != "PUT":
            return await self.app(scope, receive, private_send)
        for key, value in scope.get("headers", []):
            if key.lower() == b"content-length" and value.isdigit():
                # Compare as decimal text, avoiding unbounded int conversion.
                length = value.lstrip(b"0") or b"0"
                limit = str(PROFILE_BODY_LIMIT).encode("ascii")
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
            if len(body) + len(chunk) > PROFILE_BODY_LIMIT:
                return await too_large()
            body.extend(chunk)
            if not message.get("more_body", False):
                break

        async def buffered_receive():
            return {"type": "http.request", "body": bytes(body), "more_body": False}

        await self.app(scope, buffered_receive, private_send)
