# Backend Bot startup — current kickBAC handoff

Snapshot prepared after backend/CI delivery and Liam's source review, with remote main `016d5b8a4c43d0f8a599f7e75303262de9b09db9` (firmware diagnostic PR10 subsequently included; no backend contract change). These are dated checkpoints, not evidence of the environment on your next launch. Fetch/reinspect before work. This is the backend role's handoff, not firmware instructions.

## Latest ownership direction

Nicholas returned remaining app work/control to Liam after the temporary cutoff
extension. Backend stopped its client worker and verified no review fix or push
was completed. PR32 stays draft/unmerged, local main-sync commit3600a57 is clean
and preserved, original Liam ref untouched. Exact heads and three unresolved SPEC
findings are in [the shared handoff](../../LIAM_BACKEND_HANDOFF.md). Do not resume
iOS takeover from the historical04:00 extension below. Backend-only host evidence
is in [HOST_TLS_INVESTIGATION.md](../../HOST_TLS_INVESTIGATION.md); no TLS/firewall/
logging change or new private provisioning was performed.

## Current release superseding the startup snapshot

Read [release verification](../../BACKEND_RELEASE_VERIFICATION.md) and the latest
[shared client handoff](../../LIAM_BACKEND_HANDOFF.md) before the historical
checkpoint below. The existing host is now on schema6/33 operations from immutable
`172e54c1604356e3e83db2fc0672706829841795` (PR30 mergec78a042), activated
2026-10-18T07:55:20UTC. Retained backup, production-copy4→6 preservation,56 target
tests, runtime simulator, exact PR/main backend+native CI and external exact-source
OpenAPI readback passed. No production user/arm/reading inserted. Actual phone
acceptance and protected physical acquisition remain unverified. Firmware's latest
reconnect failed, superseding earlier bounded online evidence; check current
DEVICE_SESSION_VERIFICATION rather than reporting permanent connectivity.
Nicholas subsequently lifted the04:00 client cutoff for necessary iOS work in
isolated branches; preserve Liam's original worktree/ref/designs. PR32 preserves
his latest preview plus compatible main; native CIgreen is not merge approval.
This is continuity documentation, not a new request to redeploy or restart work.

## 1. Identity, ownership and first reads

- Nicholas Reyes owns kickBAC, a 36-hour UF SwampHacks prototype. Display brand **kickBAC**, folders/packages `kickbac`.
- This Bot owns the backend, webserver/API, database, auth/service integration, hosting and shared contract. The separate ESP32 Bot owns physical/firmware work. Liam owns SwiftUI. Do not take over either workstream.
- Repository: https://github.com/spherohero/kickbac . Intended isolated local worktree: `C:/Users/nicho/Desktop/SwampHacks26/kickbac-backend-bot`.
- Read `AGENTS.md`, `docs/PROJECT_BRIEF.md` (original brief; preserve verbatim), `docs/API.md`, `docs/LIAM_BACKEND_HANDOFF.md`, `docs/BACKEND_RELEASE_VERIFICATION.md`, and this directory's `IOS_REVIEW.md`. Load relevant project/API/backend/GitHub/testing skills and `swamphacks-planning` references if present in this Bot's own profile.
- The original brief's FIRST TASK and older provider/deployment blockers are history, not a new implementation request. Do not restart them. Repository/project guidance does not itself request autonomous work beyond Nicholas's current instruction.
- SOUL template and creation fields are adjacent; a repository SOUL is not automatically active. Hermes loads SOUL only from the owning Bot's profile home. If cwd is wrong, explicitly read the project files rather than assuming inherited context. Do not modify other profiles.

## 2. What is already delivered

The backend is published, reviewed, merged and live at **https://api.kickbac.vodka**, with trusted public HTTPS, **17 API operations** and persistent **SQLite schema4** at the last verified checkpoint.

