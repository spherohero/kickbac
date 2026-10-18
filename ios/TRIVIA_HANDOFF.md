# Trivia flow and live integration requirements

Owner Liam/iOS; branch `liam/party-setup`, HEAD/base `4d34436769401b8c1567eb316436705843016a23`. Main fetched/read `86adb12b4c1f669aafb1ee5ee1726f6da87454bb`. These changes are local/uncommitted. No new PR, merge, installation, deployment or teammate message is implied.

## Current product flow

FigJam Party `52:129`, Trivia `52:142` and Breathalyzer `52:174` were read through their source structure, without screenshots or canvas mutations. Latest user instructions supersede the original host-only spinner and party-device restriction:

1. Host opens Trivia. A small sheet contains only the approved logo, Trivia, Join game and Skip game.
2. Every participant including the host chooses join or skip. Join opens the tap illustration, then HomeView's existing gauge/metrics/duration layout. At Liam's request the game breath screen automatically runs a local sequence: two-second preparation, six-second fill, stop cue, then 0.08 for two seconds before entering the ready roster. Game copy and accessibility text omit demo/preview labels. The completed fixture BAC is passed back to the local game for the podium; it is not a measurement or hardware success. The requested live product permits either the shared party device or a personal breathalyzer.
3. The roster uses avatar/name and Ready, Checking in, Sitting out or Not ready. Ready gets a check; BAC is omitted here. Leave game sits above Start trivia, clears only the current player's readiness/BAC and dismisses to the party. Rejoining requires a fresh check-in. The host starts the round.
4. Ready players rotate as spinner. Tap or drag the wheel itself; the center star rotates with its wedges while the pointer stays fixed. The rounded white pointer has a dark outline, explicit square-wheel alignment and an overlay outside the wheel button so it stays anchored through rotation and press feedback. One category/question is shared by everyone. Six unused categories are selected across six rounds.
5. Four answer options stay on a fixed page with a shrinking countdown line. Choices have solid coral/blue/yellow/green fills, black text and a black outline only on the selected answer. Omit Choose your answer and the answered count. Submitting locks the answer, shows Answer locked, and acknowledges only the selection; spectators see Sitting out. The status line keeps its space before selection so the layout stays fixed. Correctness and points remain hidden until everyone answers or the 20-second absolute deadline passes.
6. A separate round-results page shows the correct answer and every participant's earned points and totals, without the explanatory sentence. After five seconds or Next round, the next participant gets the wheel. With VoiceOver, explicit Next round retains time to read. After the last round, show the podium.
7. Final results use the 2–1–3 podium and ranked list, without the Good game / Here's where everyone landed introduction. The current player's local check-in BAC reaches the podium, accessibility labels and retained party standings. Missing check-ins and example players stay null. BAC remains separate from points/rank. Ties share rank. Accessibility sizes omit decorative podium columns.

The bundled six questions, twenty seconds, six rounds and 1000 points per correct answer are **local preview defaults**, not an approved scoring protocol. No multiplayer game engine is connected. Correct answers are bundled locally and therefore not secret; production must deliver them only at reveal.

## Reproduce in Debug

Party → Create a party → enter name → Create party → Start a game → Trivia → Start game → compact Join game sheet. Tap screen: hold the Tap your phone to the breathalyzer text for 0.7 seconds to simulate tapping `kb-demo-01`, or use options icon → Development · local simulation → Simulate device tap. The caption has a minimum 44-point target; the animation ignores touches. VoiceOver exposes the named Debug simulation action on the caption. The breath sequence now runs automatically; the Debug menu's Simulate completed test remains an optional shortcut. No hardware is armed and no actual sample is collected.

Lobby: optionally enable Example players in the options menu, then Start trivia. Tap or swipe the wheel. Answer a question and wait for results; example participants submit explicit fixture answers after two seconds and take their turns automatically. Their names always begin with Example; they never get fabricated BAC. With no examples, only the current player appears and answering satisfies everyone-answered after a short acknowledgement delay. A skipped player stays a spectator; with example players enabled they can watch the flow. Guest Debug options can simulate the host-start event; it isn't a server permission.

Release omits device-success and fictional-roster controls; live check-in isn't connected. Removing preview captions from product screens does not establish native success. Final/round points remain in memory and are never sent to the private game ledger or lifetime stats. Close/reopen retains the game and its absolute deadline; room teardown, replacement and account-owner changes clear it. Back to party clears the ongoing marker while retaining the local standings for that room.

## UI and data boundaries

Apple Design and Emil Design Engineering guide grouping, stable hierarchy, immediate press/selection feedback and causal outcome feedback. Primary capsules have no custom shadow. Only the shared approved tap artwork and Home gauge are used for check-in. Wheel dragging tracks the finger directly and hands its angular release velocity to a native settling spring. Wheel and question/waiting pages have no ScrollView; landscape places content alongside wheel/options, and answer columns adapt to text size and available height. Reduce Motion skips wheel spinning. VoiceOver has full question/answer labels, status labels and remaining seconds.

