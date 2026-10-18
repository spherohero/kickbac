# KickBAC: Nicholas backend handoff — linked parties and app-reading persistence

October 18, 2026. Consolidated from Liam's party-linking handoff and authenticated
app-reading persistence request. This is the single forwardable handoff for both
workstreams. They are independent backend changes; neither requires modifying
firmware measurement semantics.

## Priorities and status

1. **Linked parties:** deploy atomic device-based party creation/joining. The iOS
   change is built and installed, but new creation is blocked until the server
   supports it. A temporary operator permission grant can repair an existing party.
2. **App readings:** publish and deploy an authenticated resource for the existing
   touch-generated records, then add iOS upload/recovery. Records currently save
   locally; backend persistence and cross-phone sync are not implemented.

The deployment/branch observations below are the October 18 handoff snapshots,
not a fresh deployment audit performed during consolidation. Fetch current refs
and recheck live OpenAPI before acting. Do not infer backend implementation,
passing tests, deployment, or physical iPhone acceptance from a proposed contract.

## Ownership and working context

Nicholas owns backend/infrastructure and deployment; Liam owns iOS integration.
Repo on Liam's Mac: `/Users/liammcauliffe/Developer/swamphacks/kickbac-repo`.
Local branch `liam/party-setup`, HEAD/base
`03a88175820dbad2d1c5a065aa307156e71c9f3b`, with extensive concurrent dirty and
untracked work. Preserve it all; do not reset, rebase, take over the branch or
merge unreviewed edits. Work in the backend owner's isolated checkout.

Read repository `AGENTS.md`, `docs/PROJECT_BRIEF.md`,
`docs/bots/backend/START_HERE.md`, `docs/LIAM_BACKEND_HANDOFF.md`, `docs/API.md`,
`docs/PARTIES.md` and current live OpenAPI at
`https://api.kickbac.vodka/openapi.json`. Read remote main's handoff after fetching
when the local branch cannot safely be updated. Deployment/backup procedures are
in `docs/OPERATIONS.md` and `docs/BACKEND_RELEASE_VERIFICATION.md`.

No backend deployment, production permission grant, database upload, bulk cleanup,
commit/push or external notification was performed by these iOS handoff tasks.

## 1. Atomic linked-party setup

### Current blocker

Liam requires that a new party and its breathalyzer binding succeed together.
The deployed API creates an unbound party with POST `/v1/parties`, then requires
a separate PUT `/v1/parties/{party_id}/device` with a per-user operator grant.
That cannot satisfy atomic creation. A failed bind leaves an OPEN party behind.
The reported error is consistent with a missing grant, but the exact current
subject/grant was not verified; the generic 404 alone is not proof of its cause.
Device online/heartbeat status is not a prerequisite in the binding handler.

Fresh public checks: OpenAPI has neither `/v1/parties/resolve` nor
`/v1/me/parties/current`. An unauthenticated empty-body POST to the former returns
HTTP **405**, `error.code=not_found`; it created no authenticated party. The
registered public target remains `https://api.kickbac.vodka/d/kb-demo-01`.

### Required permanent fix

Implement and deploy the already frozen contract on remote
`backend/device-party-resolve`, documentation head
`cdba99b65af740ae77c2f4a1c3416ff20e6d8004`, based on main `22c1215`.
Read `docs/DEVICE_PARTY_RESOLVE.md` from that branch. A final fetch advanced the
branch to `c6dfecc` with HTTP acceptance tests, but still no implementation changes
relative to main. No open PR was found at the earlier inspection. Do not assume
implementation, passing new backend tests, merge or deployment.

```http
POST /v1/parties/resolve
Authorization: Bearer <user API access token>
Content-Type: application/json

{"request_id":"<persisted UUID>","device_id":"kb-demo-01","name":"Friday"}
```

Return `{"action":"created"|"joined","party":<existing PartyResponse>}`.
Within one transaction, join the already bound OPEN party or create name/code,
host membership and binding together. No new-route per-user grant, unknown-device
provisioning, implicit host transfer, test arming or partial creation. Roll back
every setup write on failure. Persist owner-private exact-request idempotency;
retries must not create another party, restore a left membership or reopen a
closed party. Member `join_code` may remain null. Enforce the documented one-OPEN-
membership policy and return `active_party_conflict` with authorized context.

