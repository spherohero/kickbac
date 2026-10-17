from datetime import datetime, timedelta

import pytest


def test_resolution_arm_retry_and_ownership(world):
    c, u, _, _, _ = world
    assert c.get("/d/one").json() == {"device_id": "one"}
    assert c.get("/d/missing").status_code == 404
    assert c.get("/v1/devices/one", headers=u["alice"]).json() == {
        "id": "one",
        "state": "AVAILABLE",
        "online": False,
        "last_seen_at": None,
    }
    first = c.post("/v1/devices/one/sessions", headers=u["alice"], json={})
    assert first.status_code == 201
    s = first.json()
    assert set(s) == {
        "id",
        "device_id",
        "user_id",
        "status",
        "created_at",
        "expires_at",
        "completed_at",
        "measurement",
    }
    assert (
        s["status"] == "ARMED"
        and s["device_id"] == "one"
        and s["user_id"] == "auth0|alice"
    )
    assert datetime.fromisoformat(s["expires_at"]) - datetime.fromisoformat(
        s["created_at"]
    ) == timedelta(seconds=60)
    retry = c.post("/v1/devices/one/sessions", headers=u["alice"], json={})
    assert retry.status_code == 200 and retry.json() == s
    assert (
        c.post("/v1/devices/one/sessions", headers=u["bob"], json={}).json()["error"][
            "code"
        ]
        == "device_busy"
    )
    assert c.get("/v1/sessions/" + s["id"], headers=u["alice"]).json() == s
    assert c.get("/v1/sessions/" + s["id"], headers=u["bob"]).status_code == 404
    assert c.get("/v1/devices/one", headers=u["bob"]).json()["state"] == "ARMED"


def test_device_heartbeat_poll_and_sampling(world):
    c, u, d, now, _ = world
    assert c.get("/v1/device/session", headers=d["one"]).json() == {
        "device_id": "one",
        "active_session": None,
    }
    beat = c.post("/v1/device/heartbeat", headers=d["one"], json={})
    assert beat.status_code == 200
    assert beat.json() == {
        "device_id": "one",
        "online": True,
        "last_seen_at": now[0].isoformat(),
    }
    assert c.get("/v1/devices/one", headers=u["alice"]).json()["online"] is True
    s = c.post("/v1/devices/one/sessions", headers=u["alice"], json={}).json()
    poll = c.get("/v1/device/session", headers=d["one"]).json()
    assert set(poll["active_session"]) == {"id", "device_id", "status", "expires_at"}
    assert poll["active_session"]["id"] == s["id"]
    route = "/v1/device/sessions/" + s["id"] + "/sampling"
    assert c.post(route, headers=d["two"], json={}).status_code == 404
    first = c.post(route, headers=d["one"], json={})
    assert first.status_code == 200 and first.json()["status"] == "SAMPLING"
    assert set(first.json()) == {"id", "device_id", "status", "expires_at"}
    assert c.post(route, headers=d["one"], json={}).json() == first.json()
    assert c.get("/v1/devices/one", headers=u["alice"]).json()["state"] == "SAMPLING"
    now[0] += timedelta(seconds=30)
    assert c.get("/v1/devices/one", headers=u["alice"]).json()["online"] is False
    assert (
        c.get("/v1/sessions/" + s["id"], headers=u["alice"]).json()["expires_at"]
        == s["expires_at"]
    )
    assert c.get("/v1/device/session", headers=u["alice"]).status_code == 401
    assert c.get("/v1/me", headers=d["one"]).status_code == 401


@pytest.mark.parametrize(
    "operation", ["read", "device", "poll", "arm", "cancel", "sampling", "heartbeat"]
)
def test_expiry_boundary_is_committed(world, operation):
    from kickbac.db import connect

    c, u, d, now, path = world
    s = c.post("/v1/devices/one/sessions", headers=u["alice"], json={}).json()
    now[0] += timedelta(seconds=60)
    if operation == "read":
        assert (
            c.get("/v1/sessions/" + s["id"], headers=u["alice"]).json()["status"]
            == "EXPIRED"
        )
    elif operation == "device":
        assert (
            c.get("/v1/devices/one", headers=u["alice"]).json()["state"] == "AVAILABLE"
        )
    elif operation == "poll":
        assert (
            c.get("/v1/device/session", headers=d["one"]).json()["active_session"]
            is None
        )
    elif operation == "arm":
        response = c.post("/v1/devices/one/sessions", headers=u["bob"], json={})
        assert response.status_code == 201 and response.json()["id"] != s["id"]
    elif operation == "heartbeat":
        assert (
            c.post("/v1/device/heartbeat", headers=d["one"], json={}).status_code == 200
        )
    else:
        route = (
            "/v1/sessions/" + s["id"] + "/cancel"
            if operation == "cancel"
            else "/v1/device/sessions/" + s["id"] + "/sampling"
        )
        response = c.post(
            route, headers=u["alice"] if operation == "cancel" else d["one"], json={}
        )
        assert response.status_code == 410
        assert response.json()["error"]["code"] == "session_expired"
    with connect(path) as db:
        assert (
            db.execute("SELECT status FROM sessions WHERE id=?", (s["id"],)).fetchone()[
                0
            ]
            == "EXPIRED"
        )


def test_cancel_is_idempotent_and_terminal(world):
    c, u, d, _, _ = world
    s = c.post("/v1/devices/one/sessions", headers=u["alice"], json={}).json()
    route = "/v1/sessions/" + s["id"] + "/cancel"
    assert c.post(route, headers=u["bob"], json={}).status_code == 404
    first = c.post(route, headers=u["alice"], json={})
    assert first.status_code == 200 and first.json()["status"] == "CANCELLED"
    assert c.post(route, headers=u["alice"], json={}).json() == first.json()
    assert (
        c.post(
            "/v1/device/sessions/" + s["id"] + "/sampling", headers=d["one"], json={}
        ).status_code
        == 409
    )
    assert (
        c.get("/v1/device/session", headers=d["one"]).json()["active_session"] is None
    )
