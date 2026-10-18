# Automatic Wi-Fi + device authentication after restart

Firmware owner `firmware/persistent-device-auth`, base `aa90d4c`. User explicitly
authorizes saving the existing registered demo-device bearer on this ESP, not
rotating it, changing servers or adding remote-start/auto-arm/upload behavior.

## Once-only private opt-in

After installing this reviewed image, with the already-saved network available:

```bash
uv tool run --python 3.11 --with pip --from platformio==6.1.19 python firmware/tools/provision_device.py --port COM3 --device-only --save-device-auth
```

The existing private helper verifies the exact USB target, asks a local default-No
storage-consent question, privately retrieves the SAME existing bearer through the
host-key-verified relay, and sends KBA1 only on explicit consent. No password/token
in chat, source, command arguments, local credential files or logs. USB provisioning
is unencrypted. Success requires a post-send `device_saved state=stored` ACK before
DEVICE_PASS; old automatic heartbeats cannot falsely satisfy the save operation.
Legacy KBD1/default provisioning remains RAM-only and cannot implicitly save.

## Security tradeoff and storage behavior

NVS encryption is NOT verified or enabled; a person able to read unprotected flash
may recover the reusable bearer and saved Wi-Fi password. CRC/version/device-ID
binding detects accidental corruption, not malicious tampering or disclosure.
No secure-boot/flash-encryption/eFuse/security-state changes. Keep this demo unit
physically controlled; ordinary backend revocation still applies. Saving does not
make an insecure storage claim disappear.

One fixed-size identity-bound blob lives at `kickbac_auth/credential`; a blocked
marker fences interrupted writes and locally observed auth/schema faults. Explicit
save first blocks, writes/readbacks the blob, then enables it. Boot reads without
rewriting, rejects invalid/corrupt/blocked records, scrubs temporary buffers and
never silently provisions another identity.401/403/schema failures clear RAM and
stop; when the block marker persists, reset cannot bypass the local fault latch.
If NVS cannot write that marker, runtime still stops but reset may reload the old
record; backend revocation continues to reject it. No storage-failure immunity.

## Autonomous restart

Boot restores the saved auth and single saved Wi-Fi. The existing lifetime
association/backoff policy remains; actual DNS/SNTP/trusted hostname/date-validated
HTTPS readiness is required BEFORE authenticated heartbeat/poll. No PC/helper/USB
credential frame is needed after successful once-only provisioning. No session,
user, party or measurement is created from boot or connectivity alone. The explicit
USB MOCK command remains the only mock trigger; remote-start is not in scope.

Session tickets are invalidated on faults; original session UUID/expiry and
unresolved pending bytes never get reassigned. Pending mock transactions are still
RAM-only: DO NOT deliberately power-cycle/reset/reflash during unknown acceptance;
reconcile the exact original measurement/session first. Boot has no pending sample
to auto-replay or attach to a newer session. This change persists auth, not a
measurement outbox or a fake sample.

## Executed source verification and physical gate

Test-first saved-auth test initially failed for a missing implementation; full
host suite now passes, including actual device adapter over synthetic Preferences,
restart without serial relay/no auto upload, corruption and revocation/schema
blocking. All41Python tests, pinned Ruff and all3pinned XIAO cross-builds pass.
Independent focused source review conditionally approved the scoped flash, noting
the documented NVS-write-failure limitation. Host fixtures/builds are not a physical
power-cycle proof. Exact source/PR/flash/serial/server results must be checked in the
publishing PR before claiming full unplug/replug acceptance.

## === BACKEND CONTRACT CHANGE ===

NON-BREAKING. Existing device identity/credential/API methods, request/response
fields, session expiry and measurement contract unchanged. No server rotation,
backend migration/deployment or new endpoint. Preserve accepted demo/history.

## === LIAM / iOS IMPACT ===

NON-BREAKING/no app action. All iOS/NFC/presentation remains Liam-owned. No automatic
arm/sample/upload, ADC enablement or BAC claim. This fixes boot connectivity/auth,
not sensing or native routing.
