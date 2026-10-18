# kickBAC firmware — USB/Wi-Fi bring-up and local signal experiments

**Latest physical checkpoint:**
Latest readback became stale and a subsequent reset/private reprovision exhausted
all three reconnect health attempts. Current online state is NOT restored; the
earlier bounded pass below is not uninterrupted connectivity. No root cause claim.
[`DEVICE_SESSION_VERIFICATION.md`](../docs/DEVICE_SESSION_VERIFICATION.md) records
the exact flashed `xiao_device` follow-up at `17ed04b`, USB identity/image hashes,
actual network/auth9heartbeat/24idle-poll run and independently advancing server
heartbeat after helper exit. Earlier reconnect failures and stale readback remain
explicit; no root-cause/reliability claim. Serial released. ADC/sampling/uploads
remain disabled; unverified electrical protection is not bypassed.

**Earlier source checkpoint (subsequently flashed with the follow-up above):**
[`FIRMWARE_SESSION_GUARD.md`](../docs/FIRMWARE_SESSION_GUARD.md) records the
current-base session UUID/expiry retention, fail-closed ticket guard and tested
immutable RAM retry-byte slot. Host suite/all three cross-builds pass; ADC,
sampling and uploads remain disabled. Fresh USB enumeration matches the known
COM3 target, not proof of its current firmware or network state. The assembly is
now owner-reported complete; minimal measured protection/serial exclusivity and
truthful deployed acquisition metadata remain physical/integration gates.
The physical connectivity/image statements below are historical evidence.

**Status:** USB-only, Wi-Fi and authenticated-device diagnostic targets build;
the new `xiao_device` image is flashed/hash-verified on COM3. Earlier actual
association/DHCP/DNS/SNTP/trusted health HTTPS and software reconnect passed.
Actual negative401, three authenticated heartbeat200 and six idle poll200 now
pass; independent live SQLite readback confirms ongoing heartbeat after the
PC helper exits, with no sessions/measurements created. See
`../docs/DEVICE_CONNECTIVITY.md` for exact evidence/commands and
`../docs/WIFI_CONNECTIVITY.md` for the preceding physical network checkpoint.
RAM-only credentials require private re-entry after reset. Sensor pins, ADC,
BLE, sampling and uploads remain disabled. No MQ readings,
breath validation or calibrated BAC result is verified. The photo-confirmed MQ
breakout still needs checked supply/protection parts before ADC enablement.

## Continuity and scope

Work in `firmware/esp32-core` in `kickbac-firmware/`, originally based on
`8b222c1` and now integrated with current main's schema4 backend. Preserve the separate dirty `kickbac/` checkout on
`backend/phone-otp`. Commit reviewed owned work and publish this feature branch
regularly; merge through the reviewed/tested integration gate when ready, not
through direct development on main. Nicholas delegates ready-merge decisions. Read the
workspace `AGENTS.md`, `.project/FIRMWARE_SESSION_PROMPT.md` and original
`kickbac/docs/FIRMWARE_HANDOFF.md`; the main-based worktree lacks those local
handoff updates. Do not copy unfinished phone work here or edit Liam's app.
Twilio approval is already verified; native acceptance remains with Liam.

## Hardware inventory: XIAO and photographed MQ breakout module

The supplied photo and ASIN B0GW8C1V6N supersede the earlier verbal bare-sensor
description: actual hardware is a Flying Fish-style four-pin MQ breakout PCB.
XIAO is attached alone; chip/flash identity, USB-only upload and two physical
serial monitor opens passed. Supporting parts can be obtained but actual supply
and resistor values/tolerances still need verification. Do not wire the six sensor
legs or add a bare-sensor load network. Follow module header labels instead.

