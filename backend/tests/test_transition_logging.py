"""Check real uvicorn defaults in isolation from pytest's logging handlers."""

import subprocess
import sys
import textwrap


def test_transition_logs_under_normal_uvicorn_startup(tmp_path):
    program = textwrap.dedent(
        """
        import logging
        import socket
        import sys
        import threading
        import time
        from pathlib import Path
        from uuid import uuid4

        import httpx
        import uvicorn

        from kickbac.app import create_app
        from kickbac.cli import provision_device
        from kickbac.db import initialize
        from kickbac.settings import Settings

        root = Path(sys.argv[1])
        path = root / 'db'
        initialize(path)
        secret = root / 'device.secret'
        provision_device(path, 'logging-one', secret)
        credential = secret.read_text().strip()
        # Explicit local identity fixture, not live Auth0.
        verifier = lambda token: 'fixture|logging-user'
        app = create_app(Settings(path), verifier=verifier)
        create_app(Settings(path), verifier=verifier)
        root_logger = logging.getLogger()
        root_level, root_handlers = root_logger.level, list(root_logger.handlers)
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            origin = f'http://127.0.0.1:{listener.getsockname()[1]}'
            server = uvicorn.Server(uvicorn.Config(app))
            worker = threading.Thread(
                target=lambda: server.run(sockets=[listener]), daemon=True
            )
            worker.start()
            try:
                deadline = time.monotonic() + 8
                while not server.started:
                    assert worker.is_alive() and time.monotonic() < deadline
                    time.sleep(0.02)
                from kickbac.sessions import log
                assert log.isEnabledFor(logging.INFO), 'transition INFO suppressed'
                assert root_logger.level == root_level
                assert root_logger.handlers == root_handlers
                with httpx.Client(base_url=origin, timeout=3, trust_env=False) as c:
                    user = {'Authorization': 'Bearer fixture-user-token'}
                    device = {'Authorization': 'Bearer ' + credential}
                    response = c.post('/v1/devices/logging-one/sessions', headers=user, json={})
                    assert response.status_code == 201
                    sid = response.json()['id']
                    assert c.post('/v1/device/sessions/' + sid + '/sampling', headers=device, json={}).status_code == 200
                    mid = str(uuid4())
                    response = c.post('/v1/device/measurements', headers=device, json={
                        'measurement_id': mid, 'session_id': sid,
                        'raw': {'sensor': 'mq3', 'value': 1234, 'unit': 'adc_counts'},
                        'breath_duration_ms': 2500, 'source': 'simulator'
                    })
                    assert response.status_code == 201
                    print('EXPECTED_SESSION=' + sid)
                    print('EXPECTED_MEASUREMENT=' + mid)
            finally:
                server.should_exit = True
                worker.join(timeout=8)
                assert not worker.is_alive()
        """
    )
    result = subprocess.run(
        [sys.executable, "-c", program, str(tmp_path)],
        capture_output=True,
        check=False,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stderr
    expected = dict(
        line.split("=", 1)
        for line in result.stdout.splitlines()
        if line.startswith("EXPECTED_")
    )
    events = [line for line in result.stderr.splitlines() if "transition=" in line]
    assert len(events) == 3  # Multiple app factories must not duplicate handlers.
    for transition in ("ARMED", "SAMPLING", "COMPLETE"):
        event = next(line for line in events if "transition=" + transition in line)
        assert "device=logging-one" in event
        assert "session=" + expected["EXPECTED_SESSION"] in event
        assert "user=fixture|logging-user" in event
    assert "measurement=" + expected["EXPECTED_MEASUREMENT"] in events[-1]
    output = result.stdout + result.stderr
    assert (tmp_path / "device.secret").read_text().strip() not in output
    for sensitive in (
        "fixture-user-token",
        "Authorization",
        "adc_counts",
        "1234",
        "2500",
    ):
        assert sensitive not in output
