# Phone-first signup/login — Auth0 + Twilio

## Run the actual iPhone app and diagnose login

This is the operational entry point, not a request to recreate Auth0/Twilio setup.
Liam owns Xcode/device execution and his active app branch. Source checked for
this guide: `liam/ios-profile-handoff@170ad17a08f43232e8ca2ea3650999261b6e080b`.
Refresh that ref before diagnosing a different installed build; its
`ios/README.md` and `ios/BACKEND_REVIEW_HANDOFF.md` are the client-owned details.
This source check is not a reproduced native login or a full client review.

### Build / install / start

1. In the existing Mac checkout, run `git status --short --branch`, `git fetch
   origin --prune`, and `git rev-parse HEAD origin/liam/ios-profile-handoff`.
   Do not discard edits or switch Liam's active worktree automatically. His
   newer phone/device/profile work is on that published branch, not necessarily
   the older app currently on main. A pushed source fix does not update an
   already-installed iPhone app: rebuild/reinstall the intended revision.
2. Open `ios/KickBAC.xcodeproj` in Xcode, resolve Swift packages, select the
   KickBAC scheme and intended iPhone, and use the owner's valid signing team.
   Follow the current client README for platform/toolchain requirements; if
   Xcode specifically reports missing Metal Toolchain, its documented command
   is `xcodebuild -downloadComponent MetalToolchain`. Do not change bundle IDs,
   entitlements or callback settings merely to suppress a build error.
3. Confirm the public values in `ios/KickBAC/Auth0.plist` against the table below.
   The phone uses the already-hosted `https://api.kickbac.vodka`; no laptop API,
   database initialization, device provisioning, new paid service or client
   secret is needed. Phone `localhost` is not the deployed backend.
4. Open the native phone screen, enter the real phone privately with its country
   code (`+` and canonical E.164 digits), and deliberately request a code once.
   Enter the Auth0-generated six-digit SMS code as a string, retaining leading
   zeroes. The configured expiry is 180 seconds; the current app has a 30-second
   same-number resend cooldown. Do not use an Auth0 Dashboard provider-test code
   to log in: that tests delivery, not Auth0 authentication.
5. On a new account, finish the current app's name/photo onboarding and await
   successful server save. Its current UI requires a captured photo; it has no
   Skip photo action. Allow camera access through the normal iOS prompt/settings.
   Existing profiles should restore. Keep this separate from initial OTP success.

The installable Personal Team build uses QR/manual device selection; NFC Tag
Reading/background Universal Links are not prerequisites for phone login. Sensor
assembly and firmware uploads are not prerequisites either. Do not use a local
simulator identity or a backend auth bypass to make a native login appear valid.

### What “account created” actually proves

These are independent checkpoints, not one database write:

| Checkpoint | Evidence | What it does not establish |
| --- | --- | --- |
| SMS request/delivery | Auth0 send outcome and delivery-provider evidence | Code accepted, Keychain save, API access or profile save |
| Auth0 SMS identity / successful token exchange | Authorized Auth0 record/login event for the actual subject | Current native credentials stored or application profile saved |
| Native secure sign-in | SDK claims validation and successful Keychain storage in that build | API acceptance or completed name/photo onboarding |
| API access | `GET /v1/me` accepts the API access token | A profile row; this route does not create one |
| Application profile | Successful `PUT /v1/me/profile`, then restored GET by the same subject | Full relogin/account-isolation/native acceptance or phone ownership inferred from a name |

Phone identity belongs to Auth0. Production SQLite has `profiles`, sessions,
measurements and game results, **not a phone/signup users table**. `GET /v1/me`
and profile GET do not create a profile. An absent profile can simply mean
onboarding is unfinished; a saved profile means a profile write reached the API.
A mutable display name is not sufficient to prove which person's phone/subject
owns that row. An operator must correlate the already-validated opaque subject
privately, not guess by name or dump phone/image/token data into chat or Git.

