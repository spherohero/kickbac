from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient
from test_app_readings import reading

from kickbac.db import connect


@pytest.mark.parametrize(
    "change",
    [
        {"value": True},
        {"value": "0.1"},
        {"value": -0.1},
        {"value": 1.1},
        {"duration_ms": True},
        {"duration_ms": 1.0},
        {"duration_ms": 0},
        {"duration_ms": 60001},
        {"recorded_at": 1},
        {"recorded_at": "123456"},
        {"recorded_at": "2026-10-18"},
        {"recorded_at": "2026-10-18T12:00:00"},
        {"source": "device"},
        {"user_id": "bob"},
        {"reading_id": "invalid"},
    ],
)
def test_strict_fields(world, change):
    c, users, _, _, _ = world
    r = c.post("/v1/me/app-readings", headers=users["alice"], json=reading(**change))
    assert r.status_code == 422
    assert r.headers["cache-control"] == "no-store"


@pytest.mark.parametrize(
    "field", ["reading_id", "value", "recorded_at", "duration_ms", "source"]
)
def test_required_fields(world, field):
    c, users, _, _, _ = world
    body = reading()
    del body[field]
    assert (
        c.post("/v1/me/app-readings", headers=users["alice"], json=body).status_code
        == 422
    )


@pytest.mark.parametrize(
    "raw",
    [
        b"\xff",
        b"[" * 2000 + b"0" + b"]" * 2000,
        b'{"value":NaN}',
        b'{"value":Infinity}',
    ],
)
def test_parser_errors_private_422(world, raw):
    c, users, _, _, _ = world
    r = c.post(
        "/v1/me/app-readings",
        headers={**users["alice"], "Content-Type": "application/json"},
        content=raw,
    )
    assert r.status_code == 422
    assert r.headers["cache-control"] == "no-store"


def test_outer_storage_error_is_private_and_rolls_back(world):
    c, users, _, _, path = world
    with connect(path) as db:
        db.execute(
            "CREATE TRIGGER fail_app BEFORE INSERT ON app_readings BEGIN SELECT RAISE(ABORT,'private fixture'); END"
        )
    with TestClient(c.app, raise_server_exceptions=False) as fresh:
        r = fresh.post("/v1/me/app-readings", headers=users["alice"], json=reading())
    assert r.status_code == 500
    assert r.headers["cache-control"] == "no-store"
    assert r.json() == {
        "error": {"code": "internal_error", "message": "Internal server error."}
    }
    with connect(path) as db:
        assert (
            db.execute("SELECT COUNT(*) FROM app_reading_save_windows").fetchone()[0]
            == 0
        )


def test_concurrent_equal_and_changed_retries(world):
    c, users, _, _, path = world
    body = reading()

    def post(payload):
        return c.post("/v1/me/app-readings", headers=users["alice"], json=payload)

    with ThreadPoolExecutor(4) as pool:
        equal = list(pool.map(post, [body] * 4))
        changed = list(pool.map(post, [{**body, "value": 0.9}] * 4))
    assert sorted(r.status_code for r in equal) == [200, 200, 200, 201]
    assert all(r.json() == equal[0].json() for r in equal)
    assert all(r.status_code == 409 for r in changed)
    with connect(path) as db:
        assert (
            db.execute("SELECT accepted FROM app_reading_save_windows").fetchone()[0]
            == 1
        )


def test_body_limit_streamed_false_header(world):
    import asyncio

    c, users, _, _, _ = world

    async def run():
        messages = iter(
            [
                {"type": "http.request", "body": b" " * 20000, "more_body": True},
                {"type": "http.request", "body": b" " * 12769, "more_body": False},
            ]
        )
        sent = []

        async def receive():
            return next(messages)

        async def send(message):
            sent.append(message)

        await c.app(
            {
                "type": "http",
                "asgi": {"version": "3.0"},
                "http_version": "1.1",
                "method": "POST",
                "scheme": "http",
                "path": "/v1/me/app-readings",
                "raw_path": b"/v1/me/app-readings",
                "query_string": b"",
                "headers": [(b"content-length", b"1")],
                "client": ("127.0.0.1", 1),
                "server": ("test", 80),
            },
            receive,
            send,
        )
        assert sent[0]["status"] == 413
        assert (b"cache-control", b"no-store") in sent[0]["headers"]

    asyncio.run(run())
    assert (
        c.post(
            "/v1/me/app-readings", headers=users["alice"], content=b" " * 32769
        ).status_code
        == 413
    )


@pytest.mark.parametrize("query", ["limit=0", "limit=101", "offset=-1"])
def test_page_bounds(world, query):
    c, users, _, _, _ = world
    assert (
        c.get("/v1/me/app-readings?" + query, headers=users["alice"]).status_code == 422
    )
