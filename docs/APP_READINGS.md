# Authenticated App readings — frozen backend contract

## Deployed — schema 8 / 38 operations

Activated **2026-10-18T10:53:55 UTC** from immutable runtime
`4a29218b1516f285d7b419edcfe0f18258064a6d`; [PR #43](https://github.com/spherohero/kickbac/pull/43)
merged as `d92a640b9a6f68b3986d27e889085cc85937f002`. Independent SPEC and
QUALITY/security approved; parent 641 combined tests (13 real HTTP), target 70
tests, lint/83-file formatting/compile/simulator, exact PR and merged-main CI passed.
Retained schema-7 backup, private 7→8 trial and final stopped-writer migration
preserved every old SQL object/typed row/BLOB/hash. All 99 source hashes, actual
PID/cwd, integrity/FK, services, fresh schema-8 backup and public exact-source
OpenAPI/auth rejection were read back. No client/local-record changes or native
sync acceptance are claimed. [Final handoff](FINAL_BACKEND_HANDOFF.md) and
[release evidence](BACKEND_RELEASE_VERIFICATION.md).

Final scope from Nicholas's forwarded `combined.md`, after linked-party work.
Backend owns API/storage/release; Liam owns the local reading store, outbox and
native acceptance. **These backend operations are live.** Existing local
records must not be removed or rewritten by backend work.

## Separate provenance and identity

An App reading is a generated client record, NOT a device measurement or validated
BAC estimate. Store it separately from measurements/sessions/game results. Always
persist/return `source:"app_generated"`; no firmware credentials, fake ADC,
production arm or score/points are involved. Token's validated opaque Auth0 `sub`
is the owner, never client-supplied user/phone/name. App reading value cannot fill
an unavailable physical BAC estimate or make a physical test ready.

## POST /v1/me/app-readings

Same user API access token, JSON only, streamed body maximum32768bytes:

```json
{
  "reading_id": "026af7c9-d605-4291-a1db-5b230e10ef43",
  "value": 0.08,
  "recorded_at": "2026-10-18T09:31:50.331196Z",
  "duration_ms": 2500,
  "source": "app_generated"
}
```

All five fields required; unknown owner/extra fields reject422. `reading_id` is
the EXISTING local UUID, never regenerated on retry. `value` is a strict finite
JSON number0..1 inclusive (booleans/strings/NaN/Infinity rejected), an app-generated
sample value, NOT an accuracy/clinical range or physical unit. `duration_ms` strict
integer1..60000 inclusive, actual client hold duration, not claimed breath time.
`recorded_at` must be a timezone-aware ISO8601 STRING, normalized to UTC in storage/
responses; numeric epoch/coerced booleans/naive strings rejected. It is client-
reported time, not independently verified observation; offline past dates are
allowed. No replacement with server receipt time. source must be exactly
`app_generated` and is immutable. Canonical numeric/time/payload normalization is
used for retry comparison without rounding generated values to a new precision.

New201; exact canonical retry200 preserving original received_at; changed accepted
payload409idempotency_conflict. A globally occupied reading UUID belonging to
another subject returns404, no disclosure or overwrite. One BEGIN IMMEDIATE
transaction serializes lookup/rate limit/insert/readback; no mutable profile copy
or device/session write. No profile creation prerequisite or automatic import of
another account/guest's local records.

Receipt contains all request fields plus server-derived `user_id` and
`received_at`; `recorded_at`/received_at normalized ISO8601 UTC. Example:

```json
{
  "reading_id": "026af7c9-d605-4291-a1db-5b230e10ef43",
  "user_id": "opaque-example",
  "value": 0.08,
  "recorded_at": "2026-10-18T09:31:50.331196+00:00",
  "duration_ms": 2500,
  "source": "app_generated",
  "received_at": "2026-10-18T10:00:00+00:00"
}
```

Only a matching authenticated receipt can mark a record Synced. Preserve local
UUID/exact pending payload until acknowledged; local save or HTTP transport
success alone is not cloud receipt. Failures keep the only local copy.

## GET /v1/me/app-readings

Private page: limit1..100/default50, offset>=0/default0 (oversized offset safely
saturates SQLite binding, not500). Response `{items,limit,offset,has_more}` with
receipts above. Order `recorded_at DESC,reading_id DESC`, explicitly client-report
chronology; exact UUID tie-break and no invented global total. No mixed device
readings/other users. Client merges/deduplicates local/server by reading_id without
changing identity/source; authentication failure is not an empty history.

## GET /v1/me/app-reading-summary

Private/read-only response:

```json
{"user_id":"opaque-example","source":"app_generated","saved_readings":0,"latest_reading":null}
```

Exact SQL count of accepted own App readings, not loaded pages/attempts/physical
measurements. `latest_reading` is full receipt in the same order as App history,
or null. Count/latest share ONE read transaction/snapshot. No average, BAC total,
physical-test readiness or point award is invented. Profile edits, restart and
same-account relogin don't alter this ledger. Server history supports another
signed-in phone; actual native outbox/reload still requires Liam implementation.

## Limits, errors and migration

60new accepted App reading UUIDs per fixed60second per-subject window, persisted
in SQLite; identical accepted retries checked BEFORE the limit and do not consume
it.429rate_limited with Retry-After whole seconds; client respects it for queued
local imports. Rejected/rolled-back inserts do not consume successful-save quota.
401missing/invalid API token,404foreignUUID,409changedretry,413bodylimit,
422validation,503identityproviderunavailable. Same typed error envelope and
Cache-Control:no-store on ALL App resource successes/errors, including outer500.
Do not normalize unrelated historical routes' error semantics.

Migration008 AFTER party007: add App readings and durable rate-window tables/
indexes, preserve all earlier party/profile/measurement/game/credential data and
objects, no bulk imports/deletes. Runtime requires the complete migrated schema;
backed-up existing-host private-copy upgrade/row+BLOB/hash preservation and
complete-schema backup tests precede live activation. No paid resource or provider
setup. Existing firmware/device/session/history/error component shapes unchanged.

## === LIAM / iOS IMPACT ===

**Additive / NON-BREAKING to existing API.** Adopt new routes only after verified
release/OpenAPI. Preserve existing PracticeReadingStore records and exact UUIDs;
add owner-scoped persistent outbox, matching receipt validation, retry/relaunch/
rate handling and local/server dedupe. Guest records stay guest until the user
explicitly assigns them to the current account; never silently upload guest or
another subject's history. Existing app/device source distinctions and unavailable
physical BAC semantics remain. No new app capability/entitlement or firmware
change. No iOS edits/rebase/reset/PR32 merge by backend.

Acceptance: owner/cross-owner auth, finite/strict/bounded JSON, UUID replay/
conflict/concurrency, canonical aware timestamp offsets, rate boundary/replay,
rollback, snapshot summary, restart/migration/complete backup and actual local
HTTP round trip. Distinguish source/fixtures/CI/host deployment from two-phone
native outbox acceptance. Nicholas's final additional firmware request is one
privately saved Wi-Fi with continued powered reconnect attempts; firmware owner
implements that separately, not by altering this App reading API.
