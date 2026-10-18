# KickBAC iOS

Open `KickBAC.xcodeproj` in Xcode. Resolve Swift packages when prompted.

[Design direction](DESIGN.md) records the approved Home style and conventions for the rest of the app.

Home uses a plain dark background. The Welcome star uses a bundled Metal shader, and the white onboarding pages stay plain. If Xcode reports a missing Metal Toolchain, install Apple's compiler once with `xcodebuild -downloadComponent MetalToolchain`.

All user-facing app names use `KickBAC`. The iOS launch configuration, Welcome, and splash view share `KickBACWordmark`. Its 1x/2x/3x PNGs come from the Mogi vector source in `Branding/KickBACWordmark.pdf`; regenerate with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift ios/Branding/generate-wordmark.swift` from the repository root. Run `python3 ios/checks/BrandingChecks.py` to check naming and launch asset wiring. These checks do not verify iOS's cached launch rendering.

## Auth0 handoff

| Setting | Value |
| --- | --- |
| Bundle identifier | `com.liam.KickBAC` |
| URL scheme | `com.liam.KickBAC` |
| Auth0 domain | `dev-c87oxm4dkbyatvrn.us.auth0.com` |
| Client ID | `5gJK2T71UkL0fbVj9pbzzEzKeMWZoYlC` |
| API audience | `https://kickbac-api` |
| Connection | `sms` |
| Scopes | `openid profile` |
| API base | `https://api.kickbac.vodka` |

Both Allowed Callback URLs and Allowed Logout URLs must contain:

```text
com.liam.KickBAC://dev-c87oxm4dkbyatvrn.us.auth0.com/ios/com.liam.KickBAC/callback
```

The app uses Auth0.swift 3.1 through Swift Package Manager. Following Liam's confirmed native flow, `startPasswordless` requests an SMS for the E.164 phone number, then `login(phoneNumber:code:audience:scope:)` exchanges the entered six-digit code using the Passwordless OTP grant. This replaces the earlier hosted Authorization Code + PKCE flow: no browser sign-in session opens. Auth0 verifies the code, and the SDK validates the returned ID token's claims before credentials are saved. This is primary login, not MFA. Phone delivery stays server-side; iOS contains no Twilio SDK, client secret, device credential, or new kickBAC send/verify endpoint.

Credentials are stored with the SDK's Keychain-backed `CredentialsManager`. The requested scopes intentionally omit `email` and `offline_access`; when the stored access token can no longer be used, the app asks the user to sign in again. Logout clears Keychain credentials; native SMS login creates no browser session. Account changes clear in-memory private data; results from an older session are discarded.

`SessionCredentialsStorage` preserves the SDK's default Keychain service/accessibility and makes deletion of an absent item idempotent. This allows first login's clear-before-store sequence to continue through session metadata cleanup. Only `errSecItemNotFound` on deletion is ignored; real deletion/write failures prevent sign-in and show a numeric Keychain status without logging credentials. The integration fixture models missing-item errors instead of making every delete succeed.

Nicholas's October 17 backend handoff reports the Native SMS connection and Passwordless OTP grant are enabled, the provider feedback Action is deployed/bound, and HTTPS plus profile persistence are live. Do not repeat provider setup based on older notes. The app still requires a consenting user's real iPhone login to accept the full Auth0/API flow.

The Me tab supports sign-in, sign-out, and retrying the private API connection. After login or session restoration, the app calls `GET /v1/me` and `GET /v1/measurements` with `Authorization: Bearer <credentials.accessToken>`. It preserves `user_id` as an opaque string and never links accounts by phone. Transient API downtime preserves sign-in and cached data. Profile loading errors show a retry instead of treating the account as new; onboarding completes only after a successful server save. Sensor counts, null BAC estimates, and simulator source labels remain distinct in the API models; Home's demo readings are not uploaded or mixed with private history.