Follow that contract's migration007, backup/private-copy trial, legacy duplicate
preservation, concurrency and retry tests before deployment. Existing multiple
OPEN memberships require explicit host close/member leave; no automatic choice,
mass deletion or silent reassignment. Publish live OpenAPI/deployment evidence
and the exact released SHA in `docs/LIAM_BACKEND_HANDOFF.md`.

### Temporary repair for a party already saved

Nicholas can verify Liam's **current authenticated opaque subject**, registered
device and host membership, then grant the existing binding permission on the
production host. Do not use a phone number/display name or guess the subject.
After confirming the configured DB/release, the existing operator command is:

```sh
cd /opt/kickbac/current/backend
runuser -u kickbac -- env KICKBAC_DB_PATH=/var/lib/kickbac/kickbac.sqlite3 \
  PYTHONDONTWRITEBYTECODE=1 /opt/kickbac/current/venv/bin/python \
  -m kickbac.cli grant-party-device kb-demo-01 '<verified opaque subject>'
```

Then Liam opens his existing host party, chooses Link breathalyzer, scans and
retries. Require the server's OPEN party response to contain
`device_id=kb-demo-01`. This grant repairs an existing party; it does **not** enable
the new atomic creation flow or replace the permanent deployment. Resolve a
competing binding or active session through its normal lifecycle, not by bypass.
Keep all device credentials out of the app, NFC tag, logs and handoff.

### iOS implementation and verification

Intentional client behavior change; proposed server contract is not deployed.
Fresh Create now persists an exact resolve request before sending it. It has no
fallback to legacy create-then-bind, so an unavailable endpoint cannot leave new
unlinked parties. UI accepts OPEN success only with the scanned device confirmed;
existing-party joins preserve server name/role, and CLOSED replays stay closed.
Timeouts preserve the UUID/body across relaunch; definitive 404/405 can be retried
or explicitly discarded. Legacy pending creates recover through GET of their
original party UUID, never another unbound POST. Existing parties retain their
explicit binding repair and close actions. Current-party restoration still uses
existing selected-ID/list reads; the new current endpoint is not yet consumed.

Party Swift integration checks passed, including exact retry/relaunch, rejected
unlinked/wrong-device responses, joined member with null code, closed replay,
HTTP405 with exactly one resolve request/no fallback, and read-only legacy recovery.
The focused UI wiring guard and signed Debug device build passed. devicectl
confirmed installation on Liam's connected iPhone. Build log:
`/tmp/kickbac-atomic-party-build.log`. No live authenticated successful resolve,
physical NFC acceptance or production permission change was tested.

Next: deploy/verify the backend contract, then test two signed-in phones scanning
the same device, exact retries, busy/unknown devices, duplicate-membership cleanup,
and restart with history intact. Liam should not keep recreating parties to try
to fix a missing host grant.

## 2. Authenticated app-reading persistence

Liam wants the existing center-touch readings saved in the backend database and
available after relaunch and on another signed-in phone. Keep presentation concise
with the App reading label and no repeated simulation banners; preserve generated
provenance in storage, responses and interpretation.

### Current state

The iOS center-touch flow generates a random value; it does not collect a physical
BAC measurement. `PracticeReadingStore.swift` saves UUID, value, date and actual
hold duration atomically in account-scoped local storage. Existing local records
are preserved. Reading history already includes those records. They are labeled
App reading, keeping their origin distinct from actual device readings while
removing the repeated Simulated/practice/phone-only captions Liam disliked.

Refreshed public OpenAPI: `/tmp/kickbac-reading-sync-openapi.json` on Liam's Mac.
Current routes:

- POST `/v1/device/measurements`: device credential and valid server session;
  the iPhone must not impersonate firmware or receive its credential.
- GET `/v1/measurements`: user's accepted measurement history, read-only.
- GET `/v1/me/reading-summary`: user's measurement summary, read-only.

There is no supported authenticated user write route for app-generated readings.
No app-reading database upload has been implemented or claimed. Local saves work.
Do not relabel generated values as device sensor measurements, invent raw ADC
samples, arm a production session to fabricate a result, or replace null physical
BAC with these numbers.

### Requested backend operation

Add a private authenticated app-reading resource. Proposed, not implemented:

