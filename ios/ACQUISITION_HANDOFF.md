# Manual acquisition client compatibility


## Current Liam adoption and native evidence

Branch `liam/party-setup`, implementation `c06192f73e5c2755f4961aa6c65e0c47811ad81f`, integrates main `a0bd77bcb79766f91de6746e0ab02fa992f4b337` via `de47523` while retaining `ef08fa8`. The older worker/platform limitations below are historical. Actual Swift acquisition/device/API/history/retry fixtures passed on Liam's Mac; final unsigned Release and signed Debug builds passed with Xcode-beta, reusing /tmp/kickbac-profile-build. Install and launch on Liam's connected iPhone were confirmed by devicectl. This is not rendering, native NFC, physical sensor or real-account acceptance.

Party check-ins adopt the server-returned session into the same DeviceSessionStore as Home. Exact UUID/body persistence and owner/session/acquisition fences prevent a local demo or unrelated Home measurement from satisfying a game check-in. Manual nullable metadata/notice and null BAC are preserved in Home and private check-in history. See PARTY_HANDOFF.md for current consumer contracts, tests and outstanding gates. No API/firmware/acquisition semantics changed.

## Historical worker checkpoint

Owner: bounded backend/iOS worker, branch `ios/manual-acquisition-notice`, isolated
worktree `kickbac-ios-acquisition-worker`; base Liam `0e5a6e4c87e650d5ea40090d7d232e9807d9dc2f`.
No push, merge, deployment, installation or native acceptance is claimed.

## LIAM / iOS IMPACT

Compatible decoding for legacy integer `breath_duration_ms` with omitted/null
new metadata, plus nullable duration with `acquisition_method:"manual_timed"`
and actual `sample_duration_ms:1...60000`. Frozen backend proposal read at
`e2a6da6527b69b64e6dcc0c92cc59ed770c9d299`; backend deployment is parent-owned.
No endpoint, auth, ownership, session UUID, 60-second expiry, cache, profile,
account stats or party preview contract changed. New manual responses remain
BREAKING for older clients that require integer breath duration.

Home and history show **Timed sensor sample — breath not validated**, including
VoiceOver. The separate sample-window duration never becomes breath duration.
SAMPLING means sensor acquisition, not breath confirmation. Null BAC stays
unavailable; manual/unknown/invalid acquisition and simulator data cannot enter
BAC summaries. Source labels explicitly say simulated for simulator fixtures.
All JSON fixtures here are synthetic compatibility examples, not physical evidence.

Connect retains QR/manual lookup, with `kb-demo-01` as a placeholder, not an
assigned user/profile or forced device choice. Explicit Arm test confirmation
explains account reservation followed by a separate operator USB sample start;
arming alone does not measure. Personal Team NFC/Universal Links and live party
integration remain blocked/unimplemented; no preview/gameplay changes.

Session review found existing exact owner/device/session checks, terminal stop,
persistent pending IDs, retry-only polling and no automatic rearm. The concrete
additional guard rejects malformed/mixed acquisition or a measurement attached
to a non-COMPLETE response before invoking completion or displaying a result.

## Executed checks / limits

`python ios/checks/AcquisitionContractChecks.py`: five source/wire guards, each
observed RED before its production change and then GREEN. These inspect checked-in
Swift wiring and JSON fixtures; they do **not** execute Swift semantics.
`python ios/checks/BrandingChecks.py` and `git diff --check` also pass.
Windows PATH has no swift/swiftc/xcodebuild; existing Ubuntu WSL PATH and standard
Swift locations also have none. No compiler/framework installed or peer setup
changed. **Swift compile, Swift behavior checks, signed build, rendering and
VoiceOver/device acceptance remain UNVERIFIED.**

On a Mac, from repository root, run:

```sh
xcrun swiftc ios/KickBAC/BACReading.swift ios/KickBAC/DeviceModels.swift ios/KickBAC/KickBACAPI.swift ios/checks/AcquisitionChecks.swift -o "$TMPDIR/kickbac-acquisition-checks"
"$TMPDIR/kickbac-acquisition-checks" ios/checks/fixtures/acquisition.json
xcrun swiftc ios/KickBAC/BACReading.swift ios/KickBAC/DeviceModels.swift ios/KickBAC/KickBACAPI.swift ios/KickBAC/DeviceSessionStore.swift ios/checks/DeviceSessionChecks.swift -o "$TMPDIR/kickbac-device-checks"
"$TMPDIR/kickbac-device-checks"
```

Then run the existing AuthContract/Profile checks and Xcode build instructions.
Exercise real same-owner/session manual completion, history/relaunch, account
switch, null BAC, simulator labels and accessibility on the combined backend/client
release. Parent review is required before publication/integration.
