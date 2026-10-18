# Account deletion handoff for Nicholas

## Status

Liam requested permanent account deletion from Settings and assigned backend implementation to Nicholas. This document is prepared locally; it has not been sent or published. No deletion request has been made and no account data has been changed.

Reviewed upstream main: `22f06354e85ad04afe522e6d870b5bf3bb206af8`. Client branch: `liam/ios-profile-handoff`, base `170ad17a08f43232e8ca2ea3650999261b6e080b`, with uncommitted iOS edits. The fetched handoff, API documentation, backend source, and live `https://api.kickbac.vodka/openapi.json` expose no account-deletion operation.

## Requested backend capability

Add authenticated deletion of the caller's own account. Derive ownership from the verified API access token; never accept a caller-supplied owner, phone number, or device credential. Coordinate the exact route and response with Liam before iOS integration. No proposed path in client code is treated as an existing contract.

Deletion must cover the saved profile/photo, private measurements, game results/points, and account-owned session associations. Release active device ownership safely. Auth0 owns the login identity: define and implement its deletion server-side, with Management API credentials kept off iOS. Define any required reauthentication before implementation.

Handle partial failures across Auth0 and application storage, retry after a timeout, and an already-deleted account. Prevent stale requests or still-valid tokens from recreating deleted data. Do not return success while required deletion work remains. If deletion is asynchronous, provide an authenticated way for the client to learn confirmed completion and retry safely.

Publish the agreed methods, request/response shapes, errors, retry semantics, deletion scope, and deployment state in canonical API docs and `docs/LIAM_BACKEND_HANDOFF.md`. Include ownership/isolation, provider failure, active-session release, and retry tests. Report source/tests separately from live deployment and actual deletion acceptance.

## iOS behavior

Settings currently shows Sign out and Delete account. Delete account presents an unavailable message; it does not call an invented endpoint, clear local data, or sign out. Existing sign-out behavior remains separate.

Once the endpoint is agreed and deployed, show a destructive confirmation that states the actual deletion scope. Preserve sign-in/data on failure. After confirmed completion, clear Keychain credentials, account-scoped profile caches and pending sessions, invalidate in-flight loads, and return to signed-out state. Verify deletion using a disposable consenting account; do not delete Liam's account as an unattended check.

## === LIAM / iOS IMPACT ===

Current API is unchanged. Permanent account deletion is pending backend work; the Settings entry is informational only. Profile editing remains on Me, photo retakes remain available, and the editor no longer offers photo removal. Existing profile PUT null semantics remain unchanged.