```http
POST /v1/me/app-readings
Authorization: Bearer <API access token>
Content-Type: application/json

{
  "reading_id": "<existing local UUID>",
  "value": 0.08,
  "recorded_at": "<ISO 8601 UTC>",
  "duration_ms": 2500,
  "source": "app_generated"
}
```

The value is an app-generated sample, not a validated BAC estimate. The server
owns the token-subject association and must preserve that source. Prefer a
separate table/resource rather than manufacturing device/session/measurement rows.
Nicholas should confirm/publish exact route, schema, timestamp handling and limits
before iOS adoption. Retain existing device/session/history behavior.

Required semantics:

- Owner-scoped, UUID-idempotent save: new 201, exact retry 200, changed accepted
  payload conflict. No client-supplied account subject or credentials in records.
- Server receipt includes accepted ID, immutable source and canonical timestamps.
  The app marks Synced only after that receipt; local write is not a cloud receipt.
- Paginated private GET and account summary support reload on another phone.
  Define counts and aggregation explicitly; preserve app/device provenance and do
  not let generated values become physical test readiness or sensor validation.
- Offline/relaunch retries reuse the existing local UUID and original payload.
  Deduplicate merged local/server history by that identity. Preserve all existing
  local records during migration and never delete the only copy on upload failure.
- Guest records remain guest-scoped until the user explicitly assigns them to an
  account; do not silently upload another account's or an anonymous user's history.
- Validate finite/ranged value, actual bounded hold duration, aware timestamps,
  request size, ownership and rate limits. Save atomically; do not award points for
  readings or change firmware credentials, session ownership or acquisition data.


### iOS source and remaining implementation

- `ios/KickBAC/PracticeReadingStore.swift`: durable local records, existing UUIDs
  and owner fences. Preserve all existing records during migration.
- `ios/KickBAC/HomeView.swift`: touch flow, App reading result, bottom connection
  status and countdown-only timer. Idle circle contains no connection caption.
- `ios/KickBAC/ProfileHistoryView.swift`: merged local/device presentation.
- `ios/KickBAC/AuthSession.swift` and `ios/KickBAC/KickBACAPI.swift`: authenticated
  API seams.
- `ios/checks/PracticeReadingChecks.swift`: persistence, isolation and failure checks.

After the backend contract is confirmed and deployed, implement an owner-scoped
persistent upload outbox with exact retry payloads, receipt validation,
merged/deduplicated history and honest sync status. Do not add a speculative POST
to an undeployed endpoint and call cloud persistence complete. Local save success
must never imply a database receipt. No production app-reading upload was tested.

## Shared delivery and acceptance requirements

Publish source/branch/head/base, PR/merge/deployment state, exact endpoint schemas,
examples/errors, migration and backup evidence, ownership/idempotency tests and
live readback in `docs/LIAM_BACKEND_HANDOFF.md` and canonical API/history docs.
Report `=== LIAM / iOS IMPACT ===` before material client-facing changes, clearly
separating proposed versus deployed behavior and identifying compatibility impact.
Neither workstream changes firmware paths, device credentials, measurement/session
ownership, acquisition semantics or the meaning of unavailable physical BAC.

Party source to inspect: `ios/KickBAC/PartyAPI.swift`, `PartyStore.swift`,
`PartyLiveView.swift`, and `ios/checks/PartyIntegrationChecks.swift`. The party
checks/build evidence is recorded above. App-reading acceptance must additionally
cover offline save/relaunch/retry, account switching, unchanged existing local
records, exact UUID deduplication and authenticated reload on a second phone.
Keep fixture/CI success, deployment verification and real native acceptance distinct.

## Suggested skills and locations

On Liam's Mac, read the applicable `SKILL.md` before use:

- Minimal implementation: `/Users/liammcauliffe/.agents/skills/ponytail/SKILL.md`.
- Diagnosis: `/Users/liammcauliffe/.agents/skills/diagnosing-bugs/SKILL.md`.
- Retry/ownership/concurrency tests:
  `/Users/liammcauliffe/.agents/skills/tdd/SKILL.md`.
- iOS integration:
  `/Users/liammcauliffe/.codex/skills/swiftui-expert-skill/SKILL.md`.

These are Mac-local paths, not assumed installed on Nicholas's host. Discover
available equivalents there. For iOS copy/layout changes also read `ios/AGENTS.md`
and `ios/DESIGN.md`; retain the established design and concurrent user edits.