`APIBaseURL` in `KickBAC/Auth0.plist` is separate from the audience. Both match the handoff: HTTPS base `https://api.kickbac.vodka`, exact audience `https://kickbac-api` with no trailing slash. The actual SDK OTP request is checked against that audience. The authoritative deployed contract is [live OpenAPI](https://api.kickbac.vodka/openapi.json); The published backend/profile/games/firmware diagnostic sources from current main are integrated into this review branch. The old request for Nicholas to publish the profile backend is resolved.

## Validation

Run the isolated request/response checks from the repository root:

```sh
swiftc ios/KickBAC/BACReading.swift ios/KickBAC/DeviceModels.swift ios/KickBAC/AuthConfiguration.swift ios/KickBAC/KickBACAPI.swift ios/checks/AuthContractChecks.swift -o /tmp/kickbac-auth-checks
/tmp/kickbac-auth-checks ios/KickBAC/Auth0.plist
```

These checks use a local URLProtocol stub, send no SMS, and prove configuration, bearer-header construction, opaque subject decoding, pagination, nullable measurements, and 401/503 handling. They do not prove a real Auth0 login or a deployed API.

Check the native Auth0 SDK requests and failure handling with:

```sh
bash ios/checks/run-authentication-checks.sh
```

This uses the real SDK with a local transport stub and in-memory credential storage. It checks SMS/token request payloads, connection/grant failures, resend cooldown, invalid codes, and rejection of invalid ID tokens. It sends no real SMS and does not touch the user's Keychain.

Live acceptance still requires:

- Complete signup on an iPhone through the native phone and code screens. Incorrect or expired codes must not complete sign-in. Check change-number and resend behavior.
- Relaunch and confirm Keychain restoration, then sign out and sign in again.
- Against the deployed API, confirm `/v1/me` accepts the API access token and private history contains only the authenticated account's records. Repeat with a second account to check isolation.
- Have Nicholas verify the bound Auth0 delivery-feedback Action actually executes on a real login. SMS delivery alone does not prove native login, token acceptance, or private-history access.

Birthday remains local to the existing age step. Phone identity remains in Auth0; name/photo use the profile endpoints below. Neither a client-supplied user ID nor a phone number is sent in profile writes.

Onboarding requires a captured photo; there is no camera skip action. Denied camera permission opens iOS Settings. Camera activity is owned by each preview and revision-ordered on the session actor, so late disposal or cancellation cannot stop a newer preview. The native preview rebinds changed sources. Check live image/capture/retake on the iPhone; lifecycle checks do not verify actual image rendering.

Camera preview uses `AVCaptureVideoPreviewLayer` directly and fills the largest centered square that fits below the title, within the page margins. The saved crop matches the entire preview, with no outer dimming or inset guide. Keep backdrop blur out of this clipped hierarchy: [UIKit does not support masks on a visual effect view's ancestors](https://developer.apple.com/documentation/uikit/uivisualeffectview). The preview has no custom pixel-buffer conversion or stride handling.

```sh
swiftc ios/KickBAC/CameraActivity.swift ios/checks/CameraActivityChecks.swift -o /tmp/kickbac-camera-checks
/tmp/kickbac-camera-checks
```

## Me and profiles

Me uses a softly rounded square photo, an editable name, saved-reading count, last check-in, and private reading history. Profile photos use the existing camera and square crop. Name/photo load from `GET /v1/me/profile` after login and session restoration, and save together with `PUT /v1/me/profile` at onboarding completion and profile edits. Both use the SDK API access token. A successful GET with null name starts profile onboarding; an error does not. Returning users skip name/photo setup. Saves await the normalized server response before dismissing, and failed saves retain form/photo input for a deliberate retry. Profile editing opens from Me. Settings contains camera permissions, Sign out, Delete account, and version. Account deletion currently shows an unavailable message; backend requirements are in [ACCOUNT_DELETION_HANDOFF.md](ACCOUNT_DELETION_HANDOFF.md).

PUT always includes `display_name` and `profile_picture`, including an explicit JSON null when no photo is selected. Name validation matches 1–80 Unicode code points after trimming, without control characters. Selected images are downsampled off the main thread, oriented, flattened onto white, and encoded as JPEG at no more than 512px per edge and 512 KiB. Name-only edits resend the current server picture without re-encoding. The editor allows taking or retaking a photo and has no Remove photo action; the existing API still accepts explicit null when no picture exists.

The per-subject local cache is retained for offline display and old local-only profiles become drafts when the server confirms a first-time account. They are never uploaded automatically. Account switches/logout clear the displayed profile; stale network responses cannot update another account. A cache-write failure after a successful server save is reported separately from a failed server save.

History includes loading, empty, retry, and pagination states. Test readings are labeled, missing BAC estimates stay distinct from raw sensor counts, and Home's demo readings never enter this history. Me loads Games played, Wins and Points from `/v1/me/stats`; failures remain unavailable rather than becoming zero. Party gameplay is still separate work; this client does not fabricate game completions or rewards.

Games played, Wins, and Points all open Recent games. It reads `GET /v1/me/game-results` with the API access token and shows actual game, outcome, score, awarded points, and completion date. Refresh/pagination preserve loaded results on transient errors and isolate them by authenticated subject. Party names/groups and linked breathalyzer check-ins are not in the current contract; those associations show unavailable. [RECENT_GAMES_HANDOFF.md](RECENT_GAMES_HANDOFF.md) records the requirements for Nicholas. The page does not submit game results.

Run the recent-game decoding, pagination, retry and account-isolation checks:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc ios/KickBAC/BACReading.swift ios/KickBAC/DeviceModels.swift ios/KickBAC/KickBACAPI.swift ios/KickBAC/RecentGamesStore.swift ios/checks/RecentGamesChecks.swift -o /tmp/kickbac-recent-games-checks
/tmp/kickbac-recent-games-checks
```

The authentication integration checks also cover the game-history access-token request, query parameters, mixed-owner response rejection, and temporary failures. Fixtures do not establish live game-history, party, or linked-check-in acceptance.

Run the local storage and timestamp checks alongside the authentication checks above:

```sh
swiftc ios/KickBAC/BACReading.swift ios/KickBAC/DeviceModels.swift ios/KickBAC/ProfileStore.swift ios/KickBAC/ProfilePhoto.swift ios/KickBAC/KickBACAPI.swift ios/checks/ProfileChecks.swift -o /tmp/kickbac-profile-checks
/tmp/kickbac-profile-checks
```

These checks cover server-confirmed onboarding, cache restoration, Unicode limits, real PNG-to-JPEG conversion/dimensions/byte limits, name-only picture preservation, deliberate removal, network-save failures, account isolation, delayed responses, and cache-write failures. Authentication integration checks cover restored identity, authenticated profile GET/PUT, wrong-owner responses, paginated history, temporary API failures, and clearing private data on session expiry.

## Integration status

The Party tab contains a local UI preview: create/link a preview breathalyzer, tap/code join, host game picker, and guest room with ongoing games, local trivia standings, and your profile. Use the Settings-style options icon to switch Host/Guest or ongoing/idle states. Entry/create/game pages use the requested product labels without preview banners or development explanations; behavior remains local. Code `KICK26` works only inside this local preview; it cannot invite another phone. No multiplayer game engine, live device association, server membership, or score submission is implemented. See [PARTY_HANDOFF.md](PARTY_HANDOFF.md) for preview checks and the separate live-contract requirements. Debug `--show-party` opens this tab without changing authentication.

The simulator build and local stub/image checks are separate from real acceptance. No unattended SMS is sent and no test bypass is added to production authentication. Complete onboarding on an iPhone, save a real photo, force-quit/relaunch, logout/relogin, test offline retry, and repeat with a second account before calling the live profile flow accepted.

Home starts without sample BAC. Its average/high values use loaded, nonsimulated, finite server BAC estimates. Uncalibrated/null readings show raw sensor values with no invented BAC. Debug Demo mode is explicitly labeled and never contributes to saved history.

Connect supports QR scanning or entry of an official device URL/ID. It validates the target against the configured API origin, resolves it publicly, preserves it through sign-in, loads independent availability/online state, and requires explicit confirmation before sending the existing empty-JSON arming request. Active sessions poll once per second with bounded backoff, stop on terminal states, support cancellation, and refresh private history on completion. Pending IDs are cached per subject for relaunch/relogin. Authoritative session 404 clears local tracking; transport failures retain the pending session. Foreground/background changes stop/resume polling without silently rearming.

Foreground NFC was excluded from the installable build because the current Personal Team does not support NFC Tag Reading provisioning. QR and printed-ID entry remain available. HTTPS background NFC/Universal Links are not configured.

Nicholas's published firmware still disables real sampling/uploads pending electrical and truthful acquisition-duration sign-off. Native app installation and source/fixture checks do not establish sensor or real Auth0 acceptance.

Run the isolated device/session checks:

```sh
swiftc ios/KickBAC/BACReading.swift ios/KickBAC/DeviceModels.swift ios/KickBAC/DeviceSessionStore.swift ios/KickBAC/KickBACAPI.swift ios/checks/DeviceSessionChecks.swift -o /tmp/kickbac-device-checks
/tmp/kickbac-device-checks
```

## Trivia preview

Trivia starts with a compact logo/Join game/Skip game sheet. Check-in uses the shared tap illustration and Home gauge, followed by the readiness roster. The host starts; ready players rotate through tap-or-swipe wheel turns. The wheel and answer pages stay fixed. A line shows the 20-second deadline; submitting locks the answer until everyone answers or time expires. A separate results page shows the correct answer and each player's round points before the next turn. Six bundled categories/questions and 1000 points per correct answer remain local defaults; no API result or lifetime reward is sent.

In Debug, use Trivia options → Simulate device tap / Simulate completed test to navigate the unfinished hardware boundary. Example players are optional, explicitly named fixtures whose answers/turns are simulated. Release omits these controls. See [TRIVIA_HANDOFF.md](TRIVIA_HANDOFF.md) for reproduction, verification, personal-device requirements and live integration boundaries.
