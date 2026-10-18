"""Deployment tests use only temporary databases, never the live service."""

import sqlite3
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "backup_sqlite.py"


def run_backup(source, output):
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--source",
            str(source),
            "--destination",
            str(output),
        ],
        capture_output=True,
        text=True,
        check=False,
    )


def test_online_backup_restores_committed_wal_schema_and_rows(tmp_path):
    source = tmp_path / "live.sqlite3"
    output = tmp_path / "backups"
    with sqlite3.connect(source) as live:
        live.execute("PRAGMA journal_mode=WAL")
        live.execute("CREATE TABLE sample (id INTEGER PRIMARY KEY, value TEXT)")
        live.execute("PRAGMA user_version=2")
        live.execute("INSERT INTO sample VALUES (1, 'fixture')")
        live.commit()
        result = run_backup(source, output)
        assert result.returncode == 0, result.stderr
        backups = list(output.glob("kickbac-backup-*.sqlite3"))
        assert len(backups) == 1
        restored = tmp_path / "restored.sqlite3"
        restored.write_bytes(backups[0].read_bytes())
        with sqlite3.connect(restored) as db:
            assert db.execute("PRAGMA integrity_check").fetchall() == [("ok",)]
            assert db.execute("PRAGMA user_version").fetchone() == (2,)
            assert db.execute("SELECT * FROM sample").fetchall() == [(1, "fixture")]
        assert live.execute("SELECT count(*) FROM sample").fetchone() == (1,)
    if sys.platform != "win32":
        assert output.stat().st_mode & 0o777 == 0o700
        assert backups[0].stat().st_mode & 0o777 == 0o600


def test_repository_schema_survives_backup_restore(tmp_path):
    source = tmp_path / "schema.sqlite3"
    backend = SCRIPT.parents[2] / "backend"
    with sqlite3.connect(source) as db:
        for migration in sorted((backend / "migrations").glob("[0-9][0-9][0-9]_*.sql")):
            db.executescript(migration.read_text())
        db.execute(
            "INSERT INTO devices(id, credential_hash) VALUES (?, ?)",
            ("fixture", "fixture-hash"),
        )
        db.execute(
            "INSERT INTO parties VALUES ('party','owner','Fixture','ABCDEFGH','time','OPEN',NULL)"
        )
        db.execute("INSERT INTO party_members VALUES ('party','owner','time',NULL)")
        db.execute("INSERT INTO party_devices VALUES ('party','fixture')")
        db.execute(
            "INSERT INTO party_resolve_requests VALUES ('2889d6a0-4719-4f23-a397-37c51d24129e','owner','fixture','Fixture','party','created')"
        )
        db.execute(
            "INSERT INTO app_readings VALUES ('026af7c9-d605-4291-a1db-5b230e10ef43','owner',0.08,'2026-10-18T09:31:50+00:00',2500,'app_generated','2026-10-18T10:00:00+00:00')"
        )
        db.execute("INSERT INTO app_reading_save_windows VALUES ('owner',1000.0,1)")
        expected = list(db.iterdump())
        db.commit()
    output = tmp_path / "backups"
    result = run_backup(source, output)
    assert result.returncode == 0, result.stderr
    restored = tmp_path / "restore.sqlite3"
    restored.write_bytes(next(output.glob("kickbac-backup-*.sqlite3")).read_bytes())
    check = subprocess.run(
        [
            sys.executable,
            "-c",
            "import sys; from kickbac.db import check_schema; check_schema(sys.argv[1])",
            str(restored),
        ],
        cwd=backend,
        capture_output=True,
        text=True,
        check=False,
    )
    assert check.returncode == 0, check.stderr
    with sqlite3.connect(restored) as db:
        assert db.execute("PRAGMA integrity_check").fetchall() == [("ok",)]
        assert db.execute("PRAGMA user_version").fetchone() == (8,)
        assert list(db.iterdump()) == expected
        assert db.execute("SELECT id FROM devices").fetchall() == [("fixture",)]
        assert db.execute("SELECT value,source FROM app_readings").fetchall() == [
            (0.08, "app_generated")
        ]
        assert db.execute(
            "SELECT accepted FROM app_reading_save_windows"
        ).fetchall() == [(1,)]


def test_retention_only_removes_exact_owned_names(tmp_path):
    source = tmp_path / "source.sqlite3"
    output = tmp_path / "backups"
    output.mkdir()
    with sqlite3.connect(source) as db:
        db.execute("CREATE TABLE fixture (id INTEGER)")
    unrelated = output / "kickbac-backup-manual.sqlite3"
    unrelated.write_text("keep")
    nested = output / ("kickbac-backup-20000101T000000000000Z-" + "a" * 32 + ".sqlite3")
    nested.mkdir()
    for _ in range(9):
        result = run_backup(source, output)
        assert result.returncode == 0, result.stderr
    assert len([p for p in output.glob("kickbac-backup-*.sqlite3") if p.is_file()]) == 8
    assert unrelated.read_text() == "keep"
    assert nested.is_dir()
    assert not list(output.glob(".kickbac-backup-*"))


def test_missing_source_is_not_created(tmp_path):
    source = tmp_path / "absent.sqlite3"
    result = run_backup(source, tmp_path / "backups")
    assert result.returncode != 0
    assert not source.exists()


def test_corrupt_source_never_publishes_or_prunes(tmp_path):
    source = tmp_path / "corrupt.sqlite3"
    source.write_bytes(b"not a database")
    output = tmp_path / "backups"
    output.mkdir()
    previous = output / (
        "kickbac-backup-20000101T000000000000Z-" + "b" * 32 + ".sqlite3"
    )
    previous.write_bytes(b"preserve previous")
    result = run_backup(source, output)
    assert result.returncode != 0
    assert previous.read_bytes() == b"preserve previous"
    assert list(output.iterdir()) == [previous]