- Python FastAPI REST/JSON server, stable IDs, ISO8601 timestamps, consistent errors, owner isolation and explicit database migrations.
- RS256 Auth0 API access-token validation; bounded JWKS-set trust/cache and transport failure behavior. User identity is verified opaque `sub`, not phone/display name or a client-selected user ID.
- Approved primary login: **phone + SMS one-time code**, not SMS MFA. Auth0 handles identity/OTP; Twilio delivers messages. Native client uses public configuration, not a client secret or Twilio credentials.
- Phone belongs to the Auth0 SMS account. Private SQLite profile stores display name and a bounded, sanitized photo by the same verified subject. `/v1/me` remains identity-only.
- Expiring exclusive device associations, server-owned sessions, correct-user results, retry-safe device uploads, privacy and restart persistence. NFC/QR identifies a unit; explicit authenticated confirmation arms it. Association cannot prove who physically supplied a breath.
- Per-person history persists every accepted completed measurement, including before profile creation. Profile/name/photo edits, game submissions, relogin and restart do not reset it. No duplicate history table or invented failed-attempt/zero reading.
- Generic private client-reported game ledger and SQL-derived profile/per-game stats. Fixed **10 participation points once per unique completion**, never rewards for BAC/drinking/testing. Not multiplayer, anti-cheat, a party engine/count, public leaderboard or currency.
- Existing authorized VM, HTTPS reverse proxy, service isolation, persistent SQLite, verified online backups and immutable release manifests. No new host or paid add-on is needed.
- Backend GitHub CI is published/merged and remotely verified, not merely prepared locally. No missing workflow-scope setup remains.

## 3. Exact public/auth configuration and client contract

- API base: `https://api.kickbac.vodka`.
- Auth0 domain: `dev-c87oxm4dkbyatvrn.us.auth0.com`.
- Issuer: `https://dev-c87oxm4dkbyatvrn.us.auth0.com/`.
- Audience: **`https://kickbac-api`**, no trailing slash. It is a logical identifier, not the deployment hostname.
- Native public client/bundle/SDK settings: read Liam's current published configuration/`docs/PHONE_LOGIN.md`; do not guess or introduce a native client secret. API calls use an **access token**, not ID token/OTP/phone.

Primary routes (complete operation inventory in API/OpenAPI):

| Contract | Existing behavior |
|---|---|
| `GET /v1/me` | validated subject only |
| `GET /v1/me/profile` | own name/photo; null fields for absent profile, not automatic insert |
| `PUT /v1/me/profile` | full replacement; both `display_name` and `profile_picture` required; explicit null clears photo |
| `GET /v1/measurements?limit=50&offset=0` | private persisted history; honor `has_more`, no invented total/detail endpoint |
| `POST/GET /v1/me/game-results` | private idempotent ledger; persist UUID/exact payload across retry/relaunch |
| `GET /v1/me/stats` | points/games/wins/per-game aggregates; error is unavailable, not zero |
| `GET /d/{device_id}` | public JSON resolver; no auth/arming/automatic Universal Links |
| `GET /v1/devices/{device_id}` | authenticated availability and separate online freshness |
| `POST /v1/devices/{device_id}/sessions` | `{}`; new201 / same-owner retry200; retry does not extend expiry |
| `GET /v1/sessions/{session_id}` | owner-only session/optional completed measurement |
| `POST /v1/sessions/{session_id}/cancel` | `{}`; owner-only terminal rules |

Profile name is bounded to80 codepoints; canonical JPEG/PNG input <=512KiB decoded, input dimensions bounded, metadata removed and JPEG normalized <=512px. Full streamed profile request cap1MiB. Read `docs/PROFILES.md` for exact validation and replacement/clear semantics; do not infer omitted-photo semantics.

Game writes require `result_id`, `game_id`, `score`, `outcome`, `data`. First acceptance201; identical canonical replay200 preserving original award/time; changed accepted payload409; foreign result UUID404. Client never chooses owner or awarded points. Exact body/JSON bounds in `docs/GAMES.md`.

Session states are `ARMED`, `SAMPLING`, `COMPLETE`, `CANCELLED`, `EXPIRED`; terminal sessions do not reactivate. Current expiry60 seconds; online freshness30 seconds. Poll own session about once/second with backoff and stop at terminal state. An offline unit can be armed: arming is not proof of device readiness. Device credentials stay out of phones/NFC/QR and group messages.

Measurements distinguish raw value/unit, source, nullable acquisition time, server receipt time and nullable estimate. **`estimated_bac_percent` is currently null; render unavailable, not0.00.** Raw ADC is not BAC. Do not promise a nonexistent `GET /v1/measurements/{id}`. This handoff does not authorize changing required duration/quality metadata or inventing physical evidence.

## 4. Production and tested release checkpoint

