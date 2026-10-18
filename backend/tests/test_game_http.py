"""Actual uvicorn HTTP, chunked bodies, restart and default-log privacy."""

import subprocess
import sys
import textwrap


def test_games_real_http_streaming_restart_and_private_logs(tmp_path):
    program = textwrap.dedent("""
        import json
        import socket
        import threading
        import time
        import sys
        from contextlib import contextmanager
        from pathlib import Path
        from uuid import uuid4

        import httpx
        import jwt
        import uvicorn
        from cryptography.hazmat.primitives.asymmetric import rsa

        from kickbac.app import create_app
        from kickbac.auth import JWTVerifier
        from kickbac.cli import provision_device
        from kickbac.db import connect, initialize
        from kickbac.settings import Settings

        path = Path(sys.argv[1]) / 'game-http.db'
        initialize(path)
        secret = Path(sys.argv[1]) / 'device.secret'
        provision_device(path, 'one', secret)
        device = {'Authorization': 'Bearer ' + secret.read_text().strip()}
        private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        verifier = JWTVerifier('https://fixture.invalid/', 'fixture-api', lambda token: private.public_key())
        def login(subject='sms|fixture'):
            token = jwt.encode({'iss': 'https://fixture.invalid/', 'aud': 'fixture-api',
                               'sub': subject, 'exp': int(time.time())+300}, private, algorithm='RS256')
            return {'Authorization': 'Bearer ' + token}

        @contextmanager
        def serve():
            with socket.socket() as listener:
                listener.bind(('127.0.0.1', 0))
                origin = f'http://127.0.0.1:{listener.getsockname()[1]}'
                # Leave default uvicorn logging enabled: audit actual output below.
                server = uvicorn.Server(uvicorn.Config(create_app(Settings(path), verifier), timeout_graceful_shutdown=3))
                worker = threading.Thread(target=lambda: server.run(sockets=[listener]), daemon=True)
                worker.start()
                try:
                    deadline = time.monotonic()+8
                    while not server.started:
                        assert worker.is_alive() and time.monotonic()<deadline
                        time.sleep(0.02)
                    with httpx.Client(base_url=origin, timeout=5, trust_env=False) as client:
                        yield client
                finally:
                    server.should_exit = True
                    worker.join(timeout=8)
                    assert not worker.is_alive()

        body = {'result_id': str(uuid4()), 'game_id': 'trivia', 'score': 42,
                'outcome': 'win', 'data': {'note': 'private-game-http-data-marker'}}
        with serve() as c:
            assert c.get('/health').status_code == 200
            assert c.get('/v1/me/stats').status_code == 401
            assert c.get('/v1/me/stats', headers=device).status_code == 401
            saved = c.post('/v1/me/game-results', headers=login(), json=body)
            assert saved.status_code == 201
            assert saved.headers['cache-control'] == 'no-store'
            expected = saved.json()
            assert expected['source'] == 'client_reported' and expected['awarded_points'] == 10
            retry = c.post('/v1/me/game-results', headers=login(), json=body)
            assert retry.status_code == 200 and retry.json() == expected
            assert c.post('/v1/me/game-results', headers=login('sms|other'), json=body).status_code == 404
            assert c.post('/v1/me/game-results', headers=login(), json={**body, 'score': 43}).status_code == 409
            assert c.get('/v1/me/game-results', headers=login('sms|other')).json()['items'] == []
            def chunks():
                yield b' ' * 16000
                yield b' ' * 16000
                yield b' ' * 1000
            response = c.post('/v1/me/game-results', headers=login(), content=chunks())
            assert response.status_code == 413 and response.headers['cache-control'] == 'no-store'
            assert c.post('/v1/me/game-results', headers=login(), json={**body, 'data': {'note': 'private-game-http-bad-marker' * 100}}).status_code == 422
            assert c.put('/v1/me/profile', headers=login(), json={'display_name': 'private-game-profile-marker', 'profile_picture': None}).status_code == 200
            session = c.post('/v1/devices/one/sessions', headers=login(), json={}).json()
            reading = c.post('/v1/device/measurements', headers=device, json={
                'measurement_id': str(uuid4()), 'session_id': session['id'],
                'raw': {'sensor': 'mq3', 'value': 900, 'unit': 'adc_counts'},
                'breath_duration_ms': 2500, 'source': 'simulator', 'measured_at': None})
            assert reading.status_code == 201 and reading.json()['estimated_bac_percent'] is None
            history = c.get('/v1/measurements', headers=login()).json()
            assert len(history['items']) == 1
            assert c.get('/v1/me/stats', headers=login()).json()['total_points'] == 10
        with serve() as c:
            assert c.get('/v1/me/game-results', headers=login()).json()['items'] == [expected]
            assert c.get('/v1/me/stats', headers=login()).json()['total_points'] == 10
            assert c.get('/v1/measurements', headers=login()).json() == history
            assert c.get('/v1/me/profile', headers=login()).json()['display_name'] == 'private-game-profile-marker'
            replay = c.post('/v1/me/game-results', headers=login(), json=body)
            assert replay.status_code == 200 and replay.json() == expected
        with connect(path) as db:
            assert tuple(db.execute('SELECT COUNT(*),SUM(awarded_points) FROM game_results').fetchone()) == (1, 10)
        print('GAME_HTTP_OK unique_results=1 total_points=10 restart=true private_history=true')
    """)
    execution = subprocess.run(
        [sys.executable, "-c", program, str(tmp_path)],
        capture_output=True,
        text=True,
        timeout=40,
        check=False,
    )
    assert execution.returncode == 0, execution.stdout + execution.stderr
    assert (
        "GAME_HTTP_OK unique_results=1 total_points=10 restart=true private_history=true"
        in execution.stdout
    )
    output = execution.stdout + execution.stderr
    for sensitive in [
        "private-game-http-data-marker",
        "private-game-http-bad-marker",
        "private-game-profile-marker",
        "Authorization",
        "Bearer ",
        "eyJ",
        "data_base64",
    ]:
        assert sensitive not in output
    print(
        "GAME_HTTP_OK unique_results=1 total_points=10 restart=true private_history=true logs_private=true"
    )
