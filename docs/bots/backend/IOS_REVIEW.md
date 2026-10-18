# Liam iOS integration review — 2cc42da6

## Scope and verdict

Reviewed published `liam/ios-profile-handoff` at `2cc42da6b6ae41284b12790d100af10c5a095592`, independently reconfirmed as the remote tip. Current remote main at final readback: `672c6a2bce2490c414d8aebd778bfb724783190a`. Parent source/contract inspection and two independent read-only reviews agreed. No iOS files edited, commits made to Liam's branch, SMS sent, or native merge performed.

**Auth/profile/history are substantially implemented and compatible with the current backend. No blocking auth/profile wire-contract defect or additional profile API was identified. The app is not yet a connected hardware demo: Home still presents fixture BAC and has no server-driven device/session flow.**

Branch inventory: 69 changed files, all under `ios/`. This includes onboarding/auth/profile/Home/camera/UI/assets and checks, not backend/firmware changes. Backend sources and current contracts are already published and deployed; Liam's request to publish the previously local profile backend is now stale.

## Already implemented in source

- Embedded Auth0 SMS OTP through Auth0.swift, exact audience `https://kickbac-api`, API base `https://api.kickbac.vodka`, claims validation and SDK Keychain credential storage: `ios/KickBAC/AuthSession.swift:66–123`.
- Profile GET after login/restoration, awaiting successful server save before onboarding/editor dismissal, missing profile distinct from load failure: `ContentView.swift:43–57`, `OnboardingView.swift:587–609`, `ProfileEditorView.swift:130–141`.
- Full-replacement profile PUT with both required fields, explicit photo null, no submitted owner or phone; name-only edits preserve sanitized photo bytes: `KickBACAPI.swift:22–32,116–121`, `ProfileStore.swift:72–97`.
- Subject-specific cache, owner validation and account-generation guards: `ProfileStore.swift:34–68,100–121`, `AuthSession.swift:140–158`.
- Authenticated identity/history, pagination/deduplication, retry and private-data clearing: `AuthSession.swift:173–215`.
- Private history correctly displays null BAC as “No BAC estimate” plus raw reading, labels simulator rows “Test reading”: `ProfileHistoryView.swift:98–107,128–133`.
- Birthday remains local UI state; it is not an extra persisted backend onboarding field. No backend expansion is proposed.

## Prioritized findings and owner actions

### P1 — Home exposes unlabelled synthetic BAC, including Release (Liam)

`HomeView.swift:10–11` seeds sample readings `0.04`, `0.05`, `0.09` unconditionally; lines58/67 render Avg/Max BAC. `#if DEBUG` only hides the controls (32–49), not the fixtures/metrics. Demo completion injects `0.08` (294–298). Accessibility reports grams/deciliter and an impairment category (323–325).

Before using the screen as a real-device demo, remove fixtures from ordinary Home or isolate them in a continuously visible simulated-demo mode, including accessibility. Ordinary unavailable data must not appear as BAC. Do not convert raw ADC into `BACReading` or imply MQ-3 calibration. The private-history screen already handles null/raw data correctly; this issue is specifically Home. No explicit safe-to-drive claim was found; the defect is unsupported/synthetic BAC presented without an adequate in-app label.

### P1 integration gap — device flow is local animation only (Liam, coordinated with Nicholas)

`ContentView.swift:22–24` creates Home without an auth/session object. `HomeView.swift:251–269` says “Tap the breathalyzer” but has only a future-NFC comment; lines277–305 progress by local timers. API methods at `KickBACAPI.swift:108–130` cover identity, profile and history only; no NFC/QR/deep-link targeting or device/session calls were found.

Consume the **existing**, unchanged API rather than inventing a new flow:

1. Resolve `GET /d/{device_id}`; the public URL returns JSON, not configured Universal Links. Preserve a trusted device ID across login. Do not forward tokens to arbitrary scanned origins.
2. Authenticated `GET /v1/devices/{device_id}` for derived availability and independent heartbeat-based online state.
3. Deliberate authenticated `POST /v1/devices/{device_id}/sessions` with `{}`.
4. Poll own `GET /v1/sessions/{session_id}` about once/second with backoff; stop at `COMPLETE`, `CANCELLED` or `EXPIRED`. Active states are `ARMED` and `SAMPLING`.
5. Cancel with `POST /v1/sessions/{session_id}/cancel` and `{}`; refresh private history after completion.

Current expiry is60 seconds; online freshness30 seconds; arming an offline unit does not prove hardware readiness. Same-owner arm retry does not extend expiry. Do not wire a scan directly to timed demo completion and call it real sampling. Nicholas owns hardware readiness and honest physical duration/sample semantics; any firmware-driven contract change still needs both collaboration headings before implementation.

### P2 — games and profile-wide stats are not integrated (Liam)

