import pytest
from fastapi.testclient import TestClient


def test_startup_refuses_missing_schema(tmp_path):
    from kickbac.app import create_app
    from kickbac.settings import Settings

    with (
        pytest.raises(RuntimeError, match="Initialize database"),
        TestClient(
            create_app(
                Settings(db_path=tmp_path / "missing.db"), verifier=lambda t: "test"
            )
        ),
    ):
        pass
