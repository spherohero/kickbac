# Profile history and parties — requested follow-up, not a live API

## Scope and ownership

Nicholas requested this follow-up in the kickBAC room while authorizing review, merge and cleanup of Liam's current iOS PR #22. This records product requirements for later contract design; it does **not** implement or approve new endpoints, migrations, NFC launch, multiplayer, scoring rules or a deployment. Backend owns persistence, authorization and contract design; Liam owns the native screens; the firmware Bot owns physical-device integration.

## Requested profile behavior

- Private saved-reading history includes **all accepted completed measurements**, whether a normal check or a game-start check. This already persists by the session owner's validated opaque subject. A game association must reference the existing measurement rather than duplicate it or remove it from normal history.
- Show the latest saved reading/check. Preserve raw values/units, source and acquisition-versus-receipt timestamps. A null BAC estimate means unavailable, not zero; the current uncalibrated producer has no numerical BAC estimate.
- Show wins, lifetime points and total games played. The current `GET /v1/me/stats` already provides ledger-derived `wins`, `total_points` and `games_played`; do not compute lifetime totals from one loaded page.
- Open Games played to private paginated game rows, grouped by **stable party identity**, with party name and party date at the section header. Identically named parties remain distinct; merge one party's rows across page boundaries.
- Each row needs a game icon selected by stable `game_id`, the user's game points/score, final placement, and that user's BAC/measurement associated with that specific game. Placement is not derivable from `win|loss|draw|completed` alone.
- Keep **game score** distinct from **server-awarded participation points**. Current `completion_v1` awards 10 points per unique saved completion, independent of score, placement, outcome or BAC. Nicholas's new screen requirements do not silently change that policy. Exact row labels and any future competitive scoring policy require coordination before implementation.

## Requested party behavior

- An authenticated host can create a named party; authenticated players can join by entering its host's code.
- A party can have a breathalyzer assigned to it. Tapping the passive NFC sticker should resolve the device's **current server-side party assignment**, not a party permanently baked into the sticker.
- A static NFC/device URL is an identifier, not authentication, a device credential or proof of membership. Never put private tokens in a tag. Joining a party is separate from explicitly arming a single-user measurement session; neither action proves who physically supplied a sample.
- Both code and device/NFC routes must lead through the same authenticated membership checks. Host authority, assignment changes, party lifecycle, code expiry/collision/guess protection, join/leave/retry behavior and concurrent device use must be specified and tested.
- Current iOS Personal Team provisioning does not support NFC Tag Reading, and background Universal Links are not configured. QR/manual device entry is the existing fallback; a backend party API alone will not enable NFC app launch.

## Existing API versus missing support

Existing routes remain unchanged: `GET /v1/measurements`, `GET /v1/me/stats`, `GET/POST /v1/me/game-results`, `GET /d/{device_id}` and the device/session routes in [API.md](API.md). Current game results have no authoritative party association, final placement or linked measurement; arbitrary `data` is **not** a replacement for server-owned party records. There is no measurement-detail endpoint to invent for clients.

Before implementation, publish an additive contract proposal covering stable party/game-instance/measurement links, nullable legacy associations, timestamp/date semantics, privacy and membership, device reassignment, explicit confirmation, idempotency and consistent errors. Validate measurement ownership and exact game association server-side; never infer them from timestamp proximity or let one participant expose another's private BAC. Preserve original history, immutable accepted results, retry IDs and existing clients through a backed-up migration.

## === LIAM / iOS IMPACT ===

**Current change: NON-BREAKING, documentation only.** No endpoint, payload, auth, identifier, state, timestamp, unit or scoring policy changes. Existing profile replacement still uses both required fields, for example `PUT /v1/me/profile` with `{"display_name":"Example","profile_picture":null}` explicitly clears a photo. Existing result writes still use the five fields documented in [GAMES.md](GAMES.md).

Liam should retain current integrations and unavailable placeholders rather than code speculative paths/fields, infer placement from outcome or show a zero BAC. Backend must publish exact methods, request/response examples, ownership rules and compatibility classification in [LIAM_BACKEND_HANDOFF.md](LIAM_BACKEND_HANDOFF.md) before he implements these additions. Firmware-driven changes also require `=== BACKEND CONTRACT CHANGE ===`; this requirement capture changes no firmware contract.

## Acceptance for later implementation

Test code and NFC/device resolution to the same party, correct host/device assignment, join retries and expiry, concurrent joins/arming/reassignment, nonmember rejection, correct-user game measurement links, no duplicate measurement/points on retry, party grouping across pagination, legacy null fields, restart/migration persistence and cross-account privacy. Keep source tests, simulator execution, native NFC acceptance and real physical sensing as separate evidence levels.
