# Profile onboarding — additive client contract

Status: **implemented and deployed**, independently verified at https://api.kickbac.vodka/openapi.json after schema3 migration and API restart. Live base: **https://api.kickbac.vodka**. See [PROFILE_VERIFICATION.md](PROFILE_VERIFICATION.md) for actual test/deployment evidence and remaining native-client acceptance. Source is local/uncommitted on `backend/profiles`, not automatically published to main.

## What is stored where

- **Phone / login identity:** Auth0's SMS account. Auth0 generates and verifies OTPs, and stores the account's phone. The kickBAC API trusts the validated RS256 API access-token `sub`, not a phone number or a client-supplied `user_id`.
- **Display name / profile picture:** a private SQLite profile keyed by that same opaque subject. It survives API restart and returning-user login, and is included in the existing online SQLite snapshots. No new cloud-storage service, provider credential or profile password is required.
- `/v1/me` stays exactly `{"user_id":"sms|opaque-example"}`. No phone is added to session, device, history or public resolver responses. Profiles are not public or discoverable by another user.

The app's verified-login/credential flow remains the source of its phone identity. Do not present a freely editable profile field as a verified phone change. Changing the SMS account phone / linking accounts is out of scope; login with a different Auth0 subject is a different account, even if a client claims the same phone.

## Load after login / app relaunch

`GET /v1/me/profile` with the existing `Authorization: Bearer <API access token>`.

A first-time account with no kickBAC profile returns **200**:

```json
{
  "user_id": "sms|opaque-example",
  "display_name": null,
  "profile_picture": null,
  "created_at": null,
  "updated_at": null
}
```

GET does not create an empty database row. The app can show onboarding when `display_name` is null. The app owns whether a picture is mandatory in its UI; the server allows a null picture for skip/removal without inventing an `onboarding_complete` flag.

## Save onboarding / edit profile

`PUT /v1/me/profile`, same API Bearer token, `Content-Type: application/json`:

```json
{
  "display_name": "Nicholas",
  "profile_picture": null
}
```

Both fields are **required**. For a selected photo, replace null with this object (the notation below explains the field; it is not a literal valid upload):

- `content_type`: `image/jpeg` or `image/png`.
- `data_base64`: standard Base64 of the actual JPEG/PNG **file bytes**, not a `data:` URL, file path, remote URL, HEIC file or base64-encoded URL. In Swift, convert the picker image to bounded JPEG/PNG data before encoding with `Data.base64EncodedString()`.

A successful **200** response uses the same shape as GET with server-owned timestamps:

```json
{
  "user_id": "sms|opaque-example",
  "display_name": "Nicholas",
  "profile_picture": null,
  "created_at": "2026-10-17T23:00:00+00:00",
  "updated_at": "2026-10-17T23:00:00+00:00"
}
```

When present, returned `profile_picture` contains `content_type: image/jpeg` and `data_base64` for the server-sanitized JPEG. Decode it with `Data(base64Encoded:)`. Do not expect the original PNG/file bytes or EXIF metadata back.

PUT atomically replaces name + picture. Sending `profile_picture: null` **clears** an existing picture; it does not mean "keep the old one". To edit only the name, send the current returned picture too. Retrying the same request does not create a second profile or alter ownership; `created_at` is preserved and `updated_at` reflects the server write. Keep the same full payload when retrying after a timeout. Treat onboarding as saved only after a successful response; do not silently discard the local pending selection on network failure.

## Validation / privacy

- Name: strict string, surrounding Unicode whitespace trimmed, 1–80 Unicode code points after trim. No control/surrogate characters. No uniqueness requirement; display names are not user IDs.
- Image input: at most **512 KiB decoded**, at most **2048 pixels per edge / 4,194,304 pixels**. JPEG/PNG only, one frame; declared MIME must match the decoded image. Malformed/truncated/animated/spoofed images, unsupported formats and non-standard/malformed Base64 are rejected. Pre-resize/compress on iOS; changing only the MIME label does not convert HEIC.
- Server applies EXIF orientation, strips metadata, flattens transparency onto white, and stores JPEG with longest edge at most **512 px**. Small source images are not upscaled.
- Request body capped at **1 MiB**, including chunked bodies without a trusted Content-Length.
- Existing JSON error envelope: `401 unauthorized` for invalid/missing auth; `422 validation_error` for invalid fields/image; `413 payload_too_large` for a request body over 1 MiB, decoded image over 512 KiB or Base64 exceeding its encoded bound. An invalid replacement leaves the prior saved profile unchanged. Unknown properties (including `phone_number` or `user_id`) are rejected.
- Profile success responses use `Cache-Control: no-store`. Never put tokens, phones, names, images or Base64 in logs, analytics or URLs. Protect local credentials with Keychain-backed storage.
- SQLite backup includes private profile images. The existing VM/daily local snapshots are not an off-host disaster-recovery guarantee or encrypted storage. Account deletion/retention and public-party profiles are not implemented by this change.

## Forward to Liam

**NON-BREAKING to existing API; new onboarding integration required.** Use current Auth0 login and API access token. After login call `GET /v1/me/profile`; if no name, collect display name + selected JPEG/PNG (phone remains the Auth0 SMS identity). Save both with `PUT /v1/me/profile` and await 200, then restore the saved fields on subsequent login/relaunch. No changes to device/session/history requests. No Twilio secrets or native client secret. See this document and the live `/openapi.json`; don't implement from the earlier assumption that `/v1/me` stores a full profile.
