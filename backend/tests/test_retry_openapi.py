import pytest


@pytest.mark.parametrize(
    ("path", "model"),
    [
        ("/v1/devices/{device_id}/sessions", "SessionResponse"),
        ("/v1/device/measurements", "MeasurementResponse"),
    ],
)
def test_retry_and_creation_have_typed_openapi_responses(world, path, model):
    client, *_ = world
    schema = client.get("/openapi.json").json()
    operation = schema["paths"][path]["post"]
    for status in ("200", "201"):
        assert status in operation["responses"]
        assert operation["responses"][status]["content"]["application/json"][
            "schema"
        ] == {"$ref": f"#/components/schemas/{model}"}
    assert model in schema["components"]["schemas"]
    security = "UserAccessToken" if model == "SessionResponse" else "DeviceCredential"
    assert operation["security"] == [{security: []}]
    for status in ("401", "404", "409", "410", "422", "500", "503"):
        assert operation["responses"][status]["content"]["application/json"][
            "schema"
        ] == {"$ref": "#/components/schemas/ErrorEnvelope"}
