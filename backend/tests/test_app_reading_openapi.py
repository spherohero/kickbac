import json

import pytest
from test_app_readings import reading


@pytest.mark.parametrize("value", [float("nan"), float("inf"), -float("inf")])
def test_full_payload_nonfinite_numbers_rejected(world, value):
    c, users, _, _, _ = world
    r = c.post(
        "/v1/me/app-readings",
        headers={**users["alice"], "Content-Type": "application/json"},
        content=json.dumps(reading(value=value)),
    )
    assert r.status_code == 422


@pytest.mark.parametrize("value,duration", [(0, 1), (1, 60000)])
def test_inclusive_bounds_and_offline_future_timestamps(world, value, duration):
    c, users, _, _, _ = world
    for stamp in ["2000-01-01T00:00:00Z", "2099-01-01T00:00:00Z"]:
        assert (
            c.post(
                "/v1/me/app-readings",
                headers=users["alice"],
                json=reading(value=value, duration_ms=duration, recorded_at=stamp),
            ).status_code
            == 201
        )


@pytest.mark.parametrize(
    "stamp", ["0001-01-01T00:00:00+01:00", "9999-12-31T23:59:59-01:00"]
)
def test_out_of_representable_utc_date_is_validation(world, stamp):
    c, users, _, _, _ = world
    assert (
        c.post(
            "/v1/me/app-readings",
            headers=users["alice"],
            json=reading(recorded_at=stamp),
        ).status_code
        == 422
    )


def test_app_openapi_typed_errors_and_replay(world):
    c, *_ = world
    spec = c.get("/openapi.json").json()
    for path, method in [
        ("/v1/me/app-readings", "get"),
        ("/v1/me/app-readings", "post"),
        ("/v1/me/app-reading-summary", "get"),
    ]:
        operation = spec["paths"][path][method]
        assert operation["security"] == [{"UserAccessToken": []}]
        for status in ["413", "429"]:
            assert operation["responses"][status]["content"]["application/json"][
                "schema"
            ] == {"$ref": "#/components/schemas/ErrorEnvelope"}
    assert "200" in spec["paths"]["/v1/me/app-readings"]["post"]["responses"]
    model = spec["components"]["schemas"]["AppReadingPut"]
    assert set(model["required"]) == set(reading())
    assert model["additionalProperties"] is False
