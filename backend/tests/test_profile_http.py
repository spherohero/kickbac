"""Real loopback HTTP and default uvicorn logging, isolated in a subprocess."""

import subprocess
import sys
import textwrap


def test_profile_real_http_streaming_restart_and_private_logs(tmp_path):
    program = textwrap.dedent("""
        import base64
        import socket
        import threading
        import time
        from contextlib import contextmanager
        from io import BytesIO
        from pathlib import Path
        import sys

        import httpx
        import jwt
        import uvicorn
        from cryptography.hazmat.primitives.asymmetric import rsa
        from PIL import Image

        from kickbac.app import create_app
        from kickbac.auth import JWTVerifier
        from kickbac.db import initialize
        from kickbac.settings import Settings

        path = Path(sys.argv[1]) / 'http.db'
        initialize(path)
        private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        verifier = JWTVerifier('https://fixture.invalid/', 'fixture-api', lambda token: private.public_key())
        def login():
            token = jwt.encode({'iss': 'https://fixture.invalid/', 'aud': 'fixture-api',
                               'sub': 'sms|fixture', 'exp': int(time.time())+300}, private, algorithm='RS256')
            return {'Authorization': 'Bearer ' + token}

        @contextmanager
        def serve():
            with socket.socket() as listener:
                listener.bind(('127.0.0.1', 0))
                origin = f'http://127.0.0.1:{listener.getsockname()[1]}'
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

        image = BytesIO()
        Image.new('RGB', (64, 32), 'red').save(image, 'PNG')
        photo = {'content_type': 'image/png', 'data_base64': base64.b64encode(image.getvalue()).decode()}
        with serve() as c:
            assert c.get('/health').status_code == 200
            assert c.get('/v1/me/profile').status_code == 401
            assert c.get('/v1/me/profile', headers=login()).json()['display_name'] is None
            saved = c.put('/v1/me/profile', headers=login(), json={'display_name': 'private-http-name-marker', 'profile_picture': photo})
            assert saved.status_code == 200
            expected = saved.json()
            assert expected['profile_picture']['content_type'] == 'image/jpeg'
            def chunks():
                for _ in range(20):
                    yield b' ' * 65536
            response = c.put('/v1/me/profile', headers=login(), content=chunks())
            assert response.status_code == 413
            assert response.json()['error']['code'] == 'payload_too_large'
            assert response.headers['cache-control'] == 'no-store'
            response = c.put('/v1/me/profile', headers=login(), json={'display_name': 'private-http-bad-marker', 'profile_picture': {'content_type': 'image/png', 'data_base64': 'private-http-invalid-image'}})
            assert response.status_code == 422
            assert c.get('/v1/me/profile', headers=login()).json() == expected
        with serve() as c:
            assert c.get('/v1/me/profile', headers=login()).json() == expected
        print('PROFILE_HTTP_OK')
    """)
    result = subprocess.run(
        [sys.executable, "-c", program, str(tmp_path)],
        capture_output=True,
        text=True,
        timeout=35,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "PROFILE_HTTP_OK" in result.stdout
    output = result.stdout + result.stderr
    for sensitive in (
        "private-http-name-marker",
        "private-http-bad-marker",
        "private-http-invalid-image",
        "data_base64",
        "display_name",
        "Authorization",
        "Bearer ",
        "eyJ",
    ):
        assert sensitive not in output
