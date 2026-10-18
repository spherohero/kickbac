import pytest

from kickbac.cli import main
from kickbac.db import connect, initialize


@pytest.mark.parametrize("existing", [False, True])
def test_init_db_reports_actual_persisted_schema(
    tmp_path, monkeypatch, capsys, existing
):
    path = tmp_path / "database.sqlite3"
    if existing:
        initialize(path)
    monkeypatch.setenv("KICKBAC_DB_PATH", str(path))
    monkeypatch.setattr("sys.argv", ["kickbac.cli", "init-db"])
    main()
    with connect(path) as db:
        version = db.execute("PRAGMA user_version").fetchone()[0]
    assert version == 5
    assert capsys.readouterr().out == f"Database initialized (schema {version}).\n"
