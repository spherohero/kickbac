import json
import os
import subprocess
import sys


def test_standalone_simulator_uses_real_http_and_restarts(tmp_path):
    result = subprocess.run(
        [sys.executable, "-m", "kickbac.simulator"],
        env={
            **os.environ,
            "TMPDIR": str(tmp_path),
            "AUTH0_DOMAIN": "",
            "AUTH0_AUDIENCE": "",
        },
        capture_output=True,
        text=True,
        timeout=40,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "SIMULATED OIDC" in result.stdout and "SIMULATED SENSOR" in result.stdout
    assert "http://127.0.0.1:" in result.stdout
    assert "Bearer " not in result.stdout + result.stderr
    summary = json.loads(result.stdout.splitlines()[-1])
    assert summary == {
        "status": "SIMULATOR_OK",
        "transport": "real HTTP loopback",
        "session_status": "COMPLETE",
        "measurements": 1,
        "duplicate_rows": 0,
        "foreign_owner_status": 404,
        "restart": "ok",
    }
    assert list(tmp_path.iterdir()) == []