| Item | Evidence / pending confirmation |
| --- | --- |
| Pressure sensor | Confirmed unavailable; delivery failed. Do not wait for it. |
| ESP32-S3 | User confirms XIAO-ESP32-S3. Standard board target selected from Seeed/PlatformIO docs. |
| MQ sensor | Actual photo confirms Flying Fish-style breakout; seller identifies MQ-3, 5 V, AO/DO. In supplied photo (trimmer top, header right) pins top-to-bottom are VCC, GND, DO, AO. Exact can maker/variant not visible. |
| DHT11 | Omit initially; not established as a useful fast breath/timing detector. |
| Power / protection | User can obtain meter/resistors/breadboard/jumpers/data cable/supply. Actual resistor values and supply ratings/output still need verification. |
| Feedback | No external button/LED planned for initial bring-up; use USB serial. |
| Wi-Fi | FPC antenna connected; actual Wi-Fi/DHCP/DNS/trusted HTTPS and software reconnect passed. Private entry provided network config to RAM only; reset needs re-entry. BLE untested/unneeded. |

The FigJam inspection was read-only. Old pressure-channel drawings and
"Keep a steady breath" text are planning context, not physical evidence or
validated sensing. Do not use them as a wiring specification.

## Electrical bring-up gate — sensor wiring still conditional

1. Use the photographed module header labels, not the earlier bare-sensor plan.
   Inspect all wiring unpowered. See `../docs/HARDWARE_BRINGUP.md` for the
   conditional divider/power design and meter checks; do not connect AO yet.
2. Confirm the board's USB/power path, supply budget, input limits, usable ADC
   channels with Wi-Fi and 12-bit readout configuration. Inventory actual
   resistors and a multimeter before designing voltage scaling.
3. This module has AO/DO, a trimmer and comparator circuitry. Leave DO unused;
   AO requires checked voltage scaling. Do not add a bare-sensor load network.
   A 5 V sensing circuit can exceed ADC/input limits. One low idle voltage does
   not prove worst-case safety; the trimmer is not input-voltage protection.
4. Supply the heater through an appropriately rated supply path, **never a GPIO**.
   Verify grounding and prevent backfeeding USB or another supply. Do not assume
   an ESP32 board's 3.3 V regulator or USB breakout can supply the module.
5. Calculate scaling using actual supply tolerances, resistor tolerances, ADC
   range/attenuation and loading; measure the protected node before connecting.
   Candidate two-10-kOhm scaling and D0/GPIO1/ADC1 are documented conditionally,
   not enabled. Actual parts/supply and protected-node measurements remain a gate.
6. USB-only flash and serial passed on the positively identified XIAO. Next is
   ADC telemetry through checked protection, not guessed sensor readings.
7. Confirm actual sensor conditioning requirements. Record uptime, drift, noise
   and supply stability before enabling any heuristic. A software baseline is
   not manufacturer conditioning or gas calibration.

Keep hot parts away from skin, liquid/condensation and flammable material.
Do not pour/spray alcohol, use lighter gas, or drink to test this prototype.
Use a dry, hygienic air path only after its physical design has been assessed.

## What the core actually implements

`include/signal_trigger.hpp` is hardware/framework independent and allocates no
heap memory. Call `update(monotonic_uint32_ms, actual_12bit_adc)` at a regular,
known cadence. It has no network, user/session association or measurement object.

- Required configuration: onset/release deltas in ADC counts, sustain,
  recovery, cooldown, maximum sample gap in milliseconds, and EWMA alpha.
  **There are no hardware defaults. Test constants are synthetic fixtures.**
- An explicit operator-accepted baseline is required. The core does not collect
  or certify a stable/clean-air baseline. Establish one from real, labeled idle
  traces after conditioning; confirm the actual module signal rises with exposure.
  Baseline plus onset must leave headroom below the largest usable raw value
  (4094, since 4095 is rejected as a rail), including for fractional baselines.
- Median of three samples, then `filtered += alpha * (median - filtered)`.
  Alpha is per sample, not per second; compare tuning at a fixed logged cadence.
- Trigger when `filtered - baseline >= on_delta_counts` continuously for the
  configured sustain period. Falling below onset resets that candidate.
