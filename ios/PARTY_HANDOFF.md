# Nearby Trivia answer-lock follow-up, October 18, 2026

Reviewed the existing uncommitted nearby Trivia implementation while continuing
Liam's party/game flow checks. A deterministic host/guest replay reproduced a
delayed host heartbeat erasing the guest's submitted answer and reopening choices.
The guest now retains its submitted choice for that round until the host confirms
or reveals it. Guest submission also requires membership in the host's round,
completed readiness and an unexpired deadline. The next round clears the choice;
the host remains responsible for accepting answers and awarding points.

Owner Liam/iOS; local `liam/party-setup`, base `03a8817`; unchanged REST endpoints,
schemas, server/firmware and reading storage. No commit or external message.
The new replay failed before the fix and passes afterward, including both
players' scores and next-round reset. Party integration, seven Party source
guards, Practice fixtures and five acquisition guards pass. Signed Debug build
passed (`/tmp/kickbac-continue-debug.log`); strict app signature verification also
passed. This follow-up was not installed because Liam's iPhone is unavailable.
Physical two-phone nearby
discovery/gameplay is not verified; Liam's iPhone is currently unavailable.

# Remove saved-party list and main-page request banners, October 18, 2026

Liam explicitly removed the entire Your parties section and the generic refresh/
pending-request text above the Party page. Deleted the list renderer, pagination,
list-error/retry controls and unused list fetches. Deleted the party room's shared
`error ?? store.message` banner entirely. Current-party restoration and game
refresh remain; refresh is quiet and does not overwrite an open form/game's
errors. Removed the unused room device-status fetch left after Online was removed.
Forms retain their own error UI. A pending game write retains its retry within
the host game controls, rather than above the party title. Saved parties and
durable requests are not deleted by this presentation change.

Owner Liam/iOS; local `liam/party-setup`, base `03a8817`; NON-BREAKING, unchanged
endpoints/schema, no backend change or external message. The updated boundary
regression failed before the fix and all seven source guards pass afterward.
Signed Debug build passed (`/tmp/kickbac-party-page-cleanup-debug.log`). Repaired
and verified the app package signature after an Info.plist signing mismatch;
installation and Party-page launch on Liam's iPhone succeeded
(`/tmp/kickbac-party-page-cleanup-install.log`).

# Ignored NFC navigation banner, October 18, 2026

Liam reported the same error-lifetime bug again: scanning outside Trivia's reading
phase wrote Close the current party action before opening this device link into
shared `error`, which the party room displayed after Trivia closed. Removed that
navigation warning from the rejected-link path; it consumes the irrelevant link
silently. Trivia dismissal also clears its local error before offering another
game. Room-operation failures keep their existing reporting. Local client-only
fix on `liam/party-setup`, base `03a8817`; unchanged API and saved party data.
The focused check failed before removal and passes afterward; all seven Party
source guards and signed Debug pass. devicectl confirmed iPhone installation and
Party launch. Logs: `/tmp/kickbac-party-navigation-banner-debug.log` and
`/tmp/kickbac-party-navigation-banner-install.log`.

# Automatic game invitation and NFC demo, October 18, 2026

Owner Liam/iOS; local uncommitted `liam/party-setup`, base `03a8817`.
NON-BREAKING API; no endpoint/schema/backend change, commit or external message.
Party no longer offers a pre-game Start my test/Online block. After the host's
server-confirmed Trivia creation, active party clients poll the shared game list
every two seconds and each offer one invitation. Busy sheets defer the popup;
polling stops off-tab/in the background. Actual party role replaces hardcoded host.
Join game uses the existing full-width capsule button style and opens the
breathalyzer page directly. Removed the intermediary check-in choices, duplicate
bottom Test cancelled and BAC will stay unavailable copy.

Liam explicitly clarified that the device does not work: NFC must generate a fake
0.00 result, not a short tap on the on-screen circle. Home and Trivia NFC now run a
six-second local App reading of exactly 0.00 without resolving/arming hardware or
posting a check-in/measurement. Holding the circle keeps the random-value demo.
Local provenance, owner-scoped storage and the simulated game BAC flag remain.
Game cancellation stops the local timer without saving, retaining Test cancelled
only in the center. Existing validated device-result decoding is unchanged.

Verification: Party/Practice/Trivia fixtures and all seven Party source guards
pass. Invitation fixtures exercise independent host/guest clients, deferred
presentation, repeat polls and foreign/closed games. Signed Debug passes. On
Liam's iPhone, launching the real configured NFC app link added one new local
reading with value 0 and duration 6 seconds; this verifies app-link handling,
not a physical NFC scan. Final signed build, installation and Party launch are
confirmed on Liam's iPhone. Logs: `/tmp/kickbac-game-flow-debug.log` and
`/tmp/kickbac-game-flow-install.log`.

**Multiplayer is not complete:** invitations share a server game ID, but readiness,
turns, questions, answers and scores still run in separate `TriviaPreview` objects
on each phone. No live shared rounds or background APNs delivery is implemented.
Exact backend requirements are in [NICHOLAS_TRIVIA_HANDOFF.md](NICHOLAS_TRIVIA_HANDOFF.md).
No two-phone gameplay acceptance is claimed.

# Close cancels unfinished setup, October 18, 2026

