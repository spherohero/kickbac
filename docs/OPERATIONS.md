# Ubuntu operations (operator runbook)

Target: existing authorized Vultr VM `144.202.38.243`, Ubuntu 24.04, Python
3.12; public origin `https://api.kickbac.vodka`. These files are deployment
artifacts, **not evidence of a completed deployment**. Execute the reviewed steps
on that host only; do not create another VM. No installer runs automatically.

**Executed checkpoint:** parent installed and validated these artifacts on the existing VM. External trusted HTTPS health/OpenAPI/resolver checks pass, protected routes reject unauthenticated requests, real device heartbeat/poll pass, and API/Caddy/backup timer are active and boot-enabled. Explicit schema/permissions/snapshot integrity and service restart were read back; the deployed Python3.12 environment passed the isolated HTTP simulator. No OS reboot or live Native Auth0-user acceptance is claimed. Current evidence is in the original checkout `../kickbac/docs/LIVE_BACKEND_STATUS.md` and workspace `.project/LIVE_BACKEND_STATUS.json`; deployment artifacts are published separately on `backend/deployment`. Do not rerun first-install commands against the now-existing directories/devices.

## Current runtime and production release gate

**Executed:** `backend/profiles` working-tree release `/opt/kickbac/releases/profiles-20261017T235249Z` is now current, with schema3 and additive GET/PUT `/v1/me/profile`. See sibling `../kickbac-profiles/docs/PROFILE_VERIFICATION.md`. Production-copy trial migration, before/after integrity-checked snapshots, old-row content equality, service restart and public contract/protection checks passed. No old session/history/credential data rewritten.

This update uses a **release-local hashed venv** at `/opt/kickbac/current/venv`, selected by `/etc/systemd/system/kickbac.service.d/profile-runtime.conf` (ExecStart reset/replacement only). The former `/opt/kickbac/venv` and initial release remain intact. The base service artifact now uses that same release-local interpreter. Preserve the existing drop-in unless separately reviewed; replacing a base unit does not remove overrides. Read the effective ExecStart before restarting. Never resync the obsolete shared interpreter. The service still runs as kickbac, one loopback worker, with the original sandbox.

SQLite snapshots include private profile image BLOBs. Profile requests are bounded and sanitized before persistence; do not dump those rows. **Rollback is not a blind symlink swap:** pre-profile code only accepts schema2, while live is now3. Preserve current data/profile rows, validate the target schema/runtime and coordinate any explicit downgrade/restore; no silent data loss or automatic snapshot restore. Profile/native acceptance and real Auth0 token checks remain Liam-owned.

**Production release gate:** this branch's base backend still requires schema2. Do not deploy its backend over live schema3 by itself. Integrate the reviewed profile backend/migration before packaging a production release, and test candidate schema3 compatibility. Recorded live checks above are parent-provided checkpoints, not a fresh host inspection by publishing these artifacts.

## Current layout and decisions

- Caddy owns public TCP 80/443 and automatic trusted TLS; direct DNS must resolve
  to this VM (check A and AAAA). Keep SSH allowed before changing any firewall.
  Do not expose port 8000. No permissive CORS or access logs are configured.
- One `kickbac` system user/group, one uvicorn worker on `127.0.0.1:8000`.
  Existing JSON/auth/session contracts remain unchanged; this does not implement
  universal links or a web frontend. Native client owner selects the public
  origin only after TLS/readiness verification; Auth0 audience stays unchanged.
- Root-owned immutable `/opt/kickbac/releases/<release-id>/` contains `backend/`
  and `deploy/ubuntu/`. `/opt/kickbac/current` points to that release directory.
  Keep previous releases. No `.env`, databases, device secrets, development
  virtualenvs or iOS build output belong in a release archive.
- Each release contains its own Python 3.12 `venv/`, built at its final absolute
  path. Install only hashed runtime dependencies from that release's `uv.lock`.
  Never move/copy a built venv or modify the running release's dependencies.
  `/opt/kickbac/venv` is preserved legacy state, not the current runtime.