### Troubleshoot the exact failing stage

| App symptom / stage | Owner and next diagnostic |
| --- | --- |
| No SMS / “Couldn't send your code” | Check the private phone input/country and whether Auth0 accepted `/passwordless/start`. Operator correlates Auth0 persisted delivery-function events with Twilio status/error codes for the reported UTC time. No automatic resend loop or paid setup redo. |
| “SMS sign-in isn't enabled” / “isn't configured” | Liam reports the sanitized Auth0 error code and build SHA. Operator checks the existing Native SMS connection and Passwordless OTP grant without replacing unrelated settings. These were configured already; a screenshot of this message alone does not prove missing configuration. |
| Incorrect/expired code or “Couldn't verify your code” | Confirm the code belongs to that app's current phone challenge, preserve leading zeroes, and check the `/oauth/token` error/claims-validation stage. Use deliberate resend after cooldown, never send codes in chat. Auth0 errors are not the kickBAC API error envelope. |
| “Couldn't save your sign-in securely” / numeric Keychain status | This happens after successful Auth0 exchange/claims validation in the current source, not at SMS delivery. Verify the installed build includes `SessionCredentialsStorage`'s missing-item deletion fix. Only `errSecItemNotFound` during deletion is ignored; actual storage errors must still fail. Do not weaken token validation or wipe another account's data as a workaround. |
| API 401 / “Please sign in again” | Check that the API receives the **access token**, for audience exactly `https://kickbac-api` and the configured issuer, not the ID token/OTP/phone/device bearer. Liam handles expired credentials with a fresh deliberate sign-in. Do not log token contents or send them to another origin. |
| API 503 / offline / “Can't reach kickBAC” | Check public health and transport separately. A temporary JWKS/provider failure is not an absent account and not proof the OTP was wrong. Do not fabricate a blank profile or clear stored history to hide it. |
| Name/photo save failure | Diagnose the profile PUT separately: both fields required, explicit picture null means removal, JPEG/PNG/body limits apply. Preserve pending input. Existing profile/history should not be deleted or detached by retries. |

No current failure cause is diagnosed merely by publishing this table. Correlate
the actual installed revision, stage, sanitized error/status and UTC time first.
Provider configuration, a DB row, a fixture pass and an actual iPhone run are
separate evidence levels.

### Safe report-back (no secrets)

```text
Installed app commit/build:
Device or simulator / iOS version:
UTC time of deliberate attempt:
Stage: build | send | receive | exchange/claims | Keychain | API | profile
Exact UI error (redact phone/code/name/photo):
HTTP status / Auth0 error code / numeric Keychain status, if available:
SMS received: yes / no / unknown (never include the code)
Profile save completed: yes / no / not reached:
```

Liam/his agent keeps native acceptance ownership; this guide does not reassign
those tests to Nicholas. The operator investigates only the requested account/
time window with read-only, allowlisted diagnostics. Never paste credentials,
OTPs, phone numbers, raw provider responses, private subjects or profile images.

## Current configuration and evidence

Phone number + SMS OTP is the primary signup/login factor, **not SMS MFA**.
Liam owns SwiftUI and native acceptance. His reported embedded OTP implementation
is supported; no hosted-only rewrite is required. No iOS or production API source,
migration or dependency changes are included in this phone branch.

| Setting | Verified value |
| --- | --- |
| Auth0 domain | `dev-c87oxm4dkbyatvrn.us.auth0.com` |
| Native client ID | `5gJK2T71UkL0fbVj9pbzzEzKeMWZoYlC` |
| API audience | `https://kickbac-api` — no trailing slash; logical identifier, not host |
| API origin | `https://api.kickbac.vodka` — public trusted HTTPS verified separately |
| Connection / realm | `sms`, enabled for kickBAC iOS only |
| OTP settings | Six digits, 180-second expiry, signups allowed, domain promotion OFF |
| Native grants | Passwordless OTP enabled; Authorization Code and Refresh Token preserved; Client Credentials OFF |
| Initial scopes | `openid profile`; no email requirement |
| Native client secret | None; never embed one in iOS |

