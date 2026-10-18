# Session ownership guard — firmware integration checkpoint

## Scope and exact patch

**MERGED, not flashed:** [PR #28](https://github.com/spherohero/kickbac/pull/28),
reviewed head `11b5e38d40eb0868096a6dc1830bd3660b5fb6b2`, merged as
`706d5bb27ab2aa00b620375b27b7a93adaf6addf`. Exact remote head, merge parents and
complete reviewed-tree equality were verified. Exact merged-main
[firmware CI](https://github.com/spherohero/kickbac/actions/runs/39107522328) and
[backend/decoder CI](https://github.com/spherohero/kickbac/actions/runs/39107522329)
passed. This docs-only closeout is on `docs/firmware-session-closeout`, based on
that merge; its publishing PR records its own state. No runtime change or flash.

Firmware owner, branch `firmware/session-ownership-guard`, based on
`86adb12b4c1f669aafb1ee5ee1726f6da87454bb`. The publishing PR/commits are the
source of exact head and publication status. This checkpoint is NOT a flash,
physical acquisition, upload acceptance or native acceptance claim.

- `PollSnapshot` retains exact validated server UUID and expiry; the existing
  status-only decoder interface remains available for backend wire fixtures.
- Device diagnostic stores a `SessionFence` updated by the actual poll adapter.
  Lost/invalid/changed sessions, expiry, network failure and poll staleness
  invalidate acquisition tickets. A new ticket requires a fresh ARMED session;
  SAMPLING can only continue a still-matching ticket, not restart an acquisition.
- Five-second local poll-freshness limit is a fail-closed guard, not a new server
  timeout or a hard latency guarantee. Synchronous HTTPS may exceed it. A future
  acquisition loop must check the fence before/after blocking I/O and at every
  sample/finalization; no concurrent sampler is implemented in this patch.
- UTC expiry validates actual calendar fields. Fractional expiry truncates down
  to milliseconds; diagnostic clock input rounds up within its whole second.
  A monotonic UTC high-water anchor survives local invalidation: backward UTC
  adjustments cannot renew an expired lease. Forward jumps can conservatively
  abort; safe recovery may require reset and real resynchronization. uint32
  monotonic rollover is tested; calls must remain more frequent than a full wrap.
- `FrozenUpload` is a tested, transport-neutral immutable RAM slot, not wired to
  runtime or an endpoint. It locks original UUIDs and exact serialized bytes,
  rejects overwrite/mismatched IDs, retains unknown outcomes and clears only on
  matching 200/201 acknowledgment. It is NOT a schema/acquisition validator,
  response decoder, UUID generator, retry scheduler or power-loss persistence.
  Before use, an uploader must validate the complete response and semantics.
- Heartbeat remains nominal 10 s and session poll 2 s after completion. No new
  requests, fields, source enums, timing promises, logs of session/user identity,
  ADC configuration, sampling action or measurement upload are enabled.

## Current target evidence, not inferred runtime

Fresh read-only PlatformIO enumeration found COM3, USB VID:PID `303A:1001`,
serial `80:B5:4E:F1:B7:30`, matching the known XIAO. This identifies the USB target,
not its currently running image. No serial monitor was opened or flash read.
Existing private provisioning helper's relay logic was executed read-only: its
permission/format/hash check matched the existing `kb-demo-01` credential record.
Only the non-secret identity/success status was printed; no USB provisioning,
credential rotation, local secret file or application owner selection occurred.
Public `/d/kb-demo-01` returned `{"device_id":"kb-demo-01"}`. No new `kb-1` unit
was registered or presumed to be an app profile.

Newer owner report, relayed by backend Bot: assembly is completed, plugged in and
electrically correct. This supersedes the older placement-only report as an OWNER
REPORT, not as independently measured sign-off. Actual protected-node/full-scale
voltage, resistor values, loaded supply/current and clear as-built photos were
not available to firmware. The minimal clarification request was undelivered
because this delivery has no interactive user. Exclusive serial access is also
unconfirmed. No flash/reset/ADC/credential entry was attempted. Reuse existing
completed measurement evidence; do not require repeating commissioning without
an actual discrepancy. Never rewire or change the ADC link while powered.

## Proposed smallest honest acquisition, NOT enabled

App confirmation/check-in must first return an authenticated server ARMED session.
Firmware never chooses a person, party or game. For initial physical bring-up,
prefer a separate deliberate USB operator start AFTER seeing that exact live
session, rather than treating MQ threshold/noise or mere arming as proof of breath.
No window/ADC aggregation is selected or physically tuned by this patch.

After electrical acceptance, serial-only protected ADC telemetry establishes
actual sampling cadence, rails, warm-up, idle noise/drift and recovery. Then
select a bounded operator-requested window, recording actual first/last sample
monotonic times, sample count/gaps and a documented raw-summary rule. An arithmetic
mean rounded to integer ADC counts is a possible first experimental summary, NOT
a selected calibration or BAC estimator. A late/dropped/railed/interrupted window
must abort rather than fabricate a reading. Do not block ADC on HTTPS requests;
transport/acquisition scheduling remains work before enabling this mode.

A manual sample would be labeled “Timed sensor sample — breath not validated.”
A no-trigger/timeout is no result, not zero alcohol. Manual timing is NOT breath
presence or duration. Arming alone does not start a physical sample in this patch.

## === BACKEND CONTRACT CHANGE ===

This patch is **NON-BREAKING**: existing methods, bodies, schemas, units, states,
auth, ownership, errors and published examples in [API.md](API.md) and
[NFC_CHECK_IN.md](NFC_CHECK_IN.md) are unchanged. Backend needs no implementation
change to consume this guard; it must continue returning the existing UUID/expiry.

Separate coordinated acquisition support remains a **BREAKING** gate, not
implemented here. Old upload requires integer `breath_duration_ms` 1..60000.
Proposed manual mode requires null duration ONLY with
`acquisition_method:"manual_timed"` and measured integer `sample_duration_ms`
1..60000; actual raw `mq3`/`adc_counts`, `source:"device"`, unknown
`measured_at:null`, stable measurement UUID and original session UUID. BAC remains
null. Do NOT send that proposal to the unchanged live server or fill the old
field with a timer. See the full request/response examples and compatibility
requirements in [FIRMWARE_DURATION_PROPOSAL.md](FIRMWARE_DURATION_PROPOSAL.md).
Affected: POST `/v1/device/measurements`, measurement responses in owning
GET `/v1/sessions/{id}` and GET `/v1/measurements`, and the SAMPLING meaning if used
for unvalidated sensor acquisition. Backend owns schema/storage/replay/simulator/
release work. Exact approved deployed contract/acceptance is required before sends.
Necessary acquisition support reported by Nicholas through backend Bot is not
silently treated as deployment or acceptance of every proposed metadata detail.

## === LIAM / iOS IMPACT ===

Current patch: **NON-BREAKING; no app action**, no endpoint/payload change. Liam
continues authenticated explicit arming and polling the returned own session;
firmware never sees/selects user or party. Existing NFC/native work remains his.

Separate manual mode: **BREAKING** nullable-duration decoding, acquisition metadata
and explicit unvalidated notice must be coordinated with Nicholas/backend/Liam
before rollout. Do not show numeric BAC from ADC, zero after timeout or confirmed
breath. No SwiftUI work or native acceptance is claimed here.

## Verification executed

- Test-first new fixture initially failed to compile because `session_safety.hpp`
  did not exist. Implemented guard/slot and reran the full host suite successfully.
- Independent read-only review found expired-lease resurrection after UTC rollback.
  Fixed using retained monotonic UTC high water; added new-ticket-after-expiry
  regression, not just old-ticket checks. Full suite rerun passed.
- `bash firmware/test_host.sh`: existing signal/parser/helper/adapter fault tests
  plus new session safety and actual-adapter retention/idle-fencing fixtures pass.
- `uv tool run --python 3.11 --with pip --from platformio==6.1.19 platformio run -d firmware -e xiao_usb -e xiao_wifi -e xiao_device`:
  all three cross-builds SUCCESS. No upload target was used.
- Final independent read-only review approved the corrected foundation with no
  actionable blockers and freshly rebuilt/reran the host suite successfully.
- Current backend over real loopback HTTP to the actual updated C++ decoder:
  `cd backend && uv run --locked --python 3.12 pytest -q integration/test_firmware_wire.py`
  returned **2 passed** (isolated scratch virtual environment, no live writes).
- Pinned Ruff helper lint/format checks passed (`firmware/tools firmware/tests`).
- `git diff --check` passed. These are host fixtures/cross-compilation, NOT physical
  sensing, physical authenticated arming, persisted device measurement or iPhone
  acceptance. Published CI and final review status belong in the PR.

## Next real gates

1. Share the already-completed minimal electrical report/photos and confirm serial
   exclusivity. Keep ADC isolated pending accepted protection; never assume idle
   AO alone proves worst-case safety.
2. Authorized identified-target flash/hash/serial execution and private RAM-only
   provisioning; confirm the credential-bound unit online without changing users.
3. Safe local ADC telemetry and truthful measured acquisition implementation.
4. Coordinated exact deployed nullable-duration support/client compatibility, then
   actual signed-in arm → same-session real acquisition → accepted upload → own
   app/history readback, including expiry/retry/isolation. No simulator substitution.
