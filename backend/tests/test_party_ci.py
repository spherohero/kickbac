"""Keep the NFC/party HTTP acceptance path in the actual Python CI matrix."""

from pathlib import Path


def test_backend_ci_executes_real_party_http_acceptance():
    workflow = Path(__file__).resolve().parents[2] / ".github/workflows/backend.yml"
    source = workflow.read_text(encoding="utf-8")
    assert "run: uv run --locked pytest -q integration/test_party_http.py" in source
