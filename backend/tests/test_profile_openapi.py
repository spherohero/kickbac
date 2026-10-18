def test_profile_openapi_has_typed_private_full_replacement_contract(world):
    c, *_ = world
    spec = c.get("/openapi.json").json()
    schemas = spec["components"]["schemas"]
    operations = spec["paths"]["/v1/me/profile"]
    for method in ("get", "put"):
        operation = operations[method]
        assert operation["security"] == [{"UserAccessToken": []}]
        assert operation["responses"]["200"]["content"]["application/json"][
            "schema"
        ] == {"$ref": "#/components/schemas/ProfileResponse"}
        for code in ("401", "413", "422", "500", "503"):
            assert operation["responses"][code]["content"]["application/json"][
                "schema"
            ] == {"$ref": "#/components/schemas/ErrorEnvelope"}
        assert "Cache-Control" in operation["responses"]["200"]["headers"]
    assert operations["put"]["requestBody"]["required"] is True
    assert operations["put"]["requestBody"]["content"]["application/json"][
        "schema"
    ] == {"$ref": "#/components/schemas/ProfilePut"}
    assert set(schemas["ProfilePut"]["required"]) == {"display_name", "profile_picture"}
    assert schemas["ProfilePut"]["additionalProperties"] is False
    assert schemas["ProfilePicture"]["additionalProperties"] is False
    assert set(schemas["ProfilePicture"]["required"]) == {"content_type", "data_base64"}
    assert schemas["ProfilePicture"]["properties"]["data_base64"]["maxLength"] == 4 * (
        (512 * 1024 + 2) // 3
    )
    assert schemas["ProfilePicture"]["properties"]["content_type"]["enum"] == [
        "image/jpeg",
        "image/png",
    ]
    assert (
        schemas["ProfilePictureResponse"]["properties"]["content_type"]["const"]
        == "image/jpeg"
    )
    assert set(schemas["ProfileResponse"]["required"]) == {
        "user_id",
        "display_name",
        "profile_picture",
        "created_at",
        "updated_at",
    }
    assert schemas["ProfilePut"]["properties"]["display_name"]["maxLength"] == 80
    assert schemas["ProfilePut"]["properties"]["display_name"]["minLength"] == 1
