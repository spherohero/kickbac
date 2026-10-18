import sqlite3

import pytest

from kickbac.db import connect, initialize


def test_connection_context_closes_on_success_and_failure(tmp_path):
    path = tmp_path / "db"
    initialize(path)
    with connect(path) as db:
        db.execute("SELECT 1")
    with pytest.raises(sqlite3.ProgrammingError, match="closed"):
        db.execute("SELECT 1")
    with pytest.raises(ValueError), connect(path) as failed:
        raise ValueError("abort")
    with pytest.raises(sqlite3.ProgrammingError, match="closed"):
        failed.execute("SELECT 1")
