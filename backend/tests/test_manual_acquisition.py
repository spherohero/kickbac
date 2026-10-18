"""Synthetic manual acquisition fixtures; not physical sensor evidence."""

from test_measurements import sample

import pytest

from kickbac.db import connect


def manual_sample(session_id):
    return {
        **sample(session_id),
        "breath_duration_ms": None,
        "acquisition_method": "manual_timed",
        "sample_duration_ms": 5000,
    }


def test_reject_null_duration_without_manual_metadata_without_writes(world):
    c, u, d, _, path = world
    sid = c.post("/v1/devices/one/sessions", headers=u["alice"], json={}).json()["id"]
    payload = {**sample(sid), "breath_duration_ms": None}
    assert c.post("/v1/device/measurements", headers=d["one"], json=payload).status_code == 422
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM measurements").fetchone()[0] == 0
        assert db.execute("SELECT status FROM sessions WHERE id=?", (sid,)).fetchone()[0] == "ARMED"


@pytest.mark.parametrize("metadata", [
    {"acquisition_method": "manual_timed", "sample_duration_ms": 5000},
    {"acquisition_method": "manual_timed"},
    {"sample_duration_ms": 5000},
    {"acquisition_method": None},
    {"sample_duration_ms": None},
])
def test_legacy_rejects_mixed_or_incomplete_metadata(world, metadata):
    c, u, d, _, path = world
    sid = c.post("/v1/devices/one/sessions", headers=u["alice"], json={}).json()["id"]
    response = c.post("/v1/device/measurements", headers=d["one"], json={**sample(sid), **metadata})
    assert response.status_code == 422
    with connect(path) as db:
        assert db.execute("SELECT COUNT(*) FROM measurements").fetchone()[0] == 0


def test_manual_upload_is_returned_in_private_session_and_history(world):
    c, u, d, _, _ = world
    sid = c.post("/v1/devices/one/sessions", headers=u["alice"], json={}).json()["id"]
    payload = manual_sample(sid)
    response = c.post("/v1/device/measurements", headers=d["one"], json=payload)
    assert response.status_code == 201
    measurement = response.json()
    assert measurement["breath_duration_ms"] is None
    assert measurement["acquisition_method"] == "manual_timed"
    assert measurement["sample_duration_ms"] == 5000
    assert measurement["estimated_bac_percent"] is None
    assert measurement["measured_at"] is None
    assert c.get("/v1/sessions/" + sid, headers=u["alice"]).json()["measurement"] == measurement
    assert c.get("/v1/measurements", headers=u["alice"]).json()["items"] == [measurement]
    assert c.get("/v1/me/reading-summary", headers=u["alice"]).json()["latest_measurement"] == measurement
