def test_game_openapi_complete_typed_additive_contract(world):
    c, *_ = world
    spec = c.get("/openapi.json").json()
    assert sum(len(ops) for ops in spec["paths"].values()) == 31
    schemas = spec["components"]["schemas"]
    for path, method, model, success in [
        ("/v1/me/game-results", "post", "GameResultResponse", "201"),
        ("/v1/me/game-results", "get", "GameHistoryResponse", "200"),
        ("/v1/me/stats", "get", "StatsResponse", "200"),
    ]:
        operation = spec["paths"][path][method]
        if method == "get":
            assert "201" not in operation["responses"]
        assert operation["security"] == [{"UserAccessToken": []}]
        assert operation["responses"][success]["content"]["application/json"][
            "schema"
        ] == {"$ref": "#/components/schemas/" + model}
        assert "Cache-Control" in operation["responses"][success]["headers"]
        for error in ["401", "404", "409", "413", "422", "500", "503"]:
            assert operation["responses"][error]["content"]["application/json"][
                "schema"
            ] == {"$ref": "#/components/schemas/ErrorEnvelope"}
    post = spec["paths"]["/v1/me/game-results"]["post"]
    assert post["responses"]["200"]["content"]["application/json"]["schema"] == {
        "$ref": "#/components/schemas/GameResultResponse"
    }
    assert post["requestBody"]["required"] is True
    assert set(schemas["GameResultPut"]["required"]) == {
        "result_id",
        "game_id",
        "score",
        "outcome",
        "data",
    }
    assert schemas["GameResultPut"]["additionalProperties"] is False
    assert schemas["GameResultPut"]["properties"]["result_id"]["format"] == "uuid"
    assert (
        schemas["GameResultPut"]["properties"]["game_id"]["pattern"]
        == "^[a-z][a-z0-9_-]{0,63}$"
    )
    assert schemas["GameResultPut"]["properties"]["data"]["type"] == "object"
    assert "4096" in schemas["GameResultPut"]["properties"]["data"]["description"]
    for field, value in [
        ("awarded_points", 10),
        ("source", "client_reported"),
        ("scoring_policy", "completion_v1"),
    ]:
        assert schemas["GameResultResponse"]["properties"][field]["const"] == value
    assert set(schemas["StatsResponse"]["required"]) == {
        "user_id",
        "total_points",
        "games_played",
        "wins",
        "per_game",
    }
