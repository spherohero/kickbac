"""Online SQLite snapshot; atomic publication; retain seven owned snapshots."""

import argparse
import os
import re
import sqlite3
import tempfile
import time
from contextlib import closing
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

OWN_NAME = re.compile(r"kickbac-backup-\d{8}T\d{12}Z-[0-9a-f]{32}\.sqlite3\Z")


def backup(source: Path, destination: Path) -> Path:
    if not source.is_file():
        raise ValueError("Source database must exist")
    destination.mkdir(mode=0o700, parents=True, exist_ok=True)
    if destination.is_symlink():
        raise ValueError("Backup directory cannot be a symlink")
    destination.chmod(0o700)
    fd, temporary = tempfile.mkstemp(prefix=".kickbac-backup-", dir=destination)
    os.close(fd)
    temporary = Path(temporary)
    deadline = time.monotonic() + 60

    def progress(status, remaining, total):
        if time.monotonic() > deadline:
            raise TimeoutError("Backup deadline exceeded")

    try:
        with (
            closing(
                sqlite3.connect(source.resolve().as_uri() + "?mode=ro", uri=True)
            ) as src,
            closing(sqlite3.connect(temporary)) as dst,
        ):
            src.backup(dst, pages=256, progress=progress, sleep=0.1)
            if dst.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                raise ValueError("Snapshot integrity check failed")
        temporary.chmod(0o600)
        with temporary.open("r+b") as stream:
            os.fsync(stream.fileno())
        stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S%fZ")
        target = destination / f"kickbac-backup-{stamp}-{uuid4().hex}.sqlite3"
        temporary.replace(target)
        snapshots = sorted(
            p
            for p in destination.iterdir()
            if OWN_NAME.fullmatch(p.name) and p.is_file() and not p.is_symlink()
        )
        for old in snapshots[:-7]:
            old.unlink()
        return target
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()
    try:
        backup(args.source, args.destination)
    except (OSError, ValueError, sqlite3.Error, TimeoutError):
        parser.exit(
            1, "Backup failed; inspect permissions, space and database integrity.\n"
        )
    print("SQLite backup verified; retention applied.")


if __name__ == "__main__":
    main()
