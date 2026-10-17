from uuid import uuid4

from test_measurement_integrity import arm
from test_measurements import sample


def test_existing_measurement_id_changed_session_is_conflict(world):
    c, u, d, _, _ = world
    payload = sample(arm(c, u))
    assert (
        c.post("/v1/device/measurements", headers=d["one"], json=payload).status_code
        == 201
    )
    response = c.post(
        "/v1/device/measurements",
        headers=d["one"],
        json={**payload, "session_id": str(uuid4())},
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "idempotency_conflict"