Liam explicitly requested that Close cancel/reset creation and make both join
options available again. Close and swipe dismissal now clear the unfinished
setup's persisted request, name, scanned device, errors and busy state. The client
creation task is cancelled; generation/revision checks ignore late setup and scan
callbacks. Confirmed parties and unrelated check-in/game requests are preserved.
This supersedes earlier guidance to retain setup requests after explicit Close;
exact retry remains available while setup stays open or after an interrupted run.
No server close/leave/delete operation is sent when dismissing a draft. A request
already accepted by the server remains server-owned and can appear in saved parties.

Owner Liam/iOS; local uncommitted `liam/party-setup`, base `03a8817`, no PR/merge.
NON-BREAKING, unchanged endpoints and payloads. Refreshed remote main handoff and
live OpenAPI confirm atomic resolve/current-party routes are now deployed; older
missing-route notes below are historical. No backend change or external message.

Verification: PartyIntegrationChecks now cover cancellation, join afterward,
relaunch, late success, confirmed-party preservation, unrelated check-ins and disk
failure. Four focused Party source guards pass. The broader source suite has a
pre-existing Home copy mismatch (`Simulated practice reading` vs `App reading`),
outside this change. Signed Debug passed; devicectl confirmed installation and
launch on Liam's iPhone with `--show-party`. Logs:
`/tmp/kickbac-party-close-debug.log`, `/tmp/kickbac-party-close-install.log`.
Run `/tmp/kickbac-party-close-checks` for the compiled fixture checks. No live
authenticated create/join or native dismissal acceptance is claimed from these
fixtures/build/installation.

# Party entry error scope fix, October 18, 2026

Liam's screenshot showed a setup error above the Party entry card. The page-wide
banner rendered `error ?? store.message` whenever `destination == nil`, so closing
setup exposed its retained error. The earlier copy/button edit left this renderer
in place. Removed it from the entry page; room-operation messages now render only
in a room with no pending setup. Setup retains its message and exact retry inside
the setup sheet; no pending write or party data is discarded.

The new source-wiring regression failed before the fix and passed afterward.
PartyIntegrationChecks and signed Debug passed, including durable request/relaunch
coverage. Build log: `/tmp/kickbac-party-error-scope-debug.log`. These checks do not
establish native screen interaction or resolve the separate backend setup failure.

# Latest atomic linked-party setup gate

October 18, 2026. Fresh Create now uses the frozen atomic resolve contract, with
durable exact retries and no fallback to unbound party creation. Public support
is still missing (HTTP405). Existing parties can still be repaired through their
explicit binding action after Nicholas verifies/grants permission. Legacy pending
creates recover read-only. No production cleanup/grant/deployment was performed.
Forward [NICHOLAS_PARTY_LINK_HANDOFF.md](NICHOLAS_PARTY_LINK_HANDOFF.md) for the
precise blocker, operator command, backend contract and verification. Party checks,
focused wiring guard and signed Debug build passed; iPhone installation confirmed.

# Latest Party Delete action and pending backend product request

Signed Debug passed after the concurrent practice-call argument ordering was
corrected. PartyIntegrationChecks passed including server-confirmed removal,
failed/OPEN-response retention, host-only access and durable selected-ID cleanup.
The backend close/game/device-release fixture passed. Acquisition guards passed;
the old Demo-specific Home source guard remains stale against concurrent practice
work (four other PartyTransparency guards passed). Log:
`/tmp/kickbac-party-delete-debug.log`. devicectl confirmed installation and Party
launch on Liam’s iPhone. No live party deletion or native/visual acceptance was
exercised here.


October 18, 2026. Local `liam/party-setup`, base `03a8817`. Liam's immediate scope
is Settings to the right of the party name with host-only Delete party. This
confirms and invokes the existing authenticated close endpoint, requiring a
CLOSED/unbound response before removing the selected party and cached active row.
Errors, busy-device rejection, unexpected OPEN replies and member attempts retain
the party. The selected ID is cleared durably on confirmed removal, so relaunch
does not reopen it. Closed rows are hidden; pagination remains available through
pages containing only closed rows. The confirmation states that saved readings
and game history are retained: no hard-delete endpoint is deployed.

The code-only setup escape and invitation code before successful binding were
removed. Existing NFC joining, illustration, account/session fencing and pending
writes remain intact. No bulk deletion or production permission update occurred.

The requested final design is one active party per user, device-ID join-or-create
with creation/binding atomic, and no recurring per-user operator-grant workaround.
This requires backend work. Forwardable Nicholas handoff:
`/tmp/kickbac-nicholas-party-handoff.md`; see current shared backend handoff for
scope, existing twenty-party cleanup status, compatibility and verification.
Do not assume that future contract or a hard-delete route is implemented.

# Party restoration and linking diagnosis, October 18, 2026

Liam reported Retry linking with the saved-party/operator-permission message and
that leaving/reopening Party removed his parties. The latter was reproduced in
actual Swift: the tab-selection and owner-load handlers called showEntry, which
cleared selectedID and persisted that deletion. A regression failed with
Returning to Party lost the saved party, host role or breathalyzer binding.

Local fix on `liam/party-setup`, base `03a8817`: tab return now refreshes the
existing selection without resetting room/game state; owner startup restores the
saved party. Presentation cleanup no longer clears party data. PartyStore's
explicit entry navigation also retains the selected ID and uncertain writes.
Your parties reads the authenticated, paginated server list, with retry,
deduplication and owner fencing, so parties lost from older local navigation can
be reopened. The room shows the party name and actual operation errors. An
unlinked host party offers Link breathalyzer and a visible disabled Start a game
with concise linking guidance. Existing NFC auto-join and approved art remain.