- Durable SQLite: `/var/lib/kickbac/kickbac.sqlite3`; not in code or venv.
  Startup checks schema and fails closed; migrations are explicit operator work.
- `/etc/kickbac/backend.env`: root:root 0600; exactly the three public runtime
  settings in `deploy/ubuntu/backend.env.example`. No Auth0 client secret, SMS
  credentials, phone numbers or device bearer credentials in runtime environment.
- Local online snapshots: `/var/backups/kickbac`, kickbac:kickbac 0700. Seven
  matching snapshots retained; backup files 0600. These remain on the same VM:
  encrypted off-host copies and restore drills are still needed for disaster
  recovery. SQLite snapshots contain private user/history data and credential
  hashes; never upload them to Git/chat. Do not print rows or raw phone data.

## First installation only: prepare host

Commands in this runbook are **Ubuntu Bash**, generally as root. Install Python
3.12 + venv, Caddy from its supported Ubuntu package source, and uv from a trusted
source. Verify package signatures/source; don't pipe unreviewed network installers
into a root shell. Ensure Caddy's normal service can retain its certificate data.

```bash
# First installation only; inspect and preserve any existing account/directories.
useradd --system --user-group --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin kickbac
install -d -o root -g root -m 0755 /opt/kickbac /opt/kickbac/releases
install -d -o root -g root -m 0700 /etc/kickbac /etc/kickbac/device-credentials
install -d -o kickbac -g kickbac -m 0700 /var/lib/kickbac /var/backups/kickbac
```

## Prepare every candidate release (before outage)

Transfer a reviewed release archive over the existing SSH channel. Extract to a
**new** release directory; choose and record a unique ID, e.g. Git short SHA plus
build timestamp. Inspect the archive paths before extraction. The archive must
include migrations and this deployment directory. Do not overwrite a release.

```bash
# Set RELEASE to the actual newly extracted absolute directory; record its commit.
set -euo pipefail
: "${RELEASE:?Set the new absolute release directory}"
case "$RELEASE" in /opt/kickbac/releases/*) ;; *) exit 1 ;; esac
test ! -e "$RELEASE/venv"
test -f "$RELEASE/backend/uv.lock"
test -f "$RELEASE/deploy/ubuntu/backup_sqlite.py"
uv export --project "$RELEASE/backend" --locked --no-dev --no-default-groups --no-emit-project --format requirements.txt --output-file "$RELEASE/deploy/ubuntu/requirements.txt"
# Export includes hashes by default. Never use --no-hashes or unpinned pip install.
python3.12 -m venv "$RELEASE/venv"
uv pip sync --python "$RELEASE/venv/bin/python" --require-hashes "$RELEASE/deploy/ubuntu/requirements.txt"
chown -R root:root "$RELEASE"
chmod -R go-w "$RELEASE"
chmod -R a+rX "$RELEASE"
```

The runtime imports source via its explicit backend working directory; the project
itself need not be installed. Never run `uv sync` inside an immutable release.
Test candidate startup/simulator using private temporary data. Before any schema
change, trial the candidate migration on an integrity-checked private production
snapshot copy and verify old-row preservation without printing rows. Do not use
a synthetic DB as a substitute for that compatibility check. Switch the pointer
only during the update procedure below, or first install with no running API.

## First installation only: initialize and provision

Select the release using the guarded pointer block in the update section first.
Do not initialize/provision the existing live device again. For a new host only:

```bash
install -o root -g root -m 0600 "$RELEASE/deploy/ubuntu/backend.env.example" /etc/kickbac/backend.env
```

```bash
cd /opt/kickbac/current/backend
runuser -u kickbac -- env KICKBAC_DB_PATH=/var/lib/kickbac/kickbac.sqlite3 PYTHONDONTWRITEBYTECODE=1 /opt/kickbac/current/venv/bin/python -m kickbac.cli init-db
# Root owns the new credential file. Never display, log or paste its contents.
umask 077
KICKBAC_DB_PATH=/var/lib/kickbac/kickbac.sqlite3 PYTHONDONTWRITEBYTECODE=1 /opt/kickbac/current/venv/bin/python -m kickbac.cli provision-device kb-demo-01 --credential-file /etc/kickbac/device-credentials/kb-demo-01.secret
```

