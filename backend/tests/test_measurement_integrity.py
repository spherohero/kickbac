from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from threading import Barrier
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from test_measurements import sample

from kickbac.app import create_app
from kickbac.db import connect


def arm(c, u, owner="alice", device="one"):
    response = c.post("/v1/devices/" + device + "/sessions", headers=u[owner], json={})
    assert response.status_code == 201
    return response.json()["id"]


def test_device_and_user_isolation_retry_after_expiry_and_changed_payload(world):
    c, u, d, now, path = world
    sid = arm(c, u)
    payload = sample(sid)
    assert (
        c.post("/v1/device/measurements", headers=d["two"], json=payload).status_code
        == 404
    )
    assert (
        c.post("/v1/device/measurements", headers=u["alice"], json=payload).status_code
        == 401
    )
    first = c.post("/v1/device/measurements", headers=d["one"], json=payload)
    assert first.status_code == 201
    now[0] += timedelta(seconds=70)
    assert (
        c.post("/v1/device/measurements", headers=d["one"], json=payload).json()
        == first.json()
    )
    assert (
        c.post("/v1/device/measurements", headers=d["two"], json=payload).status_code
        == 404
    )
    for change in [
        {"raw": {"sensor": "mq3", "value": 1201, "unit": "adc_counts"}},
        {"source": "device"},
        {"breath_duration_ms": 2501},
        {"measured_at": "2026-10-17T00:00:00Z"},
    ]:
        r = c.post(
            "/v1/device/measurements", headers=d["one"], json={**payload, **change}
        )
        assert (
            r.status_code == 409 and r.json()["error"]["code"] == "idempotency_conflict"
        )
    r = c.post(
        "/v1/device/measurements",
        headers=d["one"],
        json={**payload, "measurement_id": str(uuid4())},
    )
    assert r.status_code == 409 and r.json()["error"]["code"] == "invalid_state"
    assert c.get("/v1/sessions/" + sid, headers=u["bob"]).status_code == 404
    assert c.get("/v1/measurements", headers=u["bob"]).json()["items"] == []
    # Reopen the persistent DB through a fresh application lifespan.
    with TestClient(
        create_app(c.app.state.settings, c.app.state.verifier, clock=lambda: now[0])
    ) as reopened:
        assert (
            reopened.get("/v1/sessions/" + sid, headers=u["alice"]).json()[
                "measurement"
            ]
            == first.json()
        )
        assert (
            reopened.post(
                "/v1/device/measurements", headers=d["one"], json=payload
            ).status_code
            == 200
        )
    with connect(path) as db:
        assert db.execute("SELECT count(*) FROM measurements").fetchone()[0] == 1
        assert (
            db.execute("SELECT user_id FROM measurements").fetchone()[0]
            == "auth0|alice"
        )


@pytest.mark.parametrize("state", ["expired", "cancelled"])
def test_no_upload_to_expired_or_cancelled_and_expiry_persists(world, state):
    c, u, d, now, path = world
    sid = arm(c, u)
    if state == "expired":
        now[0] += timedelta(seconds=60)
    else:
        c.post("/v1/sessions/" + sid + "/cancel", headers=u["alice"], json={})
    response = c.post("/v1/device/measurements", headers=d["one"], json=sample(sid))
    assert response.status_code == (410 if state == "expired" else 409)
    with connect(path) as db:
        assert (
            db.execute("SELECT status FROM sessions WHERE id=?", (sid,)).fetchone()[0]
            == state.upper()
        )
        assert db.execute("SELECT count(*) FROM measurements").fetchone()[0] == 0


@pytest.mark.parametrize("identical", [True, False])
def test_concurrent_uploads_create_exactly_one_result(world, identical):
    c, u, d, _, path = world
    sid = arm(c, u)
    first = sample(sid)
    second = first if identical else sample(sid)
    gate = Barrier(2)

    def submit(payload):
        gate.wait(timeout=5)
        return c.post(
            "/v1/device/measurements", headers=d["one"], json=payload
        ).status_code

    with ThreadPoolExecutor(2) as pool:
        assert sorted(pool.map(submit, [first, second])) == (
            [200, 201] if identical else [201, 409]
        )
    with connect(path) as db:
        assert db.execute("SELECT count(*) FROM measurements").fetchone()[0] == 1
        assert (
            db.execute("SELECT status FROM sessions WHERE id=?", (sid,)).fetchone()[0]
            == "COMPLETE"
        )


def test_global_id_conflict_and_paginated_private_history(world):
    c, u, d, now, _ = world
    created = []
    for owner, device in [
        ("alice", "one"),
        ("alice", "one"),
        ("bob", "two"),
        ("alice", "two"),
    ]:
        sid = arm(c, u, owner, device)
        payload = sample(sid)
        if created:
            conflict = c.post(
                "/v1/device/measurements",
                headers=d[device],
                json={**payload, "measurement_id": created[0]["id"]},
            )
            assert conflict.status_code == (409 if device == "one" else 404)
        result = c.post("/v1/device/measurements", headers=d[device], json=payload)
        assert result.status_code == 201
        created.append(result.json())
        # First two share a receive timestamp to exercise the ID tiebreak.
        if len(created) != 1:
            now[0] += timedelta(seconds=1)
    expected = sorted(
        [created[0], created[1], created[3]],
        key=lambda m: (m["received_at"], m["id"]),
        reverse=True,
    )
    page1 = c.get("/v1/measurements?limit=2", headers=u["alice"]).json()
    page2 = c.get("/v1/measurements?limit=2&offset=2", headers=u["alice"]).json()
    assert page1 == {"items": expected[:2], "limit": 2, "offset": 0, "has_more": True}
    assert page2 == {"items": expected[2:], "limit": 2, "offset": 2, "has_more": False}
    assert c.get("/v1/measurements?limit=0", headers=u["alice"]).json() == {
        "items": [],
        "limit": 0,
        "offset": 0,
        "has_more": True,
    }
    assert c.get("/v1/measurements?offset=99", headers=u["alice"]).json()["items"] == []


def test_upload_and_completion_rollback_together_on_storage_failure(world):
    c, u, d, _, path = world
    sid = arm(c, u)
    with connect(path) as db:
        db.execute(
            "CREATE TRIGGER fail_complete BEFORE UPDATE OF status ON sessions WHEN NEW.status='COMPLETE' BEGIN SELECT RAISE(ABORT,'private-storage-marker'); END"
        )
    with TestClient(c.app, raise_server_exceptions=False) as client:
        response = client.post(
            "/v1/device/measurements", headers=d["one"], json=sample(sid)
        )
    assert response.status_code == 500 and "private-storage-marker" not in response.text
    with connect(path) as db:
        assert db.execute("SELECT count(*) FROM measurements").fetchone()[0] == 0
        assert (
            db.execute("SELECT status FROM sessions WHERE id=?", (sid,)).fetchone()[0]
            == "ARMED"
        )
