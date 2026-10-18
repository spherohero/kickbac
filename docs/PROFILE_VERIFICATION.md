# kickBAC profile backend — deployed checkpoint

**Historical initial profile-deployment checkpoint.** Profiles are now published in merged [PR #3](https://github.com/spherohero/kickbac/pull/3); later phone/deployment/auth hardening/games are also published. Current games/schema4 release supersedes this schema3 symlink. Use [BACKEND_RELEASE_VERIFICATION.md](BACKEND_RELEASE_VERIFICATION.md) for current source/runtime status. The working-tree/no-push wording below describes the original deployment, not a current publication blocker.

**Live:** https://api.kickbac.vodka ; contract: https://api.kickbac.vodka/openapi.json ; docs: https://api.kickbac.vodka/docs .

## Implemented and verified

- Phone account stays with Auth0 SMS. The new private `GET` and `PUT /v1/me/profile` persist display name + sanitized JPEG picture against the existing validated Auth0 subject.
- `/v1/me` remains exactly `user_id`; all 12 pre-existing operations and all pre-existing OpenAPI component schemas were compared before/after deployment and are unchanged. Live contract now has 14 operations.
- New accounts return 200 with null profile fields. GET performs no writes; PUT atomically replaces both required fields, preserves creation time, uses server update time, and allows explicit null to remove a picture. No client user ID, verified phone or external image URL accepted.
- Strict 80-codepoint name limit, canonical Base64, decoded-image cap 512 KiB, 2048px input edge cap, 1 MiB streamed request cap. JPEG/PNG only. Photos are decoded, resized to at most 512px, EXIF-oriented, stripped of metadata and saved as JPEG. Damaged PNG IEND framing/CRCs are explicitly checked beyond Pillow validation.
- **185 tests passed** after independent review and five RED→GREEN PNG checksum/truncation regressions. Ruff lint / 38-file formatting / compilation pass. Dependency audit: 22 runtime packages, zero known vulnerabilities returned at this checkpoint; only new locked dependency is Pillow13.0.0, all previous dependency versions unchanged.
- Local and target Python3.12 real-loopback HTTP checks pass for profile save/load, picture normalization/removal, ownership isolation, request streaming caps and fresh-server/fresh-token persistence. Existing simulator returns `SIMULATOR_OK`, COMPLETE, one measurement, zero duplicates, foreign-owner404 and restartok. These use explicit isolated signed OIDC and image/sensor fixtures, NOT real Auth0/iPhone/sensor evidence.

## Actual deployment

- Existing authorized VM only, no new paid services. Release `/opt/kickbac/releases/profiles-20261017T235249Z`, activated **2026-10-17T23:53:50.810585+00:00**.
- Profile worktree `../kickbac-profiles`, branch `backend/profiles`, based on main `8b222c1`. Runtime is **uncommitted working-tree code**, not a newly published Git commit. Allowlisted archive SHA256 `cba7b6361850cdc8ef61b3e141a6ee821e1614da34f1c369da53ac1650e1b5c9`; 26 manifest entries verified on VM, including runtime/deployment/check files. No dotenv/credential/database/iOS archive payload.
- Migration003 first tested on a private VM-local copy of the production DB; all old rows preserved, repeated initialize passed. Actual update paused API/timer, took an exact pre-upgrade online SQLite snapshot, explicitly migrated schema2→3, compared old table contents unchanged, switched source/runtime, then restarted API and backup timer.
- Existing device rows1, sessions0, measurements0 at upgrade; no customer data or fixture records inserted into production. Before/after snapshots passed integrity, schema and mode0600 checks. Backup includes profile BLOBs because they live in the same SQLite file.
- New runtime is release-local: `/opt/kickbac/current/venv/bin/python`. Override `/etc/systemd/system/kickbac.service.d/profile-runtime.conf` changes only ExecStart's interpreter path; sandbox/user/single loopback worker remain. Previous release and former `/opt/kickbac/venv` are preserved.
- Public trusted HTTPS health200 and OpenAPI200 after restart; both new profile methods without credentials return401/normal error envelope with `Cache-Control: no-store`. API/Caddy/timer active.

## Liam / iOS impact — NON-BREAKING

The server is ready for integration. See [PROFILES.md](PROFILES.md) for exact JSON, image conversion/size limits, response shape and atomic replacement/removal/retry behavior. GET after login/relaunch; PUT the collected name and selected photo at the end of onboarding and wait for success. Phone stays Auth0-owned; same token/identity as measurements. No SwiftUI files changed.

## Remaining, not misreported as done

Liam still needs to wire the new save/load calls and verify an actual native access token against the live API, then relogin/profile/history. No iPhone build, real user's profile upload or production-auth bypass was performed. PostLogin feedback configuration is complete; its execution after a real SMS login remains unverified. Native NFC/QR launch, firmware/hardware and calibrated sensing remain separate.

This is controlled hackathon hosting: snapshots are local to the VM, no OS reboot/off-host recovery/account-deletion acceptance is claimed. Existing per-key JWT cache-freshness concern remains outside this profile change. No commits, pushes or merges were requested/performed; original phone/deployment/firmware worktrees are preserved. Before rollback, note that the pre-profile code refuses schema3: preserve current DB/profile data and coordinate an explicit migration/data plan rather than just switching the symlink or silently restoring an old snapshot.