- Emit one **signal event** and lock out further events. Release requires
  continuous `abs(filtered - baseline) <= off_delta_counts` plus cooldown since
  the event, with `0 < off_delta_counts < on_delta_counts`.
- Freeze baseline during each experiment. Do not automatically learn a high
  residual/ambient signal as the new normal. Explicit rebaselining is refused
  during Candidate/Recovering; accept a new measured baseline only after recovery.
- Duplicate/backward timestamps, excessive sampling gaps, raw ADC at either rail
  or outside `0..4095`, and invalid tuning latch a local Fault. Recreate the core
  only after inspecting/correcting the cause and re-establishing baseline.
  Ordinary uint32 timer wrap is supported with bounded, positive intervals.
- Local states are Uncalibrated, Ready, Candidate, Recovering and Fault. These
  are **not** new backend status values. Numeric filter fields are diagnostic
  only; do not consume them as valid acquisition data in Uncalibrated/Fault.

No trigger means **no signal event**, not a zero-alcohol result. Rail rejection
is a conservative local experiment rule, not an API schema revision. The core
reports no breath duration, acquisition UTC, BAC or proof that anyone exhaled.
An elevated ambient signal can still trigger; alcohol-free breath may not.

### Evaluating a higher minimum

Raising the onset delta trades fewer weak/noisy events for missed weak changes;
it does not solve the sober-breath/no-breath ambiguity. Collect real idle noise
and baseline drift first. Select and log onset/release margins from those traces,
then compare the same labeled trials across several settings. A noise-relative
selection such as a measured noise multiple plus a minimum margin is a tuning
procedure, **not an automatic noise-adaptive feature in this core**.
Do not ship synthetic test thresholds as measured device settings.

## DHT11 assessment

The retrieved OSEPP-translated DHT11 datasheet specifies a humidity response
(63% step response, 25 C, 1 m/s air) of 6–15 seconds and warns against dew and
nearby heat sources. Its communication/readout interval is not that physical
response time. It may provide slow environmental context or a measurable humidity
change, but cannot be assumed to time a short breath. Availability, actual part
specification, latency, false events, recovery, condensation and MQ-heater
interference must be tested before any use. Do not implement a flow claim or
breath-duration field from it by assumption.

## Physical experiment protocol — not yet performed

After wiring/power are verified, log labeled raw traces separately from synthetic
fixtures: monotonic time, raw ADC, filtered ADC, accepted baseline, delta, local
state/event, sensor powered uptime, configuration, supply observations and notes.
No credentials or user data in serial logs.

1. Condition per the actual sensor docs; record idle drift/noise and rail events.
2. Compare observed idle/no exposure, ordinary alcohol-free exhalation only with
   a safe dry/hygienic path, and recovery/repeated attempts. No alcohol consumption
   or hazardous vapor generation is required or prescribed.
3. Record operator-observed exhalation separately from the heuristic event. Do
   not train labels from the trigger itself or equate signal-above time to breath.
4. Test ambient disturbances, slow drift, residual high signals, power/reconnect
   and dropped samples. Compare measured detection latency and false/missed events.
5. Reuse one baseline until recovery is demonstrated; do not mask contamination
   by repeatedly pressing a baseline/reset control.
6. If available, compare DHT11 temperature/humidity onset and recovery separately,
   placed away from the MQ heater. Reject it as a gate if latency/recovery is poor.
7. If sober breath cannot be distinguished from no breath, use an honest manual
   acquisition only after the contract/UX proposal is explicitly approved.

## Wi-Fi/backend integration boundary