Party is blank (`ContentView.swift:26–28`); there are no game-result/stats consumers. Existing live routes are `POST/GET /v1/me/game-results` and `GET /v1/me/stats`. Save each completion UUID and exact payload before sending and retain it account-scoped across retries/relaunch. Use server-awarded participation points and totals, not raw game score.

Existing example request, not a new schema:

```json
{"result_id":"2889d6a0-4719-4f23-a397-37c51d24129e","game_id":"trivia","score":8,"outcome":"win","data":{"correct_answers":8,"questions":10}}
```

First acceptance201, canonical identical retry200, changed accepted payload409, foreign result UUID404. Fixed10 participation points per unique completion; outcomes are client-reported, not anti-cheat evidence. There is no party engine/count/public leaderboard. Errors mean unavailable, not zero. A stored game result does not implement gameplay.

### P3 — possible profile-load race (Liam)

`ProfileStore.refresh` returns immediately when already loading (`ProfileStore.swift:53–54`). If onboarding opens while the root request is still pending, `OnboardingView.swift:594–601` can see `.unknown` after that immediate return and show a false failure requiring Retry. Coalesce/await the in-flight request or observe its completion. Source-traced possibility, not a reproduced native UI failure.

### P3 — history count/time wording (Liam/product clarification)

`AccountView.swift:146–153` uses loaded count with `+` and acquisition-preferred dates for “Last check”; history re-sorts loaded pages by that date (`ProfileHistoryView.swift:26–28`). This is not falsely labelled “Total”, but loaded count is a lower bound and device clock skew can differ from server receipt chronology. Consider explicit loaded/saved count wording and agree whether the intended order is acquisition time or server receipt. No endpoint/schema change is needed for this clarification.

## Integration / merge status

Fresh `git merge-tree --write-tree origin/main origin/liam/ios-profile-handoff` against current main is a **dry-run only** and reports conflicts in:

- `ios/KickBAC/Auth0.plist`
- `ios/README.md`

Preserve Liam's APIBaseURL and the exact audience when the owner integrates; do not wholesale choose an old config. His backend-review handoff line28 and README statements about unpublished backend/stat-source waiting should be updated to the current published handoff. No PR for this branch was returned by the GitHub query at review time. No merge or conflict resolution was performed here.

## === LIAM / iOS IMPACT ===

**NON-BREAKING. No backend paths, schema, auth, units, states or point policy changed during this review.** Findings identify existing client behavior and missing consumers. Liam owns app fixes/integration and actual native acceptance. Nicholas's backend needs no new auth/profile API; remaining backend-owned coordination is hardware/duration honesty and verifying real post-login feedback after a consenting user's successful login. No repeat Twilio compliance/funding/setup is required.

Current published contract: https://github.com/spherohero/kickbac/blob/main/docs/LIAM_BACKEND_HANDOFF.md . See `docs/API.md`, `docs/GAMES.md`, `docs/READING_HISTORY.md` and `docs/BACKEND_RELEASE_VERIFICATION.md`.

## Verification and limits

- Parent verified current remote SHAs, clean detached review worktree, conflict dry-run, client configuration and live public OpenAPI/health. Two independent reviewers traced source and test fixtures; their summaries were checked against the critical source paths above.
- Windows PATH has no `swift`, `swiftc` or `xcodebuild`. No Swift fixture suite or Xcode build was rerun here. Liam reports prior simulator/fixture passes, explicitly not real production authentication/hardware acceptance.
- Liam's macOS reproduction command is `bash ios/checks/run-authentication-checks.sh`; additional fixture/image/Xcode commands are in his `ios/README.md`. Run on the exact integrated commit, not an older UI snapshot.
- Required native acceptance: actual consenting SMS OTP → API access-token acceptance → profile photo save → force-quit/relaunch and same-account relogin → offline/error retry → deliberate photo removal → second-account isolation. Then connected correct-device arming/expiry/cancel/completion/history and game retry/relaunch/stats.
- GitHub backend CI is now independently green on Python3.11/3.12 and Node22; it does not compile or validate iOS. No tokens, phones, OTPs, private photos, Keychain contents or secret environments were accessed by this review.

## Short forwardable note

Liam: I reviewed `liam/ios-profile-handoff@2cc42da6` against the published/live backend. Auth/profile/history look contract-compatible; no extra profile endpoint is needed. Backend source and games/stats are already on main—use docs/LIAM_BACKEND_HANDOFF.md. First fix Home's unlabelled fixture BAC (also rendered in Release); keep demo data explicitly simulated. Next connect the existing device resolver/arm/session poll/cancel flow, then game-results/stats with persistent idempotency IDs. Small follow-up: onboarding can show a false load failure if a profile GET is already in flight. Integration currently conflicts in Auth0.plist and ios/README; retain APIBaseURL and exact audience. Please run current Xcode/native acceptance; review here was source-only on Windows. No app files were changed or merged.