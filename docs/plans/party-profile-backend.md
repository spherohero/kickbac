# Party and profile backend implementation plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Implement Nicholas's requested authenticated party create/join and richer private profile/game history without replacing existing backend or Liam's app.

**Latest product priority:** Host NFC tap-to-link, then player tap-to-arm the next
measurement for the authenticated person and party/game, comes before general
party/game extras. See `docs/NFC_CHECK_IN.md`: static NDEF device URI, explicit
intents, native entitlement/Universal Link gates, and proposed atomic party
check-in context. The original tasks below remain useful foundations, but their
client-linked game result alone does not implement authoritative party context
at arming time. Freeze/test that additive check-in contract before coding it;
never silently change firmware metadata or treat tag possession as host approval.

**Architecture:** Keep the existing immutable game ledger and measurement store; add schema5 party/context tables and new additive routes from `docs/PARTIES.md`. Grant hardware-assignment authority through the private backend operator CLI; code or assigned-device joins never arm a measurement. Preserve all existing 17 operation shapes and firmware/iOS sources.

**Tech Stack:** Existing FastAPI, Pydantic, sqlite3, Auth0 verifier, pytest, uv and Ruff; no new dependency, service or paid resource.

## Execution checkpoint — completed and merged, not deployed

The original tasks1–9 are implemented and their independent scoped reviews
passed. Task10's real HTTP/restart/streaming/compatibility checks pass locally;
both final independent reviews and exact5a8d8e0 push/PR CI passed with no blockers.
Final8cdab3a PR CI passed; PR26 merged as67c46916bda95250cdae739fd99e19cde8634667
with verified parents/ancestry/tree equality. Exact merged-main CI39105975584
also passed. All original implementation tasks are complete; this is not a
production release. Additional
NFC-first scope is frozen and implemented in migration006/schema6 with atomic
check-in POST/private GET and exact party/game result fencing; see
`docs/NFC_CHECK_IN.md`. Parent combined execution at2f04074 returned528 tests on
each Python3.11/3.12. Current source has33 operations, while production remains
schema4/17 operations. The remaining original numbered tasks below describe
historical implementation sequencing, not permission to rebuild completed work
or deploy schema5-only code over schema6.


---

## Preconditions

Read `AGENTS.md`, `docs/LIAM_BACKEND_HANDOFF.md`, `docs/PROFILE_PARTY_REQUIREMENTS.md`, `docs/PARTIES.md`, current API/OpenAPI and role handoffs. Base `dd19b404210517b1b0c8b8f8a1809ba988bb250d`; isolated backend-owned worktree `kickbac-backend-pr22` now on `backend/party-profile-contract`. Original backend startup worktree has a dirty `AGENTS.md`: leave it untouched. Publish/notify the LIAM impact contract before production-code changes. Use synthetic identities/DBs only; no SMS, live user writes, grants, arming, deployment or firmware changes.

## Task 1: Review and freeze the additive contract

- Create `docs/PARTIES.md` and this plan; add proposal checkpoint in `docs/LIAM_BACKEND_HANDOFF.md`.
- Read current definitions/callers in `kickbac/app.py`, `db.py`, `games.py`, `models.py`, `sessions.py`, `measurements.py`, `profile_body.py`, `errors.py`, `cli.py`, migrations and deployment backup tests.
- Independent design review: privacy/membership, operator-controlled binding, exact retry ordering, lifecycle/concurrency and legacy compatibility.
- Publish draft feature PR and report `=== LIAM / iOS IMPACT ===` with exact endpoints/examples, no required client implementation until release. Resolve substantive design concerns before coding.

## Task 2: Reading summary vertical slice

**Files:** `backend/tests/test_reading_summary.py`, `backend/kickbac/measurements.py`, `backend/kickbac/models.py`, scoped cache middleware/error coverage.

1. Write `test_empty_summary_is_owned_exact_zero_and_latest_null`: request `GET /v1/me/reading-summary` using `world` fixture, assert200 and `{user_id:'auth0|alice',saved_readings:0,latest_measurement:None}`. Run and observe404 (RED).
2. Add minimum typed SQL-backed read-only route; run same test (GREEN).
3. Add next failing test with two completed simulator sessions before profile creation, newest received ordering, count unaffected by profile edits and other subject; implement only missing behavior. Verify no-store on success/auth/storage failure.
4. Run `cd backend && uv run --locked --python 3.12 pytest -q tests/test_reading_summary.py tests/test_profile_reading_history.py`; commit focused change.

## Task 3: Schema5 migration vertical slice

**Files:** `backend/migrations/005_parties.sql`, `backend/kickbac/db.py`, `backend/tests/test_parties_migration.py`, relevant existing schema assertions and complete-schema backup tests.

1. Write migration-upgrade test building populated schema4 via existing four SQL files, preserving all prior row digests. Assert schema5/tables/indexes after `initialize`, repeated initialize and `check_schema`; observe intended missing-schema failure.
2. Add schema5 tables from contract (parties, members, device-host grants, current device bindings, game instances, result contexts, durable join counters) and indexes/constraints. No ALTER to old ledger/profile/session/measurement schemas. Add migration to `initialize` and `check_schema`.
3. Extend exact backup/schema-version fixture expectations, not old historical prose. Test orphan/FK/unique constraints and restore to new app.
4. Run migration and existing schema/backup/CLI tests; commit.

## Task 4: Party create/read vertical slice

**Files:** new `backend/kickbac/parties.py`, `backend/tests/test_parties.py`, router wiring in `backend/kickbac/app.py`, body/cache/errors helpers.