The breath page receives a fresh read-only DeviceSessionStore: an older Home result cannot satisfy a new game check-in. Home's default behavior remains unchanged. Game mode reuses Home's in-memory animation and fixture values, hides Connect/development controls and demo/preview labels, and shows only local fixture Avg/Max rather than private Home history. Leaving or backgrounding an unfinished sequence clears the run and cancels readiness; foreground/reopen starts a fresh sequence. Only matching-owner profile name/photo is used in party/player rows. Home passes its completed fixture value into completePreviewBreath(bac:); the model accepts a finite nonnegative value only during the breath phase and retains it for this game. Skip/leave and rejoin clear it. No measurement ID, recorded duration or physical success is invented or sent to a server. NFC entitlements, session endpoints and polling are unchanged.

## === LIAM / iOS IMPACT ===

**NON-BREAKING local UI/state revision.** No endpoint, request/response schema, identity, timestamp, unit, hardware sampling duration, firmware or auth change. Existing `completion_v1` lifetime participation awards remain distinct from competitive game score. No client action required for existing consumers. The game breath animation drives local readiness in both configurations; Debug device-tap/fixture controls remain separate. No sender notification is claimed.

Latest main source has schema6/33 operations, including parties and owner-private check-ins. PR #26 merged as `67c46916bda95250cdae739fd99e19cde8634667`; backend handoff records passed exact-main CI. It is **not deployed**. Live OpenAPI read this turn still exposes 17 schema4 operations. The merged source adds `POST /v1/parties/{party_id}/check-ins` with exact attempt UUID/device/game context, and private `GET /v1/me/check-ins`; the existing session shape/polling is preserved. Its frozen policy requires the party-assigned device, so the newly requested personal-device option requires server coordination before integration. Read `origin/main:docs/NFC_CHECK_IN.md` and the latest backend handoff; older schema5-only draft notes are historical.

## Remaining live work

- Verify deployment and migrations before adopting the merged party/check-in operations. Preserve exact UUID/payload retries, owner binding, expiry/cancellation, occupied-device behavior and private-history association.
- Define and authorize personal-device game check-ins without attributing one person's sample to another, replacing or implicitly joining the wrong party, or silently rewriting the assigned device.
- Server owns invitations, join/skip/readiness, eligible roster, rotating spinner, shared category/question IDs, private answer submissions, all-voted/deadline reveal, idempotent awards and reconnect behavior. The local driver is not a network permission check. Production clients must not receive correct answers early.
- Define late join, spectator, departure and result visibility semantics. The current private ledger isn't authoritative competitive scoring or a public leaderboard.
- Liam requests game points and that game's check-in BAC on the final leaderboard. No member-visible BAC contract exists; define server-owned consent/sharing policy and expose only permitted nullable game-check-in estimates. Never publish raw subjects or private history, infer BAC from ADC, or reward higher BAC.
- Preserve all accepted check-ins in private history independently of game completion. Native NFC/Universal Link, real hardware and multi-phone acceptance remain separate gates.

## Verification

```sh
swiftc ios/KickBAC/TriviaPreview.swift ios/checks/TriviaChecks.swift -o /tmp/kickbac-trivia-checks
/tmp/kickbac-trivia-checks
swiftc ios/KickBAC/BACReading.swift ios/KickBAC/DeviceModels.swift ios/KickBAC/KickBACAPI.swift ios/KickBAC/TriviaPreview.swift ios/KickBAC/PartyPreview.swift ios/checks/PartyPreviewChecks.swift -o /tmp/kickbac-party-checks
/tmp/kickbac-party-checks
swiftc ios/KickBAC/HomeGauge.swift ios/checks/HomeGaugeChecks.swift -o /tmp/kickbac-home-gauge-checks
/tmp/kickbac-home-gauge-checks
xcodebuild -project ios/KickBAC.xcodeproj -scheme KickBAC -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/kickbac-review-build CODE_SIGNING_ALLOWED=NO build
# Repeat the build with -configuration Release.
git diff --check
```

State checks cover check-in order, readiness, skip/spectate, host-only start, eligible rotating spinner, one shared category/no reuse, locked/duplicate/invalid answers, deadline boundary, all-voted gating, per-player round awards, one-time totals, timeouts, nullable BAC, completed fixture BAC retention through all rounds, leave/rejoin clearing, invalid BAC rejection, duplicate/late completion guards, fixture isolation, teardown, wheel angular boundaries/landing and countdown bounds. Gauge checks protect Home geometry. Builds/checks provide no visual, native NFC, hardware or multiplayer acceptance. No vision or computer use was used.

Latest refinement verification: TriviaChecks and PartyPreviewChecks passed, unsigned generic-iOS Debug and Release builds passed, and git diff --check passed. A headless check of the actual WheelPointer path confirmed centered, bounded, downward, symmetric geometry; this does not verify native rendering or touch behavior. Build logs: /tmp/kickbac-trivia-refinements-debug.log and /tmp/kickbac-trivia-refinements-release.log. No install, visual inspection, hardware or multiplayer test was performed.

Verified October 18, 2026: TriviaChecks, PartyPreviewChecks and HomeGaugeChecks passed. Final unsigned generic-iOS Debug and Release builds passed; only the standard no-AppIntents metadata extraction notice appeared. Whitespace check passed. No installation, visual inspection, NFC/hardware or multi-phone acceptance was performed.