The Custom/Text provider's exact source was saved/deployed and read back. The
separate **kickBAC Verify success feedback** Post Login Action is deployed, its
three secret names verified, and its Login flow binding saved/read back as live
(audit event `2026-10-17T23:17:31.922Z`). Real feedback execution after a real SMS
login is **not verified**.

Twilio is Full/PAYG with independently verified individual PRIMARY compliance
approval. Earlier team dashboard tests produced two DELIVERED/error-0 attempts
and human receipt. No new unlisted-recipient delivery test is claimed after
approval. Normal signup must not require manually adding each user in Twilio;
country, carrier and anti-abuse policies still apply. Auth0 showed one SMS account
with a stored phone and one recorded login, without extracting phone values.
That observation is not native access-token/API/history acceptance.

No additional funds, auto-recharge, purchased sender, Photon work or optional
custom rate-limit provisioning is authorized. No hard spending cap is claimed.
Existing fallback connections, custom prompts and MFA are preserved.

## Liam / iOS handoff — NON-BREAKING API

Embedded requests go to the Auth0 domain, **not** the kickBAC API:

1. `POST /passwordless/start`: public `client_id`, `connection: "sms"`, privately
   entered canonical E.164 `phone_number`, and `send: "code"`.
2. `POST /oauth/token`: `grant_type: "http://auth0.com/oauth/grant-type/passwordless/otp"`,
   the same public `client_id`, `realm: "sms"`, private phone as `username`, private
   `otp`, exact `audience: "https://kickbac-api"`, and `scope: "openid profile"`.
3. Securely store credentials; send the **API access token** as
   `Authorization: Bearer <API_ACCESS_TOKEN>` to the API. The OTP, phone number,
   ID token and device credential are not user API bearer tokens.

Hosted Authorization Code + PKCE remains available with `connection=sms` and the
same audience/scopes. Do not reset Identifier First/custom prompts merely for
embedded login. Existing bundle/URL scheme is `com.liam.KickBAC`; preserve the
callback/logout target exactly:

```text
com.liam.KickBAC://dev-c87oxm4dkbyatvrn.us.auth0.com/ios/com.liam.KickBAC/callback
```

The unchanged `GET /v1/me` uses the bearer access token and returns, illustratively:

```json
{"user_id":"sms|example-opaque-subject"}
```

Treat the entire subject as opaque; do not parse a phone or require a prefix.
SMS/database accounts do not automatically share history when contact claims
match. No automatic linking by phone/email is implemented. Phone stays in Auth0.
Display name/picture use the separately implemented live `GET`/`PUT /v1/me/profile`;
its published source/schema is now included from current main. Use
`docs/API.md`/`docs/PROFILES.md`/live OpenAPI for that contract.

## Versioned Actions and operator configuration

`backend/auth0/twilio-verify.cjs` exports two dependency-free handlers. Deploy each
to its corresponding Auth0 trigger, **not** the API server. Target: Auth0 Node 22.

- **Custom Phone Provider / Text:** `onExecuteCustomPhoneProvider` sends real
  `otp_verify` notifications with Auth0's exact six-digit `CustomCode`, preserving
  leading zeroes, through the existing custom-code-enabled Twilio Verify Service.
  Auth0 alone generates/compares the login OTP and issues identity/tokens.
- **Dashboard `provider_test`:** connectivity only; omits `CustomCode`, letting
  Verify generate a test code. That code cannot authenticate an Auth0 user.
- Other notification types/channels are explicitly dropped. Do not enable phone
  MFA/recovery/enrollment without implementing and testing their delivery needs.
