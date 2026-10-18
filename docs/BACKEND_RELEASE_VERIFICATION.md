# Backend release verification — games, profiles and private history

## NFC context merged and main CI verified — not a production release

[PR #26](https://github.com/spherohero/kickbac/pull/26) head
`8cdab3a5b52e7d59115586719a90ff69233e46e6` merged as
`67c46916bda95250cdae739fd99e19cde8634667`. Remote-main ancestry, exact
parents (prior main dd19b40 and reviewed head8cdab3a) and full reviewed-tree
equality were independently read back. Existing branches/worktrees are retained.

Integrated runtime `2f0407483bc5f2b539de79495a171d86c0571b67` now includes
migration006/schema6 and33 operations. Parent ran the full backend/deployment and
signed-fixture real-HTTP acceptance command on **both Python3.11 and3.12:528
passed on each**. Seven HTTP cases include the actual party-aware reservation,
unchanged device session poll/upload, private party/game/ordinary reading history,
terminal replay after leave/close and new server restart, plus streaming bounds.
Ruff lint,71-file formatting, compile, original `SIMULATOR_OK` and immutable old
17-operation/23-schema compatibility checks passed.

Both independent final reviews APPROVED the unchanged runtime at2f04074:
SPEC PASS, QUALITY/security PASS and cross-feature integration PASS, no actionable
blockers. Integration reviewer ran528 tests plus20 scratch-only real-HTTP race
probes (check-in versus close/rebind, upload versus cancel/leave, result versus
game close); parent repeated528 tests and all local gates after review.

Published5a8d8e0 differs from the reviewed runtime only in documentation. Exact
[push CI](https://github.com/spherohero/kickbac/actions/runs/39105274853) and
[PR CI](https://github.com/spherohero/kickbac/actions/runs/39105277114) passed on
that head. Logs read back521 backend/deployment tests plus7 party HTTP checks
per Python version,2 actual C++ decoder checks,78 non-sending Node22 Action
fixtures, Ruff/compile and `SIMULATOR_OK`. The final8cdab3a
[PR CI](https://github.com/spherohero/kickbac/actions/runs/39105861628) passed,
then exact67c4691 [merged-main push CI](https://github.com/spherohero/kickbac/actions/runs/39105975584)
passed. Actual merged-main logs confirm the same521+7 tests per interpreter,
2 decoder checks,78 Action fixtures and simulator result. The subsequent
`docs/nfc-merge-verification` closeout changes documentation only; existing
workflow path filters do not require a new runtime run for it.

No native tag scan, live Auth0 acceptance, physical sensing, target-host isolated
test or production upgrade is claimed. Fresh public readback after reviews:
health200,17 operations, no check-in routes. Production remains the deployed
schema4 runtime below. Upgrades require verified backup/copy testing for both
005+006; source/merge does not automatically deploy. Older checkpoints below
describe their own historical state, not missing implementation now.

## Earlier party/profile foundation checkpoint — historical, not production

Draft [PR #26](https://github.com/spherohero/kickbac/pull/26) has been integrated
locally on backend-owned `backend/party-profile-completion`, with worker commits
cherry-picked into the complete application and both routers registered. Current
local surface is 31 operations/schema5. Existing production runtime/checkpoint
below remains unchanged; **no production migration, deployment, user writes or
sensor enablement occurred**.

Parent execution of the combined source passed **447 tests**, including
backend/deployment suites and six real-loopback HTTP party/history/streaming
acceptance cases. Ruff lint, 65-file formatting, compilation, `git diff --check`
and the original explicit simulator passed. Two additional parent concurrency
checks passed: simultaneous join-limit exhaustion across three app instances,
and an arm transaction holding the write lock while a competing reassignment
waits then rejects `device_busy`. These are local fixture results, not native,
Auth0 delivery, physical sensor or target-host acceptance. Independent core/game
reviews and new exact-head CI are still required before ready/merge claims.

Migration005/reading-summary slices at `73d66be` independently passed spec and
security/correctness review, including populated backups/restores and a WAL
snapshot probe. Executable compatibility checks preserve the existing live 17
operations, 23 schemas and authentication definitions. NFC party/game context
at arming is **not yet implemented**; see [NFC_CHECK_IN.md](NFC_CHECK_IN.md).

## Live checkpoint

**Current final runtime:** `/opt/kickbac/releases/games-1e9d830-20261018T005743Z`, activated **2026-10-18T00:57:57.865903+00:00**, source **`1e9d83070cf4096283246078cb9a9193519a13ec`**, merged [PR #8](https://github.com/spherohero/kickbac/pull/8), main merge `58c3a0bcef5afd9aa8d0a040f0ccdba7310dd529`. ArchiveSHA256 `537d0840f298a2620ea4912bc0a31bf1d1ec3e755805fb25297669b517eba462`;31 manifest entries verified after activation. Effective process working directory matches this release; runtime/lock/migration/deployment hashes match published main. Fresh trusted public health200/OpenAPI17 and all6 missing-auth profile/game/stats/history requests were read back; all rejected401 as intended. Initial schema4 rollout below is retained as migration evidence.

Public base: **https://api.kickbac.vodka**. Live schema: https://api.kickbac.vodka/openapi.json . Games/schema4 was activated at **2026-10-18T00:42:59.175342+00:00** on the existing authorized VM; no new paid resource.

- Games source **`1ed11dab277dc5ba8be44d61c267d7fc651766fa`**, merged through [PR #7](https://github.com/spherohero/kickbac/pull/7), main merge **`181bf9654aa0acecf9ea0b7bb04d3bbf800b9413`**. Reviewed feature/remote-main trees matched **`6e2b9798452faa7713240089403e4a2ab34dfe4f`**.
- Release `/opt/kickbac/releases/games-1ed11da-20261018T004223Z`; archiveSHA256 `64dbbaead81e85071721cd0d89d8c2ef7d8344413214b0bf6b623f54aa85847a`;31 manifest entries verified. Runtime source/lock/migrations come from committed Git objects, not a dirty working tree. Isolated acceptance helpers are separately included/hashed, not production auth bypasses.
- Dedicated kickbac user, one uvicorn loopback worker behind trusted Caddy HTTPS; release-local hashed venv at `/opt/kickbac/current/venv`. Durable SQLite remains `/var/lib/kickbac/kickbac.sqlite3`; existing private environment/device credentials and sandbox preserved.
- Staged Ubuntu/Python3.12 runtime passed actual isolated game HTTP/streaming/owner/retry/restart/log-privacy, synthetic profile photo/save/load/removal/body-cap/restart and original simulator checks. Fixture records used private temporary DBs, never production identity/data.
- Production-copy schema3→4 migration, repeated initialize and exact old-table content comparison passed before activation. Actual update paused API/timer, took a verified exact pre-upgrade online snapshot, applied migration004, verified schema/integrity/all old row digests unchanged, switched release/runtime and restarted API/timer. All31 manifest entries were rechecked after activation.
- Upgrade preserved1 device and0 sessions/readings/profiles present at that checkpoint; no fake customer data or game results inserted into production. Readings saved by actual accepted tests will persist in the durable DB. This is not evidence that a real person's hardware test has occurred.
- API/Caddy/backup timer active; verified pre/post snapshots schema3/4, integrity and0600. Prior release remains intact, but schema3-only code **cannot** run over schema4: no blind symlink downgrade/automatic old-data restore.
- Public trustedHTTPS health200,17 operations; all14 previous operations and18 previous component schemas compared unchanged. New profile/game/stats missing-auth requests reject401; private profile/game/stats errors use no-store. Actual user-token/native acceptance remains separate.

## Published implementation

- [PR #3](https://github.com/spherohero/kickbac/pull/3): private name/sanitized-avatar profiles and existing per-person reading-history linkage regression.
- [PR #4](https://github.com/spherohero/kickbac/pull/4): Ubuntu release-local service/Caddy/snapshot artifacts and complete-current-schema backup fixture.
- [PR #5](https://github.com/spherohero/kickbac/pull/5): configured Auth0 Text/advisory PostLogin source,78 mocked fixtures and6 phone-identity cases; exact operator setup and embedded flow docs.
- [PR #6](https://github.com/spherohero/kickbac/pull/6): removed-key cache hardening,10 transport-mocked real PyJWKClient regressions; no Auth0 key-removal/network test claimed.
- [PR #7](https://github.com/spherohero/kickbac/pull/7): generic private game ledger/SQL stats, fixed10 participation points, schema004, strict JSON/body/privacy/concurrency/restart tests; profile/reading-history preservation.

## Executed local gates

- Games release: **336 combined backend/deployment tests** passed onPython3.12; Ruff lint and52-file format check, compilation and diff checks passed. Both independent spec and independent security/quality reviewers passed with no blocking findings.
- Final operator CLI follow-up: its two new tests first failed because the status message said schema3 while the actual DB was4. After reading the persisted version instead of hardcoding the text, **338 combined tests passed onPython3.11 andPython3.12**. Ruff lint/53-file formatting and compilation passed. This count includes that follow-up; its publication/runtime provenance is recorded separately below, not silently attributed to the earlier games commit.
- Real HTTP game result first201/retry200/conflict409/foreign404, streaming413/validation422, points10 exactly once, fresh-server/fresh-token history/profile/result restoration and log privacy passed. Existing simulator returned `SIMULATOR_OK`,COMPLETE,1 measurement,0 duplicates,foreign404,restartOK. Identities/readings/images are explicit fixtures, not real Auth0/iPhone/MQ-3 evidence.
-5 game JSON examples validated against actual models;17-operation API inventory matched generated OpenAPI. Runtime audit of22 locked packages returned0 known advisories at this checkpoint; no new game dependency.
- Source scans/staging allowlists excluded iOS, firmware, private operator paths and credential patterns. Original dirty/concurrent worktrees preserved; no force-push, branch deletion or client takeover.

## CLI follow-up provenance

The migration correctly persisted schema4; only the original CLI success text was stale. [PR #8](https://github.com/spherohero/kickbac/pull/8) queries `PRAGMA user_version` and reports the actual value for fresh/repeated initialization; independent review passed with both regressions reproduced RED then GREEN. The final current runtime above includes the fix, and actual target execution printed **Database initialized (schema 4)**. Its isolated game/profile/simulator checks, private production-copy repeated initialize, pre/post snapshots, all5 table row digests, running process path, public contract and31 manifest entries were verified again. No downgrade, lost rows or new migration was required for this follow-up.

## How to reproduce

From `backend/`, with no PYTHONPATH pointing at another worktree:

```bash
unset PYTHONPATH
uv run --locked --python 3.12 pytest -q tests ../deploy/ubuntu/tests
uv run --locked ruff check . ../deploy/ubuntu
uv run --locked ruff format --check . ../deploy/ubuntu
uv run --locked python -m compileall -q kickbac ../deploy/ubuntu
uv run --locked python -m kickbac.simulator
node --test auth0/test-twilio-verify.cjs
```

**GitHub CI is now published, merged and verified**, superseding the earlier missing-workflow-scope blocker. [PR #11](https://github.com/spherohero/kickbac/pull/11), exact head `35d98776cae433283fb276e9e4551ec38d8631e0`, merged as `e7af213036a29de75f9273af03f8219a6d12c1e6`; reviewed/remote merge trees matched. Successful [PR run](https://github.com/spherohero/kickbac/actions/runs/39085572064) and [merged-main run](https://github.com/spherohero/kickbac/actions/runs/39085675988) ran the Python3.11/3.12 matrix and Node22 Action fixtures. Logs confirmed338 tests for each Python version, Ruff53-file formatting, lint/compile, real-loopback `SIMULATOR_OK` and78 passing Auth0 fixtures. Immutable action revisions, read-only permissions and disabled checkout-credential persistence are versioned in `.github/workflows/backend.yml`. No SMS is sent by fixtures, and backend CI does not compile/verify Liam's iOS app or hardware. Initial local Action checks used Node24; CI now matches the hosted Node22 runtime.

## Remaining acceptance / limits

Liam owns real iPhone/Auth0 access-token/profile/photo/history/game/secure-storage and account-switching acceptance. Provider configuration is complete, not new-recipient delivery or real PostLogin feedback execution. No need to repeat Twilio compliance/setup/funding or create another service.

No full party/multiplayer/drawing/trivia engine, membership/count, public leaderboard, anti-cheat, account deletion/retention, off-host disaster recovery, OS reboot, Universal Links/native NFCQR launch or real sensor calibration is certified complete. The current store trusts authenticated client-reported completions and allows new-UUID submissions; no prize/currency trust claim. MQ-3 BAC remainsnull; no zero/no-trigger fabrication or safe-to-drive verdict. Firmware was not changed in this backend work.
