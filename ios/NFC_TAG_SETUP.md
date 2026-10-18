# NFC sticker setup on Liam's iPhone

## Current setup

The sticker already contains the correct first NDEF URI record:

```text
https://api.kickbac.vodka/d/kb-demo-01
```

Keep it unchanged. Nicholas's canonical instructions are in
[NFC_CHECK_IN.md](../docs/NFC_CHECK_IN.md). Never put account IDs, session IDs,
party IDs, credentials or an arm command on the sticker. Firmware documentation
records the board's credential-bound identity as `kb-demo-01`; the live resolver
returns that ID. `kb-1` returns 404. Resolver success alone does not establish
current board connectivity or sampling/upload capability.

The current Personal Team build has no NFC Tag Reading or associated-domain
entitlement. Scanning the HTTPS sticker normally opens the JSON resolver in a
browser; it does not open this app automatically. Use the phone's Shortcuts NFC
automation for this installed build. No tag rewrite, backend change or native
Core NFC permission is needed for that route.

## One-time steps on each demo iPhone

1. Sign into KickBAC. Home now says Tap the breathalyzer to start; Connect is no
   longer part of the normal test flow.
2. Open Apple's Shortcuts app → Automation → add an automation → NFC. Scan the
   existing sticker and name it KickBAC. Choose Run Immediately.
3. Add an Open URLs action using this exact URL. If needed, add a URL action with
   this value and pass its output to Open URLs:

   ```text
   com.liam.KickBAC://device/kb-demo-01
   ```

4. Save the automation. Keep the iPhone unlocked for the first test, hold its top
   near the sticker, and accept any system permission to open KickBAC.
5. Liam's latest request uses this tag as a demo trigger because the hardware does
   not work. From Home, the app link runs the reading flow for six seconds and
   saves a local 0.00 App reading. During Trivia's breathalyzer page, the same tap
   runs that demo and readies the local player. Holding the on-screen circle keeps
   the random-value demo. Sign-in is still required, and a signed-out Home scan
   retains its target through onboarding. No hardware-online check, reservation,
   device arming or measurement upload is sent for these simulated readings.

The HTTPS resolver itself never arms. Outside the game's breathalyzer page,
Party's NFC still performs its explicit create/join/link actions through the
deployed party API. The demo never invents a server measurement or check-in.

Apple documents the NFC automation trigger in its
[Shortcuts guide](https://support.apple.com/en-gb/guide/shortcuts/apde31e9638b/9.0/ios/26).
That trigger uses the tag identifier, ignoring its contents. Register the same
physical sticker separately on each demo phone. Phones without this automation
can still use the printed ID/QR. General native tag launch for all phones remains
a separate paid-team/associated-domain/server AASA integration, not delivered here.

## Acquisition and simulator behavior

The quoted pending-backend message is historical. On October 18, public OpenAPI
readback confirms 33 operations, party check-ins, and nullable manual acquisition:

```json
{
  "breath_duration_ms": null,
  "acquisition_method": "manual_timed",
  "sample_duration_ms": 5000
}
```

5000 is only an example. The uploader reports the actual window. Existing iOS
models already decode this contract; SAMPLING means sensor acquisition, and the
UI retains “Timed sensor sample — breath not validated”. `estimated_bac_percent`
is null, so BAC stays unavailable. An online heartbeat does not complete a test.

The phone never receives the device credential or uploads measurements. The
firmware/operator must complete the exact reserved session. If using the existing
backend simulator, preserve `source: "simulator"` and its visible source label;
do not turn ADC counts, no sample or a simulator payload into a sober/0.00 BAC
reading. NFC identification itself is independent of the result's source.

## Verification

Run the existing native checks; the device fixtures now also cover the app URL,
untrusted schemes/hosts/paths, separation from the Auth0 callback, target retention
through sign-in, and no arming merely by selecting a scanned target:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
  ios/KickBAC/BACReading.swift ios/KickBAC/DeviceModels.swift \
  ios/KickBAC/KickBACAPI.swift ios/KickBAC/DeviceSessionStore.swift \
  ios/checks/DeviceSessionChecks.swift -o /tmp/kickbac-nfc-device-checks
/tmp/kickbac-nfc-device-checks
```

Signed builds, installation and launch are separate from physical tag acceptance.
This change passed the native device-session (including app-link), acquisition,
and party integration fixtures, plus the signed Debug device build. `devicectl`
confirmed installation and launch on Liam's connected iPhone 17, including launch
with the exact app URL above. This confirms delivery to the app launch API, not
rendering, the on-phone Shortcuts registration or a physical NFC scan. Existing
signed entitlements and provisioning were read back: neither NFC reading nor
associated domains is enabled. No production test was armed/uploaded by these
checks. Existing simulator tooling remains an isolated loopback fixture, not a
new production uploader; firmware/operator upload execution remains separate.
Liam reports the configured sticker scan opens the app; this is user-reported
route acceptance. The new direct scan-to-arm behavior still needs a physical scan
after installing this revision. The Mac agent cannot provision a personal NFC
automation remotely.

### Firmware completion gate

The known main firmware sends heartbeat/poll traffic but does not produce
measurements. New remote `firmware/explicit-mock-uploader@13bcd3b`, open
[PR39](https://github.com/spherohero/kickbac/pull/39), documents a real ESP32 HTTPS
mock upload only after an explicit USB operator command against the app's current
ARMED session. Its source/tests do not establish flashing or physical acceptance.
See that branch's `firmware/MOCK_DEMO.md`: the operator runs
`firmware/tools/send_mock.py --port COM3` on Nicholas's machine while the session's
60-second lease is active. This branch uses the existing legacy simulator payload
(synthetic 2500ms breath duration, `source:simulator`), not a measured manual window.
Do not call that synthetic duration measured breath or stable ADC evidence. The
owner still needs to flash/operate the uploader and verify its matching server
acknowledgment/history. No app change can make heartbeat-only firmware complete a
measurement. The payload contains no stability verdict; raw counts, acquisition
metadata and null BAC are displayed as returned.

## === LIAM / iOS IMPACT ===

Additive / NON-BREAKING app-only adoption on `liam/party-setup`. The existing app
URL scheme now accepts only `://device/<valid-device-id>` without credentials,
port, query, fragment, encoded path or extra path segments. HTTPS links remain
restricted to the configured API origin. Auth0 callbacks remain separate. An
active session cannot be replaced by a different target; a repeat tap of the same
active unit preserves that session. The automation URL's behavior intentionally
changes from confirmation to authenticated scan-to-arm at Liam's explicit request;
the public HTTPS locator remains read-only. Home replaces Connect with live
cancel/retry actions. Party joins and host links use existing explicit forms and
API payloads. No backend, firmware, measurement schema, entitlement, logo or
gameplay engine change is introduced. Results/history remain server-owned.
