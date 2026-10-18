# Recent games: party groups and check-ins

## Status for Nicholas

Liam requested a Recent games page reached from Games played, Wins, or Points. He wants party names as section headings and game rows with a square image, outcome, awarded points, and that game's breathalyzer check-in. He assigned missing backend fields to a handoff for Nicholas. This handoff is local and has not been sent or published.

Reviewed main: `22f06354e85ad04afe522e6d870b5bf3bb206af8`; client base: `170ad17a08f43232e8ca2ea3650999261b6e080b` on `liam/ios-profile-handoff`, plus uncommitted iOS edits. The fetched shared handoff, API/game docs, and live OpenAPI describe generic game results without a party or linked measurement. The arbitrary `data` object is not an authoritative party record.

## Existing client integration

The page reads `GET /v1/me/game-results?limit=50&offset=0` with the API access token. It shows `game_id`, `outcome`, `score`, `awarded_points`, and `created_at`. It paginates with `has_more`, deduplicates result IDs, preserves loaded rows on transient errors, and clears them when the authenticated subject changes. Every returned row's owner must match the current subject.

Square native game icons provide thumbnails. Until the server provides the missing associations, the section says “Party unavailable” and rows say “Check-in unavailable.” No party names, game results, check-ins, or statistics are invented. Game-result submission and Party gameplay remain separate work.

## Requested contract, not yet adopted

Provide a stable server-owned party identity and display name for each result, plus the authenticated user's measurement associated with that specific game. Coordinate exact field names, null semantics, creation/association flow, and error behavior before iOS consumes them. Use null for unavailable historical associations. Group by party identity, so different parties with the same name stay separate; merge the same party across pagination boundaries.

A check-in needs its stable measurement identity, acquisition/receipt timestamp semantics, source (`simulator` versus `device`), and nullable BAC estimate. Provide an authorized embedded snapshot or an existing authorized lookup path. Do not invent a measurement-detail route or infer association from timestamp proximity. Enforce party membership and measurement ownership server-side, without exposing another player's private reading. A stored association does not establish who physically blew.

Keep raw game score distinct from server-awarded participation points. Current `completion_v1` awards 10 points per saved completion regardless of outcome; no BAC/drinking/test rewards are requested. Preserve existing result retry IDs, immutable ledger semantics, and old requests when adding fields. Changes remain provisional until coordinated and tested.

## === LIAM / iOS IMPACT ===

Current integration is NON-BREAKING and read-only; existing paths and payloads are unchanged. Party grouping and per-game check-ins are pending backend work. Publish the agreed contract in canonical docs/live OpenAPI and `docs/LIAM_BACKEND_HANDOFF.md`, with exact reviewed heads, tests, merge/deployment state, and native verification limits. No backend deployment, party functionality, or live authenticated game-history acceptance is claimed by this client work.