The earlier public timeout is superseded. Actual ESP32 Wi-Fi diagnostics now
returned trusted-HTTPS `/health`200 with `{"status":"ok"}` before and after
a controlled software disconnect/rejoin. The firmware uses a public ISRG Root X1
trust anchor, actual SNTP synchronization and hostname/date checks; it never
disables TLS verification. Subsequent `xiao_device` acceptance also verifies
device-bearer heartbeat/poll and independently persisted ongoing heartbeat;
see `../docs/DEVICE_CONNECTIVITY.md`. This is not sampling, real-user arming or
measurement-upload acceptance. Earlier Wi-Fi evidence is in
`../docs/WIFI_CONNECTIVITY.md`. PC-side resolver/OpenAPI checks
also passed; the live schema still requires integer breath duration. Deployment
handoff is now published in `../docs/BACKEND_RELEASE_VERIFICATION.md` and
`../docs/LIAM_BACKEND_HANDOFF.md`. Current main's backend/API/deployment/iOS
content is preserved unchanged by this firmware increment. Combined integration
passed338backend/deployment tests,78Action fixtures and the simulator; these
fixture results remain distinct from physical firmware acceptance above.

Preserve `docs/API.md`: device bearer credential; heartbeat `{}` independently
of session polling; server-owned exclusive 60-second sessions; no selected user
in firmware; identical measurement UUID/payload across retries; actual raw
readings use `source: device`; unknown acquisition UTC uses null. Never disable
TLS verification or print credentials. A physical board cannot use laptop
`127.0.0.1`. A temporary LAN fixture with simulated identity would need an explicit
proposal; no public unauthenticated arm/login endpoint is being added.

**Blocked upload semantics:** required `breath_duration_ms` cannot be populated
from this heuristic or a manual timer. No sampling/upload call is emitted here.
See `../docs/FIRMWARE_DURATION_PROPOSAL.md` for the unapproved breaking proposal.
Before implementation coordinate both backend and Liam; update schemas, stored
payload compatibility, examples, simulator and tests together. Do not carry an
old queued sample into a newly armed session. Real integration acceptance still
requires physical acquisition -> exact session/user persistence/readback, expiry,
identical retry, unknown-outcome retry and disconnect/reconnect evidence.

## Run the actual available tests (Git Bash, repo root)

### XIAO USB-only build — cross-compiled, flashed and serial-verified

The confirmed board is supported by PlatformIO as `seeed_xiao_esp32s3`.
`platformio.ini` pins Espressif32 7.1.3, Arduino framework package
4.20017.260907+sha.dcc1105b (Arduino 2.0.17), and esptool package
2.41100.260830 (esptool 4.11.0). The board manifest enables native USB CDC on
boot (`ARDUINO_USB_MODE=1`, `ARDUINO_USB_CDC_ON_BOOT=1`). No external UART wiring,
sensor pin or radio initialization is used. Application `src/main.cpp` reports
monotonic uptime once per second with `sensor=disabled network=disabled`; it
does not wait indefinitely for a serial monitor, invent readings or emit uploads.

Build from this checkout's root (requires uv; it can provision Python 3.11):

```bash
uv tool run --python 3.11 --with pip --from platformio==6.1.19 platformio run -d firmware -e xiao_usb
```

Keep `--with pip`: this esptool package's installer invokes `python -m pip` to
install its own contributions; a plain uv tool environment lacks pip. A mirror
reset was recovered using PlatformIO's next mirror. A partial esptool install
caused by missing pip was preserved outside the project and reinstalled with pip
available; no backend dependencies or credentials were changed.

Observed target build: **SUCCESS**. Output is under
`firmware/.pio/build/xiao_usb/` (ignored): firmware ELF/bin, bootloader and partition
table. The later physical upload to verified COM3 also returned SUCCESS with
flash hashes verified, followed by repeating physical USB status lines.
Do not flash `firmware.bin` alone at an invented offset; use the board's recipe
and positively identify/re-enumerate the target before each later upload.

The initial physical step was completed with XIAO alone and MQ disconnected.
For later operations re-inspect ports rather than assuming COM3 is unchanged:

```bash
uv tool run --python 3.11 --with pip --from platformio==6.1.19 platformio device list --json-output
```

After identifying the actual target, the executed upload was:

```bash
uv tool run --python 3.11 --with pip --from platformio==6.1.19 platformio run -d firmware -e xiao_usb -t upload --upload-port COM3
```

