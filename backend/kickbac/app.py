from contextlib import asynccontextmanager
from datetime import UTC, datetime
from typing import Annotated

from fastapi import FastAPI

from .db import check_schema, connect
from .models import ErrorEnvelope, MeResponse
from .settings import Settings


def create_app(settings=None, verifier=None, clock=None):
    settings = settings or Settings.from_env()

    @asynccontextmanager
    async def lifespan(app):
        check_schema(settings.db_path)
        if app.state.verifier is None:
            from .auth import auth0_verifier

            app.state.verifier = auth0_verifier(settings)
        yield

    app = FastAPI(
        title="kickBAC",
        lifespan=lifespan,
        responses={
            status: {"model": ErrorEnvelope}
            for status in (401, 404, 409, 410, 422, 500, 503)
        },
    )
    from .errors import install_errors

    install_errors(app)
    from .profile_body import ProfileBodyLimit

    app.add_middleware(ProfileBodyLimit)
    app.state.settings = settings
    app.state.verifier = verifier
    app.state.clock = clock or (lambda: datetime.now(UTC))

    @app.get("/health")
    def health():
        with connect(settings.db_path) as db:
            db.execute("SELECT 1").fetchone()
        return {"status": "ok"}

    from fastapi import Depends

    from .auth import user_subject

    @app.get("/v1/me", response_model=MeResponse)
    def me(subject: Annotated[str, Depends(user_subject)]):
        return {"user_id": subject}

    from .games import router as games_router
    from .measurements import router as measurements_router
    from .profiles import router as profiles_router
    from .sessions import router

    app.include_router(router)
    app.include_router(measurements_router)
    app.include_router(profiles_router)
    app.include_router(games_router)
    from .parties import router as parties_router

    app.include_router(parties_router)
    return app


app = create_app()
