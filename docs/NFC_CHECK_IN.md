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

### Frozen check-in contract — approved for test-first implementation, not live

The independent design review approved this approach after the policies below
were made explicit. Nicholas confirmed tap-before-measurement arming. This is an
additive backend operation, not approval of new acquisition semantics, native
entitlements, physical execution or production deployment.

```http
POST /v1/parties/{party_id}/check-ins
Authorization: Bearer <API_ACCESS_TOKEN>
Content-Type: application/json

{"check_in_id":"11111111-1111-4111-8111-111111111111","device_id":"kb-demo-01","game_instance_id":"22222222-2222-4222-8222-222222222222"}
```

Require UUID `check_in_id` and strict registered-device slug `device_id`; optional
UUID `game_instance_id` defaults to null. Null explicitly means party-only, never
“whichever game is current.” Reject unknown fields; streamed POST maximum32768
bytes, including absent/false Content-Length. All new success/errors are no-store.
No client-supplied owner, BAC, award or timestamps. Persist UUID/exact payload
before sending, account-scoped across retries/relaunch.

Response is `{check_in_id,party_id,game_instance_id,session}`. Its `session` is the
unchanged existing `SessionResponse`; poll `GET /v1/sessions/{session_id}` for live
status and accepted result.201 first acceptance /200 exact accepted retry. The
session ID/context/expiry never change; status/measurement reflect its current
server state, not an immutable first-response snapshot.

Use one `BEGIN IMMEDIATE` transaction shared with legacy arming/upload/lifecycle
serialization. Capture server time after acquiring the lock; expire sessions at
`expires_at <= now`. Retry lookup comes before membership/current-state checks.
For new IDs require active token-subject membership, OPEN party, registered device
and exact current binding. Optional game must belong to that party, be OPEN and
have a non-null device snapshot equal to this device. Reject ANY active session,
even the same owner's ordinary session/check-in, with409 `device_busy`; never
attach, relabel, return as newly accepted, or extend it. Insert one fresh
server-generated60-second ARMED session and immutable check-in context atomically.
Expected domain rejections may preserve lazy expiry but must precede business
inserts; unexpected failure rolls back both inserts.

Retries: original owner+route party+normalized payload returns original attempt
through COMPLETE/CANCELLED/EXPIRED, leaving, game/party close or later reassignment.
Foreign accepted ID is404. Same-owner changed accepted content is409
`idempotency_conflict`; under another party path return404 unless the subject has
at least historical membership there, before returning a conflict. Never move
context. Rejected attempts do not consume a retry ID. No new ID after ambiguous
transport failure. A genuinely new deliberate attempt after expiry needs a new ID.
Unknown/nonmember/unavailable assigned device is404; non-OPEN lifecycle or
incompatible game/device snapshot is409 `invalid_state`; malformed input422;
body overflow413. Legacy session/auth errors otherwise unchanged.

Add **`GET /v1/me/check-ins?limit=50&offset=0`**, default50/limit1..100,
offset>=0 (overflow-safe). Same `{items,limit,offset,has_more}` envelope; items are
check-in wrappers above, ordered by session `created_at DESC,check_in_id DESC`.
Read only token-owned rows regardless of present membership/lifecycle, with
current session/optional accepted measurement. Use one read-only SQL snapshot;
never lazily expire or mutate from this GET. No other-player readings or roster.

Migration **006**, schema6: add `party_check_ins` with primary check-in UUID,
unique session FK, party FK, nullable game-instance FK, token-derived owner,
device FK and owner/history index. Preserve migration005 and populated schema5
rows; test schema4→5→6, populated5→6, repeated initialization, failed-upgrade
rollback and full populated online backup/restore/startup.

Lifecycle policy:
- Party close/device unbind or rebind retain active-device409 fences.
- Member leave/game close remain allowed; accepted session/context remain valid.
- Upload after leave/game close uses existing session ownership/expiry only.
- New game result after leave/game close remains rejected; check-in does not
  reserve a later completion write or reopen gameplay. Private reading/context
  persists even without an accepted completion.
- Legacy arm may return the owner's existing party-check-in session without
  adding context. Legacy nonmember arming remains unchanged; assignment is not
  an exclusive arming permission.

For a new party result with a measurement, resolve its session's check-in. If
present, require EXACT party and game-instance equality with the result target;
party-only cannot be promoted to game-specific context. Mismatch422
`validation_error`. Ordinary non-check-in measurements keep existing eligibility
rules. Accepted result retries precede these checks. No duplicate measurement or
points; taking a test never awards game participation points. Legacy arbitrary
`data` is not authoritative. Readings remain private unless a separately approved
sharing policy is implemented; this does not expose BAC to other party members.

The device upload still references only its server-issued session ID. Backend
SQL derives owner and immutable party/game context without firmware knowing either.


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

**Decision checkpoint:** the manual-timed/null-breath-duration contract remains
unapproved. Preserve existing measurement semantics and unavailable BAC. Continue
NFC/session/context software work; physical upload completion remains gated by
truthful acquisition metadata and electrical commissioning. A numeric visual
demonstration must remain explicitly simulated.

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
