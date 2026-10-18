# kickBAC engineering guidance

Read `docs/PROJECT_BRIEF.md` before substantive work; it is the full user-authored engineering brief. Display name is **kickBAC**. Nicholas owns backend/infrastructure FIRST, then ESP32 firmware; Liam owns SwiftUI. Do not rewrite, redesign, reorganize or overwrite his app. Assume concurrent work.

## Current delivery scope

Nicholas explicitly authorized full GitHub control for this kickBAC project: focused commits, branch publication, reviewed PRs and tested merges. This supersedes older no-push/no-merge checkpoints, not protection of teammate work/secrets or the prohibition on force-push/history rewrites/destructive resets/branch deletion. Keep unfinished firmware/client work off main.

Backend profile, phone Action source, deployment artifacts, JWKS cache hardening and generic games are published/merged. Current games release exposes17 operations and requires explicit schema4 migration; inspect current live OpenAPI and `docs/BACKEND_RELEASE_VERIFICATION.md`, not older schema2/3-only notes. Phone stays Auth0-owned; name/photo use private `/v1/me/profile`. Per-person test history already persists by the same verified subject at `/v1/measurements`, independent of profile creation/edits; unavailable BAC is null, not zero. Generic game results/stats use an immutable private ledger and10 participation points per completion, never BAC/drinking/test rewards. Client-reported games are not verified competitive scoring, a party engine or a public leaderboard.

Use `docs/LIAM_BACKEND_HANDOFF.md` for client catch-up. Liam owns real native login/access-token/profile/history/game acceptance; delegation does not mean those tests passed. Auth0 SMS/grant and separate feedback deployment/binding are configured; do not repeat Twilio approval/funding/setup from stale notes. GitHub CI workflow publication currently requires the saved login's missing workflow scope; do not claim CI ran until remote checks prove it.

Preserve concurrent firmware worktrees; coordinate any pressure-less duration/quality contract change before implementing it. Do not fabricate breath duration, a sober/zero reading on no trigger, or calibrated BAC. No firmware changes are part of this backend delivery.

Figma is STRICTLY READ-ONLY, including comments and creations. Known board: https://www.figma.com/board/XlYEabKISK95kAu1XfxaCB/Swamp-Hacks . Load `swamphacks-planning` for event resources and standing project guidance.

STOP and proactively report any material client-facing decision/change with `=== LIAM / iOS IMPACT ===`: what/why/exact client actions/endpoint and payload examples/BREAKING or NON-BREAKING. Includes auth, IDs, schemas, states, timestamps, units, NFC/QR, errors, polling/realtime and app behavior. Firmware-driven contract changes also require `=== BACKEND CONTRACT CHANGE ===` before implementation/merge.

Inspect status, all branches, latest remote state, README/code and teammate work before edits. Never develop/commit on main without explicit permission. Use focused branches from current appropriate base. No destructive Git operations, force pushes, shared history rewrites/rebases, discarded changes, branch takeovers/deletions or unchecked merges. Do not auto-merge unfinished work.

Prioritize one reliable end-to-end demo. Check existing SwampHacks resources before infrastructure choices. Keep REST/JSON straightforward and firmware HTTP simple. Server owns identities, short-lived exclusive single-use associations, lifecycle and private history. NFC/QR scans identify a unit; authenticated confirmation arms it. Sessions reduce stale association but cannot prove who actually blew into a shared device. Treat raw MQ-3 data separately from estimates; no certified BAC, medical-accuracy or safe-to-drive claims. Clearly label simulated data/authentication. Never log or commit secrets.

`docs/API.md` is the human-readable integration contract. Keep request/response/error examples synchronized with actual OpenAPI and tests. Record significant choices briefly in `docs/DECISIONS.md`. Follow test-driven-development; verify startup, migration, private ownership, expiry, retry idempotency, concurrency and simulator over real HTTP. Never infer hosted/Auth0/iPhone verification from local simulated tests.

After meaningful work report COMPLETED; BRANCH (commits/files/merge readiness); CURRENT ARCHITECTURE (relevant updates); LIAM / iOS IMPACT when applicable; HOW TO TEST (exact commands); NEXT RECOMMENDED STEP; BLOCKERS / QUESTIONS (actual only), using `=== ... ===` headings. Before recommending merge verify latest main, tests/startup/demo/docs match, no secrets/unrelated changes and Liam impact.
