# kickBAC API contract — v0

Status: initial implementation contract, not a deployed URL. Display name **kickBAC**. REST JSON uses snake_case, opaque UUID session/measurement IDs, a provisioned device slug, and ISO 8601 UTC timestamps (`Z` or `+00:00`). Users are opaque verified Auth0 `sub` strings, not client-chosen IDs. No certified BAC or safe-to-drive interpretation is provided.

## Authentication
User routes require `Authorization: Bearer <Auth0 API access token>` (not an ID token). RS256 signature, issuer, audience, expiry and subject must be validated. `/v1/me` returns the verified subject. Auth0 Native app uses Authorization Code + PKCE through Auth0.swift; native client ID/domain/audience/bundle/callback values must be coordinated with Liam. There is no backend password/login endpoint.

Device routes use `Authorization: Bearer <per-device credential>`, issued through a backend-only provisioning command, stored hashed in the database. Device identity derives from that credential. Never put it in NFC, QR, iOS, Git or logs. Device routes do not reveal the associated user's identity.

No demo auth endpoint exists. Local simulator identities and measurements must be explicitly labeled as simulated; they do not prove live Auth0 login.

## Endpoint summary
| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/health` | public | database/server readiness |
| GET | `/d/{device_id}` | public | resolve NFC/QR unit ID; no arming or private data |
| GET | `/v1/me` | user | identity |
| GET | `/v1/devices/{device_id}` | user | current derived availability and online state |
| POST | `/v1/devices/{device_id}/sessions` | user | arm known unit; empty JSON `{}` |
| GET | `/v1/sessions/{session_id}` | owning user | session and optional result |
| POST | `/v1/sessions/{session_id}/cancel` | owning user | cancel active session; `{}` |
| GET | `/v1/measurements` | user | private history with `limit` and `offset` |
| POST | `/v1/device/heartbeat` | device | record connectivity; `{}` |
| GET | `/v1/device/session` | device | fetch its current active session |
| POST | `/v1/device/sessions/{session_id}/sampling` | device | report valid breath sampling start; `{}` |
| POST | `/v1/device/measurements` | device | idempotent sample upload |

Normal server must be configured with Auth0 and an initialized persistent DB. `/docs` and `/openapi.json` document the implemented schema; keep examples in this document synchronized. The simulator starts an isolated loopback instance. Public hosting, universal links, actual NFC writing and SwiftUI login are separate integration steps, not already configured features.

## Lifecycle and concurrency
Session status is one of `ARMED`, `SAMPLING`, `COMPLETE`, `CANCELLED`, `EXPIRED`. Creation sets `ARMED` with 60-second server-owned expiry. Device state is `AVAILABLE`, `ARMED` or `SAMPLING`, derived from an active unexpired session. `online` is separately derived from a heartbeat within the last 30 seconds; heartbeat does not extend an arming session. An offline device may be armed; app should show online state and timeout honestly.

One active session per device, enforced transactionally. An owner's repeated arm returns the existing session (`200`) without refreshing expiry; competing owner receives `409 device_busy`. A new session returns `201`. Expiry wins at the boundary `now >= expires_at`; state checks persist expiry lazily on reads/writes, with no scheduler required. Sampling does not extend expiry. Upload is allowed from ARMED or SAMPLING. A completed sample consumes the session. Cancellation is idempotent if already CANCELLED; completed session is not cancellable. Terminal sessions never become active again.

Poll `GET /v1/sessions/{id}` once per second while active. Stop at a terminal state; apply backoff for temporary failures. No WebSocket/SSE integration is required. User-private resources return 404 for a foreign ID, not the other user's record.

## Examples

### Identify current user
```http
GET /v1/me
Authorization: Bearer <access_token>
```
```json
{"user_id":"auth0|example-subject"}
```

### Resolve NFC/QR
The NFC sticker and QR contain the same future public HTTPS URL, e.g. `https://<api-host>/d/kb-demo-01`. This example host is NOT a configured deployment. GET does not arm, log in, or consume a session. Initial response is JSON; Liam must handle the device path and preserve its ID across login before explicitly calling arm. Universal links/associated domains are not configured yet.
```http
GET /d/kb-demo-01
```
```json
{"device_id":"kb-demo-01"}
```

### Fetch device
```http
GET /v1/devices/kb-demo-01
Authorization: Bearer <access_token>
```
```json
{"id":"kb-demo-01","state":"AVAILABLE","online":false,"last_seen_at":null}
```
No user association or secret appears in public/device availability responses.

### Arm
```http
POST /v1/devices/kb-demo-01/sessions
Authorization: Bearer <access_token>
Content-Type: application/json

{}
```
Response 201 (or 200 for same-owner retry):
```json
{
  "id":"3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b",
  "device_id":"kb-demo-01",
  "user_id":"auth0|example-subject",
  "status":"ARMED",
  "created_at":"2026-10-17T01:00:00Z",
  "expires_at":"2026-10-17T01:01:00Z",
  "completed_at":null,
  "measurement":null
}
```
GET session and cancel return the same schema. `measurement` is a result object on COMPLETE and null otherwise. Expired/cancelled sessions remain readable by their owner. Cancel expired session: 410 session_expired; cancel completed: 409 invalid_state.

