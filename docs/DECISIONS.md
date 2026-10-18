# Architectural decisions

## Shared game ledger and profile-wide points
- **Choice:** one immutable owner-scoped game_results table and additive POST/GET `/v1/me/game-results`, GET `/v1/me/stats`; SQL aggregates derive profile-wide/per-game totals. Fixed10 server-assigned participation points per unique accepted completion under `completion_v1`; raw score stays separate.
- **Why:** generic Trivia/Pictionary/future-game result data without a table per game, mutable client balances or double awards during retries/concurrency. Persisted UUID/canonical payload gives201first/200replay/409changed; verified token subject owns all data, independent of mutable profile or readings.
- **Limits/rejected:** bounded client-reported outcomes are not verified gameplay/anti-cheat. No multiplayer engine, party membership/count, public leaderboard or reward for BAC/alcohol/tests. Figma Party/Me flows inspected read-only; full roadmap not assumed. Schema004 explicitly upgrades preserved existing data; backups/rollback must respect schema4. Exact JSON/limits in GAMES.md.

## Signing-key cache lifetime
- **Choice:** disable PyJWT's non-expiring per-key LRU, retain300-second JWKS-set cache and5-second fetch timeout. Removed keys cannot remain trusted indefinitely; transport outage is503 rather than stale-key fallback. Existing401/503 contract unchanged.
- **Why:** JWKS-set TTL alone did not expire previously resolved keys. Ten transport-mocked real-client regressions cover removal/rotation/cache/outage and malformed inputs, with independent review. No real Auth0 key-removal/network/native-acceptance claim.

## Minimal profile onboarding (additive)
- **Choice:** keep SMS phone/verified login in Auth0; store only display name and a bounded, sanitized JPEG in a private SQLite profile keyed by the validated subject. Add `GET`/`PUT /v1/me/profile`; preserve `/v1/me`, auth and all device/session/history contracts. Schema 003 adds profiles without rewriting historical migrations/data.
- **Why:** Nicholas confirmed the only onboarding fields are phone, picture and name. This closes the actual app-persistence gap without inventing demographics, a second identity authority or another cloud service. Inline bounded Base64 JSON is a low-volume demo tradeoff, not a design for bulk media.
- **Security:** owner is token-derived; no client phone/user ID accepted. Validate/normalize photos rather than trusting MIME/file names, strip metadata, cap bytes/pixels/body streams, and include profile data in private SQLite snapshots. Public profile lookup, account linking, phone changes and account deletion are not added.
- **Client coordination:** NON-BREAKING existing routes; Liam integrates the two new profile requests and image conversion/size limits as documented in `PROFILES.md`. No SwiftUI files changed. API deployment and native acceptance remain explicit verification gates.

## First vertical slice
- **Choice:** FastAPI, SQLite, synchronous transactional writes, one API process, HTTP polling. Users are verified external identity subjects; no speculative profile table.
- **Why:** quickest reliable authenticated association -> simulator measurement -> private history path. One low-volume shared demo unit does not require distributed workers or realtime infrastructure.
- **Rejected for now:** managed Postgres/realtime (extra provisioning), WebSockets/SSE (extra connection/reconnect behavior), party-game backend (outside initial milestone). SQLite requires persistent disk, backups and one deployment instance; never deploy it on ephemeral serverless storage.

## Auth and sponsor resources
- **Choice:** Auth0 RS256 access-token validation with exact issuer/audience/expiry and public JWKS. No backend login/password service or client secret. Existing Vultr API at https://api.kickbac.vodka has verified trusted HTTPS; no additional infrastructure is authorized here.
- **Why:** sponsor-supported identity with a public Native client. Liam owns native callbacks/credential storage and real token/API acceptance; provider configuration or public discovery does not prove that acceptance.
- **Rejected:** duplicate identity providers, M2M tokens as user identity, or sponsor stacking without a functional need.


## Association and identity limits
- **Choice:** authenticated confirmation arms a known device for 60 seconds, one active session per device; retry by its owner reuses the session without extending expiry. Cancel/expiry releases the unit. Device credentials are provisioned independently, random and stored hashed.
- **Why:** bounds stale assignments and prevents competing app requests from stealing a session. The backend derives ownership; device requests cannot select a user.
- **Limit:** a timeout does not authenticate the person physically exhaling. Confirm target on the phone/device before the sample; no biometric identity claim.

