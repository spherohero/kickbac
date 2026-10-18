# Backend ↔ firmware wire compatibility (no hardware required)

This check runs the **actual backend over loopback HTTP** and passes its raw
heartbeat/session response bodies into a host-compiled bridge that includes the
**actual current `firmware/include/device_diagnostic.hpp` decoder**. It does not
replace the parser with a Python imitation or canned server response.

It is independent of perfboard assembly, soldering, battery review or ADC wiring.
Run it while hardware construction is still in progress. It never opens a serial
port, flashes a board, reads private configuration, calls production, sends SMS,
or arms a real device. Database, devices, RSA signing key, users and measurement
are temporary fixtures; ordinary backend startup has no fixture authentication.

## Run from the repository root (Git Bash)

Prerequisites: `uv` and `g++` (or `CXX` set to a compatible compiler). The same
pinned PlatformIO/ArduinoJson dependency used by firmware is installed below;
this is dependency installation only, not a build upload or hardware operation.

```bash
uv tool run --python 3.11 --with pip --from platformio==6.1.19 platformio pkg install -d firmware -e xiao_device
cd backend
unset PYTHONPATH
uv sync --locked --python 3.12
uv run --locked pytest -q integration/test_firmware_wire.py
```

Expected result: **2 passed**, one lifecycle for UTC timestamps without fractional
seconds, one with six fractional digits. The suite deliberately fails rather than
skipping or faking the decoder when compiler/headers are unavailable. Advanced
local checks can set `ARDUINOJSON_INCLUDE` to the pinned library's `src` directory;
normal runs use this checkout's `.pio/libdeps/xiao_device/ArduinoJson/src`.

`KICKBAC_FIRMWARE_HEADER_DIR` is an explicit test-only override for scratch
negative controls. Leave it unset for verification of the tracked decoder. No
production code reads these integration-test settings.

## What is exercised

- Device heartbeat `POST /v1/device/heartbeat` with `{}` and device polling
  `GET /v1/device/session`, using actually provisioned temporary device bearers.
- Actual HTTP status, JSON MIME, nonempty Content-Length matching response bytes,
  no chunked response, no embedded NUL, and the current adapter's 768-byte bound.
- Strict device identity and device-safe response shapes: no associated user is
  exposed to the device decoder. Current diagnostic identity is `kb-demo-01`;
  a successful response for a different fixture device is rejected by that parser.
- Missing/invalid/user-kind credentials get real 401 responses that the C++
  decoder rejects, not a false idle/success state.
- Actual `IDLE → ARMED → IDLE` after cancellation and expiry, and
  `ARMED → SAMPLING → IDLE` after fixture completion. Same-owner arming retry
  preserves ID/expiry; competing owner gets 409; foreign session access gets 404.
- The device polls exactly the server-created session ID/expiry. Wrong-device
  sampling is rejected. UTC timestamps with/without microseconds both decode.
- An explicitly simulated upload is accepted once, replay returns the original
  record, BAC remains null, and a fresh application/listener over the same DB
  retains the owner's reading and excludes a second user. The restarted server's
  heartbeat/idle responses still decode with the unchanged firmware header.

The Python driver makes simulated sampling/upload calls to cover the backend's
existing lifecycle. **The physical diagnostic firmware still does not make
those calls**; its existing disabled-acquisition behavior is unchanged. The
fixture's duration is not evidence of measured exhalation.

## Verification checkpoint and limits

On base `6906b8b`, the two tests passed locally on Python 3.12 and 3.11 with the
pinned ArduinoJson 6.21.6 header and a real host C++ compiler. Existing 338
backend/deployment tests, Ruff lint/54-file formatting and compilation also
passed. Scratch-only header mutations for wrong device identity, wrong sampling
state and rejecting fractional UTC each produced the intended assertion failures;
restoring the tracked header passed again. These negative controls are sensitivity
experiments, not an added CI mutation-testing gate.

The backend workflow now has a dedicated `Backend HTTP to firmware decoder` job
and watches changes to the consumed decoder, device adapter and firmware manifest
as well as backend/deployment paths. Read the exact PR/main run before claiming
hosted CI passed; local execution is not hosted execution.

This proves backend response serialization ↔ current C++ decoder compatibility
and local lifecycle/persistence behavior. It does **not** execute ESP32 networking,
the full Arduino HTTP adapter, real TLS, a reverse proxy, USB, Wi-Fi faults,
physical sensors or native Auth0/iPhone acceptance. Existing firmware adapter
fault tests and separate physical connectivity evidence cover different layers.
No new physical measurement, calibrated BAC or breath-validity claim is made.

## === LIAM / iOS IMPACT ===

**NON-BREAKING / no app action.** Test/CI coverage only; no API endpoint, payload,
state, auth, timestamp, units, required duration or point policy changes. No iOS
or production firmware source is edited; no backend deployment is needed.
Nullable/manual-acquisition semantics remain separately coordinated work, not
implied approval from a green fixture test.
