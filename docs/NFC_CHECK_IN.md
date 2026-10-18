# NFC-first party check-in — implementation direction

**Status: design proposal, not an implemented/deployed check-in API.** Nicholas clarified that the primary product slice is host NFC linking, then player tap → next measurement → correct authenticated person and party/game. This takes priority over general party/game extras. Published foundation: draft [PR #26](https://github.com/spherohero/kickbac/pull/26), head `31f986e91d530e885b7cf8bc16049cfb21fea110`; main at inspection `dd19b404210517b1b0c8b8f8a1809ba988bb250d`. The existing [party contract candidate](PARTIES.md) does not yet implement authoritative party context at session creation.

## What to write to each sticker

Write one standard **NDEF URI / URL record**, first URI record, identifying the physical unit:

```text
https://api.kickbac.vodka/d/kb-demo-01
```

This example is the existing registered demo unit, not a reusable ID for every breathalyzer. Each other unit needs its own registered device ID and URL. Keep the matching QR and printed ID as fallback. Do not put party IDs, user IDs, phone numbers, access tokens, device credentials, Wi-Fi credentials or a write/arm command in the tag. Do not rewrite it between players or parties. Keep it rewritable during bring-up; read back the exact URL before attaching it and before considering permanent write protection. Tag model/NDEF compatibility and installed-position readability remain physical checks; do not assume a sticker against metal will read reliably.

The sticker is passive identification. It has no electrical connection to the ESP32 and does not notify the board itself. HTTPS GET resolution remains read-only and returns the unchanged `{"device_id":"kb-demo-01"}` JSON. A URL fetch, preview, notification or cached launch must never arm, join or bind anything.

## Three separate user intentions

1. **Host setup:** create party → select “Link breathalyzer” → scan device URL → authenticated, explicit host confirmation → server validates assignment permission and atomically binds current device. Existing proposal: `PUT /v1/parties/{party_id}/device` with `{"device_id":"kb-demo-01"}`. Public device IDs are not ownership proof; keep backend operator approval for the demo units, not a secret on the tag. Busy/conflicting units cannot be stolen.
2. **Membership:** a player may join the currently assigned party using the device locator (or host code). Existing proposal: `POST /v1/parties/join` with `{"device_id":"kb-demo-01"}`. Joining never arms.
3. **Player check-in:** signed-in player deliberately chooses “Start my test” (or enters that scan mode), scans the same URL, and confirms the intended party/game/device. Server creates exactly one exclusive next-test session for the token subject, with party/game association snapshotted in the same transaction. The phone can show whose turn it is and a countdown; the board can acknowledge readiness without receiving a user identity.

A plain background scan does not select one of these intentions securely. Preserve target through login, then require the intended authenticated action. A tag is clonable/public identification, not proof of physical presence or proof of who supplies the sample.

## === LIAM / iOS IMPACT ===

**Proposed additive / NON-BREAKING to existing routes and payloads.** Native NFC/link handling and party check-in consumers are new client work owned by Liam. Keep his existing auth/profile/history/device consumers intact. The parent notified Nicholas before writing this proposal; no app source is edited here.

### Proposed check-in operation (not adopted or live)

Candidate route:

```http
POST /v1/parties/{party_id}/check-ins
Authorization: Bearer <API_ACCESS_TOKEN>
Content-Type: application/json

{"check_in_id":"11111111-1111-4111-8111-111111111111","device_id":"kb-demo-01","game_instance_id":"22222222-2222-4222-8222-222222222222"}
```

For a party-only check, `game_instance_id` can be null. No client-supplied owner, BAC, award or timestamp. Persist `check_in_id` and exact payload once per deliberate attempt; accepted retry returns the same session even after it completes/expires, never starts the next person's test.

Candidate response wrapper: `{check_in_id,party_id,game_instance_id,session}`; `session` retains the existing session shape and can continue to be polled through the existing owner-only session route. New acceptance 201 / identical retry 200. Foreign IDs/nonmembership 404, changed accepted payload 409 `idempotency_conflict`, concurrent occupied device 409 `device_busy`, invalid party/game lifecycle 409 `invalid_state`; full limits/OpenAPI/examples must be frozen and tested before code. Do not implement against this candidate path until the shared contract is finalized.

In one serialized SQL transaction, check retry ownership/payload first, validate OPEN party/current device assignment/optional OPEN game membership and snapshotted device, enforce unchanged device exclusivity and expiry, and create the session plus immutable check-in context. Never silently attach an already-existing ordinary session to a party/game. A new deliberate attempt after expiry uses a new UUID; an automatic retry must retain the old one. Close, rebind, leave and upload races need an explicit tested policy that preserves an accepted session's original owner/context without transferring its next reading.

The eventual device upload references only its server-issued session ID. The backend derives user plus party/game through the saved context, preserving one existing measurement row in private history. Game result/points remain separate; taking a check never awards points. Publishing a BAC to other party members is NOT included: readings stay private unless a separate explicit sharing policy is approved.

### Native launch prerequisite

The current published `ios/BACKEND_REVIEW_HANDOFF.md` says Personal Team provisioning cannot enable NFC Tag Reading. Current client supports QR/manual trusted `/d/{id}` selection, not native NFC or background Universal Links.

- Foreground scan: Liam implements the entitled Core NFC NDEF reader and routes only the official URL/device ID.
- Background scan: NDEF HTTPS URL → iOS notification → user opens notification/unlocks → valid Universal Link delivers URL to app. This is not silent app execution.
- Universal Links require the appropriate signed Associated Domains entitlement and a matching HTTPS `/.well-known/apple-app-site-association` file, without redirects. Backend needs the exact signed application identifier from Liam, not an assumed prefix. No new account purchase or membership spend is authorized here.
- Current `/d/{id}` returns JSON in Safari; it is not already a browser onboarding/arming flow. A browser fallback would be a separately designed authenticated user flow, not a GET mutation or implicit reuse of native Keychain credentials. Do not claim native tap acceptance from writing a URL.

Apple references inspected: [background tag reading](https://developer.apple.com/documentation/corenfc/adding-support-for-background-tag-reading), [associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains). Actual entitlement/provisioning and iPhone acceptance remain Liam-owned.

## ESP32 communication — reuse HTTPS, not NFC or per-sample cloud traffic

Proposed flow reuses existing device endpoints and private bearer:

1. Heartbeat `POST /v1/device/heartbeat` with `{}` independently of test ownership.
2. Poll `GET /v1/device/session` for the server-issued session ID and expiry. No user or party identity is needed by firmware.
3. Acknowledge actual acquisition start through existing sampling operation only under coordinated truthful acquisition semantics.
4. Sample MQ-3 locally at a measured/validated rate; do not POST each ADC conversion. Final raw summary selection/window must come from firmware experiments, not a convenient constant.
5. Immediately upload one bounded completed measurement using `POST /v1/device/measurements`, with persisted measurement UUID and unchanged payload on every retry. Do not silently move a failed upload to a newer session. 201 is first acceptance; 200 identical replay; stop/reconcile terminal 409/410 and reject authentication failures.
6. Phone polls its existing session, then reads the saved measurement/private history. Never display a result before server acceptance.

Current source/evidence documents a diagnostic poll interval of 2 seconds and heartbeat interval of 10 seconds, plus HTTP/TLS request time; sampling/uploads remain disabled. A **proposed** active-party poll interval of about 500 ms can reduce control lag, subject to firmware-owner review, bounded retries, server load and measured TLS/Wi-Fi latency. Reuse connections where the actual transport safely supports it; do not block ADC acquisition on network I/O. Existing phone polling is about once/second. No hard realtime or end-to-end latency claim is made; sensor response/recovery is distinct from network delay. Start with REST polling; add SSE/WebSocket/MQTT only if actual measurements establish a need.

## Physical truthfulness gate

Raw MQ-3 ADC is not calibrated BAC. Save raw value/unit/source and preserve `estimated_bac_percent:null` as unavailable. Do not attach a fabricated numerical BAC or safe-driving verdict to a party player.

Pressure sensing is unavailable and the current duration proposal is still unapproved. Existing upload requires integer `breath_duration_ms`; a manual sensor window is not measured breath duration. Firmware must not enable production uploads by filling that field with a constant. A coordinated acquisition/duration revision would require both `=== BACKEND CONTRACT CHANGE ===` and `=== LIAM / iOS IMPACT ===`, legacy retry/decoder tests, simulator parity and separate deployment. This direction changes no firmware wire field.

## Acceptance priority

1. Read sticker URI on actual phones; prove genuine native routing or explicitly use QR/manual fallback.
2. Host binds authorized correct unit by scan; no GET mutation or device theft.
3. Two authenticated players contest same unit; exactly one receives an active session; retries do not extend/reassign.
4. The winning player's explicit party/game check-in creates immutable context; ESP32 consumes only that session.
5. Real HTTP fixture upload completes once, links to that person's original party/game, remains in ordinary private history and survives restart. Test rebind/close/leave/expiry races.
6. Exact duplicate upload/check-in never creates another reading or points. Cross-user access fails. Null/simulated values remain honest.
7. Then prove the same on actual signed iPhone + safe physical ESP32/MQ-3, clearly distinguished from fixture CI. Generic party/game extras do not supersede this slice.
