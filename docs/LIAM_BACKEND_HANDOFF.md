# kickBAC backend handoff — Liam / iOS agents

This replaces the older local/unpublished-profile handoff. **Backend profile, phone source, deployment, auth-cache fix and games are published and merged. Games are live.** Preserve Liam's actual local/unpublished SwiftUI work; no UI redesign, branch takeover or provider reprovisioning is requested.

### Integrated party/profile source — review checkpoint, not deployed

- Owner: backend Bot; integration `backend/party-profile-completion`, publishing
  `backend/party-profile-contract` in [PR #26](https://github.com/spherohero/kickbac/pull/26).
  Base remains main `dd19b404210517b1b0c8b8f8a1809ba988bb250d`; combined router/race
  checkpoint is `802f5c4`. Worker source is cherry-picked and parent-executed,
  not accepted solely from worker summaries. PR remains draft; no merge/deployment.
- **Additive / NON-BREAKING:** 31 local operations/schema5; all existing 17 public
  operations, 23 component schemas and security definitions pass the immutable
  compatibility fixture. Exact new methods/payloads/errors/examples are in
  [PARTIES.md](PARTIES.md); current production remains schema4/17 operations.
  Liam retains current UI and integration until deployment availability. No iOS
  or firmware source changes, production grants, user writes, SMS or arming.
- Implemented locally: host create/read/membership lifecycle; code/device join and
  persisted attempt limits; operator-granted binding and busy-session fences;
  host game instances; atomic own result/context with one award; rich all-game
  history; SQL reading summary. Parent combined Python 3.12 run passed **447 tests**
  including six actual loopback HTTP acceptance cases, Ruff lint/65-file formatting,
  compilation and the original simulator. Two further parent cross-app race tests
  passed (join limit; arm-before-rebind). Independent core/game review is in progress.
- NFC ARM-time authoritative context is still the next implementation, not proved
  by existing result-link history. Nicholas confirmed tap before measurement to
  arm for the specific user, then live app status. Initial app updates use session
  polling and accepted server completion, not fabricated or preaccepted results.
  Native entitlement/routing and truthful physical acquisition remain separate.
- Reproduce from `backend/` with `PYTHONPATH` unset:
  `uv run --locked --python 3.12 pytest -q tests ../deploy/ubuntu/tests integration/test_party_http.py`,
  `uv run --locked ruff check . ../deploy/ubuntu`,
  `uv run --locked ruff format --check . ../deploy/ubuntu`,
  `uv run --locked python -m compileall -q kickbac ../deploy/ubuntu`,
  `uv run --locked python -m kickbac.simulator`.
  New CI explicitly executes party HTTP acceptance rather than only collecting unit tests.

### NFC-first product priority — proposed check-in context

Nicholas clarified that the primary slice is host tap-to-link, then player tap
→ exclusive next measurement → correct person and party/game. Read
[NFC_CHECK_IN.md](NFC_CHECK_IN.md) before extending generic party/game work.
The sticker contains one static NDEF HTTPS device URI, for example
`https://api.kickbac.vodka/d/kb-demo-01`, never a user/party ID or secret.

**Additive / NON-BREAKING proposal, not implemented/deployed:** existing host
binding, authenticated join and legacy session/device endpoints are preserved.
A new candidate `POST /v1/parties/{party_id}/check-ins` with
`{check_in_id,device_id,game_instance_id}` would atomically snapshot party/game
context while creating the exclusive session; its response wraps the existing
session shape. Exact retry returns the original attempt even after completion.
This candidate requires contract freeze/tests before client adoption; it is not
already provided by game-result measurement linking. Existing physical device
poll/upload payloads remain unchanged and user/party ownership stays server-side.

Liam owns entitled foreground NFC and/or Universal Link delivery. Current owner
handoff records Personal Team NFC provisioning limits and no configured Universal
Links; writing the sticker alone does not make native launch work. QR/manual
fallback remains. The parent notified Nicholas before this proposal and asked
the firmware owner for current cadence/acquisition constraints; no claim of peer
acknowledgment, implemented native routing or physical uploads is made. Raw ADC
is not BAC; the unapproved duration proposal is not adopted by this change.

### Direct-chat implementation continuation — PR #26 still draft

- Nicholas moved party/profile implementation into the backend Bot's direct chat;
  the earlier group run is being stopped. Integration worktree is
  `kickbac-party-completion`, local branch `backend/party-profile-completion`,
  retaining all published ancestry through `ad495315840b21b66407da146547311078f57594`.
  The existing publication target remains [PR #26](https://github.com/spherohero/kickbac/pull/26)
  on `backend/party-profile-contract`, based on main `dd19b404210517b1b0c8b8f8a1809ba988bb250d`.
  Earlier dirty/untracked work, including the initial party-create RED test, is preserved.
- **NON-BREAKING; not deployed.** Same proposed methods, schemas and examples in
  [PARTIES.md](PARTIES.md); no change to auth, existing operation shapes, session
  behavior, firmware metadata, null BAC or fixed 10-point participation awards.
  Liam retains his current integration until actual release availability. No iOS
  or firmware source edits, production grants, SMS, user writes or device arming.
- Parent execution on foundation `73d66be`: Python 3.12 **372 backend/deployment
  tests passed**, Ruff lint and 56-file formatting passed; existing real-loopback
  simulator returned COMPLETE, one measurement, zero duplicates, foreign 404 and
  restart OK. Exact-head [PR CI](https://github.com/spherohero/kickbac/actions/runs/39101672443)
  was read back successful for Python 3.11/3.12, Auth0 fixtures and firmware decoder.
  These are foundation checks, not completed party API/native/physical acceptance.
- Party core and game/context/history implementations run in separate backend-owned
  worker worktrees. Independent migration/reading-summary review is also running.
  The real HTTP party lifecycle acceptance and additional chunked-body tests are
  currently RED at the missing party routes, as expected before implementation.
  Do not mark PR ready or merge until integrated source review, full tests, exact-head
  CI, immutable compatibility checks and updated canonical docs pass. Deployment
  and schema5 production migration remain separate backup/target-host gates.

### Additive reading summary — implemented foundation, not deployed

This slice is published in PR #26 as `73d66be` (cherry-picked from worker commit
`5008c7f`). The original worker-local checkpoint below is historical; the parent
has executed the combined 372-test foundation run recorded above.

- Owner: backend reading-summary worker, `backend/reading-summary`, base
  `d9aeb744663cc77a25a1012cf62c9d876b35c451`. Local commit only; no PR, push,
  merge or deployment. Parent owns integration and the wider party contract.
- **NON-BREAKING:** `GET /v1/me/reading-summary` adds exact lifetime owned SQL
  count and latest accepted measurement, independent of profile/history pages.
  Existing operations/models are unchanged. Optional client adoption only; keep
  errors unavailable, null BAC unavailable, and caches scoped to the validated subject.
- Bodyless authenticated GET; response example and semantics:
  [API.md](API.md#private-reading-summary). Private success and errors are no-store.
- Local Python 3.12 signed-token/simulator fixtures exercise empty totals, retries,
  receipt-time/ID ordering, ownership, profile edits, restart, expiry read-only
  behavior and private 401/500. Reproduce from `backend/` with
  `uv run --locked --python 3.12 pytest -q tests/test_reading_summary.py`.
  This is not live Auth0, iPhone, deployed API or physical sensor acceptance.

## Read first — agent sync and latest branch/change checkpoint

This is the shared catch-up entry point for Liam and his agent, not a request to redo completed integration. Before work, fetch without changing the active checkout:

```bash
git status --short --branch
git fetch origin --prune
git show origin/main:docs/LIAM_BACKEND_HANDOFF.md
git log -5 --oneline origin/main
git rev-parse origin/main
git branch -r
# liam/ios-profile-handoff was merged via PR #24 and retired; inspect current refs.
```

Read root `AGENTS.md` as well as Liam's `ios/AGENTS.md` when present on his branch. If main has not been integrated, read these shared docs directly from `origin/main`; do not reset, stash automatically, overwrite local edits or merge blindly. Documentation publication cannot prove an already-running remote agent has read it. Liam/his agent should report the main and client SHAs read when next giving a substantive integration update; no repeated acknowledgment pings or new user-run native tests are requested.

### Requested party/profile implementation — contract candidate, not live

- Owner: backend Bot, `backend/party-profile-contract`, base
  `dd19b404210517b1b0c8b8f8a1809ba988bb250d`. Nicholas authorized continuing
  implementation of the recorded profile/history and party create/join requirements.
- [Party contract candidate](PARTIES.md) specifies new authenticated create/code-or-
  device join/lifecycle/host-binding operations, game instances, one private completed
  result per user/instance, exact owned measurement links and rich all-game history.
  [Implementation plan](plans/party-profile-backend.md) orders test-first vertical
  slices. Both are designs until actual tested implementation/release evidence.
- **Additive / NON-BREAKING proposed:** all existing 17 routes, schemas, Auth0 access
  tokens, 60-second sessions, required duration, null BAC and 10 participation points
  remain unchanged. New reads: `GET /v1/me/reading-summary` (SQL count/latest accepted
  measurement), `GET /v1/me/game-history` (all own results, nullable party/placement/
  measurement context). Existing exact lifetime games/wins/points stay on `/v1/me/stats`.
- Examples: `POST /v1/parties` with `{"party_id":"<UUID>","name":"Friday"}`;
  `POST /v1/parties/join` with exactly one of `{"join_code":"ABCDEFGH"}` or
  `{"device_id":"kb-demo-01"}`. New game-result route accepts the original five
  fields plus optional owned `measurement_id` and nullable `placement`; canonical
  complete request/response/status/error examples are in the candidate, not live API.
- Liam: preserve existing app/UI; consume new fields only after published implementation
  and production availability. Join does not arm. Group by stable party UUID and use
  its server UTC creation date; legacy context/null BAC remain unavailable. QR/manual
  remains fallback; current Personal Team NFC capability/Universal Links are not fixed
  by a backend change. No action for firmware; device upload/polling remains identical.
- Security decision: public device ID/NFC is not ownership. Binding requires host role
  plus a backend-operator grant for that subject/device; no phone/device credentials
  sent to iOS. Join invitation locators do not prove physical presence. No production
  grant, user write, SMS, device arm, migration or deployment is authorized by publishing
  the design. New join limits are per-subject persisted10/60s, not global anti-abuse.
- Independent design/spec/security review approved test-first implementation at
  `d9aeb744663cc77a25a1012cf62c9d876b35c451`; firmware Bot separately reports no
  firmware-interface blocker (contract/source review, not endpoint execution).
  Clarified fixed join window, immutable cross-route UUID/context retries and the
  distinction between party-assignment grants and unchanged legacy arming rights.
- First source slice: additive schema5 migration, populated schema4 old-row/table-SQL
  preservation, repeated initialization, backup restoration, failed-upgrade rollback
  and new-table startup checks. Upgrade test observed RED (schema4 versus required5)
  before implementation, then GREEN. Local Python3.12 backend/deployment run returned
  **348 passed**, excluding the separate not-yet-implemented reading-summary RED
  test; Ruff lint and changed-file formatting passed. Feature PR remains draft;
  party/game endpoints, full integration/CI/native/target-host acceptance and runtime
  migration/deployment are not claimed complete. Summary is an independent test-first
  slice in a backend-owned worker worktree, not client work.

### Backend review of iOS PR #22 and requested profile/party follow-up

- Owner: backend Bot, isolated `review/ios-pr22`, live base
  `8dce54179366aaeff669525ef414e7f228d44e40`, Liam head
  `bba989d978b146b50335621039ab9949629e5f2c` ([PR #22](https://github.com/spherohero/kickbac/pull/22)).
  Nicholas requests review/ready merge and obsolete iOS branch cleanup. The only
  current integration conflict is this shared handoff; retain both the USB-only
  safety entry and Liam's integration/earlier-cleanup entries. App source remains
  byte-for-byte Liam's; backend/firmware runtime remains byte-for-byte live main.
- **MERGED and independently read back:** [PR #24](https://github.com/spherohero/kickbac/pull/24)
  merged as `734a82228e6a1c561005fa80e30caba99bd768fe`; GitHub also marks
  [PR #22](https://github.com/spherohero/kickbac/pull/22) **MERGED** by inclusion.
  Remote main's parents/ancestry and complete tree equality with reviewed head
  `f09781db7c456ee475dff1b34f74b49a4e37f66b` were verified. Liam's exact head remains
  an ancestor; the merged iOS tree is byte-for-byte his source. Parent inspection
  and two independent source reviews found no blocking auth/profile/privacy/device/
  session/game/provenance defect. **No backend deployment or physical/native
  acceptance was performed.** This docs-only closeout is owned by backend Bot on
  `docs/ios-merge-verification`; its publishing PR records its own merge state.
- Nonblocking follow-ups: Home daily Avg/Max use loaded pages (already owner-accepted);
  device online state is a lookup snapshot; history's “Test reading” simulator badge
  would be clearer as “Simulated reading”. No app source was changed for these notes.
- **NON-BREAKING:** existing endpoints, fields, payload examples, authentication,
  units, states, duration and participation-point policy are unchanged. Liam keeps
  ownership of the app and native acceptance; no source redesign is requested.
  See canonical examples below and [API.md](API.md).
- Current local checks on the combined tree: Python 3.12 **338** backend/deployment
  tests; Ruff lint/format (**54** files), compile and real-loopback simulator passed
  (COMPLETE, one measurement, zero duplicates, foreign 404, restart OK). Branding
  check and **78** non-sending Auth0 fixtures passed on Node 24.18.1. Windows has
  no Swift/Swiftc/Xcodebuild; Liam's reported signed Debug build/eight Swift checks
  are owner evidence, not independently reproduced here. Path-filtered iOS/docs
  changes do not trigger the existing backend/firmware workflows.
- [Profile and party requirements](PROFILE_PARTY_REQUIREMENTS.md) captures Nicholas's
  later scope: all saved readings including game-start tests, latest check, lifetime
  stats, party/date-grouped game rows with score/points, placement and exact owned
  measurement, plus create/join by host code or assigned-device NFC. It is not an
  implemented party engine or an adopted wire schema. Do not invent unavailable
  placement/BAC/party data or change the existing 10-point participation policy.
- Authorized cleanup completed only after exact remote-tip and main-ancestry checks:
  deleted remote `liam/ios-profile-handoff@bba989d978b146b50335621039ab9949629e5f2c`
  and backend-owned `review/ios-pr22@f09781db7c456ee475dff1b34f74b49a4e37f66b`
  in one ordinary atomic push; independent remote listing confirmed both absent.
  The reviewer branch was detached then safely deleted locally with `git branch -d`.
  Older `ios` and `feat/ios-setup` remote refs were already absent, not newly deleted
  here. Exact SHA/ref/worktree recovery inventory was retained privately. Firmware
  refs, unrelated docs branches, active peer worktrees and the backend startup
  worktree's dirty `AGENTS.md` were preserved. This follow-up branch is backend-owned
  and may be retired after its verified merge; no teammate worktree is removed.
- Reproduce from repository root: `python ios/checks/BrandingChecks.py` and
  `node --test backend/auth0/test-twilio-verify.cjs`; from `backend/`:
  `uv run --locked --python 3.12 pytest -q tests ../deploy/ubuntu/tests`,
  `uv run --locked ruff check . ../deploy/ubuntu`,
  `uv run --locked ruff format --check . ../deploy/ubuntu`,
  `uv run --locked python -m compileall -q kickbac ../deploy/ubuntu`,
  `uv run --locked python -m kickbac.simulator`. Native commands remain in
  `ios/README.md`; native/physical acceptance is not established by these checks.

### USB-C-only hardware revision — firmware owner

- Owner/branch/base: firmware Bot, `docs/usb-only-commissioning`, based on
  `22f06354e85ad04afe522e6d870b5bf3bb206af8`. The publishing PR/commits provide
  exact reviewed head and merge status; documentation publication is not hardware
  approval, deployment or native acceptance.
- Nicholas drops battery operation for this demo. New
  [USB-only commissioning guide](USB_ONLY_COMMISSIONING.md) provides the
  conditional single-cable VBUS schematic, keep/remove list, capacitor marking
  checks, illustrative current budget and required actual measurements. Older
  separate-supply/battery guides are marked superseded for current topology.
- **NON-BREAKING; no client action.** Existing methods, payloads, schemas, auth,
  states, units, examples and duration semantics in [API.md](API.md) are unchanged.
  No firmware runtime, backend or iOS source changes; no deployment or flash.
  USB supplies power/serial; API traffic still uses Wi-Fi. On reset/unplug the
  diagnostic loses RAM-only credentials and needs private operator provisioning.
  Do not infer battery-percentage support from the earlier battery proposal.
- Local verification passed: seven Markdown files, 49 relative link targets,
  balanced fences, `git diff --check`, divider/RC/current arithmetic and safety
  text assertions. Independent engineering/doc review passed for conditional
  documentation, not electrical approval. Its clarity suggestions were applied:
  explicitly historical old parts/revision text and maximum-bound divider testing.
  No sensor measurements, rated USB path, physical execution or app acceptance
  is established by these checks. ADC remains physically isolated; MCU+heater power path/current,
  capacitor identification and full-scale divider tests remain physical gates.
  Duration proposal remains unapproved; hardware completion/uploads stay disabled.
  Publication: [PR #23](https://github.com/spherohero/kickbac/pull/23), initial
  reviewed head `d3c58cb2b9528186157cc0efaf97eb26a4f62873` plus the focused
  review-clarification commit shown in that PR. PR state/merge commit are
  authoritative for subsequent merge status. No deployment.

### Authorized iOS branch cleanup — October 18, 2026

- Owner: Liam; explicitly requested deletion of local and remote `feat/ios-setup` and `ios`.
- Deleted local `feat/ios-setup@c5939d5` and `ios@7c87e09`, and their remote branches (`ios@88cd59c`). Before deletion, ancestry checks verified setup in `origin/main@22f0635` and both ios tips in `liam/ios-profile-handoff@3a7fa1c`. No commits were discarded.
- PR [#22](https://github.com/spherohero/kickbac/pull/22) remains open on `liam/ios-profile-handoff`; main was not merged. This documentation commit records the cleanup on the PR branch.
- **NON-BREAKING:** no client action; endpoints, schemas, payload examples and app behavior unchanged. Verification: Git ancestry checks, successful remote deletion and local safe branch deletion; no runtime tests needed. PR review/merge remains pending. Nicholas's branches were untouched.

### Liam iOS integration — current app and latest backend/docs

- Owner/branch: Liam, `liam/ios-profile-handoff`. App polish/game-history commit
  `4e31406`; latest-main integration commit `89e698c`; reviewed source head
  `550355c824852c5476e021bd6907273c2d6268dd`. Backend/docs base is
  `22f06354e85ad04afe522e6d870b5bf3bb206af8`. Publication is being prepared in
  the iOS integration PR; main is not merged or deployed by this work.
- Branch audit: `feat/ios-setup@c5939d5` is already an ancestor of main. Remote
  `ios@88cd59c` and local `ios@7c87e09` are ancestors of this integration branch.
  One PR includes all of that client work. No branches were deleted; no firmware
  branch was modified. Recheck remote heads before any later cleanup.
- **NON-BREAKING / existing contracts unchanged.** The client consumes native
  SMS auth, private profile/history, device/session state, stats and
  `GET /v1/me/game-results?limit=50&offset=0` with the API access token. See the
  canonical examples below and [API.md](API.md). No new path, payload, identity,
  timestamp, duration, unit, scoring rule or backend runtime change is introduced.
- App behavior: consistent `KickBAC` display/launch/Welcome branding; full-square
  camera/crop without the masked blur; approved Home gauge retained; profile
  header/settings simplified; reading statistics open history; game statistics
  open private Recent games; Cancel is hidden while sampling.
- Nicholas follow-ups: [account deletion](../ios/ACCOUNT_DELETION_HANDOFF.md) and
  [party groups/per-game check-ins](../ios/RECENT_GAMES_HANDOFF.md). These remain
  requests, not implemented backend functionality. Delete account is informational;
  missing party/check-in data is shown unavailable. Gameplay/submission stay separate.
- Review: no actionable documented-standard breaches or confirmed spec regressions.
  One inherited limitation remains by Liam's explicit choice: Home Avg/Max summarize
  loaded history pages; with over 50 real estimates today, loading more can alter
  those values. Track complete-day aggregation as follow-up while preserving Home.
- Verification: all eight iOS Swift check executables, branding checks and Auth0 SDK
  fixtures passed; signed Debug build with Xcode-beta passed using
  `/tmp/kickbac-profile-build`. Combined backend/deployment tests: **338 passed**;
  Ruff lint/format and isolated HTTP simulator passed. Auth0 Action fixtures:
  **78 passed**. Backend HTTP/actual C++ decoder fixtures: **2 passed**, with pinned
  ArduinoJson 6.21.6 headers. Local backend runtime was Python 3.14; Action runtime
  Node 26, separate from hosted Python 3.11/3.12 and Node 22 CI.
- Evidence limits: builds/fixtures are not visual, physical-sensor or live game-history
  acceptance. Liam reported login/profile working; that report is not an independent
  agent reproduction. No real SMS, account deletion, live game submission, backend
  deployment, or screen inspection was performed during integration review. Hosted
  backend/firmware workflows filter paths; an iOS/docs-only PR may have no CI jobs.

### Actual-app phone login troubleshooting

- Owner/branch/base: backend Bot, `docs/phone-login-troubleshooting`, based on
  `176f0620ee0e453ab31a76125b4908fab1cada90`. The publishing PR/commit records
  the exact reviewed documentation head and merge status; no runtime deployment.
- What/why: [PHONE_LOGIN.md](PHONE_LOGIN.md#run-the-actual-iphone-app-and-diagnose-login)
  now starts with actual Xcode/iPhone startup, installed-build checks and
  separate send/exchange/Keychain/API/profile troubleshooting. An Auth0 identity
  and an application profile are not the same checkpoint; no SQLite signup users
  table is expected. No private account records or diagnostic payloads are
  published in these docs.
- **NON-BREAKING / no app implementation action.** Existing paths, auth, audience,
  fields, states, units and examples are unchanged. Preserve both required profile
  PUT fields (`{"display_name":"Example","profile_picture":null}` clears a photo),
  the API **access token**, exact audience `https://kickbac-api`, and Auth0 phone
  ownership. No new backend OTP route or provider reprovisioning.
- Reviewed client input: `liam/ios-profile-handoff@170ad17a08f43232e8ca2ea3650999261b6e080b`,
  its README/review handoff, native AuthSession and SessionCredentialsStorage.
  The current source already includes the empty-Keychain deletion fix; an older
  installed app can still lack it. This is source inspection, not a reproduced
  current login failure, full client review, Xcode build or native acceptance.
- Verification: public HTTPS health readback and authorized read-only aggregate
  production DB inspection, without credentials/phone/images/row dumps; Markdown
  links and paths/config/source assertions checked. Local isolated checks:
  `cd backend && uv run --locked pytest -q tests/test_phone_identity.py tests/test_auth.py tests/test_profiles.py`
  returned **62 passed**; signed fixtures are not native acceptance. No SMS, account creation,
  session arming, profile write, provider setting or live data was changed.
  Follow-up remains Liam-owned: report installed build, failing stage, sanitized
  code/status and UTC time using the guide's non-secret template. Do not infer
  the cause or reassign completed integration from an older review.

### Documentation synchronization change

- Owner/branch: backend Bot, `docs/liam-agent-sync`, based on `307aa694098ee3922e9e7454ef58f4dccbac9b51`. The publishing PR provides this change's exact head and merge state; do not infer merge or deployment from a branch name.
- What/why: require this portable handoff for every backend/firmware/shared-contract change and branch operation so Liam's agent does not rely on group history or stale reviews. Entry points are root `AGENTS.md` and `README.md`.
- **NON-BREAKING.** No endpoint, payload, auth, identity, state, timestamp, unit, duration or scoring change. No app code action and no deployment. Existing examples below remain valid; this adds a read/sync step only.

### Verified upstream changes since the older iOS review

| Change | Published/merged evidence | Liam action and verification limit |
| --- | --- | --- |
| Backend HTTP to actual C++ firmware decoder tests | [PR #18](https://github.com/spherohero/kickbac/pull/18), head `4aebbfa`, merged `3771596c51de35bfc1fc2c38359939a59a68a676`; [exact merged-main CI](https://github.com/spherohero/kickbac/actions/runs/39092673467) read back successful | NON-BREAKING; no API/client changes. Reproduction/prerequisites: [FIRMWARE_WIRE_VERIFICATION.md](FIRMWARE_WIRE_VERIFICATION.md). Tests are real loopback HTTP plus the firmware decoder, not full ESP32 HTTPS execution, physical sensing or native acceptance. |
| Placement-only hardware correction | [PR #19](https://github.com/spherohero/kickbac/pull/19), merged `307aa694098ee3922e9e7454ef58f4dccbac9b51` | NON-BREAKING; parts are placed, not soldered/connected; no boost converter, pressure sensor or installed JP1. Software communication checks do not require assembly photos. Physical commissioning and truthful acquisition metadata remain separate. Docs-only, not a new runtime/CI result. |
| Scoped merged-branch cleanup | Remote refs read back: `main`, `liam/ios-profile-handoff`, `ios`, `feat/ios-setup`, `firmware/esp32-core`; no open PRs at this checkpoint | NON-BREAKING; Liam's branches were preserved. No code/runtime change or new merge-ready client claim. Use main/PR/commit links rather than deleted feature refs; fetch again because this inventory can change. |

### Newer Liam branch — do not reassign old findings blindly

Observed client tip: `liam/ios-profile-handoff@48f1744c3f499c1a333525919977c0b2eaf9c0d0`, after `be3fcbb` and backend integration merge `8f0d8fa`. Read its `ios/BACKEND_REVIEW_HANDOFF.md` and `ios/README.md` before assigning follow-up work. Those current owner documents describe connected QR/manual selection and session polling/cancel/recovery, real-account Home data, stats, coalesced profile loads and first-login empty-Keychain handling. Game-result submission/gameplay remain separate in that handoff; do not confuse stats consumption with implemented gameplay.

Those documents and commit identities were independently read, **not a full fresh source/contract review, Swift test run or native acceptance reproduction**. A dry-run `git merge-tree --write-tree origin/main origin/liam/ios-profile-handoff` succeeded against main `307aa69`; the old two-file conflicts were not reproduced at these tips. That is not merge approval and does not prove an Xcode/iPhone build. The older `2cc42da6` review and readiness document remain historical evidence, not current defect assignments. Refresh both refs before an actual merge/review; Liam's active branch and app remain untouched.

### Required entry for every subsequent change

The responsible backend/firmware owner updates this section in the same PR, even for NON-BREAKING work or branch-only cleanup; contract docs remain the single schema source, not a second divergent specification. Record:

1. Owner, branch, exact reviewed head/current base, PR, publication/merge SHA/state, and deployment state separately.
2. What/why; current versus proposed contract; BREAKING or NON-BREAKING; exactly what Liam must do, or explicitly **no action**.
3. Methods/paths, changed fields/types/states/units/errors and request/response examples; if none, explicitly say unchanged and link canonical examples.
4. Verification actually run, exact commands/evidence links, limits and remaining owner/gates. Never promote source/fixture/backend CI to native or physical acceptance.
5. Before material client-facing implementation/merge, notify Nicholas using `=== LIAM / iOS IMPACT ===`; firmware-driven changes also need `=== BACKEND CONTRACT CHANGE ===`. Keep proposals provisional until coordinated/tested.

After merging, update the entry with actual merge/deployment evidence as needed, and share its main/commit link in the room. Do not edit Liam's app, agent configuration or working branch to force discovery.

## === LIAM / iOS IMPACT ===

**Additive / NON-BREAKING:** existing14 operations and18 component schemas were compared unchanged against the live pre-games contract. Three new game/stats operations bring the API to17. `/v1/me` remains identity-only. Two existing error **messages** now use generic resource/payload wording; codes/statuses remain unchanged—branch on `error.code`, not English text.

The following sections describe the existing contract, not a list of missing client features. Preserve published profile/history/device/stats integration; refresh Liam's branch before proposing more work. Game result persistence uses the same validated Auth0 subject. Phone stays in Auth0. No Twilio SDK/secret, native client secret or device credential belongs in iOS. Do not invent missing party/leaderboard/measurement endpoints to fit mock screens.

Canonical references (same GitHub repository): [API](API.md), [profiles](PROFILES.md), [games/points](GAMES.md), [reading history](READING_HISTORY.md), [phone login](PHONE_LOGIN.md), [release verification](BACKEND_RELEASE_VERIFICATION.md). Live schema is authoritative for implemented wire shapes: https://api.kickbac.vodka/openapi.json .

## 1. Exact public settings

| Item | Value |
|---|---|
| API origin | `https://api.kickbac.vodka` |
| Auth0 domain | `dev-c87oxm4dkbyatvrn.us.auth0.com` |
| Issuer | `https://dev-c87oxm4dkbyatvrn.us.auth0.com/` |
| Native public client ID | `5gJK2T71UkL0fbVj9pbzzEzKeMWZoYlC` |
| Audience | **`https://kickbac-api`**, no trailing slash; NOT the deployment host |
| OTP connection/realm | `sms` |
| Initial scopes | `openid profile` |
| Bundle / scheme | `com.liam.KickBAC` |
| Callback/logout | `com.liam.KickBAC://dev-c87oxm4dkbyatvrn.us.auth0.com/ios/com.liam.KickBAC/callback` |
| Demo device/resolver | `kb-demo-01` / `https://api.kickbac.vodka/d/kb-demo-01` |

Keep cached profile/history/stats and pending completions scoped to the opaque authenticated subject. Clear/switch account caches on logout. Matching phone/display name does not link different Auth0 subjects.

## 2. Auth0 phone/code flow — configured, don't recreate

Primary SMS OTP, **not MFA**. Embedded requests go to Auth0, not kickBAC:

`POST https://dev-c87oxm4dkbyatvrn.us.auth0.com/passwordless/start`

```json
{"client_id":"5gJK2T71UkL0fbVj9pbzzEzKeMWZoYlC","connection":"sms","phone_number":"PHONE_IN_E164","send":"code"}
```

`POST https://dev-c87oxm4dkbyatvrn.us.auth0.com/oauth/token`

```json
{"grant_type":"http://auth0.com/oauth/grant-type/passwordless/otp","client_id":"5gJK2T71UkL0fbVj9pbzzEzKeMWZoYlC","username":"PHONE_IN_E164","otp":"USER_ENTERED_CODE","realm":"sms","audience":"https://kickbac-api","scope":"openid profile"}
```

Those phone/code strings are placeholders, not test destinations/codes. Preserve leading zeroes and the same normalized phone. Six-digit/180-second SMS setting, Native SMS assignment and Passwordless OTP grant are saved/read back. Hosted Authorization Code+PKCE remains supported; do not rewrite existing embedded screens to hosted-only login. Existing grants/connections are preserved; refresh-token issuance is not promised by initial scopes.

Auth0 validates login codes; Twilio delivers them. Separate Post Login Verify feedback is deployed/bound and advisory, not an authentication authority. Existing PRIMARY compliance is approved; no repeat setup, normal-user manual Twilio allowlisting, extra funding, Photon or optional rate-bucket work. Real new-recipient delivery/feedback execution after login remain unverified.

Store credentials securely in Keychain. Send **API access token**, never ID token/OTP/phone/device secret:

```http
GET /v1/me
Authorization: Bearer <API_ACCESS_TOKEN>
```

```json
{"user_id":"sms|opaque-example"}
```

Do not parse the subject or require a provider prefix/email. Auth0 responses have their own error format. Use deliberate user-driven sends/resends; no automatic SMS loops. Never log/share phones, codes or tokens. Provider configuration/SMS account evidence does not establish actual native API acceptance.

## 3. Onboarding: name + picture persistence

Authenticated `GET /v1/me/profile` returns200. A first profile has `user_id` plus null `display_name`, `profile_picture`, `created_at`, `updated_at`. GET does not create a record. API failure is **not** a blank/new account.

Authenticated `PUT /v1/me/profile`, `Content-Type: application/json`; **both keys required**:

```json
{"display_name":"Nicholas","profile_picture":null}
```

Photo object instead of null:

```json
{"content_type":"image/jpeg","data_base64":"CANONICAL_BASE64_OF_ACTUAL_IMAGE_BYTES"}
```

The photo snippet is structural only; placeholder bytes are not a valid upload. Real JPEG/PNG only. Convert HEIC/PhotosPicker files before sending, don't relabel their MIME. Name trims outer whitespace,1–80 codepoints; no control/surrogate characters. Decoded input<=524288bytes, Base64<=699052characters, input edge<=2048px, whole JSON<=1048576bytes including streaming. Output is metadata-stripped JPEG, longest edge<=512px. No avatar URL/multipart/public lookup.

Swift: optional encoding must emit explicit `profile_picture:null`, not omit it via `encodeIfPresent`. PUT replaces **both** fields; null clears a photo, not “leave unchanged.” Name-only edits must resend the current photo when retaining it. No owner/phone/timestamps/extra fields. Successful response returns normalized saved profile; creation time is retained, update time server-owned. Rejected writes leave old data intact; preserve pending form/photo on errors. Await save success before marking server onboarding complete; load after login/relaunch.

## 4. Private per-person reading history

`GET /v1/measurements?limit=50&offset=0` with the user token:

```json
{"items":[],"limit":50,"offset":0,"has_more":false}
```

Default50, allowed0–100, nonnegative offset; choose positive page size. Newest server receive time thenID descending; honor `has_more`, don't invent totals. Each accepted completed test persists independently by the session owner's verified subject—even **before** profile creation. Name/photo/game/point edits, same-account relogin and server restart do not reset it. Reconnect retries do not create extra tests.

Illustrative simulator item:

```json
{"id":"026af7c9-d605-4291-a1db-5b230e10ef43","session_id":"3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b","device_id":"kb-demo-01","raw":{"sensor":"mq3","value":1200,"unit":"adc_counts"},"breath_duration_ms":2500,"source":"simulator","measured_at":null,"received_at":"2026-10-17T23:00:05+00:00","estimated_bac_percent":null}
```

`estimated_bac_percent` is currently **always null**: render unavailable, not0.00. Raw ADC counts are not BAC; no client conversion or safe-to-drive verdict. Distinguish simulator/device. Acquisition `measured_at` may be null; `received_at` is server receipt time. No failed/no-trigger test is fabricated as zero; unsuccessful-attempt history isn't implemented. There is no `/v1/measurements/{id}` detail route; own session detail includes its result.

The pressure sensor is unavailable. Required duration metadata does not validate breath quality; no accepted DHT11/MQ threshold workaround proves a sober breath. Coordinate firmware-driven duration/quality changes with Nicholas before changing models/UX. iOS reads measurements, never submits device uploads or receives device credentials.

## 5. Generic game results + profile-wide points — live

`POST /v1/me/game-results`, same token; all five fields required:

```json
{"result_id":"2889d6a0-4719-4f23-a397-37c51d24129e","game_id":"trivia","score":8,"outcome":"win","data":{"correct_answers":8,"questions":10}}
```

Persist UUID **once** with the exact pending payload before sending; reuse after timeout/relaunch. First acceptance201, identical canonical retry200/original record, changed accepted fields409, another owner's UUID404. Never retry a conflict under a new UUID to manufacture points. Response adds `user_id`, `awarded_points:10`, `scoring_policy:"completion_v1"`, `source:"client_reported"` and server `created_at` to the five submitted fields.

- `game_id`: strict lowercase slug `^[a-z][a-z0-9_-]{0,63}$`; current UI examples Trivia/Pictionary. A stored slug is not an implemented engine.
- `score`: integer0–1000000, no boolean/string/float; game-specific raw score, **not** profile-wide award.
- `outcome`: `win|loss|draw|completed`.
- `data`: required object, `{}` allowed. Canonical UTF-8<=4096bytes; depth<=4 fromroot0, value nodes<=128 inclroot; keys1–64codepoints, arrays<=64items, strings<=512codepoints, finite numbers abs<=1e12. Whole POST<=32768bytes including streaming. See GAMES.md for exact validation/privacy.
- Server awards fixed10 participation points **once per unique saved completion**, independent of score/outcome/BAC. Client cannot submit owner/awardedpoints/total.
- These are authenticated **client-reported** outcomes, not verified gameplay/anti-cheat or currency/prizes. No manual “give points,” BAC/drinking/test rewards, public leaderboard or multiplayer/party backend.

`GET /v1/me/game-results?limit=50&offset=0&game_id=trivia` returns own paginated full result objects. Game filter optional; limit1–100/default50; offset>=0; newest created time/ID first. Auth errors are not an empty ledger.

`GET /v1/me/stats` supplies **separate** Me counters:

```json
{"user_id":"sms|opaque-example","total_points":10,"games_played":1,"wins":1,"per_game":[{"game_id":"trivia","total_points":10,"games_played":1,"wins":1,"best_score":8}]}
```

A real zero-result account has0totals/empty `per_game`. Error is unavailable, not zero. Wins count `win`; game count unique saved completions; totals derive from immutable ledger; per-game sortedID ascending, bestscore assumes higher isbetter. No `parties` count is returned: don't fabricate it. Profile GET/PUT remain unchanged. Private game/stats/profile responses/errors are no-store.

## 6. Existing device/session flow — unchanged

Public resolver `GET /d/kb-demo-01` returns `{"device_id":"kb-demo-01"}`. It's JSON, **not configured Universal Links**; doesn't arm/authenticate. Keep target through login, confirm then `POST /v1/devices/{device_id}/sessions` with `{}`. Don't forward tokens to arbitrary scanned origins.

User availability `GET /v1/devices/{device_id}`: state `AVAILABLE|ARMED|SAMPLING`; `online` separately uses30-second heartbeat freshness. Offline can be armed; don't equate arming with hardware readiness.

Arming201new/200sameownerretry, exclusive device,60-second server expiry; retry doesn't extend. Competing owner409device_busy. Poll own `GET /v1/sessions/{id}` aboutonce/second whileactive, stopon `COMPLETE|CANCELLED|EXPIRED`; otherstates `ARMED|SAMPLING`. Result is `measurement` whencomplete. Cancel `POST /v1/sessions/{id}/cancel` `{}`. Terminal session neverreusable; no silent rearm aftertimeout/conflict. Foreign/unknown IDs404. No WebSocket/SSE required; association doesn't prove who physically blew.

## 7. Errors and native acceptance

API error envelope: `{"error":{"code":"...","message":"..."}}`. Decode code, not exact message.401unauthorized/Bearerchallenge,404not_found,409device_busy/invalid_state/idempotency_conflict,410session_expired,413payload_too_large,422validation_error,503auth_unavailable,500internal_error. Handle transport/non-JSON errors too. Expired signing-key cache does not fall back to removed keys; temporary JWKS failure503 is not successful login or an absent account.

Liam owns actual Xcode/iPhone/authenticatedAPI acceptance. Verify real send/exchange→APIaccess token→profile save/photo/restore→same-subject history→game retry/stats/relaunch; account switching/privacy, invalid/expired/resendcodes, image/body errors, pending-result retries, deliberate device arming/expiry/polling. Keep existing UI/navigation and inspect localwork before editing. Report build/branch, sanitizedstage/code/time and pass/fail/notrun—no tokens/phones/images/OTPs.

Backend local/target fixtures, reviewed migration, protected public routes and healthy HTTPS are verified; **real native token/profile/history/game and real sensor acceptance are not**. Auth0 PostLogin feedback execution/new-recipient delivery remain separately unverified. Firmware/native NFCQR app launch/off-host recovery/OS reboot/calibration are not implemented by this release. GitHub CI is now published and merged in [PR #11](https://github.com/spherohero/kickbac/pull/11), with successful Python3.11/3.12 and Node22 checks on the [merged-main run](https://github.com/spherohero/kickbac/actions/runs/39085675988). This backend-only CI does not verify the iOS build. No additional accounts/paid services needed.
