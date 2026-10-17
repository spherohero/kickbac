# Phone-first signup/login — Auth0 + Twilio

## Decision and actual status

Nicholas approved **phone number + SMS one-time code as the primary signup/login method, NOT SMS MFA**. Team members are the demo testers; judges are not expected to install the app. Use Auth0-hosted Universal Login with Native Authorization Code + PKCE. Liam owns the SwiftUI client.

**Not live yet.** An authenticated inspection of the correct tenant found the `sms` configuration explicitly reporting **No Valid Phone Provider Configured**. Nicholas does not yet have a Twilio account and is creating one. No provider credentials, billable sender, SMS send, or working phone login have been configured or verified. Existing login connections were not disabled.

The tenant uses New Universal Login. Changing its Authentication Profile to Identifier First displays a confirmation that **custom prompts will be reset**. That confirmation was cancelled; no login-profile change is claimed saved. Review/preserve any custom prompts before confirming the eventual profile change.

The existing backend already accepts correctly signed SMS-user API tokens as opaque subjects; no new SMS-sending backend, Twilio SDK dependency, phone-number table, route, migration or credential environment variable is needed. `backend/tests/test_phone_identity.py` verifies that existing compatibility using **local signed fixtures, not real Auth0/SMS**.

## What a verified recipient means

A normal mobile number is suitable, but that does not automatically make it a verified recipient in a Twilio trial account. Twilio must verify control of the number through its own verification flow. This is a **trial testing allowlist**, not an additional kickBAC authentication factor. The number used when signing up is automatically verified; other team numbers must be added and verified individually in the trial Console. Current trial docs allow up to five recipients and restrict destination geography.

**Recipient verification is different from sender verification.** The Twilio-owned number or Messaging Service sending your messages must also satisfy provider/carrier requirements. For example, purchased US/Canada toll-free numbers cannot send SMS there until verification is approved; US long-code sending has A2P registration requirements. Do not use a tester's personal number as the Twilio `From` sender.

## Important new-trial limitation

Current Twilio trial documentation restricts SMS API message bodies to predefined template names and does not allow custom bodies. Auth0's normal Twilio integration sends its own generated OTP in the body, so a new trial is **not sufficient merely because team recipients are verified**. Confirm account capabilities; upgrading may be required, and upgrading alone does not waive sender approval.

Do not purchase numbers, upgrade billing or promise immediate US delivery without checking the specific cost and sender requirements first. A Twilio Verify trial demonstration is **not** an Auth0-generated-code integration: do not silently replace Auth0 OTP validation with a second verification system.

## Nicholas: account setup and safe report-back

1. Create an account at https://www.twilio.com/try-twilio . Verify your email and personal phone number privately. Select SMS/authentication as the use case and use your actual country/details; do not invent a business or sender approval.
2. Reach the Console. In the SMS trial flow, verify additional team recipient numbers using each person's device. Do not share numbers or verification codes in chat.
3. Stop before upgrading or buying a number. Inspect whether custom SMS content is permitted and what sender/compliance steps and charges are required. Report the status/quote below. Free units do not automatically mean this integration is free or deliverable immediately.
4. After a sending-capable account/sender is agreed, configure its credentials directly in Auth0's **Branding -> Phone Provider**. Never put the Twilio Auth Token in Git, iOS, screenshots, shell arguments, chat or the kickBAC backend `.env`.

```text
Twilio account created: yes/no
Account: trial/upgraded
Signup country:
Additional team recipients verified: yes/no/not applicable
Custom SMS body supported: yes/no/unknown
SMS sender or Messaging Service ready: yes/no
Sender verification/registration: approved/pending/not started/not applicable
Required upgrade/deposit/monthly/registration quote, if shown:
Any error or dashboard option that differs:
```

No Account SID, Auth Token, private phone number, password or OTP is needed in this report.

## Operator: configure and verify Auth0 after the provider is ready

