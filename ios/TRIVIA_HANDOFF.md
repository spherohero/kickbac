# Trivia — local gameplay with real private check-in

Owner Liam/iOS; branch `liam/party-setup`, implementation head `c06192f73e5c2755f4961aa6c65e0c47811ad81f`.
Base `ef08fa8`; merged main `a0bd77bcb79766f91de6746e0ab02fa992f4b337` through `de47523`. This checkpoint supersedes the earlier automatically simulated breath flow and view-only 0.08 fixture.

## Current flow

1. The authenticated Party tab lists/creates server game-instance context. This persistence is not shared Trivia gameplay. Play local Trivia opens a compact invitation labeled Local game / scores aren't saved or shared.
2. Join opens Your check-in, naming the selected instance's snapshotted device and explaining that reservation does not measure. Explicit Start my test sends the persisted exact check-in request for that party/game/device. There is no inferred current game, personal-device authorization bypass or implicit arm on join.
3. The returned session is adopted into ContentView's existing DeviceSessionStore and displayed by HomeView in game mode. No fresh store, synthetic timer, automatic demo BAC or fake physical completion is used. The operator starts acquisition separately over USB. Busy/offline/expiry/cancel/retry remain honest; closing the screen does not manufacture readiness or create another session.
4. Only the expected session UUID, device and current owner with COMPLETE plus a valid accepted measurement can mark the local player Ready. Manual acquisition preserves null breath duration, actual sample-window duration, the notice Timed sensor sample — breath not validated, and unavailable BAC. Simulator/unknown/manual estimates never become numerical game BAC. The Debug Home demo is isolated from game readiness.
5. The ready page shows own avatar/name/status with Leave game above Start trivia. Leave clears personal readiness/BAC and returns to the party. Rejoining requires another deliberate check-in. The current phone starts its own clearly labeled local run; server role is not used to imply shared round authority. The Debug-only party fixture separately offers explicitly labeled local practice / Continue without a test, with nil BAC; it never reports a successful physical test.
6. Existing local gameplay is preserved: tap/swipe wheel, fixed rounded/outlined pointer, rotating center star, eligible rotating local spinner, one question per local round, six unused categories, fixed question page, solid coral/blue/yellow/green answers with black text and selected outline, line countdown, answer lock and reveal only after everyone local answers or the absolute deadline. No Choose your answer or answered-count copy.
7. Separate round results show the correct answer and per-player earned/total points, without the explanation. Five-second auto-advance and explicit Next round remain; VoiceOver retains results until explicit advance.
8. Final results retain the 2–1–3 podium and list, remove the Good game introduction, and explicitly label local/unsaved standings. Only permitted own check-in BAC appears when available; missing/manual/simulator/example values stay unavailable. BAC never affects rank/reward. No game result or participation award is uploaded. Close/reopen returns to the same local run/deadline/results in that party view; account changes clear it.

## Boundaries

Bundled answers are local and not secret. Twenty seconds, six categories/rounds and 1000 points per correct answer remain local defaults, not an approved server scoring protocol. Example players remain explicit Debug fixtures with nil BAC. No public roster or synchronized state is inferred from private game/check-in history. The persistent accessible local-game label remains present during play, not only in a menu or final screen.

Default Release has real authenticated party/check-in consumers and no automatic sample simulation. NFC/Universal Links remain unavailable: use code/QR/manual-device fallback. KICK26 exists only inside the clearly labeled Debug-only unsaved Party preview. Its 0.7-second caption hold simulates a local fixture action, not NFC success; real screens use explicit authenticated controls.

Server instance creation/close, private check-in and local play are distinct. Host game-context permissions and assigned-device validation stay server-owned. Members can run independent local questions on their own phone; this is not a shared host-start event. Check-in readings remain owner-private, regardless of leaving/closing or whether local play finishes. No fake result enters private history and no raw subject is shown to another player.

## API and retry evidence

See PARTY_HANDOFF.md for exact payloads, persisted bytes/UUIDs, account generation fences, safe rejection discard, returned-session adoption and private-history pagination. Live OpenAPI was read as 33 operations with manual metadata; the backend release handoff records schema6 deployed. New consumer behavior is NON-BREAKING to the server. There is no auth, endpoint, schema, firmware, duration, points or database change. No teammate notification is claimed.

Shared roster, invitations/readiness, question/category authority, rotating turn authority, private submissions, reveal timing, authoritative awards, late join/departure, reconnect and consent-based member BAC visibility still require server contracts. Personal units cannot bypass the assigned-device/operator policy. Native NFC and physical sensor acceptance remain separate.

## Checks and acceptance

```sh
swiftc ios/KickBAC/TriviaPreview.swift ios/checks/TriviaChecks.swift -o /tmp/kickbac-trivia-checks
/tmp/kickbac-trivia-checks
python3 ios/checks/PartyTransparencyChecks.py
# Full retry/acquisition/session commands and build settings: PARTY_HANDOFF.md.
```

Trivia checks cover local readiness/skip/rejoin, late/duplicate/invalid callbacks, finite nullable BAC, spinner authority, shared local question/no category reuse, locked answers, all-answered/deadline reveal, per-player awards and one-time totals. PartyIntegrationChecks execute the production API/store/session logic with synthetic transports, including retry/relaunch/account and manual-null handling. Source guards check Release/UI wiring; they are not native interaction tests.

Debug/Release builds and all listed client checks passed. Final signed Debug installed and `devicectl` confirmed launch on Liam's iPhone with --show-party. No visual inspection, screenshots, Device Hub, real authenticated party/check-in write, physical measurement, NFC, VoiceOver or multi-phone acceptance was performed. Logs: /tmp/kickbac-party-live-signed.log and /tmp/kickbac-party-live-release.log.
