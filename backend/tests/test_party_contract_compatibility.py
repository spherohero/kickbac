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
    for name, schema in baseline["schemas"].items():
        assert spec["components"]["schemas"].get(name) == schema, (
            f"Existing schema changed: {name}"
        )
    assert spec["components"]["securitySchemes"] == baseline["securitySchemes"]


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
