# Nicholas: linked party setup deployment and existing-party repair

October 18, 2026. Owner Liam/iOS. Local branch `liam/party-setup`, base
`03a88175820dbad2d1c5a065aa307156e71c9f3b`; changes are uncommitted in Liam's
shared dirty checkout. Preserve unrelated edits. No backend deployment, grant,
production cleanup, commit/push or external notification was performed here.

## Current blocker

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

## Required permanent fix

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

## Temporary repair for a party already saved

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

## === LIAM / iOS IMPACT ===

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
