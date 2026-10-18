# Shared Trivia gameplay gap — October 18, 2026

Follow-up: the current working tree also contains an uncommitted
`NearbyTrivia.swift` transport using MultipeerConnectivity and host-owned round
snapshots. Its model replay now covers delayed snapshots preserving a locked
guest answer, host acceptance/scoring, next-round reset, deadline rejection and
round-roster enforcement. This is a nearby prototype, not a deployed backend
gameplay contract; physical two-phone discovery, reconnect and gameplay remain
unverified. The backend requirements below still apply to server-owned gameplay.

Liam requested a host-started game invitation for every party member and asked
that gameplay work across phones. The client now discovers server-created OPEN
Trivia instances with foreground polling and presents one invitation per phone.
That polling shares the invitation; the nearby prototype separately transports
round state between connected phones.

The live OpenAPI inspected for this work exposes game-instance create/list/close,
private check-ins and private result submission. It has no participant/ready
roster, shared round state, turn selection, question/deadline, answer collection
or reveal/scoring operations. The nearby prototype exchanges `TriviaPreview`
snapshots with the party host. Guest clients use the actual party role instead of
being treated as hosts. No two-phone synchronized gameplay is accepted.

## Backend work required before shared gameplay can be connected

- Provide a member-authorized current game snapshot with a revision, participant
  join/skip/readiness, host, phase, round, spinner, category/question and absolute
  answer deadline. Never expose another player's private measurement/BAC.
- Define host start, assigned-player spin, one locked answer per player/round,
  server-controlled reveal/scoring, next round and completion. Require versioned,
  idempotent mutations so retries and two simultaneous phones cannot fork a round.
- Resolve player identity and display names through authorized membership; do not
  use each phone's local `you` identity or example roster as network participants.
- Keep Liam's explicitly requested fake NFC 0.00 and random touch demos separate
  from real device check-ins. They are local App readings, not server-confirmed
  sensor sessions or competitive results. Agree how demo readiness participates
  in a shared game before implementing it.
- Validate with two independent authenticated clients: both see the same game,
  join/skip/ready state, spinner, question/deadline, locked answers, reveal and
  final standings; cover reconnect, expiry, duplicate submissions and owner change.

These are requirements for a new contract, not invented deployed routes. No
backend change, deployment, teammate message, test arming or score upload was made.
Background invitation delivery also needs APNs/device-token support if required;
the delivered client polling operates only while the app/Party view is active.
