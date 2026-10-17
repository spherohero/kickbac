from datetime import timedelta

import pytest

from kickbac.db import connect


@pytest.mark.parametrize("device_id", ["one", "missing"])
def test_public_resolution_never_mutates_expired_sessions(world, device_id):
    client, users, _, now, path = world
    for device, owner in (("one", "alice"), ("two", "bob")):
        assert (
            client.post(
                f"/v1/devices/{device}/sessions", headers=users[owner], json={}
            ).status_code
            == 201
        )

    def snapshot():
        with connect(path) as db:
            return {
                table: [
                    tuple(row)
                    for row in db.execute(f"SELECT * FROM {table} ORDER BY id")
                ]
                for table in ("devices", "sessions", "measurements")
            }

    before = snapshot()
    now[0] += timedelta(seconds=60)
    response = client.get("/d/" + device_id)
    if device_id == "one":
        assert response.status_code == 200
        assert response.json() == {"device_id": "one"}
    else:
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "not_found"
    assert snapshot() == before

    # Lazy expiry remains owned by authenticated state operations.
    assert (
        client.get("/v1/devices/one", headers=users["alice"]).json()["state"]
        == "AVAILABLE"
    )
    with connect(path) as db:
        assert [row[0] for row in db.execute("SELECT status FROM sessions")] == [
            "EXPIRED",
            "EXPIRED",
        ]
