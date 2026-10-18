# kickBAC backend handoff — Liam / iOS agents

This replaces the older local/unpublished-profile handoff. **Backend profile, phone source, deployment, auth-cache fix and games are published and merged. Games are live.** Preserve Liam's actual local/unpublished SwiftUI work; no UI redesign, branch takeover or provider reprovisioning is requested.

## Read first — agent sync and latest branch/change checkpoint

This is the shared catch-up entry point for Liam and his agent, not a request to redo completed integration. Before work, fetch without changing the active checkout:

```bash
git status --short --branch
git fetch origin --prune
git show origin/main:docs/LIAM_BACKEND_HANDOFF.md
git log -5 --oneline origin/main
git rev-parse origin/main origin/liam/ios-profile-handoff
```

Read root `AGENTS.md` as well as Liam's `ios/AGENTS.md` when present on his branch. If main has not been integrated, read these shared docs directly from `origin/main`; do not reset, stash automatically, overwrite local edits or merge blindly. Documentation publication cannot prove an already-running remote agent has read it. Liam/his agent should report the main and client SHAs read when next giving a substantive integration update; no repeated acknowledgment pings or new user-run native tests are requested.

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