Run provisioning once, preferably before starting the API. Existing CLI refuses
both an existing device ID and credential-file overwrite. Securely deliver the
credential out-of-band to the device operator; never put it in NFC/QR/iOS or
runtime env. Losing it requires a separately reviewed rotation procedure, not
reprovisioning an existing device blindly. Only its hash is stored in SQLite.

## Validate, install and start (first install or reviewed update)

Install only reviewed changed artifacts for updates; do not blindly overwrite
edited Caddy settings or populated env. The block below is the complete first
installation set. Preserve the existing runtime drop-in on the live host.

```bash
install -o root -g root -m 0644 "$RELEASE/deploy/ubuntu/kickbac.service" /etc/systemd/system/kickbac.service
install -o root -g root -m 0644 "$RELEASE/deploy/ubuntu/kickbac-backup.service" /etc/systemd/system/kickbac-backup.service
install -o root -g root -m 0644 "$RELEASE/deploy/ubuntu/kickbac-backup.timer" /etc/systemd/system/kickbac-backup.timer
install -o root -g root -m 0644 "$RELEASE/deploy/ubuntu/Caddyfile" /etc/caddy/Caddyfile
systemd-analyze verify /etc/systemd/system/kickbac.service /etc/systemd/system/kickbac-backup.service /etc/systemd/system/kickbac-backup.timer
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl daemon-reload
systemctl show kickbac -p ExecStart
systemctl enable --now kickbac.service
curl --fail --silent --show-error http://127.0.0.1:8000/health
systemctl enable --now caddy.service
systemctl reload caddy.service
curl --fail --silent --show-error https://api.kickbac.vodka/health
systemctl start kickbac-backup.service
systemctl enable --now kickbac-backup.timer
systemctl is-active kickbac caddy kickbac-backup.timer
systemctl list-timers kickbac-backup.timer
ss -ltnp
```

Read back installed configuration, ownership/modes, listener bindings and service
status (never dump private env/credentials). Test public HTTPS from outside the
VM too; localhost health alone proves neither DNS nor certificate reachability.
Check `/openapi.json` and unauthenticated rejection on protected endpoints;
coordinate live Native PKCE and device acceptance with their owners. Do not use
bearer tokens in command arguments, URL queries, screenshots or logs.
`--no-access-log` also disables uvicorn request logging. Routine application
transition logs may still contain user IDs: restrict journal access. Caddy runtime
errors are not a substitute for privacy review; never enable verbose request
logging on the demo service. API errors must not be debug tracebacks.

## Backups, updates and rollback

`kickbac-backup.timer` runs daily at 03:15 UTC with up to 15-minute jitter and
persistent missed-run handling. On-demand: `systemctl start
kickbac-backup.service`. Confirm its exit status and a new matching file; a
successful timer activation alone does not prove a backup. Script opens the
source with SQLite `mode=ro`, uses the online backup API (including committed WAL
content), verifies integrity, fsyncs and atomically publishes a snapshot, then
prunes only exact `kickbac-backup-<UTC timestamp>-<32 hex>.sqlite3` filenames to
seven. Unrelated names, directories and symlinks are not pruned. It does not
create a missing source DB. Failed snapshots are not published or used to prune.
The script has a 60-second progress deadline, service a 120-second bound.
Do not run overlapping manual copies; systemd serializes this service's runs.

### Update sequence (existing host)

1. Record `readlink -f /opt/kickbac/current`, source commits, effective ExecStart,
   installed unit/drop-in and DB schema (no rows). Prepare/test candidate first.
2. Run and verify an online backup. Privately retain the pre-update snapshot
   outside routine seven-file pruning if a downgrade may require it.
3. Stop timer, API, then backup job; verify all are inactive. `After=kickbac.service`
   is ordering only and does not stop the backup job with the API:

   ```bash
   systemctl stop kickbac-backup.timer
   systemctl stop kickbac.service
   systemctl stop kickbac-backup.service
   ```

