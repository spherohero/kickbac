from fastapi import HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

MESSAGES = {
    "payload_too_large": "Request payload exceeds the size limit.",
    "unauthorized": "Invalid or missing credentials.",
    "not_found": "Resource not found.",
    "device_busy": "Device has an active test session.",
    "invalid_state": "Operation is not valid for the current state.",
    "session_expired": "Session has expired.",
    "idempotency_conflict": "Resource ID has different accepted fields.",
    "validation_error": "Request validation failed.",
    "auth_unavailable": "Identity verification temporarily unavailable.",
}


def fail(status, code):
    raise HTTPException(
        status,
        detail=code,
        headers={"WWW-Authenticate": "Bearer"} if status == 401 else None,
    )


def install_errors(app):
    @app.exception_handler(StarletteHTTPException)
    async def http_error(request, exc):
        # FastAPI wraps parser depth/integer/encoding failures as HTTP 400.
        # The additive game API promises 422 for all invalid JSON, without
        # changing historical endpoints' handling of malformed requests.
        if (
            exc.status_code == 400
            and request.method == "POST"
            and request.url.path.rstrip("/") == "/v1/me/game-results"
        ):
            exc = StarletteHTTPException(422, "validation_error")
        code = exc.detail if exc.detail in MESSAGES else "not_found"
        return JSONResponse(
            {"error": {"code": code, "message": MESSAGES[code]}},
            status_code=exc.status_code,
            headers=exc.headers,
        )

    @app.exception_handler(RequestValidationError)
    async def validation(request, exc):
        return JSONResponse(
            {
                "error": {
                    "code": "validation_error",
                    "message": MESSAGES["validation_error"],
                }
            },
            status_code=422,
        )

    @app.exception_handler(Exception)
    async def unexpected(request, exc):
        return JSONResponse(
            {"error": {"code": "internal_error", "message": "Internal server error."}},
            status_code=500,
            # ServerErrorMiddleware is outside our profile body/cache middleware.
            headers={"Cache-Control": "no-store"}
            if request.url.path.rstrip("/")
            in {"/v1/me/profile", "/v1/me/game-results", "/v1/me/stats"}
            else None,
        )
