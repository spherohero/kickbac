"""Signed isolated fixtures for retry, privacy and transactional failure boundaries."""

import asyncio
import json
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from threading import Event
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from test_party_check_ins import body, post
from test_party_games import party_world as party_world

from kickbac.app import create_app
from kickbac.db import connect
from kickbac.settings import Settings


def test_clock_captured_once_after_writer_lock(party_world, monkeypatch):
    c, _, _, now, path, _ = party_world
    import kickbac.db as module

    original = module.connect
    waiting = Event()
    called = Event()

    def clock():
        called.set()
        return now[0]

    c.app.state.clock = clock

    def traced(path):
        db = original(path)
        db.set_trace_callback(
            lambda sql: waiting.set() if sql == "BEGIN IMMEDIATE" else None
        )
        return db

    with original(path) as lock:
        lock.execute("BEGIN IMMEDIATE")
        monkeypatch.setattr(module, "connect", traced)
        with ThreadPoolExecutor(max_workers=1) as pool:
            task = pool.submit(post, party_world, body())
            try:
                assert waiting.wait(3)
                assert not called.is_set()
                now[0] += timedelta(seconds=10)
            finally:
                lock.commit()
            r = task.result(10)
    assert r.status_code == 201, r.text
    assert r.json()["session"]["created_at"] == now[0].isoformat()


@pytest.mark.parametrize("mode", ["identical", "changed", "new_id", "ordinary"])
def test_concurrent_claims(party_world, mode):
    c, u, _, _, path, _ = party_world
    first = body()
    second = {**first}
    if mode == "changed":
        from test_party_games import create_game

        second["game_instance_id"] = create_game(party_world).json()["game_instance_id"]
    if mode == "new_id":
        second["check_in_id"] = str(uuid4())
    gate = Event()

    def claim(which):
        gate.wait(3)
        if which and mode == "ordinary":
            return c.post("/v1/devices/one/sessions", headers=u["alice"], json={})
        return post(party_world, second if which else first)

    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(claim, n) for n in (0, 1)]
        gate.set()
        responses = [f.result(10) for f in futures]
    assert sorted(r.status_code for r in responses) == (
        [200, 201] if mode == "identical" else [201, 409]
    )
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM sessions").fetchone()[0] == 1
        assert db.execute("SELECT COUNT(*) FROM party_check_ins").fetchone()[0] == (
            0 if mode == "ordinary" and responses[1].status_code == 201 else 1
        )


@pytest.mark.parametrize(
    "rejection", ["not_found", "invalid_state", "idempotency_conflict"]
)
def test_boundary_expiry_persists_on_rejection(party_world, rejection):
    _, _, _, now, path, _ = party_world
    payload = body()
    first = post(party_world, payload).json()
    now[0] += timedelta(seconds=60)
    if rejection == "not_found":
        payload = body(device_id="two")
    if rejection == "invalid_state":
        payload = body(game_instance_id=str(uuid4()))
    if rejection == "idempotency_conflict":
        payload["device_id"] = "two"
    r = post(party_world, payload)
    assert r.status_code == (404 if rejection == "not_found" else 409)
    assert r.json()["error"]["code"] == rejection
    with connect(path) as db:
        assert (
            db.execute(
                "SELECT status FROM sessions WHERE id=?", (first["session"]["id"],)
            ).fetchone()[0]
            == "EXPIRED"
        )
        assert db.execute("SELECT COUNT(*) FROM party_check_ins").fetchone()[0] == 1


def test_second_insert_failure_rolls_back_session_and_expiry(party_world):
    c, _, _, now, path, _ = party_world
    first = post(party_world, body()).json()
    now[0] += timedelta(seconds=60)
    with connect(path) as db:
        db.execute(
            "CREATE TRIGGER fail_check_in BEFORE INSERT ON party_check_ins BEGIN SELECT RAISE(ABORT,'private-storage-marker'); END"
        )
        before = list(db.iterdump())
    with TestClient(c.app, raise_server_exceptions=False) as safe:
        r = post((safe, *party_world[1:]), body())
    assert r.status_code == 500
    assert r.headers["cache-control"] == "no-store"
    assert "private-storage-marker" not in r.text
    with connect(path) as db:
        assert list(db.iterdump()) == before
        assert (
            db.execute(
                "SELECT status FROM sessions WHERE id=?", (first["session"]["id"],)
            ).fetchone()[0]
            == "ARMED"
        )


