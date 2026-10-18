import argparse
import hashlib
import os
import re
import secrets
import sqlite3
from pathlib import Path

from .db import check_schema, initialize, transaction
from .settings import Settings


def provision_device(db_path, device_id, credential_file):
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}", device_id):
        raise ValueError("Invalid device ID")
    check_schema(db_path)
    credential = secrets.token_urlsafe(32)
    target = Path(credential_file)
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(credential + "\n")
        with transaction(db_path) as db:
            db.execute(
                "INSERT INTO devices(id,credential_hash) VALUES (?,?)",
                (device_id, hashlib.sha256(credential.encode()).hexdigest()),
            )
    except BaseException:
        target.unlink(missing_ok=True)
        raise


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("init-db")
    provision = commands.add_parser("provision-device")
    provision.add_argument("device_id")
    provision.add_argument("--credential-file", required=True)
    args = parser.parse_args()
    path = Settings.from_env().db_path
    try:
        if args.command == "init-db":
            initialize(path)
            print("Database initialized (schema 3).")
        else:
            provision_device(path, args.device_id, args.credential_file)
            print(
                "Device provisioned; credential written to private file. Never share it."
            )
    except (OSError, ValueError, RuntimeError, sqlite3.Error):
        parser.exit(
            1,
            "Command failed. Check initialized database, unique device ID, and new private file path.\n",
        )


if __name__ == "__main__":
    main()