1. Inspect the existing tenant/apps/connections first. Work only in `dev-c87oxm4dkbyatvrn`, and select the Native `kickBAC iOS` app with public client ID `5gJK2T71UkL0fbVj9pbzzEzKeMWZoYlC`. Preserve unrelated apps and existing fallback access.
2. **Branding -> Phone Provider**: select Twilio, delivery method **Text** only, and the approved From sender or Messaging Service. Enter credentials privately and save. Read back the provider/delivery/sender configuration without exposing the Auth Token.
3. Use the provider's **Try** flow with a team phone entered privately. Check actual receipt and provider/Auth0 delivery logs. A successful provider SMS is not yet an end-to-end signup/login.
4. **Authentication -> Passwordless -> SMS -> Settings**: connection `sms`, OTP length **6**, expiry **180 seconds**, **Disable Sign Ups OFF**, **Promote Connection to Domain Level OFF**. These are the observed default targets, not a completed deployment claim. Keep broad/domain-level access disabled.
5. Enable the connection for **kickBAC iOS only**, not the Default App or machine-to-machine test application. Save, reopen the exact connection and verify its settings/app assignment.
6. Review/preserve custom prompt text. Set **Authentication Profile -> Identifier First** (not the Enterprise biometrics option). Auth0 warns that changing this resets custom prompts; do not confirm blind or overwrite teammate customization. Reopen the profile and read it back after saving. Do not equate clicking Save or dismissing a confirmation with persisted settings.
7. Liam's hosted authorization request explicitly selects `connection=sms`. Do not enable an embedded Passwordless OTP grant merely for this hosted PKCE flow. Keep the existing fallback until actual phone login/API acceptance succeeds; never modify tenant MFA settings as a substitute for primary passwordless login.
8. Apply destination restrictions, appropriate rate/abuse controls and spending safeguards supported by the actual account. A budget alert is not automatically a hard spending cap.

## Liam / iOS handoff

**NON-BREAKING API; coordinated primary-login UX/identity change.** No SwiftUI source is changed by this backend branch. The app currently contains only a starter; Liam still needs to integrate Auth0.swift and secure credential storage.

| Item | Exact value / behavior |
| --- | --- |
| Auth0 domain | `dev-c87oxm4dkbyatvrn.us.auth0.com` |
| Native client ID | `5gJK2T71UkL0fbVj9pbzzEzKeMWZoYlC` |
| Connection | `sms` |
| Audience | `https://kickbac-api` — no trailing slash |
| Initial scopes | `openid profile`; do not require an email claim for phone-only users |
| Flow | Hosted Universal Login, Authorization Code + PKCE; SDK manages state/nonce/PKCE |
| Bundle ID / URL scheme | `com.liam.KickBAC` |
| Callback/logout target | `com.liam.KickBAC://dev-c87oxm4dkbyatvrn.us.auth0.com/ios/com.liam.KickBAC/callback` |
| Backend authentication | API **access token**, not the OTP, ID token or phone number |
| Future API base URL | `https://api.kickbac.vodka` — hosting/HTTPS remains separately unverified |

The existing identity route is unchanged:

```http
GET /v1/me
Authorization: Bearer <API_ACCESS_TOKEN>
```

Example response (illustrative subject, not a real login result):

```json
{"user_id":"sms|example-opaque-subject"}
```

Treat `user_id` as an opaque value, not a phone number or a required `auth0|`/`sms|` prefix. Separate SMS and database identities do not automatically share history, even when phone claims match. Do not auto-link accounts by email/phone or discard a previous user's results. Repeated real sign-in to the same SMS account must return the same subject/history.

The separate `origin/ios` navigation branch predates the audience correction and still had `https://kickbac-api/` when inspected. Liam should incorporate current main before integrating login; do not overwrite or merge his navigation work implicitly.

## Acceptance gates

- Real first SMS signup and later login on a team phone; no password or email prerequisite.
- Correct API access-token audience/issuer/signature, `/v1/me` subject and user-private session/history.
- Same user's history after logout/login and app restart; another subject cannot read it.
- Invalid/expired code, resend/old-code invalidation, failure/retry and rate-limit behavior.
- Actual delivery logs/phone receipt; no fake fallback or hardcoded code/token.
- Primary login works without turning SMS into an MFA requirement.
- Native Xcode/device build and callback/credential-store behavior verified by Liam.

Local compatibility tests do not satisfy these real-provider/native gates.

## Local verification on the phone-login branch

`backend/tests/test_phone_identity.py` adds six compatibility checks for the existing API: a signed SMS subject with no email claim, exact-audience enforcement, rejection of a bare OTP/phone number as a bearer credential, isolation from other SMS/database subjects even when contact claims match, and persisted private history after a fresh app restart. These fixtures do not send messages or authenticate against live Auth0.

Fresh full-branch execution: **107 tests passed**, Ruff lint passed, **31 files** passed formatting, byte compilation passed, and the real-HTTP simulator returned `SIMULATOR_OK`, `COMPLETE`, one measurement, zero duplicates, foreign-owner `404` and restart `ok`. Production API code, migrations and dependency pins are unchanged.

## References

- https://auth0.com/docs/authenticate/passwordless/passwordless-with-universal-login
- https://auth0.com/docs/authenticate/passwordless/authentication-methods/sms-otp
- https://auth0.com/docs/customize/phone-messages/configure-phone-messaging-providers/configure-twilio-as-a-phone-messaging-provider
- https://auth0.com/docs/authenticate/passwordless/best-practices
- https://www.twilio.com/docs/usage/trials
- https://www.twilio.com/docs/usage/trials/try-out-sms
- https://www.twilio.com/docs/messaging/compliance/toll-free/console-onboarding