@pytest.mark.parametrize("terminal", ["CANCELLED", "EXPIRED"])
def test_terminal_retry_survives_restart_close_leave_rebind(party_world, terminal):
    c, u, _, now, path, party = party_world
    payload = body()
    first = post(party_world, payload).json()
    sid = first["session"]["id"]
    if terminal == "CANCELLED":
        assert (
            c.post(f"/v1/sessions/{sid}/cancel", headers=u["bob"], json={}).status_code
            == 200
        )
    else:
        now[0] += timedelta(seconds=60)
        assert post(party_world, payload).json()["session"]["status"] == "EXPIRED"
    # Historical context must not depend on current assignment.
    with connect(path) as db:
        db.execute(
            "UPDATE party_members SET left_at=? WHERE user_id='auth0|bob'",
            (now[0].isoformat(),),
        )
        db.execute("UPDATE party_devices SET device_id='two'")
        db.execute(
            "UPDATE parties SET state='CLOSED',closed_at=?", (now[0].isoformat(),)
        )
    app = create_app(Settings(path), c.app.state.verifier, clock=lambda: now[0])
    with TestClient(app) as restarted:
        r = post((restarted, *party_world[1:]), payload)
        assert r.status_code == 200, r.text
        first["session"]["status"] = terminal
        assert r.json() == first
        assert restarted.get("/v1/me/check-ins", headers=u["bob"]).json()["items"] == [
            first
        ]


def test_history_read_only_snapshot_order_pagination_and_no_expiry(
    party_world, monkeypatch
):
    c, u, _, now, path, _ = party_world
    items = []
    for _n in range(3):
        item = post(party_world, body()).json()
        items.append(item)
        c.post(
            "/v1/sessions/" + item["session"]["id"] + "/cancel",
            headers=u["bob"],
            json={},
        )
    # All creation instants tie; ID descending is the stable tie-breaker.
    items.sort(key=lambda i: i["check_in_id"], reverse=True)
    active = post(party_world, body(), user="alice").json()
    now[0] += timedelta(seconds=60)
    with connect(path) as db:
        before = list(db.iterdump())
    from contextlib import contextmanager

    import kickbac.party_check_ins as module

    statements = []

    @contextmanager
    def traced(path):
        with connect(path) as db:
            db.set_trace_callback(statements.append)
            yield db

    monkeypatch.setattr(module, "connect", traced)
    first = c.get("/v1/me/check-ins?limit=2", headers=u["bob"]).json()
    second = c.get("/v1/me/check-ins?limit=2&offset=2", headers=u["bob"]).json()
    assert [i["check_in_id"] for i in first["items"] + second["items"]] == [
        i["check_in_id"] for i in items
    ]
    assert first["has_more"] is True and second["has_more"] is False
    assert all(
        i["session"]["status"] == "CANCELLED" for i in first["items"] + second["items"]
    )
    assert statements[:2] == ["PRAGMA query_only=ON", "BEGIN"]
    huge = 10**100
    assert c.get(f"/v1/me/check-ins?offset={huge}", headers=u["bob"]).json() == {
        "items": [],
        "limit": 50,
        "offset": huge,
        "has_more": False,
    }
    with connect(path) as db:
        assert list(db.iterdump()) == before
        assert (
            db.execute(
                "SELECT status FROM sessions WHERE id=?", (active["session"]["id"],)
            ).fetchone()[0]
            == "ARMED"
        )


@pytest.mark.parametrize(
    "query",
    ["limit=0", "limit=101", "limit=1.5", "limit=true", "offset=-1", "offset=1.5"],
)
def test_history_pagination_validation(party_world, query):
    c, u, *_ = party_world
    r = c.get("/v1/me/check-ins?" + query, headers=u["bob"])
    assert r.status_code == 422
    assert r.headers["cache-control"] == "no-store"


