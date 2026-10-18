# Architectural decisions

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
- **Choice:** Auth0 access-token validation with RS256/JWKS, exact issuer/audience/expiry; no passwords or login endpoint in the backend. Vultr is the proposed host; user confirms account/credits ready, but no VM/region/budget or hosted service is verified.
- **Why:** sponsor-supported authentication with documented SwiftUI SDK. Auth0 tenant/API/Native app creation is reported complete, and public discovery/JWKS were independently verified. Liam's exact bundle ID is com.liam.KickBAC and the target public API is https://api.kickbac.vodka. Callback allowlists are reported saved and a fresh public request now returns login_required to the URI-equivalent callback rather than a mismatch; real user login remains unverified. Native callback/bundle configuration belongs to Liam; coordinate before changes.
- **Rejected for now:** DeepSpace browser-oriented auth, whose native Swift handoff has not been verified; combining two identity providers; Tiger Data merely for sponsor coverage.
- **Sources:** https://www.mlh.com/events/swamphacks-xii/prizes ; https://auth0.com/docs/quickstart/native/ios-swift ; https://docs.deep.space/guides/authentication . Account credits are not proof of free deployment or successful integration.

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
