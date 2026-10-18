# Verification scope — phone-login publication

These are actual local executions on `backend/phone-otp`, not predicted results.
Production API source, migrations, dependencies and iOS source are unchanged by
this branch. Earlier implementation/security review applies to the initial local
backend milestone, not to unverified native/provider/hardware integrations.

## Reproduced checks

From repository root:

```bash
"C:/Program Files/nodejs/node.exe" --check backend/auth0/twilio-verify.cjs
"C:/Program Files/nodejs/node.exe" --check backend/auth0/test-twilio-verify.cjs
"C:/Program Files/nodejs/node.exe" --test backend/auth0/test-twilio-verify.cjs
cd backend
uv run --python 3.12 pytest -q
uv run --python 3.12 ruff check .
uv run --python 3.12 ruff format --check .
uv run --python 3.12 python -m compileall -q kickbac
uv run --python 3.12 python -m kickbac.simulator
```

Results: **78 Action fixtures passed** on Node 24.18.1; **107 backend tests passed**
on Python 3.12.5; Ruff lint passed; **31 files** already formatted; CJS syntax and
Python compilation passed. Simulator returned `SIMULATOR_OK`, real HTTP loopback,
`COMPLETE`, one measurement, zero duplicate rows, foreign-owner 404, restart `ok`.
It uses ephemeral signed identities and simulated sensor data, not live Auth0.

Six collected phone-identity cases verify SMS identity without email, rejection of
both wrong audiences, bare OTP/phone bearer rejection, and persisted private
history isolated by subject even when contact claims match. Existing tests cover
expiry/exclusive arming, one-time completion, malformed readings, public read-only
resolution, retry/concurrency/rollback, restart and auth/device/user isolation.

## Source/security review

The dependency-free Action source was reviewed separately from API runtime code:
fixed HTTPS origin, validated service/account IDs, canonical E.164 and six-digit
real login code, bounded requests, redirect rejection, no automatic retries and
no VerificationCheck-based authentication. Unsupported notifications are dropped.
Dashboard `provider_test` explicitly omits CustomCode and never authenticates.
Errors contain fixed stages/allowlisted numeric provider codes, not untrusted
bodies, phone/OTP/credential values or original exceptions. Feedback is advisory,
verified-SMS-only, skips refresh and cannot grant/deny login. Phone-address feedback
is not exact transaction correlation. Fixtures use fake credentials and mocked
fetch; no populated private operator configuration was read for publication.

Previous independent local milestone review approved the backend's documented
hackathon scope after regression fixes for logging, typed retry responses and
read-only public resolution. That is not a new independent review of these Actions.
Production follow-ups remain: PyJWKClient per-key cache freshness and actual remote
HTTP timeout/unknown-key/rotation/removal tests. No production security certification
or hard provider spending cap is claimed.

## External evidence versus remaining acceptance

Prior operator readbacks establish Custom/Text delivery source, Auth0 Node 22
no-SMS configuration/connectivity, Native SMS assignment/OTP grant, and deployed
Post Login feedback source/secret names/saved binding. Earlier dashboard delivery
was corroborated by provider DELIVERED/error-0 status and human receipt. Individual
PRIMARY compliance approval is independently verified; no repeat setup is needed.
One Auth0 SMS account/recorded login was observed without exposing phone values.

Public trusted HTTPS is separately verified; it is no longer the earlier timeout
blocker. Live profile GET/PUT and schema 3 belong to the separately tested/deployed
profile branch; **107 tests here are not that branch's 185-test profile evidence**.
This phone branch's local API remains schema 2 until parent integration.

Not established by these checks: real native access-token/API/history acceptance,
feedback execution after real login, delivery to a newly unlisted recipient,
physical NFC/QR app routing, real Auth0-owner-to-device end-to-end measurement,
ESP32 firmware/sensing/calibration or certified BAC accuracy. Liam owns native
acceptance; safe firmware bring-up can proceed independently. No new live SMS,
host/dashboard changes or paid resources were used for publication.
