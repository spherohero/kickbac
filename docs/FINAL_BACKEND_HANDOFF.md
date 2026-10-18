# kickBAC — final backend handoff for Liam

Verified October 18, 2026. This is the concise closeout of `combined.md`, plus
Nicholas's saved-Wi-Fi request. Backend implementation, merge and deployment are
complete. Liam retains ownership of iOS integration and native acceptance; no
app files or existing local records were changed by this work.

## 1. Live configuration and release

- API: **https://api.kickbac.vodka**
- OpenAPI: **https://api.kickbac.vodka/openapi.json** — **38 operations / schema 8**.
- Auth0 API audience: **`https://kickbac-api`**, no trailing slash.
- User endpoints consume an API **access token**, not an ID token, OTP or phone.
  Ownership comes only from its validated opaque subject.
- [Party PR #40](https://github.com/spherohero/kickbac/pull/40) merged as
  `9d523902dc97595fe5982fbd1fa3e54abfe59187`; party behavior remains live.
- [App readings PR #43](https://github.com/spherohero/kickbac/pull/43) merged as
  `d92a640b9a6f68b3986d27e889085cc85937f002`.
- App runtime source: `4a29218b1516f285d7b419edcfe0f18258064a6d`; activated at
  **2026-10-18T10:53:55.947827+00:00**, immutable release
  `/opt/kickbac/releases/app-readings-4a29218-20261018T104512Z`.
- [Release evidence and backup handles](BACKEND_RELEASE_VERIFICATION.md).

**=== LIAM / iOS IMPACT ===**

App reading operations are **additive / NON-BREAKING** to existing consumers.
The party operations are additive, but their one-OPEN-party and automatic
registered-device assignment policies are intentional behavior changes. Use the
routes below rather than create-then-grant/bind. Existing firmware measurement,
profile, physical-history and game-result contracts remain unchanged.

## 2. Atomic device-linked parties — live

```http
POST /v1/parties/resolve
Authorization: Bearer <API access token>
Content-Type: application/json
```

```json
{
  "request_id": "2889d6a0-4719-4f23-a397-37c51d24129e",
  "device_id": "kb-demo-01",
  "name": "Grub"
}
```

Persist this request UUID and exact payload before sending. `name` is optional;
omission defaults to exactly `Party`. Explicit null/blank is invalid. Existing
parties are not renamed by a scan.

- If that registered device has an OPEN party, join/return the same party,
  retaining its host, name and code. Otherwise create the party, host membership,
  code and device binding **atomically**, without a per-user operator grant.
- Response: `{action:"created"|"joined",party:<PartyResponse>}`. First create
  **201**; successful join/same-party lookup or accepted request replay **200**.
- Same UUID with changed canonical body: **409 `idempotency_conflict`**.
  Another owner's request UUID: **404**. Accepted replay returns the original
  party/action with its current lifecycle; it does not rejoin after leave/close.
- A user may have only **one OPEN party**, including hosted parties. Different
  active membership: **409 `active_party_conflict`**, with only caller-authorized
  `error.current_parties` and `error.has_more`. Do not silently leave or switch.
  Legacy duplicates are preserved, not automatically deleted.
- Restore using **`GET /v1/me/parties/current`**: `PartyResponse` or JSON `null`.
  Legacy ambiguity also returns the authorized conflict, not a chosen winner.
- Host **Delete party** uses existing
  **`POST /v1/parties/{party_id}/close`** with `{}`. Confirm CLOSED/unbound before
  clearing active UI. Games close and the device/code is released; private
  readings, results and historical metadata are retained. An active test still
  fences close with `409 device_busy`.
- Unknown device/foreign resource: 404; new binding while busy: 409 `device_busy`;
  invalid input: 422. No legacy create/bind fallback after a resolve failure.

Exact policy, retry/lifecycle and code-join details:
[DEVICE_PARTY_RESOLVE.md](DEVICE_PARTY_RESOLVE.md).

## 3. App-generated reading persistence — live

This is a separate authenticated ledger, not a firmware measurement upload.
Use the **existing local reading UUID**, preserving its original pending payload:

```http
POST /v1/me/app-readings
Authorization: Bearer <API access token>
Content-Type: application/json
```

```json
{
  "reading_id": "026af7c9-d605-4291-a1db-5b230e10ef43",
  "value": 0.08,
  "recorded_at": "2026-10-18T09:31:50.331196Z",
  "duration_ms": 2500,
  "source": "app_generated"
}
```

All five keys are required; extra keys, including client-selected owners, reject
422. `value` is a finite strict JSON number **0..1**; no strings, booleans, NaN or
Infinity. `duration_ms` is a strict integer **1..60000**, the actual client hold
duration, not breath time. `recorded_at` is a timezone-aware ISO 8601 **string**;
client time is retained and normalized to UTC, not replaced with upload time.

The receipt contains these same fields plus the validated owner's `user_id` and
immutable server `received_at`, with UTC ISO timestamps. Only a matching receipt
marks the record Synced.

| Result | Meaning / client handling |
|---|---|
| 201 | First accepted save; validate and retain the receipt. |
| 200 | Exact canonical retry; original receipt/time, no duplicate. |
| 409 `idempotency_conflict` | That UUID's accepted payload differs; preserve the local record and resolve the conflict, not a new UUID retry. |
| 404 | Globally occupied UUID belongs to another owner; no disclosure/overwrite. |
| 429 `rate_limited` | Honor whole-second `Retry-After`, retaining queued records. |
| 401 / 503 | Authentication failure / identity-provider availability; not empty history. |
| 413 / 422 | Body too large / invalid input; retain local data and correct the request. |

- Maximum streamed JSON body: **32768 bytes**.
- **60 new accepted UUIDs per subject per fixed 60-second window**, persisted
  across restart. Accepted exact retries bypass the quota; rejected/rolled-back
  saves do not consume it.
- All App resource successes/errors, including unexpected 500, use
  **`Cache-Control: no-store`** and the existing typed error envelope.
- **`GET /v1/me/app-readings?limit=50&offset=0`** returns
  `{items,limit,offset,has_more}`. Limit 1..100, default 50; offset nonnegative.
  Order: `recorded_at DESC,reading_id DESC` (client-reported chronology).
- **`GET /v1/me/app-reading-summary`** returns
  `{user_id,source:"app_generated",saved_readings,latest_reading}`.
  Count is exact; latest is a full receipt or null, from one read snapshot.
- These writes do not create sessions, device measurements, profiles or points,
  and do not populate the separate physical reading summary.

Full request/receipt examples and invariants: [APP_READINGS.md](APP_READINGS.md).

### Liam-owned upload and recovery acceptance

Preserve every existing `PracticeReadingStore` record and UUID. Keep a persistent
owner-scoped outbox, original pending payload, receipt verification, backoff and
relaunch recovery. Merge/deduplicate local/server records by `reading_id`; never
delete the only copy on failure. Guest records remain local until explicit
assignment to the current account; account changes must not upload another
subject's queue. Verify offline save → relaunch → retry → one server receipt,
second-phone restoration and account isolation on the actual app. Backend tests
and public auth rejection do not establish those native behaviors.

## 4. Saved Wi-Fi — firmware lane merged, no iOS change

Nicholas's requirement: **while powered, the ESP32 continually tries the one
privately saved Wi-Fi connection**, including boot restore and after network
loss. It does not permanently give up after a finite number of attempts.

[PR #41](https://github.com/spherohero/kickbac/pull/41) merged as
`2c8ab9dc7f16acedf79d8eaec1710ccc4f91bf99`. Firmware owner documented physical
opt-in save, software-reset restore and powered hotspot loss/return. Attempts have
bounded association windows and capped jittered backoff, not a hot loop. Trusted
TLS, auth, session fences and original pending upload bytes/IDs are preserved.
There is no automatic measurement when Wi-Fi returns.

The private local flow is documented in [SAVED_WIFI.md](../firmware/SAVED_WIFI.md):

```bash
uv tool run --python 3.11 --with pip --from platformio==6.1.19 python firmware/tools/provision_device.py --port COM3 --save-wifi
```

The save checkbox starts **unchecked**. Explicit opt-in stores/replaces one
2.4 GHz personal-network record in application NVS. Enter credentials only in the
existing private local dialog, never chat, Git or logs. NVS is not claimed
encrypted; no eFuse, flash-encryption or secure-boot change was made.

**Cold-boot limitation:** Wi-Fi credentials survive reset, but the existing
**device bearer remains RAM-only**. After power loss, saved Wi-Fi reconnect alone
does not restore authenticated API/uploads. The documented `--device-only` private
bootstrap is still required; fully standalone power-bank cold boot needs a
separately approved device-auth persistence/bootstrap policy. Software-reset
restore and powered hotspot recovery are not proof of a physical cable/power-bank
cold-cycle. Do not reset a device with an unresolved upload.

## 5. NFC and the existing device demo are unchanged

Stable tag URL: **https://api.kickbac.vodka/d/kb-demo-01**. It identifies the unit;
public GET does not arm, join, upload or authenticate anyone. No tag rewrite per
party. Native NFC/URL handling and any manual ID/URL entry fallback are Liam-owned.
Party resolve does not itself start a test.

The accepted device demo remains deliberate signed-in app arm → explicit USB
mock command → ESP32 HTTPS upload → one owner-linked COMPLETE result. The existing
one-shot operator helper is:

```bash
uv tool run --python 3.11 --with pip --from platformio==6.1.19 python firmware/tools/send_mock.py --port COM3
```

Run only after a real user's accepted arm, within its lease, with no serial monitor
holding COM3. The original accepted reading remains persisted exactly once. No
remote-start endpoint or automatic-on-arm upload was added by these tasks. Saving
Wi-Fi does not remove that explicit USB trigger or the cold-boot bearer limit.
Existing wire provenance and unavailable physical BAC behavior remain unchanged;
this handoff makes no calibrated sensor or safe-driving claim.

## 6. Verification completed and ownership boundary

- Parent **641 combined tests**, including **13 real-HTTP cases**, passed; Ruff,
  83-file formatting, compile and simulator passed. Current firmware decoder
  compatibility also passed after integrating the firmware main advance.
- Independent SPEC and QUALITY/security reviews approved exact runtime `4a29218`.
- [Exact-head CI](https://github.com/spherohero/kickbac/actions/runs/39120683806)
  and [merged-main CI](https://github.com/spherohero/kickbac/actions/runs/39121048075)
  passed, including Python 3.11/3.12 and the real HTTP-to-C++ decoder checks.
- Target: **70 focused tests**, production-venv simulator, 99 manifest hashes,
  unprivileged imports, retained schema-7 backup and private 7→8 preservation of
  all old SQL objects/typed rows/BLOBs/hashes passed. Final stopped-writer backup,
  actual migration, PID/cwd, integrity/FK, public exact-source 38-operation contract,
  missing-auth protection and fresh schema-8 backup were verified.
- Post-release readback at **10:56:36 UTC**: original demo still COMPLETE, same
  session owner/device, exactly one reading; device heartbeat age **1.75 s**.
  This is dated online evidence, not a permanent connectivity promise.
- No production fixture upload, user creation, grant or bulk cleanup was used.
  Existing profile/history/party/game/credential data was preserved.

Reproduce backend verification from `backend/` in an isolated environment:

```bash
unset PYTHONPATH
uv sync --locked --python 3.11
uv run --locked pytest -q tests ../deploy/ubuntu/tests integration/test_party_http.py integration/test_party_resolve_http.py integration/test_app_readings_http.py
uv run --locked ruff check . ../deploy/ubuntu
uv run --locked ruff format --check . ../deploy/ubuntu
uv run --locked python -m compileall -q kickbac ../deploy/ubuntu
uv run --locked python -m kickbac.simulator
```

Liam owns any remaining client adoption and actual native two-phone/offline/NFC
acceptance. Firmware owner owns hardware/provisioning and any future standalone
boot or remote trigger. Neither is silently implemented or proven by this backend
release. The backend/API/deployment requests in the consolidated handoff are done.
