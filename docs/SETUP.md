# Account setup and safe report-back

This checklist is for Nicholas. It does not claim any account or deployment is configured. The backend/API contract is `API.md`; Liam owns SwiftUI. Do not send client secrets, passwords, bearer/refresh/device tokens, recovery codes, private SSH keys, or unredacted credential screenshots in chat.

## Initial Auth0 public configuration

Nicholas supplied domain `dev-c87oxm4dkbyatvrn.us.auth0.com`, audience `https://kickbac-api`, Native client ID `5gJK2T71UkL0fbVj9pbzzEzKeMWZoYlC`, and reported RS256 plus enabled Native API access/login connection. Public OIDC discovery and RS256 RSA JWKS were independently fetched successfully. This does not verify API registration, application grants or a real user login. Liam's bundle ID and callback/logout URLs remain pending. Backend configuration is saved in git-ignored `backend/.env`; the Native client ID is for Liam, not a backend secret.

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
4. Go back to **kickBAC API -> Application Access**. Find `kickBAC iOS`, select **Edit**, and grant **User-Delegated Access**. Select **Always grant all permissions** if that is the available grant option; no custom API permissions currently exist. Do not grant Client Access. The login request must explicitly request OIDC scopes (e.g. `openid profile email`) and audience `https://kickbac-api`; scopes and credentials management remain Liam's implementation responsibility.
5. Under the Native app's **Connections**, make sure a user login connection is enabled (the default username/password database connection is sufficient). No Google/Apple provider setup is required for milestone one. Test-account passwords must remain private.
6. Ask Liam for the app target's exact **Bundle Identifier** from Xcode. Do not guess or change his bundle ID. For the simplest custom-URL-scheme callback, add the following to BOTH **Allowed Callback URLs** and **Allowed Logout URLs**, replacing the placeholders with the actual values:

   ```text
   {BUNDLE_ID}://{AUTH0_DOMAIN}/ios/{BUNDLE_ID}/callback
   ```

   Save. Liam registers the matching URL scheme in Xcode and uses the appropriate Auth0.swift SDK configuration. Preserve his existing callback setup if he already has one; coordinate instead of replacing it. Universal-link callbacks require additional Apple/associated-domain setup and are not a prerequisite for this first auth demo. Auth0 callback URLs and NFC/QR device links are different things.
7. Do not add a backend client secret or management token: the backend validates signed access tokens using public JWKS. Refresh-token/offline-access options are not needed to prove initial login; coordinate them with Liam if requested by his SDK/configuration.

## 3. Vultr — inspect before creating anything billable

Nicholas confirms account/credits ready, but no server is verified. Open https://my.vultr.com/ . Confirm credits are visible and check whether a VM already exists. Do not create another instance yet or paste billing/payment information.

Report one of:
- No VM yet: available credit confirmed, preferred US region, and acceptable advertised monthly VM price limit. We will choose one small persistent-disk instance and confirm before spending/provisioning.
- Existing VM: public IP, OS/version, region, advertised monthly price, and whether SSH key login is already configured. Do not send root passwords or private keys. Do not repurpose a VM running other projects without inspection/isolation.

Also report whether a domain is already owned and usable for the API. Do not buy one solely to proceed; public trusted HTTPS and iPhone reachability can be planned after inspecting hosting. Do not treat a laptop loopback URL as a public iPhone endpoint.

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
Liam's exact iOS bundle ID: [value or pending]
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