Physical serial at 115200 returned one-second uptime messages on two monitor
opens. The second open restarted uptime; no cable-replug test is claimed. Logs
are under ignored `firmware/build/`; see the hardware checkpoint. For a future
missing-port issue, Seeed's documented
recovery is hold the onboard BOOT button while connecting the data cable, then
release BOOT; inspect the newly enumerated port. This uses the board's built-in
button, not an added sample-control button. After successful upload, verify actual
repeating uptime/status lines and reconnect recovery before enabling sensors.

### Host-only fixtures

```bash
bash firmware/test_host.sh
```

Requires an installed `g++` (or `CXX` pointing to a compatible compiler). The
script compiles with C++11, warnings-as-errors, exceptions/RTTI disabled, then
runs synthetic trigger tests and a USB adapter test against a test-only Arduino
stub with no GPIO/ADC/Wi-Fi APIs. Build outputs/private configuration are ignored.
It never flashes a board. Host fixtures do not prove physical runtime; the separately
captured real USB serial trace above establishes USB-only execution.

Backend checks executed against this worktree's unchanged main-based backend
using the already-installed Python 3.11 environment from the original checkout:

```bash
cd backend
../../kickbac/backend/.venv/Scripts/python.exe -m pytest -q
../../kickbac/backend/.venv/Scripts/python.exe -m kickbac.simulator
```

Observed: 101 backend tests passed; simulator reported `SIMULATOR_OK`, one
persisted fixture measurement, zero duplicate rows, foreign owner 404 and restart
success. These tests use simulated identity/sensor input over real loopback HTTP.
They do not include the original checkout's pending phone work, establish native
login, or demonstrate hardware. Host scenarios all passed, including higher
minimum sensitivity tradeoff, fractional-baseline headroom, exact timing/gap
boundaries, interrupted onset/recovery, rebaseline filter reset, and candidate,
recovery and cooldown timers spanning rollover. Independent review's headroom
finding was reproduced as a failing regression and fixed. Separate physical
evidence now verifies XIAO USB execution only, not sensor or Wi-Fi behavior.

## Sources (context, not confirmation of the actual parts)

- [Seeed XIAO ESP32-S3 documentation](https://wiki.seeedstudio.com/xiao_esp32s3_getting_started/)
  confirms board/radio/USB details; do not confuse a 5 V power pin with a 5 V-safe
  GPIO/ADC or assume the heater fits an unmeasured power budget.
- [PlatformIO XIAO board target](https://docs.platformio.org/en/latest/boards/espressif32/seeed_xiao_esp32s3.html).
- [Parallax-distributed MQ-3 datasheet](https://www.mouser.com/datasheet/2/321/605-00011-MQ-3-Datasheet-370469.pdf)
  specifies a 200 kOhm example load and over 24-hour preheat; the
  [Pololu-distributed MQ-3 datasheet](https://www.pololu.com/file/0j310/mq3.pdf)
  lists materially different sensing resistance and over 48-hour preheat.
  These variants are historical background, not instructions to add a bare-sensor
  load circuit to the now-photographed breakout module. Do not promote a quick
  bench response or seller warm-up claim to a conditioned/calibrated result.

- [Read-only team FigJam](https://www.figma.com/board/XlYEabKISK95kAu1XfxaCB/Swamp-Hacks).
- [SwampHacks hacker guide](https://swamphack.notion.site/swamphacks-xii-hacker-guide)
  confirms a hardware lab resource; actual available stock still needs checking.
- [Winsen MQ-3B specifications](https://www.winsen-sensor.com/product/mq-3b.html):
  this **example variant** specifies a 5.0 V ±0.1 V heater, up to 900 mW and over
  48 hours preheat under its standard conditions. These are not asserted as the
  unidentified module's final specification or a calibrated hackathon result.
- [OSEPP-translated DHT11 datasheet](https://www.mouser.com/datasheet/2/758/DHT11-Technical-Data-Sheet-Translated-Version-1143054.pdf).
