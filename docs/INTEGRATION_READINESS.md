# Cross-team integration readiness

## Scope and verified source checkpoint

Backend-owned continuation on `docs/integration-readiness`, based on remote main
`b84b3bc7ced9fbdaab894d80566d970fef1fc7b6` (PR #14). This is a verification and
handoff correction, not a runtime release or approval of new sensor semantics.
Existing dirty worktrees were preserved; no iOS or firmware files were edited.
Refresh remote state before using this checkpoint as merge evidence.

At discovery, GitHub returned no open PRs. Already-merged backend and diagnostic
firmware branches are not pending implementation. Liam's published branch
`liam/ios-profile-handoff` remains at
`2cc42da6b6ae41284b12790d100af10c5a095592`; it is not merged.

## Freshly executed backend verification

Executed from this branch's isolated `backend/` directory with `PYTHONPATH`
unset, locked dependencies and the imported app path confirmed in this checkout:

- Python 3.12.5: **338 backend/deployment tests passed**.
- Python 3.11.15 in a separate `.venv311`: **338 tests passed**.
- Ruff lint, 53-file format check and compilation passed on Python 3.12.
- Explicit real-loopback simulator: `SIMULATOR_OK`, session `COMPLETE`, one
  measurement, zero duplicates, foreign-owner 404 and restart `ok`.
- Node 24.18.1: **78 mocked Auth0 Action fixtures passed**; no SMS sends. This
  local run is not the hosted Node 22 runtime or actual Post Login execution.
- Trusted public `GET https://api.kickbac.vodka/health`: 200, `{"status":"ok"}`.
- Live OpenAPI compared **exactly equal** to `create_app().openapi()` from this
  checkout, with 17 operations. This does not inspect the production database or
  establish native/user-token acceptance.
- Missing-auth GET/PUT profile, GET measurements, GET/POST game results and GET
  stats all returned 401 with `error.code: unauthorized`. Profile/game/stats
  errors carried `Cache-Control: no-store`; the history 401 did not. No new
  cache-header guarantee is asserted for history errors.

Existing [merged-main backend CI](https://github.com/spherohero/kickbac/actions/runs/39085675988)
was independently read back as successful at exact SHA
`e7af213036a29de75f9273af03f8219a6d12c1e6`, including Python 3.11/3.12 and Node
22 jobs. `backend/`, `deploy/` and `.github/workflows/backend.yml` are unchanged
between that tested SHA and the base above. A docs-only PR is excluded by the
workflow's path filters: no new check is not a new CI pass. No deployment,
production fixture insertion, device arming, provider setup or SMS was performed.

## Owner handoffs and merge gates

| Owner | Current evidence | Exact next step / merge gate |
| --- | --- | --- |
| Backend Bot | Fresh local tests and public read-only contract comparison above | Review coordinated producer changes against this API; test retry/expiry/ownership and persisted legacy compatibility before a runtime PR. No backend auth/profile rebuild is needed. |
| ESP32 Bot (`@esp32-hardware-integration-engineer`) | Diagnostic foundation already merged in PR #10; physical evidence is recorded in `DEVICE_CONNECTIVITY.md`, not rerun here | Publish the next focused branch/PR with current physical evidence and exact acquisition payload/meaning. Sensor electrical sign-off and truthful duration remain gates; keep unapproved sampling/uploads disabled. |
| Liam | Published native auth/profile/history implementation; current API helper, Home fixtures, profile-load guard and public config re-read at the SHA above | Owner resolves current merge conflicts in `ios/KickBAC/Auth0.plist` and `ios/README.md`, preserving API base and exact audience. Address Home's unlabelled fixture BAC, integrate device/session then games/stats, and run current native acceptance. Backend Bot does not edit or merge an unfinished client. |
| Nicholas + Liam coordination | Manual/timed acquisition is still an unapproved breaking proposal | Make an explicit contract decision before implementing nullable duration/acquisition metadata; broad permission to continue Git workflow does not approve that proposal. |

`git merge-tree --write-tree origin/main origin/liam/ios-profile-handoff` against
the base above reconfirmed those two client conflicts. This was a dry-run only.
The possible concurrent profile-load race remains source-traced, not a reproduced
native failure. See [full iOS review](bots/backend/IOS_REVIEW.md).

### === LIAM / iOS IMPACT ===

**NON-BREAKING: documentation/status correction only.** No endpoint, request,
response, auth, state, timestamp, unit, point policy or runtime behavior changes.
Liam already has profile save/load/editing and private history in source; do not
assign those again as missing implementations. Preserve `PUT /v1/me/profile`
full replacement, including explicit `{"display_name":"Nicholas","profile_picture":null}`
for photo removal. Device/session and game examples remain in
[the current handoff](LIAM_BACKEND_HANDOFF.md). Native tests remain Liam-owned;
backend tests and public unauthenticated probes are not substitutes.

### Unchanged acquisition gate

[The duration proposal](FIRMWARE_DURATION_PROPOSAL.md) remains **UNAPPROVED / NOT
IMPLEMENTED / BREAKING**. Live `POST /v1/device/measurements` still requires an
integer `breath_duration_ms` in 1..60000; responses use an integer too. Liam's
current `APIMeasurement.breathDurationMS` is a nonoptional `Int`, so switching to
null would break decoding. A manual acquisition window or MQ threshold duration
must not be relabelled breath duration. Do not submit the proposed
`acquisition_method` / `sample_duration_ms` fields to the unchanged server.

The ESP32 Bot should hand off measured acquisition facts and desired semantics;
backend changes require both `=== BACKEND CONTRACT CHANGE ===` and
`=== LIAM / iOS IMPACT ===` notices before implementation/merge. Coordinate
legacy rows/replays, schema migration, simulator, tests and client decoding.
Null BAC remains unavailable, raw ADC is not BAC, and no-trigger is not zero.

## Exact local reproduction

Run from the intended checkout's `backend/` directory (Git Bash on Windows):

```bash
unset PYTHONPATH
uv sync --locked --python 3.12
uv run --locked python -c 'import kickbac.app; print(kickbac.app.__file__)'
uv run --locked pytest -q tests ../deploy/ubuntu/tests
uv run --locked ruff check . ../deploy/ubuntu
uv run --locked ruff format --check . ../deploy/ubuntu
uv run --locked python -m compileall -q kickbac ../deploy/ubuntu
uv run --locked python -m kickbac.simulator
node --test auth0/test-twilio-verify.cjs
UV_PROJECT_ENVIRONMENT=.venv311 uv sync --locked --python 3.11
UV_PROJECT_ENVIRONMENT=.venv311 uv run --locked pytest -q tests ../deploy/ubuntu/tests
uv run --locked python -c 'import json, urllib.request; from kickbac.app import create_app; live=json.load(urllib.request.urlopen("https://api.kickbac.vodka/openapi.json", timeout=30)); assert live == create_app().openapi(); print("LIVE_LOCAL_OPENAPI_EXACT_MATCH")'
```

Use only owned focused branches and exact-head/current-base review. Preserve
other owners' branches and dirty worktrees; do not treat branch cleanup as
permission to erase unmerged history. A GitHub merge is not deployment. Actual
native-token/profile/history/game acceptance, real post-login feedback and
physical sensor/session upload acceptance remain separate and unverified here.
