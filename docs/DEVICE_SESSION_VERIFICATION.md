# Session-guard device execution — actual USB/Wi-Fi/device evidence

## Result and limits

**Physical flash/hash verification and authenticated diagnostic execution passed.**
The exact registered `kb-demo-01` persisted heartbeat advanced after the PC USB
helper exited. This is NOT protected ADC, a breath sample, measurement upload,
actual-user arming/attribution, calibrated BAC or native acceptance.

Nicholas, through backend Bot, explicitly authorized exclusive COM3 open/reset/
flash and existing private RAM-only provisioning. He reports completed correct
assembly but declines additional electrical checks/photos. Record that as an
OWNER REPORT, not measured sign-off. ADC remains disabled; no electrical gate was
waived and the same checklist is not repeatedly requested.

## Exact target/source/image

- USB was freshly matched before uploads: COM3, VID:PID `303A:1001`, serial
  `80:B5:4E:F1:B7:30`. Actual esptool identified ESP32-S3 QFN56 rev0.2,
  embedded8MB PSRAM,40MHz crystal, native USB-Serial/JTAG and matching MAC.
- First flashed source: main `3fd50c7f2520982696a4f2e4ac095a06e34d1887`, firmware
  equal to reviewed PR28 head `11b5e38`. App SHA256:
  `47a61ca5e3794b1156d21ee1ff568ec91aa0c57ae49bc922c447fd14b520f8fa`.
- Current flashed source: `17ed04ba393f8d5e6124c65d0eb07d926db85d43`, published
  `firmware/session-guard-device-verification`, base `3fd50c7`. Exact head/PR and
  later documentation commits are authoritative for publication/merge state.
- Target `xiao_device`; application SHA256:
  `ffb51345bc8c40606c6436d23b2ebe54944da2156c1d04f563d898f922aba012`.
  Actual application file852560bytes; esptool verified all four programmed image
  hashes. Package pins remain those in `firmware/platformio.ini` (Espressif32
  7.1.3, framework4.20017.260907+sha.dcc1105b, uploader2.41100.260830,
  ArduinoJson6.21.6).
- The application file SHA256 above identifies the local flashed artifact;
  uploader hash verification is separate evidence. No readable build-ID line is
  claimed. Later evidence/docs edits do not change the flashed runtime source.
- Sensor/ADC/BLE/sampling/uploads stay OFF. Credentials remain RAM-only; reset
  requires private re-entry. No Wi-Fi/device credential appeared in chat/logs/
  screenshots/source/arguments or a local secret file. USB provisioning is not
  encrypted. Existing operator access/credential was reused, not rotated.

## Failures preserved, not converted to success

Two physical runs of the first image passed association/DHCP, DNS, SNTP, first
trusted health200, deliberate software disconnect/rejoin and DNS, then failed
second HTTPS with HTTPClient `-1`. Neither reached device authentication.
Sanitized local evidence:

- `firmware/build/session-guard-connectivity-attempt1.log`
- `firmware/build/session-guard-connectivity-attempt2.log`
- `firmware/build/session-guard-upload.log`

The reviewed follow-up adds numeric-only TLS code/elapsed output for future
failures and at most three reconnect public-health attempts (labels2..4), waiting
1second between failures. Each repeats the same certificate/hostname/date,
redirect and exact bounded-body checks; exhaustion still fails. No insecure TLS,
authenticated request retries, heartbeat/poll cadence or API contract changes.

A first short-helper run of the follow-up reached DEVICE_PASS with3heartbeats /
5idle polls, but a later read-only DB check at `2026-10-18T07:44:02.535935+00:00`
found last_seen `07:43:12.772350+00:00`, age49.763585s. It therefore FAILED ongoing
freshness; no device failure line was captured and the cause is unknown. A later
35s listen received no allowlisted lines. Do not claim continuous connectivity
from that short run or infer reset, brownout, TLS cause or hardware correctness.

## Subsequent actual continuous run

After an authorized esptool reset (no new image), the existing private entry/
relay logic was used with continuous sanitized serial observation. Actual:

