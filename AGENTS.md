# kickBAC engineering guidance

Read `docs/PROJECT_BRIEF.md` before substantive work; it is the full user-authored engineering brief. Display name is **kickBAC**. Nicholas owns backend/infrastructure FIRST, then ESP32 firmware; Liam owns SwiftUI. Do not rewrite, redesign, reorganize or overwrite his app. Assume concurrent work.

Figma is STRICTLY READ-ONLY, including comments and creations. Known board: https://www.figma.com/board/XlYEabKISK95kAu1XfxaCB/Swamp-Hacks . Load `swamphacks-planning` for event resources and standing project guidance.

STOP and proactively report any material client-facing decision/change with `=== LIAM / iOS IMPACT ===`: what/why/exact client actions/endpoint and payload examples/BREAKING or NON-BREAKING. Includes auth, IDs, schemas, states, timestamps, units, NFC/QR, errors, polling/realtime and app behavior. Firmware-driven contract changes also require `=== BACKEND CONTRACT CHANGE ===` before implementation/merge.

Inspect status, all branches, latest remote state, README/code and teammate work before edits. Never develop/commit on main without explicit permission. Use focused branches from current appropriate base. No destructive Git operations, force pushes, shared history rewrites/rebases, discarded changes, branch takeovers/deletions or unchecked merges. Do not auto-merge unfinished work.

Nicholas expects reviewed owned work to be committed in focused chunks and pushed to remote feature branches regularly. Ordinary feature-branch commits/pushes are authorized; verify the exact remote SHA after pushing and report the branch URL. Do not commit/push directly to main, merge to main or enable auto-merge without explicit authorization. Preserve unrelated dirty work. This policy supersedes historical no-commit/no-push checkpoint text, not safety/collaboration gates.

Prioritize one reliable end-to-end demo. Check existing SwampHacks resources before infrastructure choices. Keep REST/JSON straightforward and firmware HTTP simple. Server owns identities, short-lived exclusive single-use associations, lifecycle and private history. NFC/QR scans identify a unit; authenticated confirmation arms it. Sessions reduce stale association but cannot prove who actually blew into a shared device. Treat raw MQ-3 data separately from estimates; no certified BAC, medical-accuracy or safe-to-drive claims. Clearly label simulated data/authentication. Never log or commit secrets.

`docs/API.md` is the human-readable integration contract. Keep request/response/error examples synchronized with actual OpenAPI and tests. Record significant choices briefly in `docs/DECISIONS.md`. Follow test-driven-development; verify startup, migration, private ownership, expiry, retry idempotency, concurrency and simulator over real HTTP. Never infer hosted/Auth0/iPhone verification from local simulated tests.

After meaningful work report COMPLETED; BRANCH (commits/files/merge readiness); CURRENT ARCHITECTURE (relevant updates); LIAM / iOS IMPACT when applicable; HOW TO TEST (exact commands); NEXT RECOMMENDED STEP; BLOCKERS / QUESTIONS (actual only), using `=== ... ===` headings. Before recommending merge verify latest main, tests/startup/demo/docs match, no secrets/unrelated changes and Liam impact.
