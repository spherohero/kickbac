# Phone-first signup/login — Auth0 + Twilio

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
its source/schema belongs to the profile branch, not this branch. Use integrated
`docs/API.md`/live OpenAPI for that contract.

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

## Local checks and outstanding acceptance

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