**Actual remaining blocker:** the reported linking message corresponds to the
backend's host-assignment permission rule, not a missing NFC/device ID. The
server's PUT /v1/parties/{party_id}/device requires an existing device_party_hosts
grant for the exact verified Auth0 subject and registered device. Recreating the
party does not provide that grant. A backend operator must verify Liam's current
signed-in subject, then run the existing `grant-party-device` command against the
correct deployed DB for `kb-demo-01` (verify the scanned ID first). After approval,
Liam can reopen his existing party, Link breathalyzer, scan, and retry linking.
No grant, production DB change or owner notification was performed here.

Verification: the failing restoration harness now passes, plus updated actual
Swift PartyIntegrationChecks for restoration/host/binding, pending-write retention,
list paging/recovery/deduplication/account isolation. Two targeted backend tests
for grant/bind/device join and game device snapshots passed in isolated fixtures.
Five PartyTransparency guards, five acquisition guards, branding, whitespace and
signed Debug passed. Log `/tmp/kickbac-party-resume-debug.log`. Public live OpenAPI
was refreshed to `/tmp/kickbac-party-recovery-openapi.json`; existing party/list/
bind/game routes remain available. Current remote main handoff was fetched/read;
no merge was performed. No API/schema/firmware/scoring change, commit or push.
devicectl confirmed installation and launch with `--show-party` on Liam’s
connected iPhone. Live linking, physical scans and native interaction remain
separate acceptance.

# Automatic NFC party joining, October 18, 2026

Liam's latest request removes the found-device status, generic Party or device
unavailable copy, and Join party confirmation from NFC joining. A valid app device
link received on Party now sends the existing authenticated device-ID join
immediately, then dismisses the tap sheet after server-confirmed success. It does
not first resolve/fetch the private device-status endpoint or gate joining on an
online status. The approved animation and Join with code fallback remain.

Real join failures still show concise recovery; a missing open party offers the
party-code fallback. The server remains authoritative for membership. Background
refresh waits while the NFC join sheet is open, and links arriving during a busy
store operation are consumed once it finishes. Owner/revision checks fence stale
UI responses. Creation, host binding, Home scanning and private check-ins retain
their existing flows. Joining never arms a test.

Owner Liam/iOS; local changes on `liam/party-setup`, base `03a8817`.
NON-BREAKING, no endpoint/schema/payload/server change or teammate message.
Signed Debug and PartyIntegrationChecks passed; acquisition/source checks and
whitespace checks passed. Build log: `/tmp/kickbac-auto-join-debug.log`.
devicectl confirmed iPhone installation and launch with `--show-party`. Physical
NFC and authenticated live joining remain unverified. No commit, push,
merge or backend deployment was made. This supersedes the explicit NFC join
confirmation and device-status gate described in older checkpoints below.

# Party NFC interface restoration, October 18, 2026

Liam requested the original NFC tap animation and no QR or My check-ins on Party.
Local changes on `liam/party-setup`, base `03a8817`, restore the existing
PartyTapIllustration in create, join, host link and invite sheets. The mint entry
card, server-code fallback, approved game picker and real authenticated consumers
remain. QR scanning, raw device-entry fields and the history screen were removed
from Party; the underlying private check-in API/store were retained.

Device links received while Party is selected stay in Party instead of entering
Home's concurrent scan-to-test flow. A tag fills the current join/link form, or
retains the chosen unit alongside the entered name during creation. Successful
creation opens host linking, with a separate explicit Link breathalyzer action.
Joining/linking still require confirmation and server authorization. No scan or
animation arms a party test. The existing per-phone Shortcuts automation is still
required; no native NFC entitlement or Universal Links were added. Other tabs'
scan handling and all concurrent dirty work were preserved.

Signed Debug build passed with Xcode-beta and `/tmp/kickbac-profile-build`;
PartyIntegrationChecks, five PartyTransparency checks (including the Party route's
early return before Home auto-arm), five acquisition source guards, branding and
`git diff --check` passed. Build log: `/tmp/kickbac-party-nfc-debug.log`.
devicectl confirmed installation and launch with `--show-party` on Liam’s
connected iPhone. Physical NFC, authenticated party writes and visual/native
interaction remain unverified. No commit, push, merge, server deployment or teammate message was made.
This checkpoint supersedes QR/history presentation statements below.

# Party integration — current checkpoint, October 18, 2026

Owner Liam/iOS. Branch `liam/party-setup`; UI implementation `b55180fcd21a798c1b6017f92e4b7b86145d24a6` follows authenticated integration `c06192f73e5c2755f4961aa6c65e0c47811ad81f`.
User base `ef08fa8`; main `a0bd77bcb79766f91de6746e0ab02fa992f4b337` integrated by merge `de47523`, preserving Liam's commits without rebasing, resetting or switching branches. Working tree was clean at entry to this UI task. Fetched/read newer main `8f60967d783adddcd02abc0b5e8e54e9935b8d8c`: firmware communication update, no client action; not merged during UI polish.

## Latest UI refinement

Liam supplied an iPhone screenshot and explicitly authorized vision for this correction. The screenshot showed an invisible primary label, intrinsic-width controls, scattered hierarchy and too much engineering copy. The live entry now restores the mint join card, full-width actions, grouped saved-party rows and compact history row. Explicit black-on-white primary styling replaces the inherited glass/tint combination. Create/join/link sheets use padded fields and clear actions; party options hold management/end/leave actions. The approved card stack is shared with live game selection. No logo, card color, icon backing, overlap or upward stack shadow changed.