1. Write create→own GET→me-list test; observe404 first. Add strict bounded models and typed responses, `BEGIN IMMEDIATE` create with host membership and generated code, read-only GET/list.
2. Add one test at a time: canonical name/UUID retry200; changed409; foreign UUID404; nonmember404; no host subject/code disclosure; strict body validation and streamed cap.
3. Keep reads query-only, pagination bounded1–100 and huge offset safe. Run old route/OpenAPI contract regression. Commit.

## Task 5: Join/lifecycle vertical slices

**Files:** `parties.py`, `backend/tests/test_party_membership.py`, `errors.py` new codes, scoped HTTP/parser/cache handling.

1. Test code join and same-member replay, then implement.
2. Test known assigned-device join convergence after binding implementation; do not bypass auth or arm.
3. Test durable10/60-second guessing bound and exact boundary/restart, then implement with separate committed rate-limit accounting before membership transaction; error429 `Retry-After`, no code/payload logs.
4. Test leave/rejoin, host leave rejection, host-only idempotent close, no reopen and former-member privacy/history. Implement each RED→GREEN slice.
5. Add threaded code/member-close contention tests; assert no duplicate membership and no writes on rejected business operations. Commit.

## Task 6: Operator-approved device binding

**Files:** `backend/kickbac/cli.py`, `parties.py`, new CLI/binding tests; `backend/README.md` only if present (otherwise existing root README operator section).

1. Inspect current argparse CLI signature before adding `grant-party-device`. Test it grants one registered device/opaque-subject pair, idempotently, no credentials/output secrets/arming.
2. Test unauthorized host cannot bind known ID; implement host+grant check returning404. Test member cannot mutate host binding.
3. Test assign/same-target retry/unassign, competing party409, active unexpired source or destination session409, boundary expiry permits. Implement transactions/unique constraints; do not mutate existing device/session rows or credentials.
4. Test party close releases binding, never steals an active unit. Commit.

## Task 7: Game instances

**Files:** new `backend/kickbac/party_games.py`, new party-game tests, router wiring.

1. Write host create→list test with snapshotted device and game slug, observe404; implement.
2. Test exact/changed/foreign retry, member-only reads, oneOPEN game perparty, host close/idempotency, party-close cascade, stable device snapshot after reassignment. Implement each missing rule afterRED.
3. Keep generic game routes and payloads untouched. Commit.

## Task 8: Atomic completed result/context

**Files:** `party_games.py`, tests `test_party_results.py`; reuse inspected validators/models from `games.py` without changing old request/response behavior.

1. Write party result first201→same200→stats10 test. Implement one serialized ledger+context transaction with explicit old-ledger column list.
2. Test per-user/instance unique completion409 `already_completed`, canonical changed fields/context409, foreign404, active membership/game/party checks. Check replay first so accepted retry remains valid after close/leave/restart.
3. Test measurement own-subject/device/game-start-session interval/future-receipt checks, null allowed, unique reuse rejected; never infer a link or synthesize BAC.
4. Test partial failure rollback, simultaneous identical/changed completions, old generic result routes unchanged, oneaward only. Commit.

## Task 9: Rich private game history

**Files:** `party_games.py`, tests `test_rich_game_history.py`.

1. Write history includes generic legacy result with explicit nullcontext and party completion with partyheader/device-source/nullBAC measurement snapshot; observe404 first, implement SQL owner-only result+context joins.
2. Test other account empty, retained after partyclose/leave, unknownplacementnull, stable pagination and sameparty acrosspages, no additional measurement rows/awards.
3. Run all backend/deployment tests plus lint/format/compile. Commit.

## Task 10: Real HTTP demo, canonical docs and readiness

**Files:** new backend-owned `backend/integration/test_party_http.py` or reusable demo helper after inspecting current simulator; `docs/API.md`, `GAMES.md`, `READING_HISTORY.md`, `PARTIES.md`, `LIAM_BACKEND_HANDOFF.md`, `DECISIONS.md`, root README and deployment migration/backup references as needed.

1. Real loopback app with ephemeral signed identities/tempDB: createparty, private fixture operatorgrant, bind, join bycode/device, creategame, deliberatelyarm correctunit, simulatorupload, save partycompletion, richhistory/summary/stats readback; exactretry/noextraaward; restart and isolation checks. Never log fixture tokens or present this as Auth0/native/sensor acceptance.
2. Preserve old17 OpenAPI operations/components exactly, except intentionally scoped new error descriptions if unavoidable; add typed new statuses200/201/429 and validate documented examples against actual models. No new party fields silently added to old responses.
3. Commands from `backend/`: `unset PYTHONPATH; uv run --locked --python 3.12 pytest -q tests ../deploy/ubuntu/tests`; `uv run --locked ruff check . ../deploy/ubuntu`; `uv run --locked ruff format --check . ../deploy/ubuntu`; `uv run --locked python -m compileall -q kickbac ../deploy/ubuntu`; `uv run --locked python -m kickbac.simulator`; `uv run --locked pytest -q integration/test_party_http.py`; `node --test auth0/test-twilio-verify.cjs`. Run3.11 as compatible gate if available.
4. Independent spec/security review, current-base integration, full tests and exact-headGitHubCI. Update PR from draft only when ready. Routine reviewed publication/ready merge is authorized, not forcepush or unreviewed deployment.
5. Deployment is separate: current schema inspection, private onlinebackup+upgradecopy rowdigests, committed immutable release, isolatedtarget tests, explicitschema5 upgrade, actualprocess/publicOpenAPI/privateauth readback. Do not deploy schema4-only code againstschema5. If deployment not performed, state it plainly; Liam keeps current live contract until release.

## Not in this slice

No iOS source/layout rewrite, account deletion, firmware sampling/duration change, live roster/leaderboard/gameplay engine, BAC calibration, drinking-based points, hosted resource creation or new paid anti-abuse service. Do not assign Liam already completed integrations again. Future production/native NFC tests remain separately owned.