- Existing Ubuntu24.04 host `144.202.38.243`, dedicated service user, Caddy TLS and one Uvicorn worker on loopback127.0.0.1:8000. Cloudflare Free DNS/public delegation already works; preserve unrelated records. No duplicate provisioning.
- Current verified release: `/opt/kickbac/releases/games-1e9d830-20261018T005743Z`; `/opt/kickbac/current` symlink; runtime source `1e9d83070cf4096283246078cb9a9193519a13ec`.
- Current interpreter `/opt/kickbac/current/venv/bin/python`; release-local locked/hashed dependencies. Do not run an old shared venv merely because a historical runbook mentions it.
- Persistent DB `/var/lib/kickbac/kickbac.sqlite3`, schema4/integrity and private modes verified; daily online backup timer active. No OS-reboot or off-host recovery proof is claimed.
- Backed-up schema3→4 migration/private-copy checks preserved existing rows.31 manifest entries, published-main runtime parity, actual process cwd, public protected routes and no-store behavior checked. No production fixtures inserted.
- SSH/deployment/environment/device credential material is private. Use the existing authorized mechanism and sanitized diagnostics; do not read/print populated environment files or private key/token contents, request secrets in chat or rotate resources just to rediscover them.
- A GitHub merge is not deployment. New runtime releases require current-base tests/review, backup/migration preflight, immutable committed content, actual target startup/public checks and readback; do not deploy an older schema2/3-only base over schema4.

## 5. Verification that actually ran

- **338 combined backend/deployment tests on each of Python3.11 and3.12**, Ruff lint/53-file formatting, compile and real-loopback simulator/restart/ownership/retry checks passed.22 runtime packages audited, zero reported known advisories at that checkpoint—not a permanent guarantee.
- **78 mocked Auth0 Action fixtures**, no SMS sends; GitHub Node22 matches the hosted runtime.
- CI PR11 head `35d98776cae433283fb276e9e4551ec38d8631e0`, merge `e7af213036a29de75f9273af03f8219a6d12c1e6`. Branch/PR/main runs passed; merged-main evidence: https://github.com/spherohero/kickbac/actions/runs/39085675988 . Status docs PR12 subsequently merged. These are exact historical runs, not a claim every newer commit triggered CI.
- Backend/workflow files were unchanged by the subsequently merged firmware diagnostic PR10. Neither backend CI nor firmware host/cross-build CI establishes actual native/hardware sample acceptance.
- Independent spec/quality/security reviews and target-host isolated HTTP/profile/game/simulator/privacy checks passed. Synthetic signing keys/identities are fixtures, not a real Auth0/native token demonstration.
- Source contracts, real HTTPS and configured auth are verified; **actual iPhone SMS → API access-token → profile/history/game acceptance remains unverified and Liam-owned**. Real post-login feedback execution/new-unlisted-recipient delivery also remain unverified.

Commands from the repository root (inspect the manifest/lock and your actual toolchain first):

```bash
cd backend
unset PYTHONPATH
uv sync --locked --python 3.12
uv run pytest -q tests ../deploy/ubuntu/tests
uv run ruff check . ../deploy/ubuntu
uv run ruff format --check . ../deploy/ubuntu
uv run python -m compileall -q kickbac ../deploy/ubuntu
uv run python -m kickbac.simulator
node --test auth0/test-twilio-verify.cjs
```

Run backend subprocess tests from `backend/`; inherited `PYTHONPATH` can silently import a sibling worktree. Never use a test command from another checkout as evidence for this one. The installed Python/pip may differ; use the manifest's supported interpreter/uv rather than assuming `python3` exists on Windows.

## 6. Liam's current published progress and remaining work

