# Explicit ESP32 mock upload demo

Firmware owner branch `firmware/explicit-mock-uploader`, base `8f60967`. Publishing
PR/head records exact source/review/CI/flash state. This implements only a deliberate
mock sample on the real ESP32 HTTPS transport. ADC remains OFF.

## Run after the uploader image is flashed and privately provisioned

1. Sticker first NDEF URI: `https://api.kickbac.vodka/d/kb-demo-01`. Public locator
   only. GET does not arm. Native NFC/Universal Link routing is Liam-owned and not
   established by the JSON resolver opening in Safari; QR/manual is a valid fallback.
2. Actual signed-in app user deliberately arms the registered device through
   existing POST `/v1/devices/kb-demo-01/sessions` `{}`. No operator-selected owner,
   fake Auth0 user, automatic arm, or firmware-selected party/profile.
3. While that60second lease is active and COM3 is exclusively available, repo root:

```bash
uv tool run --python 3.11 --with pip --from platformio==6.1.19 python firmware/tools/send_mock.py --port COM3
```

The helper checks actual USB identity, opens without an explicit reset/control-line
pulse, discards stale input, and waits up to20seconds for fresh `MOCK_READY` carrying
session UUID. It writes exactly ONE `MOCK <that UUID>\n` line, then waits up to90s
for post-send `MOCK_PENDING` and matching `MOCK_ACCEPTED http=200|201` UUIDs. No
credentials/API/provisioning/arming/resending in this helper. It stores only
allowlisted serial stages in ignored `firmware/build/mock-operator.log`.

Firmware requires that exact current ARMED session, freshly polls to confirm SAME
UUID/expiry/ticket, generates UUIDv4 using ESP-IDF random bytes, freezes the entire
payload once and sends existing authenticated POST `/v1/device/measurements`:

- `measurement_id`: fresh UUID; `session_id`: exact server-created UUID.
- `raw`: `mq3`, value1200, `adc_counts` — SYNTHETIC fixture.
- `breath_duration_ms`:2500 — SYNTHETIC fixture, NOT measured breath/window.
- `source:"simulator"`, `measured_at:null`. BAC remains null.

Arming/timeout alone never uploads. First send aborts on expired/lost/changed ticket;
backend expiry/cancel validation also fences races during HTTP. After an attempted
unknown outcome, ONLY the frozen original IDs/bytes may be replayed, including
when original session is now terminal or a different one is polled. Existing
server idempotency resolves200replay/201first/409conflict/410expiry. No retargeting.

Transport/500/502/503/504 errors get at most3 retries with2/4/8second waits while
heartbeat/poll continue. Each upload fault clears acquisition tickets. Full ACK
must match all nine response fields including original IDs/device/source/raw/
synthetic duration/null acquisition time/null BAC/valid received UTC. Wrong or
malformed ACK/permanent error/exhaustion holds original RAM transaction, blocks new
mock commands, and never claims acceptance.401/403 additionally clear bearer and
stop. Reset loses pending RAM state: DO NOT reset/reflash on an unresolved outcome;
retain identifiers/log and reconcile backend acceptance first. No power-loss
persistence or held-transaction recovery UI is implemented.

## Verification level

Full host suite (mock core/actual adapter plus15USB helper tests), pinned Ruff and
all three XIAO builds pass. Independent focused review approved mock-only flash.
An isolated signed-fixture real-loopback HTTP test passed201→identical200 through
the actual C++ ACK decoder, single private history and restart. Those are NOT
production acceptance. Physical mock acceptance still needs actual user arm,
explicit command, real ESP32 accepted handle and independent server readback.

## === BACKEND CONTRACT CHANGE ===

NON-BREAKING; existing endpoints/fields/auth/units/states/examples unchanged.
Uses the existing legacy simulator request; no new metadata/duration meaning.
Backend parent verifies persisted same-session/user linkage after actual ACK.

## === LIAM / iOS IMPACT ===

NON-BREAKING; no app edit/action newly required. Use existing authenticated arm/
owned session/history and existing simulator/null-BAC interpretation. Liam keeps
ALL iOS/NFC/presentation ownership. Neither this mock nor its duration validates
breath, measures alcohol or supplies BAC. No sensor safety gate is bypassed.
