from datetime import timedelta
from uuid import uuid4


def test_private_pages_summary_order_and_huge_offset(world):
    c, users, devices, _, _ = world
    for route in ["/v1/me/app-readings", "/v1/me/app-reading-summary"]:
        assert c.get(route).status_code == 401
        assert c.get(route, headers=devices["one"]).status_code == 401
    receipts = [
        c.post("/v1/me/app-readings", headers=users["alice"], json=reading()).json()
        for _ in range(3)
    ]
    receipts.sort(key=lambda r: (r["recorded_at"], r["reading_id"]), reverse=True)
    page = c.get("/v1/me/app-readings?limit=2", headers=users["alice"])
    assert page.json() == {
        "items": receipts[:2],
        "limit": 2,
        "offset": 0,
        "has_more": True,
    }
    assert (
        c.get("/v1/me/app-readings?offset=2", headers=users["alice"]).json()["items"]
        == receipts[2:]
    )
    assert (
        c.get(
            "/v1/me/app-readings?offset=" + str(2**100), headers=users["alice"]
        ).json()["items"]
        == []
    )
    assert c.get("/v1/me/app-reading-summary", headers=users["alice"]).json() == {
        "user_id": "auth0|alice",
        "source": "app_generated",
        "saved_readings": 3,
        "latest_reading": receipts[0],
    }
    assert (
        c.get("/v1/me/app-reading-summary", headers=users["bob"]).json()[
            "latest_reading"
        ]
        is None
    )
    assert c.get("/v1/me/app-readings", headers=users["bob"]).json()["items"] == []


def test_quota_exact_boundary_restart_replay_and_rollback(world):
    from fastapi.testclient import TestClient

    from kickbac.app import create_app
    from kickbac.db import connect
    from kickbac.settings import Settings

    c, users, _, now, path = world
    body = reading()
    assert (
        c.post("/v1/me/app-readings", headers=users["alice"], json=body).status_code
        == 201
    )
    for _ in range(59):
        assert (
            c.post(
                "/v1/me/app-readings", headers=users["alice"], json=reading()
            ).status_code
            == 201
        )
    with TestClient(
        create_app(Settings(path), c.app.state.verifier, clock=lambda: now[0]),
        raise_server_exceptions=False,
    ) as fresh:
        limited = fresh.post(
            "/v1/me/app-readings", headers=users["alice"], json=reading()
        )
        assert limited.status_code == 429
        assert limited.headers["retry-after"] == "60"
        assert (
            fresh.post(
                "/v1/me/app-readings", headers=users["alice"], json=body
            ).status_code
            == 200
        )
        now[0] += timedelta(seconds=59.5)
        assert (
            fresh.post(
                "/v1/me/app-readings", headers=users["alice"], json=reading()
            ).headers["retry-after"]
            == "1"
        )
        now[0] += timedelta(seconds=0.5)
        with connect(path) as db:
            db.execute(
                "CREATE TRIGGER fail_app BEFORE INSERT ON app_readings BEGIN SELECT RAISE(ABORT,'fixture'); END"
            )
        assert (
            fresh.post(
                "/v1/me/app-readings", headers=users["alice"], json=reading()
            ).status_code
            == 500
        )
        with connect(path) as db:
            assert (
                db.execute("SELECT accepted FROM app_reading_save_windows").fetchone()[
                    0
                ]
                == 60
            )
            db.execute("DROP TRIGGER fail_app")
        assert (
            fresh.post(
                "/v1/me/app-readings", headers=users["alice"], json=reading()
            ).status_code
            == 201
        )


def test_canonical_replay_precedes_clock_and_conflicts_hide_foreign_owner(world):
    c, users, _, _, _ = world
    body = reading(value=1)
    first = c.post("/v1/me/app-readings", headers=users["alice"], json=body)
    c.app.state.clock = lambda: (_ for _ in ()).throw(AssertionError("retry clock"))
    retry = c.post(
        "/v1/me/app-readings",
        headers=users["alice"],
        json={**body, "value": 1.0, "recorded_at": "2026-10-18T10:00:00Z"},
    )
    assert retry.status_code == 200 and retry.json() == first.json()
    assert (
        c.post(
            "/v1/me/app-readings", headers=users["alice"], json={**body, "value": 0}
        ).status_code
        == 409
    )
    assert (
        c.post("/v1/me/app-readings", headers=users["bob"], json=body).status_code
        == 404
    )


def reading(**changes):
    return {
        "reading_id": str(uuid4()),
        "value": 0.08,
        "recorded_at": "2026-10-18T11:00:00+01:00",
        "duration_ms": 2500,
        "source": "app_generated",
        **changes,
    }


def test_save_returns_private_owner_receipt(world):
    c, users, _, _, _ = world
    body = reading()
    r = c.post("/v1/me/app-readings", headers=users["alice"], json=body)
    assert r.status_code == 201
    assert r.json() == {
        **body,
        "recorded_at": "2026-10-18T10:00:00+00:00",
        "user_id": "auth0|alice",
        "received_at": "2026-10-17T00:00:00+00:00",
    }
    assert r.headers["cache-control"] == "no-store"
