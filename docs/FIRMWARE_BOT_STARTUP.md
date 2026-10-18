# kickBAC firmware bot — current startup handoff

## Automatic authenticated restart — new explicit owner authorization

`firmware/persistent-device-auth`, base `aa90d4c`; exact publishing PR/head gives
state. [AUTONOMOUS_BOOT.md](../firmware/AUTONOMOUS_BOOT.md) defines once-only
private `--device-only --save-device-auth` default-No consent, identity-bound NVS
record/readback and autonomous saved-Wi-Fi→trusted TLS→device heartbeat/poll.
Bearer saving is NOW explicitly authorized; older RAM-only limit below describes
the preceding image. NVS encryption NOT verified; no eFuse/security-state changes.
Corrupt/blocked credentials fail closed; auth/schema faults stop and persist a
block when storage works. No boot arm/upload/ADC/app change. Pending samples stay
RAM-only: reconcile before reset. Full host/41Python/Ruff/all3builds and focused
independent review pass. Physical unplug/replug is not established by those tests;
read exact actual flash/boot/server evidence before declaring it passed.

## One saved Wi-Fi / lifetime recovery — focused firmware change

Physical update: [PR41](https://github.com/spherohero/kickbac/pull/41) runtime
`9b0ca25` flashed/hashverified; explicit private save confirmed stored/saved1.
Software reset restored Wi-Fi with NO Wi-Fi frame; bearer-only bootstrap passed.
Operator hotspot-loss/return test observed attempts/backoff/trusted rejoin and
authenticated heartbeat resume without reset/re-entry. Post-listener server
heartbeat advanced10:38:32.407638→10:38:45.315899UTC inside30s; accepted demo remains
exactly1/COMPLETE. See actual evidence/limits in the guide below. Serial released;
no physical power-bank/cable cold-cycle or bearer persistence claim.

`firmware/saved-wifi-recovery`, base `22c1215`; see
[SAVED_WIFI.md](../firmware/SAVED_WIFI.md) for private unchecked opt-in, exact
commands, single NVS key and tested1..60s jitter/30s association/lifetime retry.
Network loss invalidates tickets and holds unresolved payloads without auto-upload;
auth/schema failures remain separate. Cold boot restores Wi-Fi ONLY: bearer stays
RAM-only, with explicit `--device-only` private bootstrap after trusted readiness.
No NVS encryption claim, eFuse/security change, app or measurement-wire change.
Host/Ruff/all3builds pass; corrected independent-review findings were regression-
tested, not silently declared a second independent approval. Actual physical
save/reboot/outage and exact source/PR state must be checked before claiming them.
Preserve accepted mock measurement `ade105cf-2dd3-4f4e-8e38-3bf7ac982154` and
session `21dbab79-4db0-4c8c-9c1e-7ab9525ba15f`; no new arm/upload for this task.

## Explicit mock uploader — current source, physical acceptance still gated

Branch `firmware/explicit-mock-uploader`, base `8f60967`. Read
[the exact operator command and limits](../firmware/MOCK_DEMO.md). New `xiao_device`
supports one deliberate USB command bound to exact live app-armed UUID, fresh
server confirmation, frozen UUID/payload and verified200/201 ACK. Raw1200/duration
2500 are SYNTHETIC with `source:simulator`, unknown acquisition UTC null, BAC null.
No ADC/sampling/app edits, no upload merely from arming. Full host/Ruff/all3builds,
isolated real-HTTP201/replay200/actual ACK/history/restart and focused independent
review pass. Publishing PR/head gives readiness/flash state; do not presume a
production measurement until actual user arm/USB/ACK/persisted readback.

## Operational communication restored — current evidence supersedes offline below

Flashed reviewed `firmware/operational-connectivity@49e8d5a4dfc41b193fffdc2cfa9f857d98e900aa`
(`xiao_device`, target identity reverified); image SHA256
`1bbb8e0861e8228db305283efd278e002ae5d23ee3241e8603a421cec03b5d8d`.
Normal boot skips intentional Wi-Fi disconnect, while `xiao_wifi` keeps that
separate fault test. Bounded transport/5xx retries invalidate tickets immediately;
auth/schema corruption/exhaustion still fail closed. No ADC/upload/app changes.
Actual serial observed heartbeat12..28 and idle poll31..73; startup marker was
missed, not fabricated. After helper exit, exact persisted `kb-demo-01` heartbeat
advanced08:50:19.816042→08:50:35.474722UTC with ages0.749303/5.572119s on schema6.
Serial released, no reset loop. `firmware/build/operational-network-serial.log`
and `operational-network-server-ongoing.json` retain sanitized local evidence.
Host/Ruff/all3builds and focused independent review passed. PR/remote head gives
publication state; this is bounded current-online evidence, not long-term soak.
Forced-reconnect-1 root cause remains unresolved; do not mistake skipping a test
for fixing it. Read source `network_runtime.hpp` for exact recovery limits.

## Latest physical checkpoint — no-ADC image flashed, real device auth passed

**Latest state supersedes the earlier pass:** at07:56:14UTC heartbeat was stale
(57.797157s); following authorized reset/reprovision passed initial trusted health
but exhausted all three reconnect attempts with HTTPClient/TLS `-1` around7s each.
Device bearer was not forwarded on that final run. Current board online state is
NOT restored. Source PR31 merged `97b30a17739ed84cec562dfdfe365c28fa8a5c26`, exact
merged-main firmware CI passed. Read the latest-state section in the evidence
below; network root cause unresolved, serial released, ADC remains disabled.
Public OpenAPI now exposes33operations/manual metadata/schema6-era routes; no
manual upload/actual-user acquisition acceptance is inferred from its presence.

Read [DEVICE_SESSION_VERIFICATION.md](DEVICE_SESSION_VERIFICATION.md). Nicholas
authorized exclusive COM3 open/reset/flash/private provisioning. Current flashed
`xiao_device` runtime is `17ed04ba393f8d5e6124c65d0eb07d926db85d43` on
`firmware/session-guard-device-verification`, base `3fd50c7`. Actual target/image
hashes, two preserved reconnect failures, a stale short-helper readback, subsequent
9-heartbeat/24-idle-poll continuous physical pass and independent advancing
persisted heartbeat after helper exit are documented there. No serial owner left.
Extra bounded reconnect retries were not needed in the pass; a later run
physically exhausted all three (no recovery).
Root cause of earlier intermittent failures remains unknown. No reliability claim.

Nicholas declines further electrical measurements/photos; assembly correctness
remains owner-reported, not independently verified. ADC/sampling/uploads stay
disabled; do not bypass safety or repeat the checklist in a loop. Separate manual
duration support/deployment/native/real-user measurement acceptance remain gates.
Earlier “not flashed”/unavailable serial authorization paragraphs below are
historical checkpoints, superseded by this authorized physical execution.

## Latest firmware integration checkpoint — session guard, not flashed

Merged [PR #28](https://github.com/spherohero/kickbac/pull/28) at
`706d5bb27ab2aa00b620375b27b7a93adaf6addf`; reviewed source head `11b5e38`,
exact remote merge/tree verified. Merged-main firmware/backend CI both passed;
links and limits are in the checkpoint below. No physical patch was applied.

Read [FIRMWARE_SESSION_GUARD.md](FIRMWARE_SESSION_GUARD.md). Firmware owner branch
`firmware/session-ownership-guard`, base `86adb12b4c1f669aafb1ee5ee1726f6da87454bb`,
adds exact session UUID/expiry retention, fail-closed acquisition tickets and a
transport-neutral immutable retry-byte slot. Full host suite and all three pinned
cross-builds passed; no ADC/sampling/upload is enabled and no flash occurred.
Fresh USB enumeration matches COM3 / `303A:1001` / `80:B5:4E:F1:B7:30`; private
read-only relay verified the existing `kb-demo-01` credential hash/record without
USB provisioning. Currently running image/online status remain unverified.

Nicholas now reports the completed board plugged in/electrically correct, relayed
by backend Bot. Treat the older placement-only paragraphs below as historical,
not a denial of that owner report. Minimal actual electrical measurements/photos
and exclusive serial access remain unavailable to firmware; clarification was
undelivered in unattended mode. Reuse existing check evidence rather than repeat
completed setup. No manual-timed contract deployment or acceptance is inferred;
coordinate truthful fields/client compatibility before enabling production sends.

## Latest owner decision — USB-C-only demo

Nicholas has removed battery operation from this demo. Read
[USB_ONLY_COMMISSIONING.md](USB_ONLY_COMMISSIONING.md) for the current conditional
single-cable VBUS-to-MQ schematic, keep/remove list, capacitor identification,
power budget and commissioning report. BAT pads stay unconnected; no battery,
boost or external charging/balancing parts are needed. USB source/cable and actual
XIAO VBUS path must be accepted for MCU plus heater load before powering that
assembly. The two reported 10 kOhm resistors remain; reported two 10 uF ceramics
and one 100 nF electrolytic are NOT silently relabelled to match the old BOM.
Markings/ratings, wiring and full-scale divider checks remain unverified. ADC lead
stays physically OPEN. No new ADC, serial, Wi-Fi, upload or native test is claimed.
The older separate-supply and battery paragraphs below are historical alternatives,
not the current positive-rail wiring. No API/iOS change; no client action.

## Scope and precedence

This is the firmware specialist's startup checkpoint, not a backend implementation brief. Nicholas is creating a Hermes Bots group with a backend/webserver bot and a firmware/ESP32 bot. The firmware bot owns MCU code, safe physical integration, sensor experiments and the device-side API client. Server implementation/hosting belongs to the backend bot; SwiftUI/native acceptance belongs to Liam; mechanical/perfboard work belongs to Austin.

Read the applicable `AGENTS.md` chain, this document and linked firmware evidence before taking action. Read `docs/PROJECT_BRIEF.md` for the preserved original brief, but its initial backend-build task is historical. The earlier workspace `.project/FIRMWARE_SESSION_PROMPT.md` and original-checkout `docs/FIRMWARE_HANDOFF.md` explain the phase change; their pre-hardware/public-timeout/no-push checkpoints are not current status. Do not restart them as tasks. Latest human instructions and fresh repository/physical evidence govern.

## First-run checklist

1. Confirm the bot's actual machine, terminal backend and checkout. Local recommended checkout: `C:/Users/nicho/Desktop/SwampHacks26/kickbac-firmware-bot`. A cloud bot cannot directly use this PC's USB port without an explicitly configured bridge.
2. Inspect `git status --short --branch`, worktrees, local/remote branches and fresh fetched main. The original `kickbac/` checkout still has separate dirty work; do not stash/discard/blanket-stage it. Do not take over another bot's branch. Continue new substantive work on a fresh focused feature branch/worktree from inspected main.
3. Read `firmware/README.md`, `docs/DEVICE_CONNECTIVITY.md`, `docs/WIFI_CONNECTIVITY.md`, `docs/HARDWARE_BRINGUP.md`, `docs/AUSTIN_PERFBOARD_GUIDE.md`, `docs/FIRMWARE_DURATION_PROPOSAL.md`, then the device portions of current `docs/API.md` and their actual models/client code. Load available `swamphacks-planning` references, collaboration, TDD and debugging skills as relevant.
4. Identify the actual backend bot from the group roster and agree ownership/contract handoff. Ask it for current public contract/reachability or a secure operator-access arrangement only when needed—not for secrets in chat. No need to relearn its server architecture here.
5. Re-enumerate USB before serial/flash. Coordinate exclusive access; monitor control lines can reset this board. Do not automatically flash or enable ADC as part of orientation.
6. Components are only placed in isolated-pad perfboard in the latest assembly report, not permanently connected. **No boost converter, no pressure sensor, no installed JP1.** Nicholas now selects USB-C-only operation: use the current USB guide above, with battery absent and ADC lead open. Continue software communication verification independently; actual source/path/current and protection sign-off remain gates for powered acquisition.

## Verified controller and module

- Standard Seeed **XIAO ESP32-S3**, not a generic ESP32 or assumed alternate XIAO variant.
- Real esptool probe: ESP32-S3 QFN56 revision0.2, 40MHz crystal, 8MB embedded PSRAM; separate flash probe: 8MB quad flash. PSRAM identification is not a memory stress test.
- Last physical USB identity: native Serial/JTAG, VID:PID `303A:1001`, serial `80:B5:4E:F1:B7:30`, port COM3, serial115200. COM3 is an observation, not a permanent port allocation. Match identity and reject a different attached target before provisioning/flashing.
- Supplied FPC antenna is connected. Real radio reception and association were measured; no BLE or calibrated antenna A/B performance test.
- Actual photo `IMG_2204.jpeg` and purchase ASIN `B0GW8C1V6N` identify a **Flying Fish-style four-pin breakout sold as MQ-3**. The can's exact maker/variant is not established. It is not an unmounted six-leg sensor.
- In the photo with trimmer TOP and header pointing RIGHT, header TOP→BOTTOM is `VCC / GND / DO / AO`. Follow actual printed labels when rotated/flipped. DO stays disconnected; AO is potentially5V and never directly MCU-safe.
- The air-pressure sensor is confirmed unavailable: delivery failed. DHT11 availability/usefulness is unconfirmed; it is not flow sensing. No external sample button/LED is planned initially; use USB serial. The board's BOOT button is a separate recovery control.

## What actually passed

**Published foundation:** [PR #10](https://github.com/spherohero/kickbac/pull/10), merge `016d5b8a4c43d0f8a599f7e75303262de9b09db9`, preserved remote branch `firmware/esp32-core`. Freshly inspect main; this hash is provenance, not a demand to reset to old history.

- Real USB-only flash reported verified image hashes; physical serial emitted one-second uptime lines on two monitor opens. A monitor reopen restarted uptime; no physical cable/power-cycle reliability claim.
- Real2.4GHz scan found46 access points (not necessarily46unique SSIDs). Initial strongest was-63dBm/channel1; SSIDs/BSSIDs were not logged.
- Wi-Fi association/DHCP, backend DNS, actual SNTP and hostname/date-validated HTTPS `GET https://api.kickbac.vodka/health` returned200 and expected health JSON. ISRG Root X1 is a public trust anchor; no insecure TLS override or redirect/captive-portal workaround.
- A controlled software disconnect/rejoin and another trusted health200 passed. This is not an AP-outage, USB power-cycle or long-duration soak test.
- Actual missing-bearer `GET /v1/device/session` returned401. The existing privately relayed device bearer then produced **three heartbeat200 and six idle poll200** for `kb-demo-01`.
- Independent live read-only DB checks after the PC helper exited showed the exact device's heartbeat continuing to advance, within the existing30s online window. Device session and measurement counts stayed0. The PC helper was not acting as a fake device.
- The last verified image is `xiao_device`: networking/device diagnostics enabled; **sensor pins/ADC/BLE/sampling/uploads disabled**. RAM-only network/device provisioning is lost on reset. No current online/attached status is implied by historical success.
- Independent core and full-diff reviews passed after the fractional-baseline headroom defect was reproduced/fixed. Source review did not independently operate the hardware; prior parent-executed physical evidence is separate.
- Current-base backend/deployment tests and mocked Action fixtures passed alongside the existing real-loopback simulator during integration. The backend bot owns the detailed release evidence; these are not native or sensor proof.
- Firmware host/parser/adapter/Python tests and all3cross-builds passed on Windows and GitHub Linux. [Merged-main firmware CI](https://github.com/spherohero/kickbac/actions/runs/39086197068) succeeded at the exact merge SHA; CI does not flash hardware.

Full published evidence is in `docs/DEVICE_CONNECTIVITY.md` and `docs/WIFI_CONNECTIVITY.md`. Detailed ignored logs remain in the older local `kickbac-firmware/firmware/build/`; they are not automatically copied into another worktree or profile. Distinguish unavailable original traces from a new run, and never synthesize replacement evidence.

## What is still NOT established

No verified perfboard assembly, module heater current, checked supply/divider, protected ADC voltage/count trace, conditioning/stable baseline, measured MQ trigger tuning, sober-breath/no-breath discrimination, breath duration, real-user arming-to-hardware-upload, calibrated BAC, BLE or long-term reliability. No-trigger is no result, never a valid zero. Do not claim the full breathalyzer demo is complete.

## Electrical gate before ADC

**Current topology:** USB-C-only by Nicholas's explicit decision; battery operation is dropped. Placement-only assembly, **no boost, pressure sensor or installed JP1** remains the latest construction evidence. [USB-only commissioning](USB_ONLY_COMMISSIONING.md) proposes USB VBUS for the MQ, conditional on verified source/cable/board path and current. It does not authorize an unchecked VBUS load. Never use GPIO/3V3 for the heater. Keep the ADC lead physically disconnected until source/divider sign-off. These physical gates do not block host/backend communication tests.

**Historical group-shared proposal, not the current bill of materials:** `docs/BATTERY_BOOST_COMMISSIONING.md` preserves the earlier LiPo + switched-boost plan and its conditional safety review. It does not establish that a converter is present or authorize that topology. The older USB/external-supply guide below is also conditional; neither is an as-built report.

Use Austin's original versioned guide as the conditional **USB / external-supply** design, not a claim of construction or battery/boost approval:

- Candidate MCU input: XIAO D0/A0 = GPIO1 = ADC1_CH0. It is not enabled yet.
- Candidate divider: AO→10kOhm R1→protected node; 10kOhm R2 node→GND;100nF node→GND; removable normally-open JP1 node→D0. Prefer measured1% parts. Full-scale ceiling/assumed supply calculations in the guide must be rechecked if actual parts/bounds differ.
- XIAO powered by PC USB; separate regulated low-voltage sensor5V; common ground. Never bridge external5V to XIAO VBUS/5V/3V3/BAT, power the heater from GPIO/3V3 or rely on ADC attenuation for protection.
- Keep JP1 OPEN. Test divider at full scale with BOTH boards absent, then remove the temporary AO-to-supply test link. Measure supply/current/AO/protected node and inspect soldering/labels before connecting D0. A low idle AO voltage alone proves nothing about worst-case protection.
- Rewire only unpowered. For the separate-supply design: USB-first/module-second startup; module-first/USB-second shutdown. Close JP1 only with both off. No hardware interlock protects accidental USB loss; do not drive an unpowered ESP32 input.
- No drinking, alcohol spraying/pouring or flammable-gas testing. Keep hot sensor, liquids/condensation and unhygienic mouth-contact paths separate.

## Signal-trigger experiment, not a breath detector

`firmware/include/signal_trigger.hpp` is a board-independent, allocation-free core with configurable onset/release deltas, sustain, recovery, cooldown, maximum telemetry gap and EWMA alpha. Explicit operator-accepted baseline; median-of-three plus EWMA; sustained crossing; hysteresis; residual lockout; frozen baseline; fail-closed invalid config/rails/gaps/timestamp faults; uint32 timer wrap support. No hardware tuning defaults: fixture constants are synthetic. Local states are not new API enums.

Collect real labeled warm-up/idle/noise/drift/recovery traces after electrical sign-off before choosing settings. Record operator observation separately from trigger output. Higher onset trades noise rejection for missed weak/sober events; it cannot prove breath presence. DHT11's slow physical response and condensation/heater sensitivity must be measured if considered. A rebaseline is not calibration or proof of clean air.

## Minimal backend-bot interface, unchanged

The firmware consumes, rather than owns, the current contract:

- Device bearer identity is provisioned separately from human login; no user ID selected by firmware.
- `POST /v1/device/heartbeat` body `{}`; refresh online independently from polling.
- `GET /v1/device/session`; `active_session:null` means idle. Current diagnostics log ARMED/SAMPLING if observed but take no sampling action.
- Server owns short-lived/exclusive sessions and terminal/expiry semantics. Never extend or reassign them locally.
- Before any future measurement upload: actual raw `adc_counts`, `source:device`, stable UUID and identical payload across retries; missing real acquisition UTC stays null. Current required `breath_duration_ms` cannot come from this MQ heuristic, time-above-threshold, an arbitrary constant or a manual sample window.

`docs/FIRMWARE_DURATION_PROPOSAL.md` is **UNAPPROVED / NOT IMPLEMENTED**. Manual timed acquisition is only a possible honest fallback. Before affecting schema/meaning/units/states/UX use both `=== BACKEND CONTRACT CHANGE ===` and `=== LIAM / iOS IMPACT ===`; state old/new payloads, why, exact affected endpoints, required client action and BREAKING/NON-BREAKING. Coordinate with the backend bot and Liam and obtain Nicholas's explicit contract decision. GitHub control is not automatic contract approval.

## Toolchain and safe commands

From the actual repo root, using Git Bash on this Windows host (native programs need `C:/...` paths):

```bash
# Read-only port discovery; no flash or provisioning:
uv tool run --python 3.11 --with pip --from platformio==6.1.19 platformio device list --json-output
# Fresh worktree: install pinned framework/tool/JSON headers before host tests:
uv tool run --python 3.11 --with pip --from platformio==6.1.19 platformio pkg install -d firmware -e xiao_device
bash firmware/test_host.sh
uv tool run --python 3.11 --with pip --from platformio==6.1.19 platformio run -d firmware -e xiao_usb -e xiao_wifi -e xiao_device
```

PlatformIO Core6.1.19, espressif32 platform7.1.3, framework `4.20017.260907+sha.dcc1105b`, uploader `2.41100.260830`, ArduinoJson6.21.6 are pinned/verified. Keep `--with pip` because the uploader installer needs it. `xiao_usb`, `xiao_wifi`, `xiao_device` have source filters selecting the appropriate application. Do not run upload commands without identified target/current wiring and an actual authorized flash task.

Private helpers are `firmware/tools/provision_wifi.py` and `provision_device.py`; inspect before reuse. They use local masked entry/RAM and the existing secure operator relay, not chat passwords, saved OS profile extraction or new public auth. USB provisioning itself is unencrypted. Never display/commit secrets, response bodies or credential frames. Current device diagnostic clears its bearer and stops on error; reset/reprovision is required. Heartbeat/poll intervals are nominal after completion, not hard-real-time guarantees; production backoff/reconnect remains separate.

Adapter-fault follow-up: `test/device-adapter-faults` (base `e8368eb`) expands host fixtures for both heartbeat and polling: unknown/zero/oversized lengths, partial/zero reads, malformed JSON, wrong identity, begin/transport/HTTP errors, exact768-byte boundary, embedded NUL, Wi-Fi loss and the negative-auth gate. Local host suite, helper lint/format and all three cross-builds pass; scratch-only negative controls detect seven deliberate regressions. See `docs/DEVICE_CONNECTIVITY.md`. Production firmware/API are unchanged; these synthetic results are not physical fault injection, new serial/network execution or acquisition/upload acceptance. PR #16 merged at `64b706c724cf699e690847d6362b515a1524b7e5` after independent assistant review and exact-head PR CI run `39090730535` passed; merge tree equals the reviewed tree. Merged-main firmware CI run `39091023006` also passed at that exact merge SHA; CI still does not establish physical sensor or native acceptance.

## Group and Git discipline

Give the backend bot a short evidence-bearing handoff: device/firmware commit, observed status, intended request and one concrete question. Ask for exact published contract/commit/examples when needed. Use actual roster handles; no fake sends/acks, secret exchange or endless acknowledgment loops. Announce serial ownership before hardware work, then release it.

Nicholas authorizes focused commits, regular remote pushes and autonomous ready merges. Inspect current live base, preserve dirty peer work, review/test the combined tree and read back exact remote heads/merge/CI. No direct development on main, force-push, shared-history rewrite, branch deletion, protection bypass or unrelated blanket staging. Figma stays read-only; Liam's app stays his. No extra paid resources.

## Next owned sequence

1. Continue real-loopback backend HTTP / current C++ decoder verification and firmware adapter host regression tests now, independent of unsoldered hardware. Preserve simulator labels and distinguish parser/host evidence from ESP32 networking/native acceptance.
2. For physical work only: identify the actual revised MQ supply/protection, inspect the eventual unpowered wiring and accept measurements with the ADC lead physically disconnected. Do not request completed solder/measurement evidence as a prerequisite for software-only communication work.
3. After electrical sign-off, build a separately selected protected serial-only ADC diagnostic, test/flash only the identified board, and collect actual warm-up/idle/noise/drift/recovery traces.
4. Compare baseline-relative configurations empirically; do not promise sober detection or turn a timeout into zero.
5. Coordinate truthful acquisition metadata and Nicholas's explicit duration decision before enabling sampling/upload. Later exercise real session ownership/expiry/idempotency/reconnect and persist/read back the real measurement.

## Portable bot package

Use `docs/bots/firmware/PROFILE.md` for Name/Title/Description and creation notes; `docs/bots/firmware/SOUL.md` is the custom persona template. Hermes loads SOUL from that bot's profile `HERMES_HOME`, not the repository CWD. The startup document and AGENTS hold project state. No bot/group/profile/routine is created merely by writing these files.