- **Post Login:** `onExecutePostLogin` reports `Status=approved` only for verified
  SMS users, skipping refresh transactions. Phone-address feedback concerns the
  latest pending provider attempt, not an exactly correlated login transaction.
  Failed/expired feedback produces a fixed warning and never grants/denies login.
  No Twilio VerificationCheck authenticates users.

Both Actions require privately configured secret **names** `TWILIO_ACCOUNT_SID`,
`TWILIO_AUTH_TOKEN`, `TWILIO_VERIFY_SID`. Values never belong in Git, iOS, API runtime
configuration, screenshots or chat. Operator-only ignored Twilio configuration
is not loaded by kickBAC; do not print it or source it as shell code. No SDK needed.

Requests use a fixed HTTPS provider origin, reject redirects, have an eight-second
timeout and no automatic retry. Delivery errors expose only fixed stage names
and allowlisted numeric HTTP/provider codes, never phone/code/credential values,
provider bodies or original exceptions. Preserve those numeric diagnostics when
troubleshooting; a pending delivery response still is not successful login.

For authorized future changes, inspect the existing tenant first; preserve
fallback/grants/unrelated Actions, configure secrets privately, and read back
exact source/settings and saved flow binding after deployment. No sender purchase
or repeated compliance setup is needed. No dashboard/host changes were made by
this source-publication task.

## Historical phone-publication checks and outstanding acceptance

The counts below describe the original phone-source checkpoint, not the latest
combined backend suite. Later release/CI evidence is in
[BACKEND_RELEASE_VERIFICATION.md](BACKEND_RELEASE_VERIFICATION.md) and
[the current Liam handoff](LIAM_BACKEND_HANDOFF.md). The phone guide and UI error
mapping above do not claim a new native login execution.


Run from repository root (explicit Windows Node path):

```bash
"C:/Program Files/nodejs/node.exe" --test backend/auth0/test-twilio-verify.cjs
cd backend
uv run --python 3.12 pytest -q
uv run --python 3.12 ruff check .
uv run --python 3.12 ruff format --check .
uv run --python 3.12 python -m compileall -q kickbac
uv run --python 3.12 python -m kickbac.simulator
```

Verified: **78 Action fixtures**, **107 backend tests**, Ruff lint, **31-file**
format check, CJS syntax and Python compilation. Six phone-identity cases cover
no-email SMS identity, both incorrect audiences, bare OTP/phone rejection, and
subject-isolated history surviving restart. Real-HTTP simulator: `SIMULATOR_OK`,
`COMPLETE`, one measurement, zero duplicates, foreign-owner 404, restart `ok`.
Local Node is 24.18.1; earlier hosted Node 22 no-SMS checks established configuration
and connectivity, not real login or feedback execution.

Liam still verifies real signup/relogin, correct access-token audience/issuer,
`/v1/me`, private history after logout/app restart, cross-user denial, invalid/
expired and resend/old-code behavior, secure storage and actual device build.
Feedback runtime, general-recipient delivery, physical NFC/QR routing and real
Auth0-owner-to-device measurement acceptance remain distinct outstanding checks.
Fixtures never substitute for live acceptance; do not add auth bypasses or fake
login endpoints. Firmware bring-up may proceed independently; sensor validation
and native acceptance are separate from provider configuration.

## References

- https://auth0.com/docs/authenticate/passwordless/authentication-methods/sms-otp
- https://auth0.com/docs/authenticate/passwordless/passwordless-with-universal-login
- https://auth0.com/docs/authenticate/passwordless/best-practices
- https://auth0.com/docs/customize/phone-messages/configure-phone-messaging-providers/configure-a-custom-phone-provider/configure-a-custom-phone-provider-with-twilio-verify
- https://www.twilio.com/docs/verify/api/customization-options
- https://www.twilio.com/docs/verify/api/verification
- https://www.twilio.com/docs/trust-hub/profiles/primary-compliance-profiles
- https://www.twilio.com/en-us/verify/pricing