Liam explicitly requested removal of sample/preview wording; this supersedes older UI disclosure requirements in these handoffs. Party/Trivia development banners and podium captions were removed, roster fixtures use ordinary names, and the 0.7-second Debug caption hold keeps its haptic without a development alert. Real API/session/ownership checks and acquisition notices remain unchanged. Endpoints, schemas, payloads, auth, firmware, private history and scoring contracts are unchanged; NON-BREAKING with no server action required. No teammate notification is claimed.

Verification: unsigned Debug/Release and signed Debug passed; PartyIntegrationChecks, TriviaChecks, branding and acquisition/session source guards passed. The exact staged UI source also built independently from an exported index, excluding concurrent device-link work. Logs: `/tmp/kickbac-party-polish-debug.log`, `/tmp/kickbac-party-polish-release.log`, `/tmp/kickbac-party-polish-signed.log`, `/tmp/kickbac-party-polish-isolated.log`. `devicectl` confirmed signed install and launch on Liam's iPhone with `--show-party`. The installed working-tree build also includes concurrent, preserved device-link edits; those are excluded from UI commit `b55180fcd21a798c1b6017f92e4b7b86145d24a6`. Only the supplied screenshot was inspected: no new screenshot, computer use, Device Hub, native interaction/VoiceOver, live write or hardware acceptance was performed.

## Current behavior and boundaries

- The default Party tab requires existing Auth0 sign-in for server effects. Create, own-party list/read, join by server code or QR/manual official device link, host bind/unbind/close, member leave, and Trivia game-instance create/read/close use the deployed API. Joining never arms a test. No NFC entitlement or Universal Link support is claimed.
- Server-issued eight-character codes replace KICK26 in the live flow. Live Start a game now reuses the approved overlapping Trivia/Pictionary cards and exact artwork/colors/shadow; unsupported Pictionary actions say Coming soon. The old fixture remains behind the Debug-only Party layout option.
- Host binding requires a preexisting backend operator grant. There is no client grant operation. Missing authorization/binding, busy/conflicting units, closed contexts, rate limiting, expiry and network/storage failures have recovery copy. Online/offline is shown independently of arming permission.
- Explicit Start my test creates a private party-only check-in. Starting from a selected server game instance creates an explicitly game-specific check-in. The app adopts the returned session into ContentView's existing DeviceSessionStore; it never calls legacy arm afterward or allocates a separate game store. Home and Trivia use the same owned session, existing foreground polling/backoff/cancel path and accepted result.
- My check-ins reads paginated owner-private history, retaining loaded rows on failure, deduplicating pages, rejecting mixed-owner/session/acquisition data and clearing visible data on account changes. Active entries can resume their existing session without rearming. Completed manual samples retain null BAC and the measured sample window; never call it validated breath.
- The API supplies member count, not a public name/photo roster or shared leaderboard. Trivia remains local and submits no score/result or lifetime reward. A server game instance is saved context only. Local rounds/results survive closing/reopening within that party view; account changes clear them. Liam's latest UI request supersedes earlier disclosure-copy requirements: Party/Trivia omit sample/preview/local/unsaved captions. Actual acquisition metadata and unavailable BAC stay accurate.

## Exact retry/session contract

`POST /v1/parties` sends `{"party_id":"<persisted UUID>","name":"<name>"}`.
`POST /v1/parties/{party_id}/games` sends `{"game_instance_id":"<persisted UUID>","game_id":"trivia"}`.
`POST /v1/parties/{party_id}/check-ins` sends `{"check_in_id":"<persisted UUID>","device_id":"<assigned unit>","game_instance_id":null}`; null means party-only, never current game. An explicitly selected instance supplies its exact UUID instead.

PartyWrite stores canonical UUIDs, route context and exact encoded body before any send in account-hashed Application Support files with atomic/protected writes. Persistence failure prevents sending. Timeout/offline/cancellation retains the same request across retry/relaunch/account switching. Changed/new requests cannot replace an ambiguous request. Exact replay adopts the original active or terminal session and never extends it. A new deliberate attempt after a resolved terminal session gets a new UUID. Only a current, explicit domain rejection (not found/busy/invalid state/expired/validation) enables Discard rejected request; transport failures, unstructured errors and idempotency conflicts cannot be discarded. After relaunch, rejection must be reconfirmed before discard.

Response checks cover UUID, route-party, game, device, session and current owner. Existing unrelated active tests cannot be replaced. Real readiness requires that exact session's COMPLETE measurement with valid acquisition; Home's Debug demo cannot advance it. Release never auto-runs a fake sample. Explicit local practice continues without a test/BAC.

## Verification and publication limits

- Live public OpenAPI fetched this run exposes 33 operations, party/check-in routes and nullable manual-acquisition metadata. The latest backend handoff records deployed schema6/source172e54c; no host/database inspection or deployment was performed here.
- Actual Swift PartyIntegrationChecks passed: durable-before-send/exact replay, canonical UUIDs, relaunch, changed-request rejection, account switch/stale response, mixed owner, unrelated active session, expiry/cancel, manual null BAC, pagination/recovery/deduplication, API access-token/body/path/code decoding, rejection discard versus ambiguous/conflict retention and storage failure.
- Acquisition, DeviceSession, AuthContract, Profile, RecentGames, PartyPreview, Trivia and HomeGauge Swift checks passed. Branding, five acquisition source guards and four local/Release source guards passed. Source guards do not execute native UI semantics.
- Final unsigned generic-iOS Release and signed Debug builds passed using Xcode-beta and `/tmp/kickbac-profile-build`; only the standard no-AppIntents metadata notice appeared. Earlier unsigned Debug also passed. Logs: `/tmp/kickbac-party-live-release.log`, `/tmp/kickbac-party-live-signed.log`, `/tmp/kickbac-party-live-debug.log`.
- `devicectl` confirmed installation and launch of `com.liam.KickBAC --show-party` on Liam's connected iPhone. No screenshots, vision, Device Hub, visual inspection, real party/check-in write, SMS delivery, physical sensing, NFC, VoiceOver or shared-gameplay acceptance was performed. Install/launch alone does not establish those outcomes.

