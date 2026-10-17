# Account setup and safe report-back

This checklist is for Nicholas. It does not claim any account or deployment is configured. The backend/API contract is `API.md`; Liam owns SwiftUI. Do not send client secrets, passwords, bearer/refresh/device tokens, recovery codes, private SSH keys, or unredacted credential screenshots in chat.

## Primary login decision and provider gate

Nicholas approved phone number + SMS OTP as the primary signup/login method, **not MFA**, for team-only demo testing. Follow [PHONE_LOGIN.md](PHONE_LOGIN.md) before changing connections. The authenticated Auth0 tenant currently reports **No Valid Phone Provider Configured**; no Twilio account/sender is ready yet. Current new Twilio trials restrict custom SMS bodies, so verifying team recipients alone does not make the Auth0 integration ready. Do not purchase an account upgrade/sender or disable fallback access without the specific cost/approval and real delivery checks.

## Initial Auth0 public configuration

Nicholas supplied domain `dev-c87oxm4dkbyatvrn.us.auth0.com`, audience `https://kickbac-api`, Native client ID `5gJK2T71UkL0fbVj9pbzzEzKeMWZoYlC`, and reported RS256 plus enabled Native API access/login connection. Public OIDC discovery and RS256 RSA JWKS were independently fetched successfully. This does not verify API registration, application grants or a real user login. Liam's bundle ID is `com.liam.KickBAC`. The exact supplied callback/logout URL is `com.liam.KickBAC://dev-c87oxm4dkbyatvrn.us.auth0.com/ios/com.liam.KickBAC/callback`. Nicholas reports both callback/logout allowlists saved. A fresh public prompt=none request now returns302 login_required to the URI-equivalent callback, with no Callback URL mismatch. The redirect canonicalizes only the scheme to lowercase; the case-sensitive bundle path is preserved. Logout behavior and actual user login remain unverified. Preserve spelling/case; do not silently normalize the bundle or callback. Planned API host is `https://api.kickbac.vodka`, not yet deployed. Backend configuration is saved in git-ignored `backend/.env`; the Native client ID is for Liam, not a backend secret.

## 1. Auth0 tenant and API — do this first

1. Open https://manage.auth0.com/ and sign up/sign in yourself. Use a free development tenant in the US region; accept a generated unique tenant name if necessary. No paid custom domain is needed. Record the tenant Domain, e.g. `dev-EXAMPLE.us.auth0.com`, without `https://` or a trailing slash.
2. Go to **Applications -> APIs -> Create API**. Create a CUSTOM API, not the existing Auth0 Management API:
   - Name: `kickBAC API`
   - Identifier (audience): `https://kickbac-api` — exactly, no trailing slash. This is an immutable logical identifier, NOT a real/public backend host; Auth0 does not call it.
   - JWT profile: `Auth0` if the selector appears.
   - Signing algorithm: `RS256`.
3. Under this API's **Settings -> Application Access Policy**, use **Per-app authorization** for **User-Delegated Access**, and **No apps allowed** for **Client Access**. We are not using Auth0 machine-to-machine tokens for users or ESP32 devices. Save. The explicit Native app grant is configured below.
4. Under API Settings, enable **RBAC** if present, as recommended by Auth0 for native apps/custom APIs. There are no custom admin roles or fine-grained permission requirements in v0: backend ownership checks still restrict every session/history read. Do not invent new scopes/roles for this milestone. Leave token profile/signing algorithm as above.

If the dashboard labels differ or an option is unavailable, report the exact labels/status rather than switching to a different grant/signing algorithm. Never use a test machine-to-machine access token as proof a real user login works.

## 2. Auth0 Native app — coordinate with Liam

1. **Applications -> Applications -> Create Application**:
   - Name: `kickBAC iOS`
   - Type: **Native** (not Single Page, Regular Web or Machine to Machine).
2. Record its **Domain** and **Client ID**. These are public configuration and safe to report. Do not copy its Client Secret.
3. Confirm **Token Endpoint Authentication Method = None**. A Native app is a public client using Authorization Code + PKCE; it must not embed a client secret.
4. Go back to **kickBAC API -> Application Access**. Find `kickBAC iOS`, select **Edit**, and grant **User-Delegated Access**. Select **Always grant all permissions** if that is the available grant option; no custom API permissions currently exist. Do not grant Client Access. The hosted PKCE request must explicitly select `connection=sms`, OIDC scopes `openid profile` and audience `https://kickbac-api`; email is not required for phone-only users. SDK credentials management remains Liam's responsibility.
5. After Twilio delivery is configured and tested, enable the SMS connection for the Native app and use it as primary, following `PHONE_LOGIN.md`. Preserve existing database fallback until actual phone login/API acceptance succeeds. Do not turn on SMS MFA as a substitute. No Google/Apple provider setup is required for milestone one. Test-account passwords and OTPs must remain private.
6. Ask Liam for the app target's exact **Bundle Identifier** from Xcode. Do not guess or change his bundle ID. For the simplest custom-URL-scheme callback, add the following to BOTH **Allowed Callback URLs** and **Allowed Logout URLs**, replacing the placeholders with the actual values:

   ```text
   {BUNDLE_ID}://{AUTH0_DOMAIN}/ios/{BUNDLE_ID}/callback
   ```

   Save. Liam registers the matching URL scheme in Xcode and uses the appropriate Auth0.swift SDK configuration. Preserve his existing callback setup if he already has one; coordinate instead of replacing it. Universal-link callbacks require additional Apple/associated-domain setup and are not a prerequisite for this first auth demo. Auth0 callback URLs and NFC/QR device links are different things.