**Read [the latest shared handoff](../../LIAM_BACKEND_HANDOFF.md#read-first--agent-sync-and-latest-branchchange-checkpoint) first.** The findings/actions in this section are the historical `2cc42da6` checkpoint, not current missing-feature assignments. Liam's newer owner documents describe device/session, stats, Home-data, profile-load and Keychain follow-ups; refresh/read his actual branch before reviewing or assigning work. The old conflicts were not reproduced by the main `307aa69` / client `48f1744` merge-tree dry-run. No current native acceptance or complete new source review is claimed. Every subsequent shared change/merge/cleanup must update the portable Liam handoff in the same PR and report actual merge/deployment state separately.

Read `IOS_REVIEW.md` and refresh his remote tip before assigning work. Reviewed `liam/ios-profile-handoff@2cc42da6b6ae41284b12790d100af10c5a095592`;69 changed iOS-only files. Native auth, server profile save/load/edit/photo removal, subject-specific cache and private paginated history are already wired in source. No blocking auth/profile wire-contract defect or new profile endpoint was identified. Birthday remains local UI, not an extra backend onboarding field.

Remaining client actions, without taking over his app:

1. **High priority:** Home unconditionally seeds fixture BAC and displays Avg/Max even in Release; timed demo injects0.08. Fix/remove unlabelled data or keep an explicit continuous simulated-demo mode, including accessibility. Private history already handles null/raw data correctly.
2. Connect trusted device targeting, deliberate arming, server-driven polling/cancel/completion/history. Local timed Home phases are not device evidence; NFC/QR/Universal Links are not already integrated.
3. Consume existing game-results/stats APIs, persist pending UUID/payload account-scoped across retries/relaunch, use server awards. Party is currently blank; do not invent a party count/engine.
4. Small possible concurrent-profile-load false onboarding failure, plus loaded-count/acquisition-versus-receipt chronology wording; see source references in the review.
5. Reconcile integration conflicts in `ios/KickBAC/Auth0.plist` and `ios/README.md`, preserving APIBaseURL/exact audience. Liam's older handoff asking to publish local backend source is stale; backend is on main/live.

No Swift/swiftc/Xcode toolchain was available in this Windows review. Liam reports prior simulator/fixture passes, not independently reproduced current native acceptance. Liam owns current integrated Xcode/iPhone SMS/token/photo/relaunch/relogin/offline/retry/account-isolation checks. Nicholas explicitly delegated those tests; do not turn Bot startup into another user-run login session.

## 7. Closed setup and spending boundaries

- Twilio individual PRIMARY compliance approval independently verified; prior team SMS delivery verified. Do not recreate compliance, re-register ordinary app users as Twilio recipients, top up further or enable auto-recharge/paid add-ons. Existing spending authorization covered only the already-added$20.
- Auth0 Native SMS connection/Passwordless OTP grant and separate Post Login feedback Action source/deployment/binding/secret names verified. No setup redo is pending. Configuration does not prove real feedback execution after successful native login.
- Historical exposed Twilio credential was rotated/promoted; never revive or reproduce it. No secret is included in this package.
- Photon was abandoned: no retries, support/provisioning or adapter work. Custom Verify rate-limit provisioning was explicitly waived; do not resume it. Keep existing provider protections; do not invent a hard spending cap.
- Public DNS/TLS/API are delivered. A stale timeout or workflow-scope note is not a current blocker. Recheck actual failure before asking Nicholas to repeat setup.

## 8. Group coordination and change gate

Use the actual firmware Bot handle once Nicholas creates it; do not invent a recipient/tool or edit the peer profile. The group does not itself synchronize files, tools, skills or credentials. Each Bot owns its worktree; do not share a mutable working directory. Share requests/results, not secrets.

A useful message names: **request or finding; owner; branch/commit/PR; current versus proposed contract; evidence and verification level; specific next action/acknowledgment**. Do not create acknowledgment loops, repeated polling chatter or unrequested autonomous routines.

Before a material iOS-facing decision/change, post `=== LIAM / iOS IMPACT ===` with what/why/exact client actions/endpoints/schema/examples and BREAKING or NON-BREAKING. Firmware-driven contract changes also require `=== BACKEND CONTRACT CHANGE ===` before code/merge. Inform Nicholas so Liam can coordinate; agreement between two Bots is not a substitute for the client-impact notice.

Nicholas delegates routine owned commits/pushes/ready merges. Use current-base focused branches; never develop on main, force-push, rewrite history, bypass protection, discard dirty work, take over/delete teammate branches, or merge unfinished work. Verify remote SHAs, exact reviewed heads, combined trees, tests/CI and actual merge/deployment readback. Preserve original brief and unrelated pending changes. Figma is strictly read-only.

## 9. First-turn acceptance and next scope

First turn should report what you actually read/verified: worktree/branch/current remote main; live health/OpenAPI; existing backend capability; Liam's latest source status; remaining acceptance and real blockers. Use safe public reads only unless current work requires more. Do not create users, arm sessions, send SMS, rotate credentials, deploy or start implementation simply to introduce yourself.

After orientation, act on Nicholas's current request or a concrete coordinated integration issue. Existing auth/profile API needs no rebuild. Backend-owned next checks are actual post-login feedback after Liam's consenting successful login, shared correct-device/session acceptance and any explicitly coordinated API implications. Physical implementation stays with the other Bot; technical detail belongs in its own handoff.

Workspace-local supplemental evidence, when available under `C:/Users/nicho/Desktop/SwampHacks26/.project`: `BACKEND_FINAL_CHECKPOINT.md`, `BACKEND_CI_VERIFICATION.json`, `GAMES_DEPLOYMENT.json`, `LIVE_BACKEND_STATUS.json`, `LIAM_BRANCH_REVIEW_EVIDENCE.json`, `TWILIO_COMPLIANCE_APPROVAL.json`. These are snapshots, not automatically present in a clone or proof of newer state. Portable published docs are the shared baseline.
