from contextlib import asynccontextmanager
from datetime import UTC, datetime
from typing import Annotated

from fastapi import FastAPI

from .db import check_schema, connect
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

    app = FastAPI(title="kickBAC", lifespan=lifespan)
    from .errors import install_errors

    install_errors(app)
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

    @app.get("/v1/me")
    def me(subject: Annotated[str, Depends(user_subject)]):
        return {"user_id": subject}

    from .sessions import router

    app.include_router(router)
    return app


app = create_app()