### Heartbeat and fetch current device session
```http
POST /v1/device/heartbeat
Authorization: Bearer <device_credential>
Content-Type: application/json

{}
```
```json
{"device_id":"kb-demo-01","online":true,"last_seen_at":"2026-10-17T01:00:01Z"}
```
```http
GET /v1/device/session
Authorization: Bearer <device_credential>
```
```json
{
  "device_id":"kb-demo-01",
  "active_session":{
    "id":"3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b",
    "device_id":"kb-demo-01",
    "status":"ARMED",
    "expires_at":"2026-10-17T01:01:00Z"
  }
}
```
When idle, `active_session` is null. Heartbeat is explicit; ordinary polling does not imply online unless implementation and contract are updated together.

### Sampling
```http
POST /v1/device/sessions/3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b/sampling
Authorization: Bearer <device_credential>
Content-Type: application/json

{}
```
Response 200: the device-safe session object above, with `status: "SAMPLING"`; retry while sampling returns the same state. Wrong-device session is 404; expired is 410; terminal is 409. No user_id is returned to the device.

### Upload measurement
```http
POST /v1/device/measurements
Authorization: Bearer <device_credential>
Content-Type: application/json

{
  "measurement_id":"026af7c9-d605-4291-a1db-5b230e10ef43",
  "session_id":"3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b",
  "raw":{"sensor":"mq3","value":1200,"unit":"adc_counts"},
  "breath_duration_ms":2500,
  "source":"simulator",
  "measured_at":null
}
```
- `measurement_id` and `session_id`: UUIDs. Persist an upload ID and exact payload across retries.
- `raw.sensor`: `mq3`; `raw.value`: integer 0–4095 for the initial 12-bit ADC contract; `raw.unit`: `adc_counts`. Actual hardware ADC configuration must match or require a reported contract revision.
- `breath_duration_ms`: integer 1–60000; firmware is responsible for valid local breath detection/sample timing. This metadata alone does not prove sample validity.
- `source`: required `device` or `simulator`, visible to the app; `measured_at`: optional nullable timezone-aware acquisition time, never silently equated to server receive time. A missing clock should send null.
- Unknown properties (including user_id or client-provided BAC) are rejected; finite/bounded strict numeric validation, no coercion from strings/booleans.

Response 201 first upload, 200 replay of identical validated fields:
```json
{
  "id":"026af7c9-d605-4291-a1db-5b230e10ef43",
  "session_id":"3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b",
  "device_id":"kb-demo-01",
  "raw":{"sensor":"mq3","value":1200,"unit":"adc_counts"},
  "breath_duration_ms":2500,
  "source":"simulator",
  "measured_at":null,
  "received_at":"2026-10-17T01:00:05Z",
  "estimated_bac_percent":null
}
```
Same ID with changed accepted payload: 409 idempotency_conflict. New ID for consumed session: 409 invalid_state. Original identical replay remains valid after the session expires/completes; it must not create a second result. Cross-device replay/session access cannot expose or claim another device's result. SQLite transaction and unique constraints enforce one measurement per session and one globally unique measurement ID.

### Private history
```http
GET /v1/measurements?limit=50&offset=0
Authorization: Bearer <access_token>
```
```json
{"items":[],"limit":50,"offset":0,"has_more":false}
```
Items use the measurement schema above, newest receive time first, then ID as tie-breaker. Default limit 50, maximum 100, nonnegative offset. has_more is computed from actual results, not guessed. No other user's rows are returned.

## Errors
```json
{"error":{"code":"device_busy","message":"Device has an active test session."}}
```
Stable error codes: `unauthorized` (401 missing/invalid/wrong-kind token), `not_found` (404 unknown device/session or foreign private resource), `device_busy` (409 competing active association), `invalid_state` (409 terminal operation), `session_expired` (410), `idempotency_conflict` (409), `validation_error` (422), `auth_unavailable` (503 identity-provider key fetch unavailable). 401 uses WWW-Authenticate: Bearer. Validation responses use the same envelope; messages must not echo credentials or untrusted full payloads. Other infrastructure failures may return a generic 500; never include stack traces or secrets in responses.

## Liam integration checklist
1. Coordinate Auth0 Native application/domain/client ID, API audience, bundle ID and callbacks. Store credentials with the SDK Keychain manager; never embed a device credential.
2. Use the confirmed reachable HTTPS API base URL; loopback on Nicholas's laptop is NOT an iPhone deployment.
3. Parse `/d/{device_id}`, preserve target through login, show confirmation and POST empty JSON to arm.
4. Keep returned session ID; poll at 1 second while active, stop on terminal state, handle 409/410 without silently reassociating.
5. Show raw/simulated/prototype status clearly; handle null BAC and null acquisition time. Do not render ADC counts as a numeric BAC.
6. This initial contract is NON-BREAKING (no earlier API), but changes to it must be reported before implementation or merge. No SwiftUI source was edited.