## PR32 disposition and remaining work

PR32 `ios/manual-acquisition-notice@f9cbce63553712806b8d39760261975e5f817088` was inspected against current main and Liam's newer branch. It remains OPEN/DRAFT/UNMERGED, with its existing green native job predating these fixes. No cherry-pick, push, merge or branch deletion was applied to PR32. Its acquisition compatibility is already on main; integrating main preserved the newer `ef08fa8` UI instead of replacing it with the older bundled preview.

Remaining acceptance: real signed-account create/join/bind with an operator-approved unit; concurrent physical test reservation, expiry/retry/relaunch/account switching against the live API; real acquisition/private readback. Personal-device check-ins still require the server's assigned-device policy. NFC/Universal Links need provisioning/configuration and separate phone acceptance. Shared questions, answers, turns, roster/visibility, scoring/reconnect and consent-based member BAC sharing remain separate backend contracts.

## Reproduce checks

```sh
xcrun swiftc ios/KickBAC/BACReading.swift ios/KickBAC/DeviceModels.swift ios/KickBAC/KickBACAPI.swift ios/KickBAC/PartyAPI.swift ios/KickBAC/DeviceSessionStore.swift ios/KickBAC/PartyStore.swift ios/checks/PartyIntegrationChecks.swift -o /tmp/kickbac-party-integration-checks
/tmp/kickbac-party-integration-checks
python3 ios/checks/PartyTransparencyChecks.py
python3 ios/checks/AcquisitionContractChecks.py
xcodebuild -project ios/KickBAC.xcodeproj -scheme KickBAC -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/kickbac-profile-build CODE_SIGNING_ALLOWED=NO build
# Debug uses the same project/scheme/cache; omit CODE_SIGNING_ALLOWED=NO for the existing signed profile.
git diff --check
```

The following is historical implementation/design evidence. Behavior statements below are superseded by the current checkpoint above and DESIGN.md.

## Historical Party UI preview


Debug tap shortcut: hold the shared Tap your phone to the breathalyzer text for 0.7 seconds to simulate `kb-demo-01`. The gesture attaches directly to the caption with a minimum 44-point target; the animation stays touch-transparent. This replaces the illustration-wide overlay after Liam reported the hold did not respond. Create uses the entered valid party name and that fixture device; invalid names remain on the form. Tap to join enters the local guest party. Trivia advances to the breath screen, which now automatically plays a local reading sequence before marking the player Ready; see TRIVIA_HANDOFF.md. Invite people acknowledges the simulated tap without replacing the current room or game. A named VoiceOver Debug action on the caption provides the same shortcut. The gesture, feedback and simulation alert compile only in Debug; Release gesture behavior is unchanged. No NFC session, hardware, live party, private measurement or server result is created. People shows the profile name and role without the redundant You label; an unavailable name falls back to Player.

