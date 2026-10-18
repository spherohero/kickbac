# Liam's iOS backend review handoff

This branch captures the current iOS implementation, including previously unpublished onboarding, auth, camera, profile, Home, assets, and checks. Existing local work is included. It does not merge or modify Nicholas's backend work.

## Implemented integration

- Native Auth0 SMS send/code exchange using Auth0.swift and Keychain-backed credentials. Exact audience: `https://kickbac-api`; API base: `https://api.kickbac.vodka`.
- Existing bearer-authenticated `/v1/me` and private paginated measurement history.
- Profile GET after login and session restoration. A successful null-name response starts profile onboarding; a failed request offers retry without treating the account as new. Returning users skip name/photo setup.
- Profile PUT after onboarding and edits, awaiting server success. Both fields are sent, including explicit JSON null for no photo/removal. No user ID or phone is submitted.
- Name validation uses 1–80 Unicode code points after trimming. Selected pictures become bounded JPEGs (512px, 512 KiB); name-only edits preserve returned image bytes.
- Failed saves preserve form input; local caches are subject-specific; logout/account switches clear displayed private data and reject stale responses.
- Existing screens/navigation and current interface work are included. Birthday remains local; phone identity remains in Auth0.

## Validation already performed

- Xcode simulator build passed during the profile integration.
- `AuthContractChecks`, `AuthIntegrationChecks`, and `ProfileChecks` passed with local transport fixtures and real image conversion.
- Live HTTPS checks returned health 200, demo resolver 200, and unauthenticated identity/profile 401. Live OpenAPI matched the profile contract.
- These checks do not prove a real Auth0 login, authenticated production profile round-trip, physical camera capture, or hardware acceptance. No real SMS was sent by the checks.

Reproduction commands are in `README.md`. Later UI changes included in this snapshot may have their own verification history; the checks above describe the profile integration verification.

## Remaining acceptance and Nicholas follow-up

1. On an iPhone with a consenting user, complete SMS login and confirm the actual API access token works against `/v1/me` and profile endpoints.
2. Save a real name/photo, force-quit/relaunch, logout/relogin, test failed-save retry, edit name without losing the photo, remove the photo deliberately, and repeat with a second account.
3. Nicholas: publish/commit the deployed backend source. The supplied handoff described the active profile backend as local/uncommitted; this iOS branch does not contain those server changes.
4. Nicholas: verify the bound delivery-feedback Action executes after a real successful login. The handoff reports SMS/grant/provider configuration is already complete; no repeat setup is requested.
5. Home still uses its existing demo reading flow. Native NFC/QR targeting, explicit device arming, session polling/cancellation, and hardware result rendering remain separate iOS integration work. Nicholas owns firmware/device readiness. Do not treat the demo as live hardware acceptance.

No additional profile endpoint or schema change is currently required. Report fresh live failures by stage/status/error code without sharing OTPs, tokens, phone numbers, or private photo bytes.
