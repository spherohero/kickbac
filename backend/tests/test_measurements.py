import json
from uuid import uuid4

import pytest


def sample(session_id):
    return {
        "measurement_id": str(uuid4()),
        "session_id": session_id,
        "raw": {"sensor": "mq3", "value": 1200, "unit": "adc_counts"},
        "breath_duration_ms": 2500,
        "source": "simulator",
        "measured_at": None,
    }


def test_upload_completes_session_and_replay_does_not_duplicate(world):
    c, u, d, now, _ = world
    s = c.post("/v1/devices/one/sessions", headers=u["alice"], json={}).json()
    payload = sample(s["id"])
    result = c.post("/v1/device/measurements", headers=d["one"], json=payload)
    assert result.status_code == 201
    m = result.json()
    assert m == {
        "id": payload["measurement_id"],
        "session_id": s["id"],
        "device_id": "one",
        "raw": payload["raw"],
        "breath_duration_ms": 2500,
        "source": "simulator",
        "measured_at": None,
        "received_at": now[0].isoformat(),
        "estimated_bac_percent": None,
    }
    retry = c.post("/v1/device/measurements", headers=d["one"], json=payload)
    assert retry.status_code == 200 and retry.json() == m
    complete = c.get("/v1/sessions/" + s["id"], headers=u["alice"]).json()
    assert complete["status"] == "COMPLETE" and complete["measurement"] == m
    assert complete["completed_at"] == m["received_at"]
    assert c.get("/v1/measurements", headers=u["alice"]).json() == {
        "items": [m],
        "limit": 50,
        "offset": 0,
        "has_more": False,
    }
    assert c.get("/v1/measurements", headers=u["bob"]).json()["items"] == []
    assert (
        c.post(
            "/v1/sessions/" + s["id"] + "/cancel", headers=u["alice"], json={}
        ).status_code
        == 409
    )
    assert (
        c.post(
            "/v1/device/sessions/" + s["id"] + "/sampling", headers=d["one"], json={}
        ).status_code
        == 409
    )
    assert (
        c.get("/v1/device/session", headers=d["one"]).json()["active_session"] is None
    )


@pytest.mark.parametrize(
    "field,value",
    [
        ("raw.value", True),
        ("raw.value", "12"),
        ("raw.value", 12.0),
        ("raw.value", -1),
        ("raw.value", 4096),
        ("raw.value", float("nan")),
        ("raw.value", float("inf")),
        ("breath_duration_ms", True),
        ("breath_duration_ms", "2500"),
        ("breath_duration_ms", 1.0),
        ("breath_duration_ms", 0),
        ("breath_duration_ms", 60001),
        ("raw.sensor", "other"),
        ("raw.unit", "bac"),
        ("source", "unknown"),
        ("measurement_id", "bad"),
        ("session_id", "bad"),
        ("measured_at", "2026-10-17T00:00:00"),
        ("measured_at", 1234),
        ("estimated_bac_percent", 0.05),
        ("user_id", "private-marker"),
        ("raw.extra", "private-marker"),
    ],
)
def test_upload_rejects_malformed_fields_generically(world, field, value):
    c, u, d, _, _ = world
    sid = c.post("/v1/devices/one/sessions", headers=u["alice"], json={}).json()["id"]
    payload = sample(sid)
    target = payload
    if "." in field:
        parent, field = field.split(".")
        target = payload[parent]
    target[field] = value
    response = c.post(
        "/v1/device/measurements",
        headers={**d["one"], "Content-Type": "application/json"},
        content=json.dumps(payload),
    )
    assert response.status_code == 422
    assert response.json() == {
        "error": {"code": "validation_error", "message": "Request validation failed."}
    }
    assert c.get("/v1/sessions/" + sid, headers=u["alice"]).json()["status"] == "ARMED"


@pytest.mark.parametrize("query", ["limit=101", "limit=-1", "offset=-1"])
def test_history_pagination_bounds(world, query):
    c, u, _, _, _ = world
    assert c.get("/v1/measurements?" + query, headers=u["alice"]).status_code == 422


def test_replay_canonicalizes_equivalent_timestamp_and_missing_null(world):
    c, u, d, _, _ = world
    sid = c.post("/v1/devices/one/sessions", headers=u["alice"], json={}).json()["id"]
    payload = sample(sid)
    payload["measured_at"] = "2026-10-17T03:00:00+03:00"
    first = c.post("/v1/device/measurements", headers=d["one"], json=payload)
    assert first.status_code == 201
    payload["measured_at"] = "2026-10-17T00:00:00Z"
    second = c.post("/v1/device/measurements", headers=d["one"], json=payload)
    assert second.status_code == 200 and second.json() == first.json()
