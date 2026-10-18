# Device communication and app-request readiness

## Current result and priority

Nicholas prioritizes **device → existing webserver data delivery first**, then
coverage of Liam's app requests. Clearly labelled sample data is an acceptable
demo fallback; it is not measured/calibrated BAC. Liam controls all remaining iOS
implementation and native acceptance. Backend did not resume the stopped client
worker or modify/push/merge his app.

Backend review checkpoint: main `a0bd77bcb79766f91de6746e0ab02fa992f4b337`,
branch `backend/communication-demo-readiness`; publishing PR records its exact
head/merge state. Deployed API remains immutable172e54c/schema6/33 operations,
with [verified release evidence](BACKEND_RELEASE_VERIFICATION.md). This audit
requires no new backend runtime, provider setup, database migration or deployment.

## Existing app requests — all11 handlers deployed

Compared both published client refs:

- Original Liam: `liam/party-setup@0e5a6e4c87e650d5ea40090d7d232e9807d9dc2f`.
- Compatible isolated draft: `ios/manual-acquisition-notice@f9cbce63553712806b8d39760261975e5f817088`,
  [PR32](https://github.com/spherohero/kickbac/pull/32), still draft/unmerged.
- Both refs request the same11unique operations. Parent independently reparsed
  anchored Swift async method definitions and matched every method/path/success
  status against freshly retrieved public OpenAPI. No missing server handler was
  found for this existing request set. This does not promise arbitrary new features.

Evidence below is `ios/KickBAC/KickBACAPI.swift` at the compatible exact ref;
query parameters are not part of the path identifier.

| App method / source line | Live operation | Request | Successful status |
| --- | --- | --- | --- |
| `currentUser`:201 | `GET /v1/me` | user access token |200|
| `profile`:205 | `GET /v1/me/profile` | user access token |200|
| `resolveDevice`:209 | `GET /d/{device_id}` | public; registered slug |200|
| `device`:214 | `GET /v1/devices/{device_id}` | user access token |200|
| `armDevice`:219 | `POST /v1/devices/{device_id}/sessions` | user access token; `{}` |201new /200same-owner retry|
| `testSession`:224 | `GET /v1/sessions/{session_id}` | owning user access token |200|
| `cancelSession`:229 | `POST /v1/sessions/{session_id}/cancel` | owning user access token; `{}` |200|
| `stats`:234 | `GET /v1/me/stats` | user access token |200|
| `gameResults`:238 | `GET /v1/me/game-results` | user access token; limit/offset |200|
| `saveProfile`:246 | `PUT /v1/me/profile` | user access token; both display_name/profile_picture |200|
| `measurements`:254 | `GET /v1/measurements` | user access token; limit/offset |200|

Identity-provider SDK calls for SMS start/login/credential refresh go to Auth0,
not missing kickBAC endpoints. The exact API audience remains `https://kickbac-api`
without trailing slash. The API takes an access token, not OTP/ID token/phone.
Full-replacement profile PUT always sends both required fields; explicit null
clears photo. These existing contracts were not changed by this audit.

The complete live inventory reconciles mechanically:11connected-client +
17available-but-unconsumed +4device-only +1public-health =33operations. All
available paths are enumerated in [API.md](API.md); device credentials never enter
phones/NFC/QR. Independent network-source scan found no other kickBAC request
producer hidden in the inspected client. Auth0 SDK and documentation URLs are
not extra app→kickBAC operations.

## Immediate compatibility action — Liam

**Original0e5a6e4 requires `breathDurationMS: Int` at line110.** A manual reading
with `breath_duration_ms:null` cannot decode on that branch, even though its
endpoint exists. Compatible manual models/fences/notices are already on main
through PR30; the isolated draftf9cbce6 also contains them. Liam should integrate
that focused compatibility, not blindly merge the entire preview with its
unresolved SPEC findings. Older installed apps must not be called compatible
merely because profile/history login works.

Example of the already-live manual measurement fields (not a captured reading):

```json
{
  "breath_duration_ms": null,
  "acquisition_method": "manual_timed",
  "sample_duration_ms": 5000,
  "source": "device",
  "measured_at": null,
  "estimated_bac_percent": null
}
```

This is a **partial illustrative response**, not a complete upload. Actual
sample window must be observed, not hardcoded; null BAC means unavailable.
Canonical full request/response is in
[FIRMWARE_DURATION_PROPOSAL.md](FIRMWARE_DURATION_PROPOSAL.md).

## Available backend features not yet connected in those clients

| Client task (Liam-owned) | Existing deployed support |
| --- | --- |
| Replace local party name/code/role/membership fixtures | `POST /v1/parties`, `POST /v1/parties/join`, own party list/detail/leave/close |
| Explicit host binding of a registered unit | `PUT/DELETE /v1/parties/{party_id}/device`; host role plus operator device-management grant required |
| Contextual premeasurement check-in | `POST /v1/parties/{party_id}/check-ins`, then poll returned owned session; private `GET /v1/me/check-ins` |
| Game-instance create/list/close and own completion | existing party-game routes; generic `POST /v1/me/game-results` also deployed |
| Exact total/latest reading | `GET /v1/me/reading-summary` |
| Private party/game/placement/exact measurement context | `GET /v1/me/game-history`; current client uses legacy game-results |

Retry-stable illustrative contextual request, not an operation performed here:

```http
POST /v1/parties/{party_id}/check-ins
Content-Type: application/json
Authorization: Bearer <USER_API_ACCESS_TOKEN>
```

```json
{
  "check_in_id": "2889d6a0-4719-4f23-a397-37c51d24129e",
  "device_id": "kb-demo-01",
  "game_instance_id": null
}
```

`game_instance_id:null` means party-only; never autoattach a game or an old Home
reading. Persist that UUID/exact payload for retries, use the returned session,
and honor server-owned60second expiry. Resolving a static tag alone does not join,
prove physical possession or arm. Management grants require backend/operator
coordination for the actual validated host subject; this audit created none.

Current local trivia check-in uses a fresh unconnected store and Debug-only
completion; Release progression and preview disclosures are unresolved client
findings, not missing server handlers. Local answer scores/example players/podium
must be labelled local/unsaved and distinguished from the server's fixed10points
once per accepted completion. Raw BAC/drinking/testing never earns extra points.

**Not implemented by this backend:** multiplayer synchronized rounds/answers/
drawings, verified competition/anti-cheat or public leaderboard. Do not infer
those engines from game-instance/result storage. If Liam needs such behavior,
coordinate a concrete scope/contract instead of inventing endpoints or claiming
all future requests are supported.

## Communication-first demo acceptance

The remaining physical work belongs to the firmware owner: recover a reliable
HTTPS device loop and add an explicit operator-triggered uploader that freezes the
original server session/measurement UUID/exact bytes. Current physical diagnostic
heartbeat/poll evidence is not an upload. The later reconnect failure is still
unresolved; see [host evidence](HOST_TLS_INVESTIGATION.md) and
[physical evidence](DEVICE_SESSION_VERIFICATION.md).

Fresh authorized read-only production checkpoint **08:32:13.245616 UTC**:
registeredkb-demo-01 last_seen07:55:16.264437UTC, outside30secondonline window;
schema6,0measurements,0unexpired active sessions. The uploader has not been
accepted merely because the server suite is green. No rows were modified.
Aggregate device-party-host grants are0; no host is silently authorized to bind
the unit. For the fastest vertical demo use the already-connected standalone
**Connect→explicit arm→poll→private result/history** flow, which does NOT require
party-management grants. A real party host binding needs a private operator grant
to the actual validated opaque subject; do not invent a host or grant all users.

If protected real acquisition is unavailable, use the **existing** fixture wire
mode with `source:"simulator"`. All fixture values/duration are synthetic and
must remain continuously labelled simulated, including accessibility. Example
shape below uses a deliberately synthetic2500ms breath fixture, NOT an observed
breath/window, and the raw1200count fixture is NOT BAC:

```json
{
  "measurement_id": "026af7c9-d605-4291-a1db-5b230e10ef43",
  "session_id": "3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b",
  "raw": {"sensor": "mq3", "value": 1200, "unit": "adc_counts"},
  "breath_duration_ms": 2500,
  "source": "simulator",
  "measured_at": null
}
```

These UUIDs are illustrative placeholders, not live device-session identifiers.
The uploader must substitute the actual server-returned session and one fresh
measurement UUID, then freeze exact bytes for retries. Server accepts201once,
200identical replay,409changed accepted payload; it always returns null BAC.
A sample arriving over a physical ESP32 transport is still `simulator` if its
sensor values are fabricated. No autoresult on arm/timeout/no-trigger, no
unconsented live user creation/arming or guessed profile assignment. A PC
simulator fallback must be identified as PC→server, not ESP32 execution.

End-to-end acceptance requires actual authenticated app arming, actual board
HTTPS upload, matching persisted owner/session result and Liam's actual private
app readback. No part is inferred from healthy HTTPS or source CI. Backend can
verify the saved record after a real consenting user/session exists; it must not
impersonate an Auth0 user to manufacture success.

## Verification actually executed

On currentmaina0bd77b/imported source from this worktree:

- **570 tests passed** on Python3.11.15 in120.29seconds: backend/deployment suite
  plus all8real-HTTPparty integration cases, including legacy/manual modes,
  check-in context, retries/privacy and restart persistence.
- Standalone real-loopback simulator returned `SIMULATOR_OK`, `COMPLETE`,
  1measurement,0duplicates, foreign-owner404, restartOK. All identity/sensor
  values are explicit local fixtures, not production Auth0/physical data.
- Both real backend HTTP→tracked C++ decoder tests passed in3.35seconds, using
  pinned ArduinoJson6.21.6 headers read-only. Full Arduino transport/TLS/ADC are
  not executed by those host-compiled tests.
- Ruff lint passed;74files already formatted. One current interpreter/full suite
  only, not a duplicate3.11/3.12 CI matrix. Previously verified exact PR/main CI
  remains separately documented in release evidence.
- Public health200, five protected unauthenticated GETs401; live OpenAPI SHA256
  `67fa8679f94449d9553cdc9b3af17ef84e006f25018d39fb8171538d3fba9220`
  independently recaptured. Parent parsed all11client method definitions/source
  lines, deduplicated and reconciled all33operations in the verified inventory.
  139test functions indexed by the
  auditor are source evidence only, not an additional executed test count.
- No production user/arm/upload, provider/SMS setting, service/TLS/firewall change,
  native phone installation, calibration or physical acceptance was performed.

Commands from `backend/` (unique scratch venv/temp on Windows; unset inherited
`PYTHONPATH`; the expected toolchain/dependency versions are locked):

```bash
uv run --locked --python 3.11 pytest -q tests ../deploy/ubuntu/tests integration/test_party_http.py
uv run --locked --python 3.11 python -m kickbac.simulator
uv run --locked --python 3.11 ruff check . ../deploy/ubuntu
uv run --locked --python 3.11 ruff format --check . ../deploy/ubuntu
# Requires existing g++ and pinned ArduinoJson src; never use a fake parser.
uv run --locked --python 3.11 pytest -q integration/test_firmware_wire.py
```

Local sanitized artifacts: `KICKBAC_APP_REQUESTS_PARENT_VERIFIED.json` is the
corrected parent-verified exact-method inventory; original audit detail and live
OpenAPI snapshot remain in backend profile scratch. They contain public schema
and source evidence, not actual user tokens, private images or device credentials.

## Liam / iOS impact

**NON-BREAKING audit/demo prioritization; no new wire change.** Existing manual
nullability is the previously coordinated breaking change for old clients.
Liam owns integrating nullable models, connecting deployed party/check-in/history
requests, honest simulator/local-preview labels and actual native acceptance.
Backend owns handlers/storage/auth/deployment, firmware owns board transport.
No app edits or merge of PR32 was performed for this audit.