7. Do not add a backend client secret or management token: the backend validates signed access tokens using public JWKS. Refresh-token/offline-access options are not needed to prove initial login; coordinate them with Liam if requested by his SDK/configuration.

## 3. Vultr — inspect before creating anything billable

Nicholas reports the VM already created at144.202.38.243, displayed price approximately$28/month, SSH key selected, no Vultr firewall attached. Do not create another VM. Exact plan/OS and SSH authentication remain unverified. Cloudflare Free DNS is staged; registrar nameserver delegation is pending. See CLOUDFLARE_DNS.md for the two exact registrar nameservers and current DNS/HTTPS status; do not share root credentials.

Report one of:
- No VM yet: available credit confirmed, preferred US region, and acceptable advertised monthly VM price limit. We will choose one small persistent-disk instance and confirm before spending/provisioning.
- Existing VM: public IP, OS/version, region, advertised monthly price, and whether SSH key login is already configured. Do not send root passwords or private keys. Do not repurpose a VM running other projects without inspection/isolation.

Registered domain is kickbac.vodka; API origin remains https://api.kickbac.vodka. Cloudflare DNS setup is documented in CLOUDFLARE_DNS.md. DNS staging is not a deployed HTTPS service; neither Cloudflare DNS nor a laptop loopback URL proves physical-iPhone reachability.

## iOS starter PR integration check

Liam corrected the audience in `ios/KickBAC/Auth0.plist` and `ios/README.md` to **`https://kickbac-api` without a trailing slash** in `c5939d5`. [PR #1](https://github.com/spherohero/kickbac/pull/1) was re-reviewed and merged at `8b222c1`; the actual merge tree and iOS source were read back and checked. No teammate source was rewritten. His separate navigation branch still needs to incorporate that correction before login integration.

The starter's bundle ID, custom URL scheme and tenant match the handoff. It does not yet include Auth0.swift or implement login. Liam must explicitly request the correct API audience during Native PKCE login and send the resulting **access token**, not the ID token, as `Authorization: Bearer <access_token>` to `GET /v1/me`; a successful response is `{"user_id":"auth0|example-subject"}`. A plist value alone does not implement that request. Credentials stay in the SDK's secure credential store; no backend client secret or device credential belongs in the app.

The project currently targets iOS 27.0. This Windows host has no Xcode, and the PR has no build checks, so parsed plist/JSON resources and reviewed source are **not** a successful iOS build or physical-phone login test. Liam must verify his Xcode/demo-device target and build/run the app. His separate `ios` navigation branch is not part of the starter PR and must not be merged implicitly.

## Copy-paste report-back template

The following fields are public configuration/status; omit unavailable fields instead of guessing.

```text
Auth0 tenant domain:
Auth0 API audience: https://kickbac-api
API signing algorithm: RS256
Native app name: kickBAC iOS
Native app Client ID:
Native app user-delegated API access granted: yes/no
Enabled login connection:
Liam's exact iOS bundle ID: com.liam.KickBAC
Callback + logout URLs saved: [yes/no/pending bundle ID]
Any dashboard option that differs / error text:

Vultr credits visible: yes/no
Existing VM: none / public IP
VM OS/version + region (if existing):
Advertised monthly VM price / acceptable price limit:
SSH key login configured: yes/no/not yet
Existing usable domain: none / domain
```

Do NOT paste Client Secret, access/refresh/device tokens, passwords, recovery codes, billing details, or private SSH keys. If a secret is needed later, use a masked local prompt, local private configuration or the browser's credential vault—not chat.

## What happens after reporting back

We can verify public OIDC discovery/JWKS against the reported domain and match issuer/audience configuration; that alone is not a login test. Actual Auth0 user login must be verified through Liam's native app or an explicitly approved PKCE test client, with secrets kept local. We will separately verify a trusted HTTPS API, auth/ownership, NFC/QR routing and the simulator/device flow from a physical iPhone. Local fixture signatures and simulated sensor values never count as those external integrations being complete.

## Official references
- Register API / audience semantics: https://auth0.com/docs/get-started/auth0-overview/set-up-apis
- Application access policies: https://auth0.com/docs/get-started/apis/api-access-policies-for-applications
- Auth0.swift callback and public-client setup: https://auth0.com/docs/libraries/auth0-swift
- SwiftUI quickstart: https://auth0.com/docs/quickstart/native/ios-swift
