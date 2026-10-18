"""Static guardrails complement (not replace) Ubuntu config validation."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_api_unit_is_loopback_single_worker_and_external_state():
    unit = (ROOT / "kickbac.service").read_text()
    for expected in (
        "User=kickbac",
        "Group=kickbac",
        "WorkingDirectory=/opt/kickbac/current/backend",
        "EnvironmentFile=/etc/kickbac/backend.env",
        "--host 127.0.0.1",
        "--workers 1",
        "--no-access-log",
        "--no-server-header",
        "UMask=0077",
        "ProtectSystem=strict",
        "ProtectHome=true",
        "NoNewPrivileges=true",
        "ReadWritePaths=/var/lib/kickbac",
        "Restart=on-failure",
    ):
        assert expected in unit
    assert "DynamicUser" not in unit
    assert "init-db" not in unit


def test_api_runtime_follows_release_without_startup_migrations():
    unit = (ROOT / "kickbac.service").read_text()
    commands = [line for line in unit.splitlines() if line.startswith("ExecStart=")]
    assert len(commands) == 1
    assert commands[0].startswith("ExecStart=/opt/kickbac/current/venv/bin/python ")
    assert "ExecStartPre=" not in unit
    assert "init-db" not in unit
    assert "/opt/kickbac/venv/" not in unit


def test_runtime_environment_has_only_public_required_configuration():
    values = dict(
        line.split("=", 1)
        for line in (ROOT / "backend.env.example").read_text().splitlines()
        if line and not line.startswith("#")
    )
    assert values == {
        "KICKBAC_DB_PATH": "/var/lib/kickbac/kickbac.sqlite3",
        "AUTH0_DOMAIN": "dev-c87oxm4dkbyatvrn.us.auth0.com",
        "AUTH0_AUDIENCE": "https://kickbac-api",
    }


def test_proxy_has_no_cors_or_request_access_logs():
    config = (ROOT / "Caddyfile").read_text()
    directives = "\n".join(
        line for line in config.splitlines() if not line.lstrip().startswith("#")
    )
    assert "api.kickbac.vodka" in directives
    assert "reverse_proxy 127.0.0.1:8000" in directives
    assert "header -Server" in directives
    assert "Access-Control" not in directives
    assert "log" not in directives


def test_backup_service_matches_timer_and_persistent_paths():
    service = (ROOT / "kickbac-backup.service").read_text()
    timer = (ROOT / "kickbac-backup.timer").read_text()
    assert "User=kickbac" in service
    assert "--destination /var/backups/kickbac" in service
    assert "ReadWritePaths=/var/lib/kickbac /var/backups/kickbac" in service
    assert "ProtectSystem=strict" in service
    assert "EnvironmentFile" not in service
    assert "Persistent=true" in timer
    assert "OnCalendar=*-*-* 03:15:00 UTC" in timer
    assert "Unit=kickbac-backup.service" in timer
