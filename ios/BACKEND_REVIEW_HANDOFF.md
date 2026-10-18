# iOS integration review and iPhone test handoff

The iOS review branch includes current main's published backend, games, deployment, CI and firmware diagnostic sources. Backend source publication is no longer a blocker. The iOS changes consume existing contracts; no server path, payload, identity, duration or scoring policy was changed.

## Implemented

- Embedded Auth0 SMS OTP with exact audience `https://kickbac-api`, API base `https://api.kickbac.vodka`, and SDK Keychain credentials.
- First-login storage handles absent Keychain items during SDK cleanup, while rejecting actual write/delete failures. The regression reproduces the former secure-sign-in error with an empty store; credentials remain Keychain-backed and prior session metadata is still cleared.
- Profile GET/PUT, explicit null photo removal, normalized bounded JPEGs, server-confirmed saves, retries, account-scoped cache and stale-response protection. Concurrent profile loaders await one request. Camera denial does not trap onboarding: Skip photo is available.
- Private paginated measurement history in server receipt order. Home uses actual loaded nonsimulated estimates; null stays unavailable/raw. Debug demo is labeled and isolated.
- QR/manual trusted device selection, public resolver, authenticated availability, explicit empty-JSON arm, session poll/backoff/cancel/terminal result and history refresh. Pending sessions persist per subject. Authoritative 404 releases unavailable local tracking without automatic rearming.
- Me loads server Games played/Wins/Points. Party gameplay and game-result submission remain separate work; no scores, completions or party totals are invented.

## Verification and limits

Profile/image/coalesced-load checks, Auth0 SDK request fixtures, API contract checks, and device/session fixtures pass. Device fixtures cover trusted URLs, persistence, offline availability, cancellation, expiry, busy conflicts, unavailable-session recovery, account switching, terminal polling and null/simulated BAC separation. A signed iPhone build and installation are recorded separately from these fixtures. No actual SMS, private photo upload, live device arming or sensor acceptance was performed by the agent. No screen inspection is used after the user's request to stop it.

NFC Tag Reading cannot be provisioned by the current Apple Personal Team. The installed build uses QR/manual entry; NFC/background Universal Links are not claimed to work.

## Test on the iPhone

1. Sign in with your own phone/code. A new account should enter name/photo setup; try Skip photo. A saved account should load its existing profile.
2. Save/edit a name and real photo. Force-quit/reopen, then sign out/in: name/photo and private history should restore. Change only the name and confirm the picture remains. Remove photo deliberately and save.
3. Turn connectivity off before saving an edit: input should remain and the error should permit retry after reconnecting. Switch accounts and confirm no prior private profile/history/stats appears.
4. Home should show dashes when there are no real BAC estimates. Debug Demo must stay visibly labeled and must not add a private history entry.
5. Connect with `kb-demo-01` (or its official QR/link). Inspect online/offline, explicitly Start test, then Cancel. Repeat and allow the server's 60-second session to expire. Relaunch during an active session: it should reload the same session, not arm a new one.
6. A coordinated completed firmware/simulator test should show its actual result and refresh history. Null BAC must show no estimate. This step requires Nicholas's producer readiness; do not expect the current disabled upload firmware to complete a sample.

## Tell Nicholas

No new profile/auth/session/stats endpoint is needed. Coordinate the real SMS login so he can verify post-login feedback execution. Firmware sampling/uploads remain disabled pending electrical checks and a truthful duration/acquisition decision; current `breath_duration_ms` remains a required Int and the nullable-duration proposal is not adopted. For this Personal Team build, supply a QR or printed ID (`kb-demo-01` works for the published demo device) rather than relying on NFC app launch.
