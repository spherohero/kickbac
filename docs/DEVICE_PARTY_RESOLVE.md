# Device party resolution — implementation contract

## Current deployment superseding implementation checkpoints below

The party contract below remains live in the current **schema 8 / 38-operation**
release, source `4a29218`, PR #43 merge `d92a640`, activated 10:53:55 UTC.
App reading persistence is also deployed; it does not change this party policy.
See the [final handoff](FINAL_BACKEND_HANDOFF.md). The schema-7 evidence that
follows records the original party activation, not the current runtime version.

**LIVE schema7/35operations at2026-10-18T10:29:53UTC.**
[PR40](https://github.com/spherohero/kickbac/pull/40), exact head9b59021, merged
`9d523902dc97595fe5982fbd1fa3e54abfe59187`; complete reviewed-tree equality,
parents and remote ancestry verified. Immutable runtime768e992/92manifestfiles,
locked runtime, retained schema6 backup/private6→7 exact old-data preservation,
36target tests/simulator, final writer-stopped backup/migration/readback passed.
Public OpenAPI exactly matches candidate35operations; both new routes401/no-store
without auth.8parties/8memberships/1profile/1measurement preserved, no cleanup.
Parent588combined tests/lint/77files/compile/simulator and independentSPEC+QUALITY
pass; exactPRCI39119170237green. App reading8target remains separate/not deployed.
Detailed proof: [BACKEND_RELEASE_VERIFICATION.md](BACKEND_RELEASE_VERIFICATION.md).
Every lower pending/not-deployed sentence is the historical implementation stage.

Owner backend; branch `backend/device-party-resolve`, base
`22c1215848aa17fdfd238c9b1759fd4be4575f00`. Requested by Nicholas from Liam's
forwarded device-party/one-current-party handoff. This document freezes the
implementation target; publication/implementation/deployment are separate gates.
**Source implemented; local acceptance passed, deployment pending.** Runtime
checkpoint `768e992e15c9c7decfb963264e30159eb818abcd` is published; parent combined
suite588tests, Ruff/77-file formatting, compile and real-loopback simulator pass.
Three actual HTTP cases include full lifecycle/private history/restart and both
first-scan/same-user-two-device races. Independent review/CI and immutable target
backup/private6→7 preservation trial gate production activation. Existing live
schema6/33 operations remains unchanged until explicit verified release.

Liam owns all iOS work, including dirty/untracked work on his Mac. No app edits,
branch reset or PR32 merge are authorized by this task.

## Exact new operations

`POST /v1/parties/resolve`, user API access token, JSON:

```json
{"request_id":"2889d6a0-4719-4f23-a397-37c51d24129e","device_id":"kb-demo-01","name":"Grub"}
```

`request_id` UUID and registered `device_id` slug required. Optional `name` defaults
to exactly `Party`; explicit null/blank/invalid names reject422. Name validation
matches existing party names (trim outer whitespace,1..80 codepoints, no control
or surrogate characters). Omitted name and explicit `Party` canonicalize alike.
Unknown fields reject422. Existing party name is never renamed by resolve.

Response: `{"action":"created"|"joined","party":<existing PartyResponse>}`.
First creation201; successful join/same-party lookup200; identical accepted
request replay200. Same request UUID is globally unique/owner-private: foreign
UUID404, same owner's changed canonical payload409idempotency_conflict. Snapshot
request ID/device/name/party/action durably; retry returns original party/action
and its CURRENT lifecycle/authorized snapshot, never creates another party or
restores membership. Late retry after close/leave is safe and may return the
original CLOSED party (no active code/device). No rearm or expiry extension.

Under ONE SQLite BEGIN IMMEDIATE transaction: validate registered device, then
find its assigned OPEN party. If found, enforce caller's one-current-party rule,
join/rejoin if permitted, retain original host/name/code, return actual snapshot.
Joining existing party is allowed during device measurement and never modifies a
test. If none exists, caller must have NO current OPEN membership, device must
have no live unexpired test, then create server UUID/name/code/host membership and
bind the registered unit atomically, with NO operator per-user grant. Failure
rolls back all setup/request-ledger writes. Never provision unknown devices,
overwrite another OPEN binding or transfer the host on rescan.

`GET /v1/me/parties/current`, user token, returns existing `PartyResponse` or JSON
null200. Query is read-only and returns the sole OPEN membership. Legacy multiple
OPEN memberships return409 context rather than silently choosing or changing one.
Historical list `GET /v1/me/parties` remains available for explicit cleanup/history.

## One-current-party policy and errors

All new memberships through legacy create, code join, device join and resolve
must enforce one OPEN membership per opaque validated subject (host counts).
Same intended party is idempotent; another current party gives409
`active_party_conflict`, including caller-authorized `error.current_parties`
(array of existing PartyResponse snapshots), `error.has_more` if bounded, never
another user's memberships or the target's hidden code. App may explicitly leave
(member) or close/delete (host), then make a NEW request UUID. Do not auto-switch.
An accepted replay is checked BEFORE current-party policy so it never mutates
membership or creates extra parties after a later lifecycle change.

Unknown device/foreign resources404; unavailable new binding409device_busy;
expired original test fences remain unchanged; malformed JSON/fields422;
body cap32768 and private success/errors Cache-Control:no-store. Auth0 audience
`https://kickbac-api` remains exact. Public GET `/d/{device_id}` remains read-only.

## Delete party = existing close, NOT purge

Use host-only `POST /v1/parties/{party_id}/close` with `{}`. It is retry-safe:
closed party returns CLOSED with null device/code, open game instances close,
binding is released. Active test fence stays:409device_busy until test terminal
or expired. Membership rows/party metadata are historical records, retained;
CLOSED parties do not count as active membership or restore as current. Old codes
never resolve a new party; later party uses new UUID/code. Private measurements,
profiles, game ledgers/context/check-ins and credentials are never deleted or
reassigned. No DELETE database-record endpoint is introduced.

## Explicit duplicate-data migration plan

Fresh read-only production audit2026-10-18T09:53:50UTC: schema6,7parties/6OPEN,
all6OPEN unbound, one subject with6OPEN memberships;1measurement,0game results.
No private IDs/subjects/images or credentials were printed. This is a dated count,
not permanent state. No production cleanup has occurred or is requested here.

Add migration007 only (do not edit005/006). Preserve every existing table/row/
BLOB/hash byte-for-byte. Install transactional SQL guards for FUTURE active
membership writes across party/member tables, allowing existing duplicates to
remain until an authorized user explicitly closes/leaves extras. No arbitrary
winner, automatic close, bulk deletion or reassignment to make an index pass.
Application returns authorized409 context for ambiguous current state and permits
host close/member leave. Once extras are explicitly resolved, normal uniqueness
is enforced. Fresh and populated6→7, duplicate preservation, SQL guard rejection,
rollback/restart and complete-schema backups require tests. Source requires7;
production upgrade requires retained backup/private-copy preservation trial first.

## Compatibility and verification

=== LIAM / iOS IMPACT ===

New endpoints are additive; one-current membership and automatic registered-device
claiming are intentional BEHAVIOR/POLICY changes. Replace create-then-grant/bind
with resolve; persist request UUID/exact payload before send; retain returned
party role/code/device and use current-party read for restoration. No extra join
confirmation after an explicitly authenticated Party scan action. Delete UI can
keep calling existing close, confirm CLOSED/unbound before clearing active UI.
Code join converges to the same device-bound party; old code-only/unlinked create
callers are not silently rewritten. Existing explicit PUT/device grant policy is
retained outside the new resolve path. No iOS changes performed by backend.

Firmware/device/session/measurement wire and upload behavior unchanged. New
policy is not multiplayer round synchronization, anti-cheat, public leaderboard
or BAC interpretation. Verify real HTTP/concurrency, private retry ledger,
unknown/busy input, close/new-party/code rotation, cross-user isolation, migration
with duplicate legacy rows and history persistence. Distinguish fixtures/local/
CI/host deployment from physical NFC/multi-phone/native acceptance.
