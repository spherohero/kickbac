# Local verification report

Implementation reviewed at `31e872f`, before the separate integration-setup documentation commits. The same backend code is now being published from `backend/initial-setup`; consult GitHub for current PR/merge state. These are real local executions, not predicted results.

## Parent execution
From `backend/`:
- `uv run pytest -q`: **101 passed**, no warnings.
- `uv run ruff check .`: passed.
- `uv run ruff format --check .`: **30 files already formatted**.
- `uv run python -m compileall -q kickbac`: passed.
- `uv run python -m kickbac.simulator`: **SIMULATOR_OK**, real HTTP loopback, session COMPLETE, one measurement, zero duplicates, foreign-owner404, fresh application/server restart over persistent SQLite ok.

The explicit CLI migration was run twice against a fresh temporary database. Parent read back schema version2 and the devices/sessions/measurements columns. Normal uvicorn module startup with the supplied real Auth0 configuration (not a fixture verifier) returned health200 and unauthenticated me401 with a Bearer challenge. Actual OpenAPI and docs table GET/POST route sets matched exactly (12 routes); bearer schemes and both typed200/201 retry responses are tested.

Runtime dependency pins exported from the lockfile were audited with pip-audit/PyPI: **no known vulnerabilities found**. This is limited to known package advisories, not a full security guarantee.

## Contract-review corrections
An independent spec reviewer identified three gaps. Each was reproduced by a failing regression test and then fixed:
- Scoped transition INFO logs now use uvicorn's runtime logger hierarchy; the regression starts real uvicorn and verifies event identifiers, no credential/payload leakage, no root logger changes or duplicate events.
- Session creation and measurement upload OpenAPI now declare typed200 retry responses alongside201.
- Public NFC/QR resolution uses a closing query-only connection. Tests verify known and unknown GETs leave expired sessions and all other rows unchanged; authenticated state operations still persist expiry.

Parent reread the exact fixes and reran the full101-test suite and simulator. **Spec recheck: PASS. Independent security/code-quality review: APPROVED for the documented local hackathon-demo scope**, with no blocking security concerns or logic errors. This is local milestone review, not approval of unverified external integrations.

Non-blocking follow-ups before production use: disable or bound PyJWT's per-key LRU cache (its `lifespan` bounds the JWKS-set cache, not individually cached keys), and test the actual PyJWKClient HTTP retrieval path for timeout/unavailability, unknown kid and key rotation/removal. Existing local provider tests verify signed tokens and exception mapping but not the complete remote retrieval/cache behavior.

## Coverage of the requested demo risks
- Correct device and user association, private ownership, exclusive concurrent arming.
- Exact-boundary expiry, cancellation, no reuse of completed sessions.
- Unknown device/session and malformed/extra/coerced/out-of-range measurement inputs.
- Same-payload retry, changed-payload conflict, concurrent duplicate uploads and one atomic measurement/session completion; rollback on DB failure.
- Correct public device resolution without mutations or private data.
- Real RSA signature/issuer/audience/expiry/subject validation in local fixtures, wrong user/device/M2M/ID-token rejection and fail-closed normal configuration.
- End-to-end simulated device flow over real HTTP and persisted restart recovery.

## Initial setup PR recheck

After fetching Liam's published starter/navigation branches, the existing backend was assembled on a dedicated `backend/initial-setup` branch from current `main`. No iOS files were added or changed. A fresh `uv sync --locked`, all **101 tests**, Ruff lint, the **30-file** format check, byte compilation and the standalone real-HTTP simulator passed again. The simulator returned `COMPLETE`, one measurement, zero duplicate rows, foreign-owner `404` and successful restart. Backend runtime, tests, migrations and lockfile remain identical to the previously reviewed implementation. Shared root ignore rules match Liam's starter exactly; Python/database/private-device artifacts are scoped in `backend/.gitignore`, while global environment-file protection is retained. This avoids an add/add conflict without changing his PR. This PR publishes that existing local foundation, including authentication, sessions and the simulator; it does not claim hosted deployment or native login.

Liam's separate initial iOS PR was structurally inspected at `6262cb7`: two XML plists, three asset JSON manifests and workspace XML parsed, and both target bundle/Info.plist settings matched. Its trailing-slash audience mismatch is a requested correction, and no Xcode build was available on this Windows host. See `SETUP.md` for the precise handoff and latest-PR caveat.

## Not verified / not implemented by this milestone
- Real Auth0 user login, application grant/audience issuance and callback/logout behavior: Bundle ID is com.liam.KickBAC; after reported allowlist saving, the public callback probe now returns login_required to a URI-equivalent callback, not a mismatch. Actual Native login/token acceptance/logout remain unverified.
- Vultr VM, trusted public HTTPS, DNS, physical iPhone reachability or NFC/QR app routing.
- ESP32 firmware, actual breath-presence validation, sensor wiring/calibration or certified BAC accuracy. Raw ADC and simulated values are explicitly labeled; estimated_bac_percent remains null.

See `API.md` for the contract, `SETUP.md` for Auth0 and `DEPLOYMENT_SETUP.md` for proposed hosting. The full branch is a local backend milestone, not a completed hosted/iOS/hardware product.

## Phone-first login compatibility branch

On `backend/phone-otp`, six new local signed-fixture checks verify SMS-subject identity without email, exact audience validation, OTP/phone-number bearer rejection, separate subject ownership despite matching contact claims, and private-history persistence after a fresh application restart. Existing production API code, migrations and dependencies are unchanged. Fresh full execution: **107 passed**, Ruff lint passed, **31 files already formatted**, byte compilation passed, and the real-HTTP simulator again returned one completed measurement, zero duplicate rows, foreign-owner404 and restartok.

Authenticated Auth0 inspection confirmed the correct tenant uses New Universal Login and has **No Valid Phone Provider Configured** for the SMS connection. The Identifier First save confirmation warns that custom prompts will reset; it was cancelled. No SMS provider, app assignment, primary-login rollout, MFA change, OTP send or paid Twilio resource was configured. Nicholas is creating the missing Twilio account. See `PHONE_LOGIN.md` for new-trial message-body restrictions, sender requirements, private credential entry and the exact client handoff. Real SMS signup/native login remains blocked and is not represented by these passing compatibility tests.
