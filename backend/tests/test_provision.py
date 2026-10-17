import hashlib
import os
import subprocess
import sys

from kickbac.db import connect, initialize


def test_provision_private_file_and_hashed_unique_keys(tmp_path):
    path = tmp_path / "db"
    initialize(path)
    env = {**os.environ, "KICKBAC_DB_PATH": str(path)}
    for device in ["one", "two"]:
        target = tmp_path / (device + ".secret")
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "kickbac.cli",
                "provision-device",
                device,
                "--credential-file",
                str(target),
            ],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        assert result.returncode == 0
        credential = target.read_text().strip()
        assert len(credential) >= 40
        assert credential not in result.stdout + result.stderr
        with connect(path) as db:
            assert (
                db.execute(
                    "SELECT credential_hash FROM devices WHERE id=?", (device,)
                ).fetchone()[0]
                == hashlib.sha256(credential.encode()).hexdigest()
            )
        again = subprocess.run(
            [
                sys.executable,
                "-m",
                "kickbac.cli",
                "provision-device",
                device,
                "--credential-file",
                str(target),
            ],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        assert again.returncode != 0
        assert target.read_text().strip() == credential
    assert (tmp_path / "one.secret").read_text() != (
        tmp_path / "two.secret"
    ).read_text()
