from contextlib import asynccontextmanager

from fastapi import FastAPI

from .db import check_schema, connect
from .settings import Settings


def create_app(settings=None, verifier=None):
    settings = settings or Settings.from_env()

    @asynccontextmanager
    async def lifespan(app):
        check_schema(settings.db_path)
        yield

    app = FastAPI(title="kickBAC", lifespan=lifespan)
    app.state.settings = settings
    app.state.verifier = verifier

    @app.get("/health")
    def health():
        with connect(settings.db_path) as db:
            db.execute("SELECT 1").fetchone()
        return {"status": "ok"}

    return app


app = create_app()
