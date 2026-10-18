# Authenticated ESP32 heartbeat / session-poll diagnostic

## Result: physical DEVICE_PASS and persisted ongoing heartbeat verified

The `xiao_device` target built and was flashed/hash-verified to the same
positively identified XIAO ESP32-S3 on COM3. The USB VID/PID and serial identity
were checked immediately before flashing, and the provisioning helper checks
the exact target again before forwarding anything.

The existing demo-device credential was privately checked over host-key-verified,
noninteractive SSH: owner root/mode0600/regular non-symlink file; exact current
operator-issued token shape; SHA256 matching the existing `kb-demo-01` database
row. No credential rotation, reprovisioning, local credential file, key display,
OS Wi-Fi-profile reads, API/server code or iOS edits occurred.

The first private Wi-Fi window closed without submission (`DEVICE_CANCELLED`),
and a reopen offer timed out. Nicholas later explicitly asked to reopen it after
returning with his phone; the submitted attempt completed on the actual ESP32:

- Association/DHCP, DNS, SNTP and trusted health200 passed; controlled software
  disconnect/rejoin and second health200 passed again. Channel6, RSSI-37/-49dBm.
- Actual unauthenticated poll returned401; the existing privately relayed bearer
  then produced **three authenticated heartbeat200 and six idle poll200**.
- Heartbeat `last_seen_at` advanced: `2026-10-18T00:52:26.897525+00:00`,
  `00:52:42.760645+00:00`, `00:52:58.054442+00:00` (same date).
- Actual final marker: `DEVICE_PASS identity=kb-demo-01 heartbeats=3 polls=6 online_refresh=1 ongoing=1 uploads=disabled`.
- Independent read-only live SQLite checks **after the helper exited** showed
  the correct device's persisted heartbeat advancing from
  `2026-10-18T00:53:13.387652+00:00` (checked00:53:21.071640) to
  `2026-10-18T00:53:42.268928+00:00` (checked00:53:46.594736).
  The latter was within the existing30s online window. These later values also
  exceed the last helper-observed heartbeat, proving the PC helper is not what
  maintains ongoing connectivity; the board continues independently.
- Device session count0 and measurement count0 before/after: no synthetic
  production identity, arming, sampling or measurement was inserted.
- Server schema changed3→4 concurrently during other backend work; the device
  timestamp/counts were unchanged after the cancelled attempt. Do not interpret
  that schema change as this firmware modifying the database or claim the whole
  DB stayed unchanged. Current public device heartbeat/poll fields were rechecked.

Full sanitized serial trace: `firmware/build/device-connectivity.log`.
Independent ongoing readback: `firmware/build/device-server-ongoing.json`.

Independent static review found no concrete blocking findings. The reviewer
correctly noted that request durations add to the nominal10s/2s intervals;
these are not hard real-time guarantees. UTC timestamp checks validate shape,
not full calendar semantics, and lexical advancement relies on the current
backend's consistent UTC serialization. Existing temporary-memory forensic
erasure and production reconnect limitations remain explicit. A later-added
host HTTP/clock harness (`device_adapter_test.cpp`) passes: traffic continues
after PASS and an injected401clears the token and latches a stop with no further
requests. This addresses the review's suggested scheduler/failure-latch fixture
coverage, without presenting fake-network tests as physical evidence.

## Behavior implemented, tested with explicit host fixtures

1. Reuse the existing actual-radio scan / association / DHCP / DNS / SNTP /
   certificate-validated health / software reconnect diagnostic first.
2. Accept an operator-only `KBD1` +43-byte bearer frame over trusted local USB,
   timeout incomplete frames after >3000ms, reject malformed bytes, clear the
   parser on timeout/failure. Bearer retained in RAM for ongoing requests only;
   no NVS storage. Existing API bearer authentication is unchanged.
3. First send an unauthenticated `GET /v1/device/session`; require401.
4. `POST /v1/device/heartbeat` with exact `{}` and the device bearer every10s
   after successful response; require200, correct device ID, boolean `online:true`
   and an advancing server UTC-formatted `last_seen_at`.
5. Independently `GET /v1/device/session` every2s after successful response;
   validate correct device and explicit idle/null or valid ARMED/SAMPLING object.
   Log only state, not session/user identity or full response bodies.
6. Report `DEVICE_PASS` only after at least3successful heartbeats and3polls.
   Keep heartbeating/polling after the checkpoint while connected. This ongoing
   behavior is host-fixture-tested and independently physically verified above.
7. Any network/auth/schema error clears the retained bearer and stops requests;
   no infinite retry, insecure TLS, cross-device fallback, or silent reassociation.
   Diagnostic recovery currently requires reset + private provisioning. This is
   fail-closed diagnostic behavior, not a production resilient reconnect client.

All requests use the official public ISRG Root X1 trust anchor and normal
hostname/date checks; redirects are disabled.200 bodies are bounded to768bytes
and checked against the expected device-safe JSON shape using pinned
`bblanchon/ArduinoJson@6.21.6`. Host fake-network tests exercise the actual C++
adapter's exact methods/paths/body/header expectations, independent cadence,
ongoing keepalive after PASS, required trust configuration, no bearer logging
and401stop/clearing. These tests do **not** implement or simulate real TLS
cryptography or replace physical HTTPS acceptance.

