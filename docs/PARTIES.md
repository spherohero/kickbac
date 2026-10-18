# Parties and richer private profile history — reviewed backend source

**Current release:** LIVE schema7/35operations, atomic resolve/current-party policy
activated2026-10-18T10:29:53UTC, runtime768e992, PR40merge9d52390. Verified
backup/old-object-row-BLOB-hash preservation/private-copy/target/public readback:
[release proof](BACKEND_RELEASE_VERIFICATION.md). Lower schema6/33/source-target
checkpoints are historical; device resolve/current is deployed, App reading8isnot.
No production party cleanup/history deletion or iOS edits were performed.

**Status: DEPLOYED after reviewed source/CI, backup/copy trial and target/public verification.** Owner:
backend Bot, integration branch `backend/party-profile-completion`, publishing
branch `backend/party-profile-contract` in [PR #26](https://github.com/spherohero/kickbac/pull/26),
based on prior main `dd19b404210517b1b0c8b8f8a1809ba988bb250d`, merged as
`67c46916bda95250cdae739fd99e19cde8634667`. Exact merged-main CI and reviewed
tree/ancestry checks passed; see [release verification](BACKEND_RELEASE_VERIFICATION.md).
The source
application currently exposes33 operations on schema6. Its real-loopback
party→join→game→check-in reservation→simulator upload→completion→private
history/restart acceptance passes. Live API is now the33-operation schema6
release, source172e54c, after verified old-row preservation and public readback.
Exact provenance/backup/acceptance: [release verification](BACKEND_RELEASE_VERIFICATION.md).

**NFC-first flow:** host binding identifies the assigned unit; new authenticated
check-in creates the exclusive session and immutable owner/party/game context
BEFORE acquisition. Exact POST/GET/retry/lifecycle semantics are canonical in
[NFC_CHECK_IN.md](NFC_CHECK_IN.md). Backend context is implemented and locally
exercised; this is not native tag-reading or physical sensing acceptance.

## === LIAM / iOS IMPACT ===

### Current requested change — device resolve / one OPEN party

Exact target: [DEVICE_PARTY_RESOLVE.md](DEVICE_PARTY_RESOLVE.md). Replace
create-then-bind with authenticated `POST /v1/parties/resolve`, using persisted
`request_id`, `device_id`, optional `name` (default `Party`). `{action,party}` is
already bound when created; assigned-unit scans join the same OPEN party without
changing host/name/code. No additional Join button/operator grant. Unknown units
are errors; creation rejects live tests, existing-party joining never alters one.

Use `GET /v1/me/parties/current` for sole OPEN PartyResponse/null restoration.
Another current membership gives409 `active_party_conflict` with only own party
snapshots; no silent switch. Legacy create/code/device joins share this policy.
Migration007 preserves all existing rows and duplicate memberships until explicit
user close/leave; no bulk cleanup, winner choice or history deletion.

**Delete party = existing host-only close, not purge.** POST
`/v1/parties/{party_id}/close` `{}` stays retry-safe/active-test fenced, closes games,
releases binding, invalidates invitation and stops current restoration. Historical
party/membership rows, readings, game results/check-ins remain. A later party gets
a different UUID/code. Clear active UI after verified CLOSED/null-device response.

These are additive routes plus intentional behavior/policy changes, not yet a
deployment claim. Operator-approval text below describes legacy PUT/device only,
not the new resolve path. Firmware wire/private identity/BAC/points unchanged.

**Additive / NON-BREAKING.** Preserve every existing route, request/response shape, Auth0 access-token behavior, opaque subject ownership, session state/expiry/duration and `completion_v1` scoring policy. No iOS redesign or edits are made by backend. New operations below use the same user API access token. Server-derived `total_points`, `games_played`, `wins` remain on `GET /v1/me/stats`; raw game `score` and fixed `awarded_points:10` remain different values. New profile/game reads avoid inferring lifetime totals from loaded pages.

Liam should implement these new consumers only after backend publishes deployed status/OpenAPI. Retain QR/manual fallback: current Personal Team lacks NFC Tag Reading provisioning and background Universal Links are not configured. Tapping a passive device tag is intended to supply the trusted device ID to the new join endpoint; it must never contain an access token, device credential, host approval or a permanently embedded party ID. Joining is not arming. No firmware field, endpoint or payload changes; firmware does not implement parties.

## Identity, permissions and trust boundaries

- Profiles, readings and completed results remain private to the validated token subject. Party membership does not expose another person's readings, photo, raw subject or per-person game ledger. This slice returns no public roster/leaderboard.
- Creating a party makes the creator its host and first member. Other users may join with the host's code **or** the known assigned device ID. Either is an invitation locator, not proof of physical presence or verified eligibility; NFC cloning/knowing the ID can lead to the same join. Authentication is still mandatory.
- Registered devices are not host-owned merely because their IDs are public. A backend-only operator command grants a validated opaque subject permission to assign a particular registered unit. The host assignment endpoint requires that grant; phones never receive device credentials. This is application-level operator approval, not new hardware/firmware provisioning or provider setup. No production grant is created by implementation/tests.
- One current device per OPEN party and one OPEN party per device. Host assignment/unassignment is atomic, rejects competing assignments and any active, unexpired measurement session on affected devices. Host cannot steal another party's unit. Closing an OPEN party releases its binding; close rejects while its unit has an active unexpired session. **Assignment approval is not an exclusive arming reservation:** existing authenticated nonmembers can still arm a known unit under the unchanged session contract. Serialize binding/close against arming and reject busy transitions rather than silently adding membership checks to legacy routes. Existing sessions/uploads are otherwise unchanged.
- Membership persists through server restart. Leave removes active membership but not private history. Host must close rather than leave. A member can rejoin an OPEN party. Closed parties cannot be reopened, joined, assigned devices or create new games/results. Exact accepted retries remain valid after leaving/closing.
- Party/game/result IDs are client-generated UUIDs persisted once for retry. Ownership, server timestamps, memberships, awards and invitation codes are never client-chosen. Create/retry checks precede state checks; a foreign UUID is 404, a changed accepted payload is 409. No new UUID to bypass a retry conflict.

## Party operations

All responses and errors on new authenticated operations are `Cache-Control: no-store`. Error envelope remains `{"error":{"code":"...","message":"..."}}`; messages are not stable client identifiers. Unknown body properties are rejected. Names trim surrounding whitespace, 1–80 Unicode codepoints without controls/surrogates. New write requests are streamed/bounded at 32768 bytes, including absent/false Content-Length.

| Method/path | Request | Success / semantics |
|---|---|---|
| `POST /v1/parties` | `{"party_id":"<UUID>","name":"Friday at Nick's"}` | 201 new / 200 same host+UUID+name; host included as member |
| `GET /v1/me/parties?limit=50&offset=0` | none | 200 own memberships (including closed); `{items,limit,offset,has_more}` |
| `GET /v1/parties/{party_id}` | none | 200 active member/host only; foreign/not joined 404 |
| `POST /v1/parties/join` | exactly one of `{"join_code":"ABCDEFGH"}` or `{"device_id":"kb-demo-01"}` | 200 joined/already joined; no automatic session arm |
| `POST /v1/parties/{party_id}/leave` | `{}` | 200 idempotent for previously joined member; host 409 `invalid_state` |
| `POST /v1/parties/{party_id}/close` | `{}` | 200 host only, idempotent; no reopen; busy assigned device 409 `device_busy` |
| `PUT /v1/parties/{party_id}/device` | `{"device_id":"kb-demo-01"}` | 200 host plus operator grant; competing party 409 `device_assigned`; no grant 404 |
| `DELETE /v1/parties/{party_id}/device` | no body | 200 host, idempotent; live session 409 `device_busy` |

Party response:

```json
{"party_id":"c16e61fc-dbad-42c0-9ec5-3aa908ec605a","name":"Friday at Nick's","created_at":"2026-10-18T05:00:00+00:00","state":"OPEN","closed_at":null,"role":"host","member_count":1,"device_id":null,"join_code":"ABCDEFGH"}
```

`role` is `host|member`. `join_code` is returned only to the host while OPEN; otherwise null. No host subject/phone/profile is returned. Party date is this stable server UTC `created_at`; format its date locally and group by `party_id`, not name or date. Names/created timestamps are immutable in this slice. List includes memberships with `left_at` null; former members retain game history but must rejoin to read party details. No scheduled expiry is invented: code is valid until party close. Code is eight cryptographically random uppercase characters from an unambiguous 32-character alphabet, unique in the database; trim and uppercase user input before validation. Do not log codes or request bodies.

`POST /v1/parties/join` is limited to 10 validated attempts per fixed 60-second per-subject window, persisted in SQLite and checked transactionally across app instances/restarts. Invalid code/device lookup returns generic 404; a closed code/device assignment is unavailable. Further attempts return 429 `rate_limited` with `Retry-After` seconds; clock boundary is server UTC, `now >= start+60` resets. Old counters are pruned on writes. This bounds guessing by one authenticated subject, not a global anti-abuse service or proof against many accounts. Invalid JSON/model requests are 422 and byte overflow 413.

## Device/NFC join

Keep existing public `GET /d/{device_id}` response exactly `{"device_id":"..."}`. No new public party metadata or write on GET. A signed-in client resolves/validates the trusted device target, then deliberately calls:

```http
POST /v1/parties/join
Content-Type: application/json
Authorization: Bearer <API_ACCESS_TOKEN>

{"device_id":"kb-demo-01"}
```

The server transaction joins whichever OPEN party currently owns the assignment. Unknown/unassigned/closed targets are 404; no stale cached party ID or code is trusted. Joining does not select an upload owner, arm a unit, extend a test, expose sensor data or communicate credentials to hardware. For party-aware arming use the explicit [check-in POST](NFC_CHECK_IN.md#frozen-check-in-contract--approved-for-test-first-implementation-not-live), not a legacy ordinary arm with no party/game context. `POST /v1/devices/{device_id}/sessions` with `{}` remains available and unchanged for ordinary tests.

## Party game instances and completed results

This is persistence/context, **not** trivia/Pictionary gameplay, answer authority, anti-cheat, a party engine or a drinking reward. Distinct instances of the same game have distinct stable IDs. Hosts create/close instances; members report only their own completed result. Higher score and placement claims remain client-reported; no other-player result is exposed.

| Method/path | Request | Success / semantics |
|---|---|---|
| `POST /v1/parties/{party_id}/games` | `{"game_instance_id":"<UUID>","game_id":"trivia"}` | 201 new / 200 exact host retry; party OPEN; snapshot current assigned device (nullable) |
| `GET /v1/parties/{party_id}/games?limit=50&offset=0` | none | 200 active member/host; paginated instances, not other users' results |
| `POST /v1/party-games/{game_instance_id}/close` | `{}` | 200 host, idempotent; new result writes disallowed afterward |
| `POST /v1/party-games/{game_instance_id}/results` | five existing result fields plus optional `measurement_id`, `placement` | 201 new / 200 identical retry, one result per user/instance |
| `GET /v1/me/game-history?limit=50&offset=0` | none | 200 ALL own generic + party results, newest completion/ID first, same pagination envelope |

Instance response: `{"game_instance_id":"<UUID>","party_id":"<UUID>","game_id":"trivia","created_at":"<ISO UTC>","state":"OPEN","closed_at":null,"device_id":"kb-demo-01"}`. Device snapshot does not change when the party is later reassigned. One OPEN game per party is enforced in this initial slice; create another only after closing the current game. A party close closes its OPEN game too.

Example new completed result (UUID strings here are illustrative, not live records):

```json
{"result_id":"2889d6a0-4719-4f23-a397-37c51d24129e","game_id":"trivia","score":8,"outcome":"win","data":{"correct_answers":8,"questions":10},"measurement_id":"026af7c9-d605-4291-a1db-5b230e10ef43","placement":1}
```

`placement`: strict integer 1–10000 or null/unset when unavailable; never infer from outcome. `measurement_id`: own existing accepted measurement UUID or null/unset. Both null and omitted normalize to unavailable for retry. A linked measurement must be owned by this token subject, use the game instance's snapshotted device, and have its session created at/after game creation and measurement received at/before result submission. This is an explicit user-selected link, not timestamp-nearest inference; a measurement may link only once across game completions. If no device was bound at game creation, measurement link must be null. No second measurement/history record is created. A stored link does not validate breath, physical identity or BAC.

The transaction writes the same immutable `game_results` ledger plus a separate context row; points/stats and old result-history routes immediately include it. Per-user/instance uniqueness prevents a new UUID from awarding that instance twice (409 `already_completed`). Changed accepted data/context is 409 `idempotency_conflict`; foreign IDs/measurement/nonmembership are 404. `game_id` must match instance, otherwise 422 `validation_error`. New writes require an OPEN game and OPEN party plus active membership; exact accepted retries are returned without requiring membership/state to remain active. Legacy `POST /v1/me/game-results` remains byte-for-byte behavior-compatible and cannot attach new authoritative context via arbitrary `data`.

New rich-history row includes all existing result fields plus:

```json
{"party":{"party_id":"c16e61fc-dbad-42c0-9ec5-3aa908ec605a","name":"Friday at Nick's","created_at":"2026-10-18T05:00:00+00:00"},"game_instance_id":"22222222-2222-4222-8222-222222222222","placement":1,"measurement":{"id":"026af7c9-d605-4291-a1db-5b230e10ef43","session_id":"33333333-3333-4333-8333-333333333333","device_id":"kb-demo-01","raw":{"sensor":"mq3","value":1200,"unit":"adc_counts"},"breath_duration_ms":2500,"source":"simulator","measured_at":null,"received_at":"2026-10-18T05:00:05+00:00","estimated_bac_percent":null}}
```

Legacy generic results return `party:null`, `game_instance_id:null`, `placement:null`, `measurement:null`; do not fabricate old associations. Group same-party rows across pagination; use `game_id` for native icon mapping (unknown slug gets a generic icon), `score` for game score, `awarded_points` for contribution to lifetime points. No image URLs or private media are added. Rich history never exposes another subject's results/measurement, including after party close/leave.

## Complete saved-reading count and latest check

New `GET /v1/me/reading-summary` returns:

```json
{"user_id":"sms|opaque-example","saved_readings":0,"latest_measurement":null}
```

Count all accepted owned measurements in SQL, independently of profile existence, pagination, ordinary/game usage or simulator source. `latest_measurement` uses existing measurement shape, ordered by server `received_at DESC,id DESC`, or null. It is the latest saved test, not necessarily a calibrated BAC estimate. Current BAC remains null/unavailable; do not fall back to an older numeric value and imply it is the latest check. Existing `GET /v1/measurements` still serves all normal/game-start readings and retains its existing wire shape. Existing `/v1/me/stats` provides exact lifetime games/wins/points.

## Storage, migration, verification and deployment gates

Use one explicit `005_parties.sql` migration to schema5, adding party/membership/device-host grants/device bindings/game instance/context/join-attempt tables and indexes, without modifying existing ledger/profile/measurement rows or their schemas. Keep schema4 runtime and production database untouched until backed-up migration/release approval. Upgrade-copy/rollback/backup validation must preserve every old table's row digests; old schema4 code cannot run against schema5 by blind rollback. Include new tables in backup/restore acceptance and operator schema reporting.

Keep legacy migration005 unchanged, then apply explicit
`006_party_check_ins.sql` to schema6 for immutable NFC arming context; populated
schema5 upgrades and complete backups/restores are tested. Current source fails
closed without schema6. Production schema4 requires both reviewed migrations005
and006 after backup/copy validation; neither schema4-only nor schema5-only code
may be blindly restarted against schema6. This is source readiness, not an
executed production upgrade.

Backend-only command: `python -m kickbac.cli grant-party-device <registered-device-id> <validated-opaque-user-subject>` against the explicitly selected configured DB. It grants assignment authority only, never returns a credential or arms anything. Exercise with synthetic identities locally, not production users. Real-host grant is a separate authorized operator action after deployment readiness.

Required tests: create/retry/changed/foreign IDs; code/device join convergence, guessing limit and restart/boundary; host/member authorization, close/leave, binding/reassignment contention and active sessions; game snapshot and result/check-in ownership, completion uniqueness and exact retries after close; old generic/profile/session/firmware contracts unchanged; summary/all-history and rich pagination, null legacy context and BAC, account isolation, malformed/streamed bodies/no-store/500/log privacy; migration from populated schema4, repeated initialize, backup/restart; real-loopback HTTP party→join→game→simulated check→completion→history/stats with no duplicate award. Source/local/CI/target-host/native/physical evidence must remain separate.