- Joined/DHCP, RSSI-32dBm/channel6; DNS and actual SNTP passed.
- Trusted health attempt1 returned200/expected body.
- Controlled disconnect observed, rejoined/DHCP RSSI-47dBm/channel6; DNS passed.
- Trusted reconnect health attempt2 returned200/expected body.
- Missing-device-bearer poll rejected401; existing private bearer then accepted.
-9heartbeat200 and24idle poll200 observed. Heartbeat1
  `2026-10-18T07:46:38.943778+00:00`; heartbeat9
  `2026-10-18T07:48:39.959463+00:00`.
- DEVICE_PASS marker at3heartbeats/6polls; capture continued90seconds after that
  marker. No sampling/action was taken even if a future poll could report ARMED.
- Helper closed serial. No further monitor was left owning COM3.

Local evidence: `firmware/build/session-guard-continuous-serial.log`,
`session-guard-connectivity-pass.log` (earlier short pass) and
`session-guard-reconnect-upload.log`.

Successful follow-up runs used the FIRST reconnect attempt. Thus the bounded
extra retries have host-fixture coverage, not a physically exercised recovery
claim. The intermittent failure's root cause is not established; a soak/AP outage/
power-cycle reliability test has not passed by implication.

## Independent server readback AFTER helper exit

Using existing host-key-verified operator access, SQLite opened `mode=ro` with
`query_only=ON`. Only this device's heartbeat and aggregate counts were returned;
no user/session IDs, private raw readings or credential values were read.

| Check UTC | Exact device last_seen UTC | Age seconds |
| --- | --- | --- |
|2026-10-18T07:48:47.513977+00:00|2026-10-18T07:48:39.959463+00:00|7.554514|
|2026-10-18T07:49:07.999963+00:00|2026-10-18T07:48:55.134353+00:00|12.865610|

The timestamp advanced after helper exit and stayed within the existing30second
online window. The PC helper was not maintaining heartbeat for the ESP32.
Both snapshots: schema4, device session count1, measurement count0. This work did
not arm any session; the pre-existing session's owner/context/status were not
inspected or inferred. No synthetic production identity or measurement inserted.
Evidence: `firmware/build/session-guard-server-ongoing.json` (ignored local file).
This is a bounded observation, not a permanent-current-online assertion.

## Source and host verification

- Test-first policy/allowlist checks failed before implementation, then passed.
- Full `bash firmware/test_host.sh`, pinned helper Ruff lint/format and all three
  cross-builds passed. Independent read-only review approved scoped no-ADC flash
  and separately ran all five helper tests.
- Source session-fence/immutable-byte coverage and PR28 main CI are documented in
  [FIRMWARE_SESSION_GUARD.md](FIRMWARE_SESSION_GUARD.md). Physical run here remained
  IDLE; real authenticated arming→acquisition fencing is not physically accepted.

## === BACKEND CONTRACT CHANGE ===

**NON-BREAKING; unchanged API.** Public health diagnostic retries only; existing
nominal10s heartbeat /2s poll after completion and fail-closed device auth/schema
behavior remain. Existing endpoint/schema/payload examples in [API.md](API.md)
remain unchanged. No device-selected user/party/game. Backend manual-timed support
is separate coordinated work; no proposed payload is sent before exact deployed
contract/acceptance. Actual sensing still lacks independent electrical acceptance.

## === LIAM / iOS IMPACT ===

**NON-BREAKING; no app action for this follow-up.** New evidence is actual device
networking, not NFC routing, native acceptance or real profile attribution.
Separate nullable duration/manual notice remains coordinated BREAKING client work.
No SwiftUI/Figma edits and no fabricated duration/BAC/no-trigger zero.

## Remaining gate

The reviewed no-ADC network/session diagnostic is physically running and its
bounded after-helper persistence is verified. ADC enablement remains blocked by
unverified protection/power, not by a request to redo completed setup. True manual
acquisition needs actual protected traces, measured timing/gaps/raw-summary choice,
exact session fencing and a verified deployed truthful contract before any upload.