The client never arms a session, starts sampling, extends an expiry, uploads a
measurement, inserts a user, or fabricates ADC/duration metadata. Polling may
lazily persist expiry according to the existing server contract. Required
`breath_duration_ms` remains unresolved and unmodified; no trigger is not zero.

## Private operator helper

`firmware/tools/provision_device.py` obtains the existing bearer internally via
SSH, captures its stdout without printing it, validates its exact format, and
relays it over USB only after the board's network checks pass. SSH uses the
existing authorized account/known host, BatchMode and StrictHostKeyChecking;
no auth bypass or new server resource. Server-side hash/permission checks fail
closed. No credential values are arguments, local files or normal output.

The helper verifies the attached USB identity, offers masked local Wi-Fi entry,
then sends the device bearer automatically; neither belongs in chat. It accepts
only exact firmware-owned output formats into ignored sanitized evidence.
The secret-containing bytearray frames are overwritten after transmission and
in cleanup. Python/GUI/SDK/HTTP temporary copies are not guaranteed forensically
erased. SSH and HTTPS are encrypted; the **local USB provisioning frame is not**.
Use only a trusted operator PC and physically controlled board. The helper is
intentionally scoped to this known demo unit, not a multi-device provisioning
service. Stop exposing its reusable bearer on unmanaged devices.

## Commands (Git Bash, `kickbac-firmware/` root)

```bash
# First install pinned JSON dependency before running new host tests:
uv tool run --python 3.11 --with pip --from platformio==6.1.19 platformio pkg install -d firmware -e xiao_device
bash firmware/test_host.sh
uv tool run --python 3.11 --with pip --from platformio==6.1.19 platformio run -d firmware -e xiao_usb -e xiao_wifi -e xiao_device
# Current image is already flashed; do not flash again just to provision.
# Confirm COM3 still identifies the same XIAO:
uv tool run --python 3.11 --with pip --from platformio==6.1.19 platformio device list --json-output
uv tool run --python 3.11 --with pip --from platformio==6.1.19 python firmware/tools/provision_device.py --port COM3
```

The last command needs the user present for private network entry and the
existing operator SSH authentication. Reset or power loss requires both RAM
credentials again. A failed device diagnostic requires reset first. Do not
request a device credential/token/password in chat to work around SSH failure.

## Acceptance coverage and remaining gates

- **PASS:** captured complete sanitized `device-connectivity.log`: negative401,
  identity-matched authenticated heartbeat200 with increasing server times,
  actual idle polling200 and `DEVICE_PASS` from the ESP32. Active-session JSON
  handling is fixture-tested only, not a physical user-arming acceptance claim.
- **PASS:** read back the exact device's `last_seen_at` independently from live SQLite
  (read-only SSH): correct device, timestamp at least as recent as the last
  board/helper heartbeat, and further advancement after the helper exits.
- **PASS:** no measurements/sessions created. Before-attempt readback was schema3,
  zero sessions/measurements for this device and an older heartbeat. Only counts
  and public device/timestamp metadata were saved to ignored evidence; no user
  rows, hashes or credential values dumped. Later readback was schema4 because
  another backend workstream advanced it; no server schema work occurred here.
- An idle poll does not prove a real user's ARMED/SAMPLING state, expiry,
  ownership assignment or upload/readback. Native arming remains Liam-owned;
  no fixture identity will be injected into production to force a positive.

Artifacts: ignored `firmware/build/device-build.log`, `device-upload.log`,
`device-connectivity.log` (created only on a submitted attempt),
`device-server-before.json` / `device-server-after.json`, and host-test log.
The initial after-file documents the cancelled attempt; ongoing accepted evidence
is in `device-server-ongoing.json`. All3board targets build; host signal/USB/
Wi-Fi/device parser/adapter/Python tests pass.101unchanged-base backend tests
pass when run from `backend/`; an initial repository-root invocation failed only
because its subprocesses could not import `kickbac`. No backend edit was needed.
Publish progress on the focused `firmware/esp32-core` remote branch; Nicholas
delegates main merges when integration, review and verification establish readiness,
never direct development on main or an unchecked merge. Firmware started at
`8b222c1`; current main `f109e55` was subsequently integrated without modifying
its backend/API/deployment/iOS content. Only README/decision-log conflict areas
needed combining, preserving both main's backend handoff and firmware evidence.
The combined tree passed338backend/deployment tests,78mockedAction fixtures,
backend/firmware lint/format, actual loopback-HTTP simulator with restart and all
three firmware cross-builds. Host core/parser/adapter tests also pass. No new
physical reflash was needed for documentation/base-only integration; the board's
already-tested firmware source is unchanged. GitHub-hosted CI is not claimed:
the saved OAuth credential still lacks workflow-publication scope, as documented
in the backend handoff. Final independent full-diff review gates main merge.
