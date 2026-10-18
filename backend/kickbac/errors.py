from fastapi import HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

MESSAGES = {
    "payload_too_large": "Profile request or picture exceeds the size limit.",
    "unauthorized": "Invalid or missing credentials.",
    "not_found": "Resource not found.",
    "device_busy": "Device has an active test session.",
    "invalid_state": "Operation is not valid for the current state.",
    "session_expired": "Session has expired.",
    "idempotency_conflict": "Measurement ID has different accepted fields.",
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
            if request.url.path.rstrip("/") == "/v1/me/profile"
            else None,
        )