Owner: Liam. Branch: `liam/ios-profile-handoff`, source base `3a7fa1c351b05d6e38c01be33cd63e2364160328`, integrated backend/docs base `22f06354e85ad04afe522e6d870b5bf3bb206af8`. Prepared as local changes following PR [#22](https://github.com/spherohero/kickbac/pull/22). No new commit, push, merge, or deployment is implied by this document. Nicholas has not been personally messaged.

## Current behavior

Liam explicitly chose UI preview first, live parties later. The previously blank Party tab now previews:

- Create a named party with instructional phone-to-breathalyzer artwork. Raw device IDs and manual selection are hidden; the local fixture still uses `kb-demo-01` internally, without claiming a live binding.
- Tap-join illustration or code fallback. Only the documented fixture code `KICK26` is accepted. This is not a real invitation or a proposed production code format.
- Host-only game picker with stacked colored Trivia and Pictionary cards, inspired by the supplied Games reference while preserving KickBAC's existing visual style.
- Game details, an ongoing-game state, and the local Trivia flow documented in [TRIVIA_HANDOFF.md](TRIVIA_HANDOFF.md). Trivia has join/skip, Debug-only simulated check-in, rotating player wheel turns, locked answers, round results, local points and a podium; no multiplayer session or server result is created.
- Guest room with ongoing games, leaderboard, and people; idle room omits ongoing games.
- The current user’s profile and local Trivia standings after a game. Private account-wide totals are not reused as party scores. The optional Debug example roster is explicitly fictional; no simulated BAC, real participants, private results or lifetime rewards are invented.

Use the circular Settings-style options icon to switch Host/Guest under Preview as, show an ongoing example, return to idle, or exit. At Liam's request, entry/create/people/game selection/details omit the preview banner and development explanations; actions say Create party, Start a game, and Start game. These wording changes do not implement live behavior. State lives only in memory and clears when the authenticated owner changes. Sign-in is not bypassed; preview entry requires no sign-in because it has no shared/private server effects. Own name/photo appear only when the loaded profile matches the current authenticated owner.

`--show-party` opens the Party tab in Debug builds, analogous to `--show-profile`. It does not create a room, bypass auth, or load fixture account data. Existing device links still follow their approved Home/confirmation flow.

## Proposed live behavior, pending contract

The host creates a party and binds its breathalyzer. A guest taps that unit to join its active party automatically, with a party-code fallback. Host selects games; guests watch ongoing games and the party's leaderboard/people. If no games are running, guests see leaderboard/people only. Gameplay is a later milestone.

**NON-BREAKING: existing endpoints, payloads, auth, private history/stats, and breath-test state are unchanged.** No speculative party endpoint is called. The generic private game ledger and arbitrary result `data` do not establish party membership or party ranking.

Before live implementation, coordinate and publish the server-owned party identity, active device binding, host permissions, join/code lifecycle, membership and leave/end behavior, ongoing-game state, party score rules, and authorized member display fields. Agree exact routes, schemas, null/error semantics, expiry, and refresh behavior in the canonical API docs/OpenAPI and shared handoff. Do not silently reinterpret global participation points as competitive party scores.

Joining a party is separate from arming a private breath test. Do not call the existing session-create endpoint on a party tap, expose another member's private measurements, or infer who supplied a sample from membership. Preserve target across authentication when live joining is added. Resolve NFC only through the authorized device/party contract.

Current signing excludes NFC Tag Reading because the Personal Team does not support it. Universal Links/background NFC are not configured. The preview requests no NFC/camera permission and changes no entitlements. Both provisioning/link support and real-device acceptance remain future gates.

## Verification

Focused state checks:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc ios/KickBAC/BACReading.swift ios/KickBAC/DeviceModels.swift ios/KickBAC/KickBACAPI.swift ios/KickBAC/TriviaPreview.swift ios/KickBAC/PartyPreview.swift ios/checks/PartyPreviewChecks.swift -o /tmp/kickbac-party-checks
/tmp/kickbac-party-checks
```

Checks cover initial/idle state, name/device validation, normalized fixture-code joining, invalid-code preservation, role changes, ongoing examples, exit reset, and a fresh tap preview. Run the signed Debug build using the existing `/tmp/kickbac-profile-build` cache. These checks/builds do not verify rendering, VoiceOver behavior, real NFC, cross-phone membership, leaderboard synchronization, or gameplay.

Verification on October 18, 2026: focused state checks and branding checks passed; signed Debug iOS build passed. Direct iPhone installation was attempted but CoreDevice returned error 4016; device inventory reported Liam's physical iPhone `unavailable`. Installation/launch and visual/native acceptance are not claimed. Source changes remain local and uncommitted.

Later copy cleanup on the same date: removed Liam's specified banners/helper text, updated action labels, and matched the options trigger to Me's Settings icon. Signed Debug rebuild and whitespace checks passed. The iPhone reconnected; direct installation succeeded and `devicectl` confirmed launch with `--show-party`. No screenshots or visual inspection were used; rendering and live party behavior remain unverified. No new commit/push was made.

Icon/join-copy follow-up: read the linked Figma board without images or canvas mutations. All custom Party SF Symbols were replaced with approved SVG assets. New direct exports from Hi-fi icons: `PartyNFC` from `86:281` (Icon / NFC), `PartyPlus` from `86:251` (Icon / Plus), and `PartyQuestion` from `86:302` (Icon / Question). Reused ProfileChevron, ProfileEdit, OnboardingBreath, and ProfileSettings for their corresponding approved icons. Removed “Meet at the breathalyzer,” the inactive-tap explanation, and the KICK26 trial instructions. Both code entry actions say Join with code; the tap action says Join party. Local preview behavior and contracts remain unchanged. Source checks found no remaining custom SF Symbols in Party; signed Debug build and whitespace checks passed, and direct iPhone installation/launch with `--show-party` succeeded. No visual inspection was performed.

Join/invite layout follow-up: removed the join welcome heading, NFC icon, tap instructions and Join party action. The tap entry reserves blank space for approved artwork above the remaining code form/action. Invite people also reserves artwork space above a centered KICK26 code and omits its heading/instructions/disclaimer. The room title shares a row with the options icon, and code-joined sample rooms are named Party. No animation/image has been fabricated; the user needs to select phone and breathalyzer artwork before it is added. Existing selected NFC artwork is available. Code joining is still local; no live behavior or contract changed. Signed Debug build, source-copy checks and whitespace checks passed; direct iPhone installation succeeded. Rendering was not inspected.

Artwork follow-up: Liam supplied a filled mobile-phone SVG and asked for a matching breathalyzer SVG from his enclosure reference. `PartyPhone` preserves his path geometry; `PartyBreathalyzer` is a monochrome rounded enclosure with left mouthpiece and four mounting tabs, without invented controls. `PartyTapIllustration` combines them with the approved NFC asset and plays one native keyframe approach/hold/withdraw sequence. Reduce Motion shows a static contact pose. It appears in Create party, Tap to join, and Invite people. No artwork completion, animation timing, or local Create party action is interpreted as a live NFC connection. Raw IDs, manual selection, and selection helper text are hidden from the UI. These supplied/commissioned assets are the user's explicit exception to Figma-only icon sourcing. No Figma file was modified.

Artwork verification: signed Debug build passed without Swift source warnings; focused Party checks (including creation without a user-entered ID), SVG XML/template-asset checks, and whitespace checks passed. Direct iPhone installation succeeded. Rendering, actual motion and NFC remain unverified; no visual inspection was used. Changes remain local and uncommitted.

Loop/styling/input follow-up: the native keyframe sequence now repeats while the scene is active and motion is allowed. The stylized SVG removes all mounting nubs and rounds the mouthpiece; the NFC mark increases from 6.5% to 11% of illustration width. Create has a Tap your phone to the breathalyzer control above its action; tapping replaces the text with the selected NFC asset and enables local creation when the name is valid. It is a local selection, not a real NFC-success acknowledgment. The name/code fields have explicit focus bindings and padded-area tap focus; illustration clipping and disabled hit testing prevent artwork from receiving input. A source-only native hit-target harness initially reached the name field, so the original user-reported typing failure was not independently reproduced. No screenshots or visual inspection were used.

Follow-up verification: a temporary native simulator harness compiled the actual updated `PartyEntrySheet`, its real model/style helpers, and illustration. The field center targeted `UITextField`; programmatic focus and insertion produced `Friday` with `isFirstResponder == true`. This verifies native field/binding operation, not a reproduction of Liam's original physical tap failure. Signed Debug build and whitespace checks passed; direct iPhone installation succeeded. No visual acceptance is claimed.

Instruction/star follow-up: Create starts with Party name; Make it your party is removed. Use exactly Tap your phone to the breathalyzer with every tap animation, using the existing control on Create and the shared caption elsewhere. Its selected state remains the approved NFC icon. Restore the approved OnboardingBreath logo star beside the room name, without showing a device ID. Invite people adds Or enter code to join between the animation/instruction and the centered code. This is copy/layout only; local pairing behavior and API contracts remain unchanged.

Latest Create correction supersedes the tap-control behavior above: Create now uses the identical shared animation and plain Tap your phone to the breathalyzer caption as Join. Removed the simulated tap button, its NFC-icon replacement state, and the tap prerequisite for creation. Only the party-name validation gates the local Create party action. Join's animation/caption remains unchanged. Existing backend contracts and real NFC support remain unchanged.

Manual preview route: Party > Create a party > enter a name > Create party > Start a game > Trivia/Pictionary > Start game. Open the Settings-style options icon and switch to Guest under Preview as; then Show no ongoing games. Exit and open Tap to join or Join with code, then enter `KICK26` and select Join with code. Tap the room's Party code row to inspect Invite people. Check looping instructional motion on Create/Tap/Invite and its static pose with Reduce Motion. Rendering/motion and the original typing symptom still need Liam's native acceptance.

Latest room-header correction: removed the logo star beside the party name at Liam's request. The shared host/guest header now contains the name and options button only; this supersedes the earlier instruction to restore the star.

Approved game artwork integration: exported the final Trivia (`191:235`) and Pictionary (`191:245`) SVGs directly from the board's Hi-fi icons section into `PartyTrivia` and `PartyPictionary` image assets. Shared game cards/details and ongoing-game rows now use those full-color illustrations at 64 points, without template tint or an extra tile background. Exports retain the bolder question mark, rounded paper fill with its open outline, supplied pencil at the restored size with its filled body gap, and final upper-left accent position. This supersedes the earlier 32-point bare question/pencil icons. App behavior and API contracts are unchanged. Unsigned Debug iOS build, Party preview state checks, asset XML/manifest checks, and whitespace checks passed. No vision or computer use was used; native rendering was not visually verified. Changes remain local, without installation, commit, or push.

Game-picker layout follow-up: applied the supplied written NYT Games critique within the existing Apple/Emil design direction. Matching cards now have a 164-point minimum height, 24-point insets, 32-point approved icons, grouped title/description, and a shallow 12-point overlap confined to the bottom inset. Text can grow; accessibility sizes retain separate cards. The picker uses Choose a game, a smaller top inset, and Close; details retain native Back navigation. Existing flat background, game colors, local preview behavior, and API contracts are unchanged. Unsigned Debug iOS build and whitespace checks passed. No vision or computer use was used; rendering and native interaction were not visually verified. Changes remain local.

Latest card-stack correction: removed Questions & answers / Drawing & guessing and their footer chevron. The picker now overlaps cards by 56 points to cover the preceding lower curves. The preceding card reserves 68 points below its content so text/artwork retain 12 points of clearance even when wrapping; accessibility sizes retain a separated stack. The 164-point minimum, approved logos, copy, game selection, and local preview behavior are otherwise preserved. This supersedes the earlier 12-point overlap.

Latest card-artwork/depth correction: interpreted the requested outline removal as the colored rounded-square backing behind each game illustration. Removed only that background path and unused gradient from the iOS SVGs, preserving all paper/pencil/question outlines and the final accent placement. Game-card artwork moves 8 points up and right; ongoing-game rows keep their placement. Card backgrounds gain a soft black shadow at 16% opacity, radius 8, y 3. The approved 56-point overlap and existing behavior remain unchanged. Figma masters were not modified.

Latest row-icon and stack-shadow correction: ongoing-game rows and profile Recent games now share the approved Trivia/Pictionary artwork on a rounded-square background filled from the same exact card color. Card/detail artwork stays transparent. Recent games maps known game IDs to the shared icons and retains a neutral approved generic icon for other game IDs. The front Pictionary card has explicit drawing priority; its shadow now casts upward (black 26%, radius 4, y −4) onto Trivia to reveal the overlap seam. This supersedes the previous downward shadow. No API or state changes.

Trivia follow-up: Start game now opens the join/skip → tap/check-in → ready → host category wheel → question/reveal → podium preview. The shared room retains and reopens its trivia state; owner/room teardown clears it. Game points are local, nullable BAC stays unavailable, and explicit Debug controls cannot be confused with live sensor/native acceptance. See [TRIVIA_HANDOFF.md](TRIVIA_HANDOFF.md) for the full sequence, privacy boundary, backend requirements, and standalone checks. This supersedes earlier statements that no local game logic exists; no shared game engine or live party contract is implemented.

Latest trivia revision: compact logo/Join game/Skip game sheet; HomeView-based breath page; avatar/name/readiness roster without BAC; flat primary controls; gesture-driven wheel with rotating center star; fixed wheel/answer pages; line countdown; delayed all-answered/deadline reveal; separate per-player round awards; rotating spinner. Hardware simulation is now in the Debug options menu, never a main-page preview action. Personal breathalyzers are a requested live capability, not implemented by removing the party-device copy. This supersedes the host-only wheel and inline reveal described above. See the updated trivia handoff.

## Party tag status and server binding follow-up

At Liam's request, Join party remains visible before scanning and disabled until
an authenticated resolver/device lookup succeeds. The shared tap illustration
uses the existing OnboardingBreath SVG beside the actual resolved ID. Confirmed
online lookup shows `<device-id> connected`; offline lookup shows
`<device-id> found · offline` and remains usable for server party joining/binding.
The animation holds its contact pose after identification. Neither a raw tag ID
nor the Debug tap shortcut is evidence of chip connectivity or a sober result.

Creating a party still persists an exact UUID/body before the server POST. When a
unit was scanned, successful creation now immediately attempts the existing host
binding PUT, retaining the created party/code if linking fails. An unsuccessful
binding does not issue another create or erase the party. A join-by-device 404 now
explains the missing open binding and offers code fallback. A bind 404 explains
that the party is saved and the operator must verify host assignment permission.
The caller reported that permission was probably granted; that is not verified
production authorization. No device credential or production grant is read,
created, weakened or disclosed by this client change.

Explicit Continue without a test allows local Trivia readiness with null BAC,
including after cancelling/expiring a device session. It does not manufacture a
measurement, complete a server check-in, upload a score or label an offline unit
connected. An active reservation is not silently cancelled by local progression.

Backend existing real-loopback HTTP/core/concurrency checks passed: 24 tests,
covering saved create/retry, operator-authorized binding, code/device joins into
the same party, correct-user session results and restart preservation. These use
isolated databases/explicit synthetic identities, not the user's live account.
The native client fixtures additionally cover exact bind/join wire bodies,
retention of a saved party/code after rejected binding, and offline-versus-online
caption meaning. Actual two-account production create/bind/join and physical NFC
rendering remain separate phone/operator acceptance.

=== LIAM / iOS IMPACT ===
Additive app UI/adoption change; existing API/schema/auth semantics unchanged.
Server create, host bind and guest join remain distinct authenticated operations.
All devices/parties stay subject to existing assignment permissions and one-open-
party-per-device rules. No fake sober BAC or phantom server party is introduced.

## Standard Party entry, no heading or cog

Liam requested removal of the Party heading and the entire cog menu, including
Refresh, All parties and the layout-preview entry. The Party tab now starts at
join/create on first load and every tab re-entry instead of fetching a cached old
room. The obsolete own-party list fetch/pagination is also removed. Explicit
create/join still opens its server room normally. This changes local navigation,
not server membership, device bindings or saved measurements. Clearing entry
invalidates late room responses and persists a null selection while retaining any
uncertain write's exact pending UUID/body; an unreadable request cache stays
protected. Pull-to-refresh can update only a currently selected explicit room.
Native fixtures cover cache/relaunch, pending-write retention and a late response
not reopening a room. No backend endpoint/schema change.

## Inline join errors and creation-time binding

The main Party page no longer renders the generic global error banner. A failed
scan-to-join message appears centered directly below Join with code in its sheet;
opening another action clears unrelated transient errors. Creation now requires
its scanned unit and performs the existing server create then host binding while
remaining on the same Create a party screen. It never navigates to the separate
binding destination during creation. If binding fails, the saved name is fixed
and Retry linking reuses that party instead of creating another. Recovery of an
uncertain create also returns to this same flow and preserves the exact request.
Binding is server metadata; its existing handler does not gate on heartbeat
online status. Missing operator authority, competing assignment, device-busy and
stale party state remain actual server errors; no false success is shown.

## Finger-generated, locally saved practice BAC

Liam requested replacing Home's Onboarding/Demo buttons with a center-icon hold.
An explicit touch runs a simulated sample; release or the six-second maximum
finishes it. A successful atomic save reveals one random value with its actual
local gesture duration. Results are always visibly simulated, including in
history, the profile count explanation and local-game standings. Navigation,
backgrounding or a real active-device session interrupts unfinished practice.
Test again clears the displayed result without deleting saved records.

The root-owned PracticeReadingStore scopes persisted local values by signed-in
subject, with a distinct guest scope. Guest practice can be viewed signed out;
it is not migrated into signed-in accounts. History merges these labeled local
entries with valid server BAC readings. Existing unavailable backend BAC remains
excluded; no server measurement or session ID is fabricated. The local Trivia
model has a separate practice completion and simulation flag; real check-in
acceptance still requires the exact completed owner/device/session. Practice
never uploads a measurement, awards server points or affects another phone.
NFC continues to use actual server/chip results, without a forced zero BAC.

Native practice fixtures cover relaunch/account/guest isolation, actual duration,
invalid inputs, disk errors and preservation of unreadable data. Trivia fixtures
cover simulation provenance and duplicate completion. This is source/native
fixture and compilation evidence, not physical gesture/NFC or cloud-sync
acceptance. Relevant implementation/testing commands are in ios/README.md.
