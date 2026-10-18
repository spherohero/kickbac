# ESP32 physical Wi-Fi connectivity checkpoint

**Later image:** `xiao_device` has since been flashed and actual authenticated
heartbeat/poll plus independent persisted ongoing heartbeat readback passed.
See `DEVICE_CONNECTIVITY.md`. The Wi-Fi evidence below is the earlier successful
checkpoint; authenticated-device evidence belongs to the later document.

## Result: CONNECTIVITY_PASS (real board, not a simulator)

The previously verified XIAO ESP32-S3 on COM3 was identified again by USB
VID:PID and serial identity before flashing `xiao_wifi`. Nicholas confirms the
FPC antenna is connected. Sensor pins, ADC, BLE and uploads remain disabled.
The test did not use any device bearer credential or create/arm/complete a session.

### Actual measurements/readback

- Physical 2.4 GHz scan: **46 access points**, strongest received **-63 dBm on
  channel 1**. SSIDs/BSSIDs were not printed. This demonstrates reception with
  the antenna connected, not a calibrated RF comparison or an exhaustive count
  of unique networks; multiple access points may broadcast the same network.
- Private user-selected network: actual association and DHCP succeeded;
  connected **-34 dBm on channel 6**.
- DNS resolution of `api.kickbac.vodka`: success.
- Actual SNTP synchronization: completed before checking certificate validity.
- Actual ESP32 `GET https://api.kickbac.vodka/health`: **HTTP200**, expected
  `{"status":"ok"}`. Public ISRG Root X1 trust anchor, hostname/date validation;
  no insecure TLS override, redirect following, HTTP downgrade or captive-portal
  acceptance. Root PEM independently byte-compared with Let's Encrypt's official
  public certificate; PC verified the server chain with that exact root too.
- Controlled software disconnect was observed. Board reassociated with the
  same RAM-only Wi-Fi configuration and DHCP succeeded, **-36 dBm on channel 6**.
- DNS succeeded again; second actual certificate-validated HTTPS health GET
  returned **HTTP200** and the correct response. This is a software reconnect
  test, not USB unplug, AP outage, reset persistence or long-duration soak.

Sanitized physical trace read back from ignored local evidence
`firmware/build/wifi-connectivity.log`:

```text
probe_join state=started credentials=ram_only
probe_wifi joined=1 dhcp=1 rssi_dbm=-34 channel=6
probe_dns ok=1
probe_clock sntp_synced=1
probe_https attempt=1 status=200 trusted_tls=1 health_ok=1
probe_disconnect observed=1
probe_wifi rejoined=1 dhcp=1 rssi_dbm=-36 channel=6
probe_dns ok=1
probe_https attempt=2 status=200 trusted_tls=1 health_ok=1
CONNECTIVITY_PASS wifi=1 dhcp=1 dns=1 trusted_https=1 reconnect=1 sensor=disabled uploads=disabled
```

Radio-scan evidence: `firmware/build/wifi-scan.log`. Initial monitor opening missed
the already-completed startup scan; a controlled esptool reset followed by immediate
serial capture obtained the actual scan. Do not treat the initial missing output
as a radio failure. Both build environments and host fixture tests pass.

## Implementation and privacy boundary

- `firmware/src/wifi_probe.cpp`: diagnostic-only application; independent from
  the USB-only `main.cpp`. Build source filters select exactly one application.
- `firmware/include/wifi_diagnostic.hpp`: bounded local binary provisioning
  parser; length checks, partial-frame timeout, explicit array clearing, no echo;
  exact tiny health-body validation. Host fixtures test these behaviors.
- `firmware/include/tls_root.hpp`: public root certificate, not a credential.
- `firmware/tools/provision_wifi.py`: user-authorized local tkinter entry window,
  masked password, no OS profile/key reading. Sends one frame over the attached
  USB serial connection, never network/wireless provisioning. USB frame itself is
  not encrypted; use a trusted local machine/board. No passwords in chat, command
  arguments, source, normal output, files or generated firmware image.
- `WiFi.persistent(false)` before mode initialization plus explicit
  `WIFI_STORAGE_RAM`; provisioning is **not** saved in ESP32 NVS. Parser copy
  cleared after SDK config copy; SDK retains RAM configuration for this session.
  Host bytearray is zeroed after transmission. This is not a claim of forensic
  erasure from Python/GUI/OS memory; those temporary copies are not logged.
- After power loss/reset the diagnostic needs private provisioning again.
  Auto-reconnect is disabled in this test; one reconnect was explicitly exercised.
  A production provisioning/persistence decision is separate work, not silently done.
- No SSID/password/device credential/user identity/IP/BSSID is included in
  committed docs or sanitized logs. Core debug level is 0; Wi-Fi log tag disabled.
- Association/DHCP, scan, SNTP and HTTP stages have bounded waits; errors stop with
  a stage label, never a fake success or insecure retry. Health acceptance requires
  200 and the exact expected tiny body. No API-auth or sensor acceptance inferred.

## Reproduce (Git Bash, repository root)

```bash
bash firmware/test_host.sh
uv tool run --python 3.11 --with pip --from platformio==6.1.19 platformio run -d firmware -e xiao_usb -e xiao_wifi
uv tool run --python 3.11 --with pip --from platformio==6.1.19 platformio device list --json-output
# Verify the actual attached target before using the observed COM3:
uv tool run --python 3.11 --with pip --from platformio==6.1.19 platformio run -d firmware -e xiao_wifi -t upload --upload-port COM3
uv tool run --python 3.11 --with pip --from platformio==6.1.19 python firmware/tools/provision_wifi.py --port COM3
```

The last command opens a local entry window; credentials never belong in chat.
Use a 2.4 GHz WPA2/WPA3-Personal hotspot/router. Captive portal / enterprise
username+password networks are not implemented. For iPhone hotspot use Maximize
Compatibility if necessary. SSID length is bounded to 1..32 UTF-8 bytes and this
helper accepts an 8..63 printable-ASCII personal password; no silent format repair.
Confirm no other serial monitor owns the port. Private dialog auto-closes after
five minutes; provisioning/reception has bounded timeouts.

## What remains unverified

- Device-bearer heartbeat/polling, session ownership, measurement upload/retry and
  persisted result readback; this probe deliberately calls only public health.
- MQ voltage-protected wiring, heater supply/current, real ADC data, conditioning,
  baseline/recovery experiments and truthful sample-duration semantics.
- BLE, antenna A/B performance, venue Wi-Fi/captive-portal operation, AP outage,
  hardware power-cycle and long-term/repeated stress reliability.
- No path/schema/units/state changes; no native/iOS or Figma edits. The duration
  proposal remains unapproved. No-trigger still means no result, not zero alcohol.
- Firmware worktree remains based on inspected 8b222c1. Shared origin/main advanced
  concurrently during this task; nothing was merged/rebased and no commits/pushes
  were made here. Reconcile latest main and companion docs before merge readiness;
  do not interpret the branch's older backend snapshot as a backend deletion.
