# One saved Wi-Fi network and lifetime reconnect

Firmware owner branch `firmware/saved-wifi-recovery`, base `22c1215`. The accepted
mock demo and backend measurement wire contract remain unchanged; no app edits.

## Private opt-in (not a password-in-chat workflow)

After the reviewed image is installed on the positively identified target:

```bash
uv tool run --python 3.11 --with pip --from platformio==6.1.19 python firmware/tools/provision_device.py --port COM3 --save-wifi
```

Enter the one2.4GHz personal network in the existing private local dialog. The
“Save this one Wi-Fi network on the device” checkbox starts UNCHECKED. Checking
it authorizes replacing ONE NVS application record (`kickbac_wifi/network`), not
saving any device bearer. Leaving it unchecked remains RAM-only. USB entry is
unencrypted. NVS storage is NOT verified encrypted; this change enables no flash
or NVS encryption, secure-boot or eFuse setting. CRC detects accidental corruption,
not disclosure/tampering. No OS password extraction, hardcoded secrets, local
credential files, log echoes or additional AP/service are used.

Default binary frame remains KBW1; explicit save uses KBS1. A WIFI_SETUP line opens
a30second in-place configuration window even if an old profile is online; incomplete
entry resumes the old configured retry policy. The helper requires a configuration/
save acknowledgment before forwarding a bearer and refuses a failed requested write.
The NVS key is written only on explicit save, never on every boot/retry. Invalid
saved records fail closed without being silently erased.

## Network behavior

Boot restores the single saved profile, if valid, and tries that exact SSID. One
explicit RAM copy is retained so an SDK config-installation failure cannot cause
fallback to an old/empty SDK profile; every retry uses explicit credentials and
online acceptance privately compares actual SSID. There is no list of alternate
networks. SDK persistence remains disabled/WIFI_STORAGE_RAM; application NVS is
separate and opt-in.

Association/DHCP attempts end at30seconds. Exponential equal-jitter backoff starts
at1..2seconds and caps at30..60seconds; counters do NOT permanently give up. Actual
DNS, SNTP and trusted health HTTPS must succeed before the device API loop resumes.
Their existing individual timeouts remain bounded, not one hard wall-clock bound.
A healthy association is not deliberately torn down merely because HTTPS failed.

Wi-Fi-loss events signal the main loop; before returning to device work it clears
acquisition tickets and holds original unresolved mock bytes/IDs unchanged. No
automatic measurement is created or retried when the network returns. RAM bearer
is retained during powered hotspot loss.401/revocation/schema faults remain
terminal and are NOT cleared by reconnection. Initial negative-auth transport
failure is bounded/retryable, never mistaken for successful401 verification.

## Cold boot device-auth limit — explicit prerequisite

Wi-Fi saving ALONE does not provide authenticated device boot. The existing device
bearer is still RAM-only and disappears on reset/power loss. After automatic saved
Wi-Fi/DNS/SNTP/trusted HTTPS readiness, bootstrap the existing private bearer without
re-entering Wi-Fi:

```bash
uv tool run --python 3.11 --with pip --from platformio==6.1.19 python firmware/tools/provision_device.py --port COM3 --device-only
```

This reuses the authorized host-key-checked private relay after device_ready; it
persists no bearer. Fully standalone cold-boot API/uploads need a separately approved
private device-auth bootstrap/persistence policy. No such policy is silently added.
Do not reset/power-cycle an unresolved upload; reconcile acceptance/expiry first.

## Verification and limits

Actual verified-target COM3 flash at source `9b0ca25e69ae2ef19a6078ec52dada204fdeea8f`:
app SHA256 `04c3e3acfe121adeefb06aa9c86cfd1c2baa84c4630dc7ede921930e1ca666fa`,
all esptool image hashes verified. Private unchecked opt-in was explicitly selected;
board reported `wifi_saved state=stored`, `wifi_config state=accepted saved=1`,
then actual trusted HTTPS and authenticated heartbeats. No credentials logged.

After a reconciled controlled SOFTWARE RESET, `--device-only` (no Wi-Fi dialog or
Wi-Fi frame) observed automatic rejoin/DHCP/DNS/SNTP/trusted health and then privately
bootstrapped the RAM bearer;3heartbeats/6idle polls/DEVICE_PASS. This establishes
persistent restore across reset, NOT a physical cable/power-bank cold-cycle claim.

An operator-started local hotspot-off/return test listened only (zero serial writes,
zero resets) and observed link loss/ticket invalidation, bounded association
attempts2/3, backoff1123/3062/7932ms, then attempt4 rejoined the same network.
DNS/SNTP/trusted health200 passed; authenticated heartbeats8 and9 resumed without
Wi-Fi re-entry or bearer relay. No mock command/upload was sent. Sanitized evidence:
`firmware/build/saved-wifi-private-save.log`, `saved-wifi-restart-bearer-bootstrap.log`,
`saved-wifi-hotspot-cycle.log` and its resultJSON. These ignored local traces are
not fabricated substitutes for future long-duration or power-cycle acceptance.

Independent read-only server checks AFTER the listener closed:
10:38:36.926389UTC last_seen10:38:32.407638 age4.518751s;
10:38:57.413956UTC last_seen10:38:45.315899 age12.098057s. Heartbeat advanced inside
the existing30second online window; production concurrently migrated to schema7.
Read-only reconciliation10:38:58UTC confirmed the original accepted demo still
COMPLETE/exactly1device measurement/no active unexpired session. No backend writes
or new app user/arm/result occurred in this firmware task.

Full host suite and all three pinned cross-builds pass; helper Ruff checks pass.
Synthetic tests cover saved blob restore/replacement/corruption/scrubbing, opt-in
versus RAM default, repeated explicit SDK configuration after failure, one SSID,
30second association windows, timer wrap,1000successive failed attempts and capped
jitter, hotspot return, live-ticket invalidation, held pending payload preservation,
negative-auth loss/recovery, auth/schema stop, private acknowledgment and bearer-only
bootstrap. Independent review identified three edge cases; corrected paths were
self-reviewed and regression-tested. No second final independent review is claimed.
Physical save/software-reset/hotspot-loss results above are separate from host
fixtures. Long-duration soak and actual cable/power-bank cycle remain unverified.

## === BACKEND CONTRACT CHANGE ===

NON-BREAKING: endpoint/schema/session expiry/measurement payload/source semantics
unchanged. No server/database or deployment edits. Already accepted mock history
must remain unchanged during commissioning; no live arms/uploads are required.

## === LIAM / iOS IMPACT ===

NON-BREAKING; no client action or app edit. Network recovery does not rearm/extend
sessions or supply a measurement. All iOS/presentation/NFC handling remains Liam's.
