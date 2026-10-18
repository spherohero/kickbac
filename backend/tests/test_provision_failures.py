import sqlite3

import pytest

from kickbac.cli import provision_device
from kickbac.db import connect, initialize


@pytest.mark.parametrize(
    "kind", ["duplicate", "missing_parent", "invalid_slug", "existing_file"]
)
def test_provision_failure_does_not_add_device_or_overwrite(tmp_path, kind):
    path = tmp_path / "db"
    initialize(path)
    target = tmp_path / "new.secret"
    device = "one"
    if kind == "duplicate":
        provision_device(path, "one", tmp_path / "original.secret")
    if kind == "missing_parent":
        target = tmp_path / "missing" / "new.secret"
    if kind == "invalid_slug":
        device = "../bad"
    if kind == "existing_file":
        target.write_text("preserve")
    with pytest.raises((OSError, ValueError, sqlite3.IntegrityError)):
        provision_device(path, device, target)
    with connect(path) as db:
        assert db.execute("SELECT count(*) FROM devices").fetchone()[0] == (
            1 if kind == "duplicate" else 0
        )
    if kind == "existing_file":
        assert target.read_text() == "preserve"
    else:
        assert not target.exists()