@pytest.mark.parametrize("method", ["get", "post"])
def test_private_auth_and_storage_errors(party_world, method):
    c, u, _, _, path, party = party_world
    url = "/v1/me/check-ins" if method == "get" else f"/v1/parties/{party}/check-ins"
    kwargs = {} if method == "get" else {"json": body()}
    r = getattr(c, method)(url, **kwargs)
    assert r.status_code == 401
    assert r.headers["cache-control"] == "no-store"
    with TestClient(c.app, raise_server_exceptions=False) as safe:
        with connect(path) as db:
            db.execute("DROP TABLE party_check_ins")
        r = getattr(safe, method)(url, headers=u["bob"], **kwargs)
    assert r.status_code == 500
    assert r.headers["cache-control"] == "no-store"


@pytest.mark.parametrize(
    "payload", [b"{", b"\xff", b"[" * 1500 + b"]" * 1500, b'{"n":' + b"9" * 5000 + b"}"]
)
def test_malformed_check_in_json(party_world, payload):
    c, u, _, _, _, party = party_world
    r = c.post(
        f"/v1/parties/{party}/check-ins",
        headers={**u["bob"], "Content-Type": "application/json"},
        content=payload,
    )
    assert r.status_code == 422, r.text
    assert r.headers["cache-control"] == "no-store"
    assert r.json()["error"]["code"] == "validation_error"


@pytest.mark.parametrize("length", [None, b"1"])
def test_actual_asgi_stream_cap(party_world, length):
    c, u, _, _, path, party = party_world
    messages = []
    chunks = iter(
        [
            {"type": "http.request", "body": b"x" * 17000, "more_body": True},
            {"type": "http.request", "body": b"x" * 17000, "more_body": False},
        ]
    )

    async def receive():
        return next(chunks)

    async def send(message):
        messages.append(message)

    scope = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "scheme": "http",
        "method": "POST",
        "path": f"/v1/parties/{party}/check-ins",
        "raw_path": f"/v1/parties/{party}/check-ins".encode(),
        "query_string": b"",
        "root_path": "",
        "server": ("testserver", 80),
        "client": ("testclient", 1),
        "headers": [
            (b"authorization", u["bob"]["Authorization"].encode()),
            (b"content-type", b"application/json"),
        ]
        + ([] if length is None else [(b"content-length", length)]),
    }
    asyncio.run(c.app(scope, receive, send))
    assert messages[0]["status"] == 413
    assert (b"cache-control", b"no-store") in messages[0]["headers"]
    assert json.loads(messages[1]["body"])["error"]["code"] == "payload_too_large"
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM sessions").fetchone()[0] == 0


@pytest.mark.parametrize(
    "field,value",
    [
        ("check_in_id", "bad"),
        ("game_instance_id", "bad"),
        ("user_id", "auth0|alice"),
        ("device_id", "one\n"),
    ],
)
def test_invalid_identity_fields(party_world, field, value):
    r = post(party_world, body(**{field: value}))
    assert r.status_code == 422, r.text


def test_exact_body_byte_boundary(party_world):
    c, u, _, _, _, party = party_world
    url = f"/v1/parties/{party}/check-ins"
    encoded = json.dumps(body()).encode()
    r = c.post(
        url,
        headers={**u["bob"], "Content-Type": "application/json"},
        content=encoded + b" " * (32768 - len(encoded)),
    )
    assert r.status_code == 201, r.text
    r = c.post(url, headers=u["bob"], content=b"x" * 32769)
    assert r.status_code == 413
    assert r.headers["cache-control"] == "no-store"


def test_legacy_arm_returns_existing_check_in_without_relabel(party_world):
    c, u, _, _, path, _ = party_world
    first = post(party_world, body()).json()
    r = c.post("/v1/devices/one/sessions", headers=u["bob"], json={})
    assert r.status_code == 200
    assert r.json() == first["session"]
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM party_check_ins").fetchone()[0] == 1
