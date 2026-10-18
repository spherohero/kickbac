# Nearby Trivia and deployed party adoption — October 18, 2026

Owner Liam/iOS, uncommitted on liam/party-setup; extensive concurrent edits retained.
Reviewed backend 22c1215...aa90d4c against Liam's consolidated handoff. Standards
and Spec reviews found no actionable defect in the merged party/App reading scope.
PR40 provides atomic resolve/current and one OPEN membership, PR43 provides private
App reading persistence, PR44 records live schema8/38-operation release. Public
OpenAPI read back both resources. These merges contain no shared Trivia engine.

=== LIAM / iOS IMPACT ===

Client scans in Party now persist POST /v1/parties/resolve request UUID/body so the
first phone creates a linked party and the second joins it; no legacy create/bind
fallback. GET /v1/me/parties/current restores the actual account's current room.
Typed active_party_conflict preserves authorized previous-party snapshots and
provides confirmed close(host)/leave(member) recovery. No automatic server cleanup.
Foreground refreshes are silent; they no longer insert/remove a loading row every
2 seconds. Existing Home NFC/App reading behavior and source distinctions retained.

NearbyTrivia.swift uses encrypted MultipeerConnectivity, scoped by a hash of party
and game IDs. Party connection shares host invitation code and participant display
names with nearby connected players; code is not invented for member responses.
A separate game connection carries host-authoritative round state and player ready,
spin and answer commands. Host controls question/deadline/reveal/scoring/progression;
players alternate the spinner and submit one answer. Guest snapshots retain pending
answer locks. At least two ready real peers are required to start. Connection loss
shows reconnection status; retained discovery retries every6seconds. No external
relay, backend gameplay endpoint or competitive score upload is claimed.

NSLocalNetworkUsageDescription and _kickbac-trivia._tcp Bonjour service are declared
in ios/Config/Info.plist. Allow Local Network on both phones; keep Wi-Fi/Bluetooth
on and devices nearby. Both users sign in separately, open Party, scan the same tag,
resolve any previous memberships explicitly, host creates Trivia, both join and
complete/skip the App reading, host starts after both Ready, assigned player spins.
No new demo/showcase banners were added.

Verification: signed Debug device builds passed; PartyIntegrationChecks passed,
TriviaChecks passed including delayed snapshot lock/roster/deadline cases, seven
PartyTransparency source guards passed. NearbyTriviaChecks runs six encoded shared
rounds with rotating turns, both answer orders, shared deadline/scoring/podium.
These tests establish model/wiring, not physical peer transport. Both phones got
an earlier nearby build and launched; user reported actual shared party counts,
then flashing. Silent refresh fixes that cause. Final physical connection/gameplay
acceptance and final phone install status must be reported from fresh readback.

Build logs /tmp/kickbac-nearby-build.log and /tmp/kickbac-nearby-final-build.log.
No commit/push/backend deploy, firmware change, secret access or external teammate
message performed. App reading cloud upload remains separate from today's urgent
party/multiplayer work; existing local records remain preserved.

Final installation readback: identical corrected signed build installed and launched
on Liam's iPhone17 and giraffe/iPhone17ProMax. Giraffe final installation container
66D57971-791D-439E-BF47-06C92FE042A4, database sequence4456; Liam sequence3536.
Final PartyIntegrationChecks, seven source guards and whitespace checks passed.
Final build includes silent background restore, party-level invitation-code/name
sharing before Trivia, game-level authoritative rounds, pending-answer locks and
retained-discovery reconnect. User physical acceptance after this correction is
pending their reply; do not call two-phone gameplay verified merely from install.
