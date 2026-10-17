def test_openapi_documents_bearer_auth_and_generic_error_envelope(world):
    client, _, _, _, _ = world
    spec = client.get("/openapi.json").json()
    paths = spec["paths"]
    assert paths["/v1/me"]["get"]["security"] == [{"UserAccessToken": []}]
    assert paths["/v1/device/measurements"]["post"]["security"] == [
        {"DeviceCredential": []}
    ]
    assert "security" not in paths["/d/{device_id}"]["get"]
    assert paths["/v1/device/measurements"]["post"]["responses"]["422"]["content"][
        "application/json"
    ]["schema"] == {"$ref": "#/components/schemas/ErrorEnvelope"}
    assert paths["/v1/me"]["get"]["responses"]["200"]["content"]["application/json"][
        "schema"
    ] == {"$ref": "#/components/schemas/MeResponse"}