4. With no other DB writers, run and verify a final pre-migration snapshot:

   ```bash
   runuser -u kickbac -- /usr/bin/python3 "$RELEASE/deploy/ubuntu/backup_sqlite.py" --source /var/lib/kickbac/kickbac.sqlite3 --destination /var/backups/kickbac
   ```

5. If needed, explicitly migrate with the **candidate** interpreter/source, not
   the old current release. Target live schema is 3; schema2-only code is forbidden:

   ```bash
   cd "$RELEASE/backend"
   runuser -u kickbac -- env KICKBAC_DB_PATH=/var/lib/kickbac/kickbac.sqlite3 PYTHONDONTWRITEBYTECODE=1 "$RELEASE/venv/bin/python" -m kickbac.cli init-db
   runuser -u kickbac -- env PYTHONDONTWRITEBYTECODE=1 "$RELEASE/venv/bin/python" -c 'from kickbac.db import check_schema; check_schema("/var/lib/kickbac/kickbac.sqlite3")'
   ```

   Verify integrity/schema and old-row preservation. On failure leave API/timer
   stopped; do not retry with old schema2 code. Startup never migrates automatically.
6. Select atomically only after compatibility checks; `current` must be absent
   or a symlink, and `current.next` absent, including dangling links:

   ```bash
   test ! -e /opt/kickbac/current || test -L /opt/kickbac/current
   test ! -e /opt/kickbac/current.next && test ! -L /opt/kickbac/current.next
   ln -s "$RELEASE" /opt/kickbac/current.next
   mv -Tf /opt/kickbac/current.next /opt/kickbac/current
   test "$(readlink -f /opt/kickbac/current)" = "$RELEASE"
   ```

7. Install reviewed changed units, validate and start with the section above.
   Read back pointer, effective interpreter, schema, permissions and actual new
   backup. Check external health, OpenAPI profile routes, protection and owner/device
   acceptance before resuming normal operation. Reenable timer only after success.
   Never run a schema migration while the old API can serve writes.

### Compatibility-aware rollback

Stop API/timer/backup job as above and preserve failed release/current DB. Validate
previous release's own venv and schema check on a private snapshot copy first.
Do not resync the legacy shared venv. If compatible, switch the complete release
using the guarded pointer block, validate effective interpreter/units and repeat
startup/acceptance checks. Code rollback does not require restoring data when the
schema remains compatible.

Pre-profile code requires schema2 and cannot start on live schema3. Prefer a
schema3-compatible fix-forward/rollback build preserving profile rows. Downgrade
or restore requires explicit coordinated approval and a tested plan: no automatic
schema downgrade, table dropping or snapshot restore. If approved, validate a
selected snapshot in a **separate private staging path**
first with `PRAGMA integrity_check`, `PRAGMA user_version` and the previous
release's `kickbac.db.check_schema`. During a planned outage, ensure API and
backup job are stopped, preserve the live DB and its `-wal`/`-shm` together,
then install the verified standalone snapshot at the live path as kickbac:kickbac
0600 with no stale live sidecars. Never delete live sidecars while connections
exist. Restart and test health/owner isolation. Restoring loses post-snapshot
writes/profile changes and may resurrect sessions/device state; coordinate users/device owners.

## Local checks (no VM access)

From `backend/`, with this worktree's uv development environment:

```bash
uv run --locked pytest -q tests ../deploy/ubuntu/tests
uv run --locked ruff check . ../deploy/ubuntu
uv run --locked ruff format --check . ../deploy/ubuntu
uv run --locked python -m compileall -q kickbac ../deploy/ubuntu
uv run --locked python -m kickbac.simulator
```

Tests restore a temporary online WAL snapshot, verify schema version/rows and
integrity, exercise exact-name retention and failure cleanup. They use this
checkout's schema2 backend; profile/schema3 migration acceptance is separate.
Static runtime guardrails assert release-local venv and no startup migration.
Static artifact
checks do **not** replace Ubuntu `systemd-analyze verify`, Caddy validation,
POSIX ownership checks or live HTTPS acceptance. No firmware/native-client edits
are part of these artifacts. See `docs/API.md` for the existing API contract.
