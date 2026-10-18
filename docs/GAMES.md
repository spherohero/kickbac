# Games, profile-wide points and private reading history

Status: **LIVE at https://api.kickbac.vodka**, now schema6/33 operations with the party/context additions below. Generic results were originally published in [PR #7](https://github.com/spherohero/kickbac/pull/7); the following schema3→4/17-operation evidence is historical. Explicit backed-up schema3→4 upgrade, staged target-host HTTP/profile/game/restart/migration checks and public17-operation contract verification passed. All14 earlier operations/18 component schemas are unchanged. See [BACKEND_RELEASE_VERIFICATION.md](BACKEND_RELEASE_VERIFICATION.md) and [LIAM_BACKEND_HANDOFF.md](LIAM_BACKEND_HANDOFF.md). Real native token/profile/history/game acceptance remains Liam-owned and unverified.

## Party/context additions — deployed, not a gameplay engine

The reviewed source in [PR #26](https://github.com/spherohero/kickbac/pull/26)
adds host-controlled parties/device assignment/game instances, one own completion
per instance, explicit owned measurement links, and `GET /v1/me/game-history`.
Read [PARTIES.md](PARTIES.md) for the exact contract. Generic live routes and their
five-field requests/responses below stay unchanged; party results share the same
immutable ledger and fixed 10-point award. Rich history returns explicit null
context for legacy rows, not guessed party/placement/BAC. All accepted readings
remain in ordinary private history. These source additions passed independent
review and CI and are deployed with schema6; this is not shared gameplay, anti-cheat, a public
leaderboard or native acceptance. Backend ARM-time context is now deployed
through [NFC check-ins](NFC_CHECK_IN.md); a check-in-linked reading cannot
be attached to another party/game or promoted from party-only into game context.

## Figma scope inspected read-only

Board: https://www.figma.com/board/XlYEabKISK95kAu1XfxaCB/Swamp-Hacks . Current `Party lofi` section `78:227` shows code join/create, a party room, a game picker with **Trivia** and **Pictionary**, and a leaderboard affordance. `Me lofi` section `83:227` shows **Games played**, **Wins**, **Points**, **Parties** and **Reading history — Private**. Table `23:184` describes games earning points and excludes manually scored games.

This milestone deliberately implements the user's requested **single shared game-result store and profile-wide points**, not the entire Figma roadmap. It is an authenticated persistence API for automatically reported game outcomes. No party creation/join/membership/count, shared live state, drawing/answer engine, public leaderboard or verified competitive scoring is implemented here. Do not substitute mock party statistics for server data, or interpret an arbitrary `data` property as an authorized server-side party record.

## === LIAM / iOS IMPACT ===

**Additive / NON-BREAKING:** existing `/v1/me`, `/v1/me/profile`, device/session and reading-history schemas do not change. Add:

| Method | Path | Purpose |
|---|---|---|
| POST | `/v1/me/game-results` | Persist one completed game outcome, award participation points once |
| GET | `/v1/me/game-results` | Own paginated game-result history, optional game filter |
| GET | `/v1/me/stats` | Own total points/games/wins and per-game statistics |

Use the same Auth0 API access token. Owner comes exclusively from verified token `sub`. The app must not submit an owner, phone number, point total or points award. Profile edits never reset game points or reading history. Names are not unique identities.

## Save a completed result

`POST /v1/me/game-results`, JSON and user Bearer token. All five top-level fields are required:

```json
{
  "result_id": "2889d6a0-4719-4f23-a397-37c51d24129e",
  "game_id": "trivia",
  "score": 8,
  "outcome": "win",
  "data": {"correct_answers": 8, "questions": 10}
}
```

- `result_id`: UUID generated **once for that completion**, persisted with the exact pending payload before sending. Reuse after timeout/relaunch/reconnect. Never generate a fresh ID just to retry.
- `game_id`: strict lower-case slug, regex `^[a-z][a-z0-9_-]{0,63}$`. Current UI examples: `trivia`, `pictionary`; schema supports future games without a table per game. Accepting a slug does not implement its gameplay.
- `score`: strict integer 0–1,000,000, not a boolean/string/float. It is game-specific, **not the profile-wide point award**. Do not compare raw scores across unlike games.
- `outcome`: `win`, `loss`, `draw` or `completed` when no win/loss applies. The server records the client report; it does not verify the answer engine/drawing outcome.
- `data`: required JSON object (empty `{}` allowed) for bounded game-specific result details. Not an unbounded blob, live multiplayer state, image store or secret container. Serialized canonical UTF-8 JSON is capped at 4096 bytes; nesting at most 4 below root; at most128 JSON value nodes, object keys1–64characters, arrays at most64items, strings at most512Unicode codepoints, finite numbers with absolute value at most1e12. Whole POST body at most32KiB, counted during streaming even when Content-Length is absent/false. Final validation/error behavior is documented by the implementation/OpenAPI.

Unknown top-level fields, `user_id`, `awarded_points`, extra ownership/profile/BAC claims and invalid data/types are rejected.

### Result response: 201 first insert, 200 identical retry

```json
{
  "result_id": "2889d6a0-4719-4f23-a397-37c51d24129e",
  "user_id": "sms|opaque-example",
  "game_id": "trivia",
  "score": 8,
  "outcome": "win",
  "data": {"correct_answers": 8, "questions": 10},
  "awarded_points": 10,
  "scoring_policy": "completion_v1",
  "source": "client_reported",
  "created_at": "2026-10-18T00:00:00+00:00"
}
```

The fixed **10 participation points** are server-assigned once per unique accepted completed result, regardless of score/outcome/BAC. The original record and timestamp are returned on an identical retry; no second award. Reordering JSON object keys is not a changed payload. Same own ID with changed accepted content returns409 `idempotency_conflict`; a result ID already owned by a different subject returns404 without exposing their record.

The immutable result ledger is the source of totals (SQL aggregate), rather than trusting a client-supplied running balance or separately incrementing points in profile PUT. This prevents duplicate/lost awards during retries/concurrent requests. `completion_v1` is an explicit initial policy, not a Figma-defined scoring rule.

**Trust limit:** authenticated client-reported completions can still be fabricated or submitted under new IDs. This is hackathon progress storage, not a tamper-proof leaderboard, award/prize/currency mechanism or proof of playing. Do not add a manual “give points” form or award points for BAC, alcohol consumption, reaching intoxication or performing more breath tests.

## Load own game history

`GET /v1/me/game-results?limit=50&offset=0&game_id=trivia`

`game_id` is optional. Limit1–100/default50; offset nonnegative/default0. Stable order: newest server `created_at` then result ID descending.

```json
{"items":[],"limit":50,"offset":0,"has_more":false}
```

Items have the full result response shape above. Use actual `has_more`; no guessed count. Each user sees only their own records. No per-user ID query, public profile lookup or other-player result list.

## Load profile-wide stats

`GET /v1/me/stats` with user token. Before any result:

```json
{
  "user_id": "sms|opaque-example",
  "total_points": 0,
  "games_played": 0,
  "wins": 0,
  "per_game": []
}
```

After the example result:

```json
{
  "user_id": "sms|opaque-example",
  "total_points": 10,
  "games_played": 1,
  "wins": 1,
  "per_game": [
    {"game_id":"trivia","total_points":10,"games_played":1,"wins":1,"best_score":8}
  ]
}
```

`per_game` sorted game ID ascending. Totals are per authenticated account across game types; `wins` counts only `outcome: win`, `games_played` counts unique saved completions. `best_score` only makes sense within that game ID; this initial store assumes higher scores are better. No `parties` count is returned because no party membership is implemented. An API error is not zero games/points; keep a clear unavailable/error state instead of overwriting existing stats with fabricated zeros.

Profile GET/PUT remain unchanged; use a separate stats request to populate Figma's Me counters. Save/load/editing a picture/name does not create a new identity or modify stats.

## Private reading history — already implemented and persisted

Every accepted breathalyzer/simulator test is stored as its own measurement owned by the verified user associated with that test session. The profile and measurement rows share the same opaque user ID; readings need not be duplicated inside the profile row or resent after onboarding.

For Figma's **Me → Reading history (Private)** use:

`GET /v1/measurements?limit=50&offset=0`

- Default50, maximum100, nonnegative offset; response `{items,limit,offset,has_more}`.
- Newest server receive time first, then ID descending. Profile creation, name/photo edits, logout/login with the same subject and server restart preserve records.
- Every measurement includes its own `id`, `session_id`, `device_id`, raw reading/units, `source`, `breath_duration_ms`, optional `measured_at`, server `received_at` and nullable `estimated_bac_percent`.
- Private token scope only; no user ID in the request, and no phone/profile supplied by the device. Idempotent device reconnect retries do not duplicate tests.
- **Current uncalibrated MQ-3 returns `estimated_bac_percent: null`.** Store/show the test with raw ADC counts/prototype/simulated label and unavailable BAC. Null is not0.00; do not invent a conversion or safe-to-drive assessment.
- Invalid, rejected or expired-session uploads are not valid completed readings; do not fabricate zero readings for them. The current API does not persist separate unsuccessful-breath-attempt records.
- The app does not submit ESP32 measurements or receive its private device credential. Coordinate a real hardware test with Nicholas; local fixtures are not measured BAC.

## Error/retry rules

Existing `{"error":{"code":"...","message":"..."}}` envelope, authenticated401/Bearer challenge and standard404/409/422/500/503 behavior remain. New bounded game-body/data overflow uses413 `payload_too_large`; invalid type/shape/depth/value uses422 `validation_error`. Preserve pending completion IDs/payloads on transient failure. Do not retry an idempotency conflict with a new ID to manufacture points.

Responses for own stats/results use no-store. Never log Bearer tokens, contact data, full `data` payloads, pictures or private readings. Phone is Auth0-owned; no client phone claim merges accounts.
