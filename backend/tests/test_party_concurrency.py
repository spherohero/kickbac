"""Force cross-application serialization, not only sequential happy paths."""

from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack, contextmanager
from threading import Barrier, Event
from uuid import uuid4

from fastapi.testclient import TestClient

from kickbac.app import create_app
from kickbac.cli import grant_party_device
from kickbac.db import connect


def test_join_limit_is_shared_across_simultaneous_app_instances(world):
    client, users, _, now, path = world
    with ExitStack() as stack:
        clients = [
            stack.enter_context(
                TestClient(
                    create_app(
                        client.app.state.settings,
                        client.app.state.verifier,
                        clock=lambda: now[0],
                    )
                )
            )
            for _ in range(3)
        ]
        barrier = Barrier(12)

        def attempt(index):
            barrier.wait(timeout=10)
            return clients[index % len(clients)].post(
                "/v1/parties/join",
                headers=users["bob"],
                json={"device_id": "unassigned"},
            )

        with ThreadPoolExecutor(12) as pool:
            results = list(pool.map(attempt, range(12)))
    assert sorted(r.status_code for r in results) == [404] * 10 + [429] * 2
    for response in results:
        assert response.headers["cache-control"] == "no-store"
        if response.status_code == 429:
            assert response.headers["retry-after"] == "60"
            assert response.json()["error"]["code"] == "rate_limited"
    with connect(path) as db:
        assert (
            db.execute(
                "SELECT attempts FROM party_join_attempts WHERE user_id='auth0|bob'"
            ).fetchone()[0]
            == 10
        )
        assert db.execute("SELECT COUNT(*) FROM party_members").fetchone()[0] == 0


def test_arm_transaction_fences_concurrent_party_reassignment(world, monkeypatch):
    from kickbac import parties, sessions

    client, users, _, _, path = world
    party = client.post(
        "/v1/parties",
        headers=users["alice"],
        json={"party_id": str(uuid4()), "name": "Race fixture"},
    ).json()
    binding = f"/v1/parties/{party['party_id']}/device"
    for device in ("one", "two"):
        grant_party_device(path, device, "auth0|alice")
    assert (
        client.put(
            binding, headers=users["alice"], json={"device_id": "one"}
        ).status_code
        == 200
    )
    arm_locked, release_arm, binding_started = Event(), Event(), Event()
    original_response, original_transaction = (
        sessions.session_response,
        parties.transaction,
    )

    def paused_response(row, db):
        if row["status"] == "ARMED":
            arm_locked.set()
            assert release_arm.wait(timeout=10)
        return original_response(row, db)

    @contextmanager
    def announced_transaction(db_path):
        binding_started.set()
        with original_transaction(db_path) as db:
            yield db

    monkeypatch.setattr(sessions, "session_response", paused_response)
    monkeypatch.setattr(parties, "transaction", announced_transaction)
    with ThreadPoolExecutor(2) as pool:
        armed = pool.submit(
            client.post, "/v1/devices/one/sessions", headers=users["bob"], json={}
        )
        try:
            assert arm_locked.wait(timeout=10)
            reassignment = pool.submit(
                client.put, binding, headers=users["alice"], json={"device_id": "two"}
            )
            assert binding_started.wait(timeout=10)
            assert not reassignment.done()
        finally:
            release_arm.set()
        assert armed.result(timeout=10).status_code == 201
        rejected = reassignment.result(timeout=10)
    assert rejected.status_code == 409
    assert rejected.json()["error"]["code"] == "device_busy"
    with connect(path) as db:
        assert db.execute("SELECT device_id FROM party_devices").fetchone()[0] == "one"
        assert db.execute("SELECT user_id,status FROM sessions").fetchone()[:] == (
            "auth0|bob",
            "ARMED",
        )
