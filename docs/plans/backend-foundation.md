# kickBAC Backend Foundation Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Prove authenticated ownership -> exclusive session -> simulated device upload -> persisted private history over real HTTP, without physical hardware or a provisioned Auth0 tenant.

**Architecture:** FastAPI + transactional SQLite; external user identity validated by RS256/JWKS; per-device hashed credentials. Single server, no worker, polling. A standalone explicit loopback simulator uses temporary RSA identity fixtures and actual HTTP; normal startup never accepts those identities.

**Tech Stack:** Python 3.11+, uv, FastAPI, Pydantic, PyJWT[crypto], uvicorn, httpx, pytest; pinned uv lockfile.

## Prerequisites and scope
User chose Auth0 (not configured) and confirms Vultr account/credits ready (not deployed/verified). Read `docs/API.md` for exact v0 contract. Backend source is `backend/kickbac/`, tests `backend/tests/`; leave Liam's app and Figma untouched. Feature branches stack on current api-contract branch until docs are merged; main stays unchanged. No cloud resource creation or public auth bypass. Each numbered task uses a failing behavioral test, minimal implementation, passing targeted/full tests and small focused commits. Expected results below are acceptance criteria, not claimed execution output.

### Task 1: Runnable foundation and persistent schema
Files: `backend/pyproject.toml`, `backend/kickbac/app.py`, `backend/kickbac/settings.py`, `backend/kickbac/db.py`, `backend/kickbac/cli.py`, `backend/migrations/001_initial.sql`, `backend/tests/test_foundation.py`.
Write/run a failing test for migration then GET /health on an initialized temporary DB. Implement versioned migration command (idempotent), schema version check and app factory; verify actual SQLite schema/version readback and restart persistence. Test command: `cd backend && uv run pytest tests/test_foundation.py -q`.

### Task 2: Verified identities and device provisioning
Files: `backend/kickbac/auth.py`, `backend/kickbac/cli.py`, `backend/tests/test_auth.py`.
Write/run a failing identity test using real ephemeral RSA-signed JWTs. Implement required signature/issuer/audience/expiry/subject validation; reject ID tokens/wrong audience, unsigned/bad/expired tokens and wrong token kinds. Test JWK retrieval with local fixture, never real credentials. Fail closed on absent Auth0 settings. Add random device-key provisioning written to an explicit private file, never stdout; hash only in DB; distinct credentials cannot read each other's sessions. Run full tests; commit auth separately.

### Task 3: Exclusive expiring sessions
Files: `backend/kickbac/sessions.py`, API schemas/routes, `backend/tests/test_sessions.py`.
Tracer bullet first: owner arms correct device and reads it, foreign user gets 404. Then separate RED/GREEN tests for owner retry without extension, competing users/concurrent requests (one winner), 60-second boundary expiry and fresh arming, cancel/retry, unknown IDs, device heartbeat/online derivation and device-safe sampling/poll. Inject clock for deterministic time tests. Enforce transactions/unique active-device constraint. No claimed physical identity guarantee.

### Task 4: Idempotent measured result and private history
Files: `backend/kickbac/measurements.py`, schemas/routes, `backend/tests/test_measurements.py`.
Tracer bullet: authorized device uploads to active session, owner gets COMPLETE and exactly one raw/simulator result; another user has empty history. Then RED/GREEN expiry, completed reuse, wrong device, malformed/extra/non-finite/coerced data, duplicate replay after expiry, changed payload conflict, concurrent repeated uploads, pagination and persistence across restart. No estimated BAC computation. Compare OpenAPI and documented examples.

### Task 5: Real-HTTP standalone simulator
Files: `backend/kickbac/simulator.py`, `backend/tests/test_simulator.py`, `backend/.env.example`, `README.md`.
Write/run failing smoke test, then implement `cd backend && uv run python -m kickbac.simulator`. It initializes temporary persistent SQLite, provisions mock device and ephemeral RSA fixture, starts actual uvicorn on OS-selected loopback port, exercises health/auth/device resolution/heartbeat/arm/sampling/upload/retry/session/history/private denial, reopens DB/app to check persistence, and cleans up. Explicitly print simulated identity/measurement disclaimers and a concise assertion-backed outcome, never bearer credentials. Catch startup failures and always shut down cleanly. Test it as a subprocess, then run it manually and run all tests. Normal startup: configure Auth0, initialize schema, provision real device privately, `uv run uvicorn kickbac.app:app --host 127.0.0.1 --port 8000`. User must supply public Auth0 configuration; cloud/SwiftUI/hardware are not proved by this fixture.

### Review/merge gate
Spec compliance review first, then code-quality/security review. Fix significant findings with failing regression tests. Parent independently runs full tests, actual simulator, startup/migration checks, OpenAPI comparisons, dependency/security checks and Git diff/no-secret checks; fetch main again before claiming readiness. No push/PR/merge without instruction; report local branch/commit/file/test evidence and explicit Auth0/hosting/iPhone/hardware gaps.