## Readings and retries
- **Choice:** explicit raw MQ-3 ADC counts, breath duration, source, optional true acquisition time, server receive time; estimated_bac_percent remains null. No numeric BAC fabricated from uncalibrated ADC values.
- **Choice:** device-generated measurement UUID; replay of identical validated payload returns the original result even after completion/expiry, changed payload conflicts, new ID cannot reuse a terminal session.
- **Why:** Wi-Fi retries must not produce duplicates or reassign samples. Device state is derived from its current unexpired session, not separately mutable state.

## Local authentication demonstration
- **Choice:** a standalone simulator may generate an ephemeral RSA identity fixture and exercise real HTTP and signed-token validation on loopback, explicitly labeled simulated OIDC. Normal server configuration accepts only the configured Auth0 tenant.
- **Why:** test without hardware/accounts, without adding a public dev-login endpoint or silently bypassing production authentication. This is NOT proof of real Auth0 login, live sensor calibration, public HTTPS or iPhone integration.

## Primary phone signup/login
- **Choice:** primary phone + SMS OTP, not MFA. Support Liam's reported embedded Auth0 `/passwordless/start` -> `/oauth/token` flow with realm `sms`, passwordless OTP grant, exact audience `https://kickbac-api`, and no client secret. Hosted Authorization Code + PKCE remains enabled, not mandated as a rewrite.
- **Why:** Auth0 owns code validation and opaque identity; existing subject-based API isolation needs no new phone table, route, Twilio dependency or API secret. Display name/picture persistence is separately owned by the profile branch; phone stays in Auth0.
- **Configuration:** Native-only SMS enabled, six digits/180 seconds, signups allowed/domain promotion OFF; existing authorization-code/refresh grants, fallback connections and custom prompts preserved.
- **Rejected:** backend OTP service, automatic phone/email account linking, app takeover, SMS MFA substitution, or counting local signed fixtures/provider delivery as native acceptance.

## Twilio Verify as Auth0 delivery provider
- **Choice:** dependency-free Custom/Text Action forwards Auth0's exact CustomCode to the existing custom-code-enabled Verify Service. Auth0 alone authenticates. Dashboard provider_test omits CustomCode for connectivity only; unsupported notifications are dropped. No VerificationCheck-based authentication or sender purchase.
- **Feedback:** separate deployed/bound Post Login Action reports advisory approval only for verified SMS users, skips refresh and cannot grant/deny login. Phone-address feedback targets the latest pending provider attempt, not exact transaction correlation. Deployment/source/secret names/saved binding verified; actual runtime after real login remains unverified.
- **Security/limits:** fixed provider origin, strict inputs, eight-second timeout, no redirects/retry; only fixed failure stages and allowlisted numeric diagnostic codes are exposed. Secrets belong privately to both Actions, never API/iOS/Git. Optional custom rate buckets waived; no extra funds, auto-recharge or hard spending-cap claim.
- **Evidence:** Full/PAYG account and approved individual PRIMARY profile independently verified. Earlier team dashboard SMS delivery corroborated by provider status/human receipt. No newly unlisted-recipient test after approval; normal signup must not require console allowlisting. Native token/API/history acceptance remains Liam's work.
- **Checks:** 78 local Action fixtures and six phone-identity cases (107 backend tests total); local Node 24 and Python 3.12. Earlier hosted Node 22 no-SMS checks verified configuration/connectivity, not real login. See PHONE_LOGIN.md and VERIFICATION.md.
- **Sources:** https://auth0.com/docs/customize/phone-messages/configure-phone-messaging-providers/configure-a-custom-phone-provider/configure-a-custom-phone-provider-with-twilio-verify ; https://www.twilio.com/docs/verify/api/customization-options ; https://www.twilio.com/docs/verify/api/verification .


## Firmware phase — pressure sensor unavailable
- **Direction:** Nicholas authorizes firmware bring-up in a new session, without reopening native login tests. Public/native integration follow-ups remain honest blockers to full end-to-end completion, not basic serial/sensor work.
- **Hardware fact:** Amazon failed delivery of the air-pressure sensor; it is confirmed unavailable. Exact ESP32-S3/MQ-3 modules and DHT11 availability must be inventoried before wiring.
- **Proposals, not validated detection:** assess DHT11-assisted humidity only if available and empirically useful, and a configurable baseline-relative MQ threshold with filtering, hysteresis and recovery. Alcohol response cannot reliably distinguish sober breath from no breath; do not treat a timeout as zero. Consider transparently manual acquisition if no usable breath signal exists.
- **Contract gate:** `breath_duration_ms` is currently required. Do not invent breath duration or silently relabel a timed window. Any affected API/units/quality/state/UX revision needs both integration headings before implementation. No schema change is made here. See `FIRMWARE_HANDOFF.md`.
