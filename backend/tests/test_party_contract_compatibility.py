"""Freeze the actual pre-party public contract, not an invented replacement.

Fixture captured from trusted public HTTPS OpenAPI before party implementation;
parent independently compared it with local source at 73d66be. No user data.
"""

import copy
import json
from pathlib import Path

import pytest

FIXTURE = Path(__file__).with_name("fixtures") / "pre_party_openapi.json"


def assert_existing_contract(spec):
    baseline = json.loads(FIXTURE.read_text(encoding="utf-8"))
    assert sum(len(methods) for methods in baseline["paths"].values()) == 17
    assert len(baseline["schemas"]) == 23
    for path, operation in baseline["paths"].items():
        assert spec["paths"].get(path) == operation, (
            f"Existing operation changed: {path}"
        )
    for name, original_schema in baseline["schemas"].items():
        schema = copy.deepcopy(original_schema)
        if name in ("MeasurementUpload", "MeasurementResponse"):
            properties = schema["properties"]
            duration = properties["breath_duration_ms"]
            properties["breath_duration_ms"] = {
                "anyOf": [
                    {key: value for key, value in duration.items() if key != "title"},
                    {"type": "null"},
                ],
                "title": "Breath Duration Ms",
            }
            properties["acquisition_method"] = {
                "anyOf": [
                    {"type": "string", "const": "manual_timed"},
                    {"type": "null"},
                ],
                "title": "Acquisition Method",
            }
            properties["sample_duration_ms"] = {
                "anyOf": [
                    {"type": "integer", "maximum": 60000, "minimum": 1},
                    {"type": "null"},
                ],
                "title": "Sample Duration Ms",
            }
        assert spec["components"]["schemas"].get(name) == schema, (
            f"Existing schema changed: {name}"
        )
    assert spec["components"]["securitySchemes"] == baseline["securitySchemes"]


@pytest.mark.parametrize("name", ["MeasurementUpload", "MeasurementResponse"])
@pytest.mark.parametrize(
    "mutation", ["duration", "method", "sample", "required", "extra"]
)
def test_guard_rejects_unapproved_acquisition_changes(world, name, mutation):
    client, *_ = world
    spec = copy.deepcopy(client.get("/openapi.json").json())
    schema = spec["components"]["schemas"][name]
    if mutation == "duration":
        schema["properties"]["breath_duration_ms"]["anyOf"][0]["minimum"] = 0
    elif mutation == "method":
        schema["properties"]["acquisition_method"]["anyOf"][0]["const"] = (
            "guessed_breath"
        )
    elif mutation == "sample":
        schema["properties"]["sample_duration_ms"]["anyOf"][0]["maximum"] = 60001
    elif mutation == "required":
        schema["required"].remove("breath_duration_ms")
    else:
        schema["properties"]["unapproved"] = {"type": "string"}
    with pytest.raises(AssertionError):
        assert_existing_contract(spec)


def test_party_feature_preserves_all_existing_operations_and_component_schemas(world):
    client, *_ = world
    assert_existing_contract(client.get("/openapi.json").json())


@pytest.mark.parametrize(
    "kind,name",
    [
        ("paths", "/v1/me"),
        ("schemas", "MeasurementResponse"),
        ("securitySchemes", "UserAccessToken"),
    ],
)
def test_compatibility_guard_rejects_endpoint_schema_and_auth_mutations(
    world, kind, name
):
    client, *_ = world
    spec = copy.deepcopy(client.get("/openapi.json").json())
    if kind == "paths":
        spec[kind][name] = {}
    else:
        spec["components"][kind][name] = {}
    with pytest.raises(AssertionError):
        assert_existing_contract(spec)
