# kickBAC setup and integration handoff

Liam owns SwiftUI. Never send passwords, client secrets, OTPs, bearer/refresh/device
tokens, recovery codes, private SSH keys or unredacted credential screenshots in
chat. This is the existing setup, not a request to recreate accounts or resources.

## Auth0 public configuration

| Item | Value |
| --- | --- |
| Tenant | `dev-c87oxm4dkbyatvrn.us.auth0.com` |
| API audience | `https://kickbac-api` — exactly, no trailing slash |
| API signing | RS256; backend validates issuer, audience, expiry and subject using public JWKS |
| Native application | kickBAC iOS |
| Public client ID | `5gJK2T71UkL0fbVj9pbzzEzKeMWZoYlC` |
| Bundle ID / URL scheme | `com.liam.KickBAC` |
| Callback/logout target | `com.liam.KickBAC://dev-c87oxm4dkbyatvrn.us.auth0.com/ios/com.liam.KickBAC/callback` |
| API base | `https://api.kickbac.vodka` |

Audience is an immutable logical identifier, **not** the deployed host. Native
clients use no client secret. Preserve callback spelling/case and Liam's existing
URL handling; callback URLs and NFC/QR device URLs are different things.

## Phone login is configured; native acceptance remains

See [PHONE_LOGIN.md](PHONE_LOGIN.md) for authoritative phone settings and requests.
The `sms` connection is enabled for the Native app: six-digit OTP, 180 seconds,
signups allowed, domain promotion OFF. Passwordless OTP grant is enabled alongside
preserved Authorization Code/Refresh Token grants. Existing fallback connections
and custom prompts are preserved; no Identifier First reset is required for the
embedded flow Liam reports using.

Embedded flow: Auth0 `/passwordless/start` then `/oauth/token` with passwordless
OTP grant, realm `sms`, exact API audience and `openid profile`. Hosted PKCE with
`connection=sms` also remains available. iOS sends the resulting **API access token**,
not an ID token/OTP/phone number, to `GET /v1/me` and other private API routes.
No new custom permissions or M2M client grants are required for this milestone.
A zero-of-zero permissions display is not proof of failed user-delegated access.

Custom/Text provider -> Twilio Verify delivers Auth0's codes; Auth0 owns validation.
Full/PAYG account, individual PRIMARY approval, earlier dashboard delivery/human
receipt, exact delivery source and separate Post Login feedback deployment/binding
were verified. These are **not pending setup**. Real native token/API/history and
feedback runtime acceptance remain with Liam. Do not require normal users to be
manually allowlisted or claim untested general-recipient delivery.

No phone values or provider secrets belong in the backend/iOS. Phone remains in
Auth0. Live display name/picture persistence uses separately owned GET/PUT
`/v1/me/profile`; this branch now includes the published schema3 profile code.
Consult API.md/PROFILES.md and live OpenAPI. Never auto-link subjects by phone/email.

## Backend and hosting

Use README for local `uv sync --locked`, environment export, explicit DB migration,
private device provisioning and single-worker startup. Backend needs
`AUTH0_DOMAIN`, exact `AUTH0_AUDIENCE`, and persistent `KICKBAC_DB_PATH`; no Auth0
client secret, management token or Twilio secret is required. Normal startup has
no fixture/login fallback. Local simulator is explicitly simulated OIDC/sensor,
not a native login service or measured BAC.

The existing Vultr service at `https://api.kickbac.vodka` has verified public trusted
HTTPS. Cloudflare DNS delegation/TLS are no longer pending. No new VM, domain,
paid add-on or billing change is authorized by these instructions. Deployment and
profile documentation owns host artifacts, schema upgrades and operational evidence;
the original phone-only test count is historical. One API worker and persistent
SQLite remain required. Never expose device credentials in app/NFC/QR.

## Remaining acceptance

Liam verifies Xcode/device build, real first signup/relogin, correct API token,
`/v1/me`, private history/session ownership, relogin/restart persistence, invalid/
expired/resend code behavior, secure storage and callback/logout behavior for any
hosted path used. Actual Post Login feedback runtime and new unlisted-recipient
delivery remain unverified. Physical NFC/QR app routing, firmware and calibrated
sensor behavior remain separate; public JSON resolution does not itself launch
the app. Do not substitute local fixtures for these checks.

Report only public configuration/status and sanitized error codes. Never paste
codes, tokens or private phone numbers. No additional funds, auto-recharge,
optional custom Verify buckets or fallback removal are authorized.

## Official references

- https://auth0.com/docs/get-started/auth0-overview/set-up-apis
- https://auth0.com/docs/get-started/apis/api-access-policies-for-applications
- https://auth0.com/docs/libraries/auth0-swift
- https://auth0.com/docs/authenticate/passwordless/authentication-methods/sms-otp
