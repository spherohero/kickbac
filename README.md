# kickBAC

Connected breathalyzer **prototype**: authenticated phone user explicitly arms a
known device, which uploads one raw sample into a short-lived, private session.
The backend is implemented locally; this is **not** a deployed service or a
certified BAC instrument.

## Layout and contract

- `backend/`: Python/FastAPI, versioned SQLite migrations, tests and simulator.
- [`docs/API.md`](docs/API.md): frozen v0 paths, bodies, errors and lifecycle.
- [`docs/SETUP.md`](docs/SETUP.md): Auth0 account/Native app and hosting checklist.
- `ios/`: Liam's separately owned SwiftUI client (not implemented here).
- ESP32 firmware and physical calibration are separate integration work.

## Local setup

Install [uv](https://docs.astral.sh/uv/) and Python 3.11 or newer. Commands below
use **Bash / Git Bash**, including on Windows; run from the repository root.

```bash
cd backend
uv sync --locked
test -e .env || cp .env.example .env
# Preserve an existing .env; edit it with your actual tenant domain and audience.
# Explicitly export the file; neither uv sync nor the app auto-loads .env.
set -a
. ./.env
set +a
uv run python -m kickbac.cli init-db
```

Environment:

| Variable | Meaning |
| --- | --- |
| `KICKBAC_DB_PATH` | Persistent SQLite file; default `data/kickbac.sqlite3`. Relative paths resolve from the process working directory. |
| `AUTH0_DOMAIN` | Actual tenant DNS name only, e.g. `dev-EXAMPLE.us.auth0.com`; no scheme, port, path or trailing slash. |
| `AUTH0_AUDIENCE` | Exact custom API identifier, coordinated as `https://kickbac-api` (no trailing slash). A logical identifier, **not a backend host**. |

`init-db` explicitly applies migrations 001 and 002, preserving existing devices;
re-running it is safe. Normal startup never initializes or upgrades a database
and fails closed without schema 2 and Auth0 configuration. Back up the SQLite
file before upgrades. Do not put SQLite on an ephemeral container filesystem or
run multiple replicas: use **one API instance with a persistent local disk**.
No hosted database, backups or Vultr deployment are configured by this code.

### Provision a device (operator only)

```bash
mkdir -p .local
uv run python -m kickbac.cli provision-device kb-demo-01 --credential-file .local/kb-demo-01.secret
```

The target must be a **new file in an existing private directory**; the command
refuses overwrites, duplicate device IDs and invalid slugs. Only the SHA-256 hash
is stored in SQLite. The generated high-entropy device credential is written to
the explicit file, never printed. Keep that file private, transfer it securely to
the device's private configuration, and never put it in iOS, NFC, QR, screenshots,
chat, shell arguments or Git. POSIX files are created with mode 0600; on Windows,
use a directory whose ACL restricts access to your account. `.local/`, `.env` and
SQLite files are ignored by Git; ignored does not mean encrypted or backed up.
The CLI is the only provisioning interface; there is no public registration or
demo-login endpoint.

### Start the normal Auth0-backed server

```bash
# Same backend directory and exported environment as above.
uv run uvicorn kickbac.app:app --host 127.0.0.1 --port 8000 --workers 1
```

Visit `http://127.0.0.1:8000/health` for readiness and `/docs` for OpenAPI.
User requests require an Auth0 **API access token** from Native PKCE login,
RS256-signed with the configured issuer/audience, expiry and nonblank subject.
ID tokens and explicit machine-to-machine tokens are not accepted as users.
Public Auth0 signing keys are cached from the fixed HTTPS tenant JWKS URL; no
backend client secret is needed. ESP32 uses its separately provisioned bearer
credential, not an Auth0 user/M2M token. Do not paste either token into chat.

This loopback server is not reachable from a physical iPhone as its own
`localhost`. Follow the setup checklist before selecting a public trusted HTTPS
origin. Do not encode a placeholder host into an NFC sticker.

## Verified local simulated demonstration

No Auth0 account or hardware is required for this isolated command:

```bash
cd backend  # omit if already there
uv run python -m kickbac.simulator
```

It explicitly prints **SIMULATED OIDC** and **SIMULATED SENSOR**, starts actual
uvicorn HTTP listeners on OS-selected **127.0.0.1-only** ports, and uses an
initialized temporary database, ephemeral RSA-signed identity fixtures and
separate generated device credentials. These are injected only by this standalone
simulator; normal app startup has no fixture fallback or login endpoint.

The run exercises readiness, signed identity, NFC/QR resolution, availability,
heartbeat, arming and retry, device polling, sampling, upload and replay,
COMPLETE/result/history, foreign-owner/device denial and one-time consumption.
It shuts down and starts a **fresh application/server over the persisted DB**,
then checks recovery and replay again. Final JSON reports `SIMULATOR_OK`, one
measurement, zero duplicates and restart success. Credentials are never printed.
Startup, HTTP calls and shutdown have bounded waits; temporary files are removed
on completion. Standard system temporary storage is used unless `TMPDIR` is set.
The simulator is self-contained and does not populate your normal database or
provide a long-running login service for the phone.

## Tests and checks

```bash
cd backend  # omit if already there
uv run pytest -q
uv run ruff check .
uv run ruff format --check .
uv run python -m compileall -q kickbac
uv run python -m kickbac.simulator
```

Tests cover auth/security failures, explicit migrations and restart persistence,
provisioning failures, exclusive/concurrent arming, owner/device isolation,
heartbeat vs session timeout, committed exact-boundary expiry, cancellation,
strict measurement validation, atomic completion/rollback, concurrent retry
idempotency and private pagination. A subprocess test runs the real-HTTP simulator.
Local fixture tests do **not** establish live Auth0 login, deployed HTTPS,
physical iPhone NFC/QR routing, ESP32 connectivity or sensor calibration.

## Phone/device behavior and safety limits

NFC and QR carry the same future HTTPS `/d/{device_id}` URL. Resolution returns
only the device ID: **GET never arms a unit**. Preserve that ID through login,
ask the user to confirm, then POST `{}` to arm. Sessions expire after 60 seconds;
heartbeat online status expires independently after 30 seconds. Poll the user's
session once per second while active, stop at terminal states, and handle 409/410
without silently claiming the next breath for a stale user. Server-owned
associations cannot prove who physically blew into a shared device.

Results distinguish raw MQ-3 ADC counts (`0..4095`, `adc_counts`) from estimates
and mark `source: device|simulator`. Missing acquisition time and
`estimated_bac_percent` are **null**, not inferred or fabricated. ADC counts must
never be displayed as numeric BAC. Hardware must match the 12-bit ADC contract
or require a coordinated contract revision. Breath timing metadata is not proof
of a valid breath sample. This uncalibrated prototype must not support medical,
police-grade accuracy or safe-to-drive claims. Authenticated history is private
but this hackathon backend does not yet implement retention/deletion, encrypted
storage, user account deletion or production operations.
