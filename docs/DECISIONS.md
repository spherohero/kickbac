# Architectural decisions

## First vertical slice
- **Choice:** FastAPI, SQLite, synchronous transactional writes, one API process, HTTP polling. Users are verified external identity subjects; no speculative profile table.
- **Why:** quickest reliable authenticated association -> simulator measurement -> private history path. One low-volume shared demo unit does not require distributed workers or realtime infrastructure.
- **Rejected for now:** managed Postgres/realtime (extra provisioning), WebSockets/SSE (extra connection/reconnect behavior), party-game backend (outside initial milestone). SQLite requires persistent disk, backups and one deployment instance; never deploy it on ephemeral serverless storage.

## Auth and sponsor resources
- **Choice:** Auth0 access-token validation with RS256/JWKS, exact issuer/audience/expiry; no passwords or login endpoint in the backend. Vultr is the proposed host; user confirms account/credits ready, but no VM/region/budget or hosted service is verified.
- **Why:** sponsor-supported authentication with documented SwiftUI SDK. Auth0 tenant/API/Native app creation is reported complete, and public discovery/JWKS were independently verified. Liam's exact bundle ID is com.liam.KickBAC and the target public API is https://api.kickbac.vodka. Callback allowlists are reported saved and a fresh public request now returns login_required to the URI-equivalent callback rather than a mismatch; real user login remains unverified. Native callback/bundle configuration belongs to Liam; coordinate before changes.
- **Rejected for now:** DeepSpace browser-oriented auth, whose native Swift handoff has not been verified; combining two identity providers; Tiger Data merely for sponsor coverage.
- **Sources:** https://www.mlh.com/events/swamphacks-xii/prizes ; https://auth0.com/docs/quickstart/native/ios-swift ; https://docs.deep.space/guides/authentication . Account credits are not proof of free deployment or successful integration.

## Association and identity limits
- **Choice:** authenticated confirmation arms a known device for 60 seconds, one active session per device; retry by its owner reuses the session without extending expiry. Cancel/expiry releases the unit. Device credentials are provisioned independently, random and stored hashed.
- **Why:** bounds stale assignments and prevents competing app requests from stealing a session. The backend derives ownership; device requests cannot select a user.
- **Limit:** a timeout does not authenticate the person physically exhaling. Confirm target on the phone/device before the sample; no biometric identity claim.

## Readings and retries
- **Choice:** explicit raw MQ-3 ADC counts, breath duration, source, optional true acquisition time, server receive time; estimated_bac_percent remains null. No numeric BAC fabricated from uncalibrated ADC values.
- **Choice:** device-generated measurement UUID; replay of identical validated payload returns the original result even after completion/expiry, changed payload conflicts, new ID cannot reuse a terminal session.
- **Why:** Wi-Fi retries must not produce duplicates or reassign samples. Device state is derived from its current unexpired session, not separately mutable state.

## Local authentication demonstration
- **Choice:** a standalone simulator may generate an ephemeral RSA identity fixture and exercise real HTTP and signed-token validation on loopback, explicitly labeled simulated OIDC. Normal server configuration accepts only the configured Auth0 tenant.
- **Why:** test without hardware/accounts, without adding a public dev-login endpoint or silently bypassing production authentication. This is NOT proof of real Auth0 login, live sensor calibration, public HTTPS or iPhone integration.

## Firmware experiment boundary
- **Choice:** a board-independent C++11 MQ signal-trigger core, explicit operator-accepted baseline, median/EWMA filtering, configurable baseline-relative onset, sustained crossing, hysteresis, recovery/cooldown, and fail-closed telemetry faults. See `firmware/README.md` for tests and pending physical experiments.
- **Why:** evaluate signal behavior without selecting an unconfirmed board, unsafe voltage/pins or fabricated breath metadata. Freeze baseline during an experiment so residual exposure is not automatically normalized away. All current test signals/tuning are synthetic; no actual sensor conditioning or breath detection is verified.
- **Rejected for now:** arbitrary fixed ADC threshold, MQ-only proof of sober breath, assumed DHT11 airflow detection, timeout-as-zero, synthetic breath duration, guessed pinout/board target, BAC conversion and disabled TLS checks.
- **Contract gate:** no paths, schemas or statuses changed. Sampling/upload implementation remains blocked on truthful duration semantics. `docs/FIRMWARE_DURATION_PROPOSAL.md` describes an UNAPPROVED breaking manual/timed fallback and Liam's required coordination; it is not permission to change the API.

## Confirmed XIAO USB-only bring-up
- **Choice:** PlatformIO's standard `seeed_xiao_esp32s3` Arduino target with pinned platform/framework/uploader and native USB CDC. First firmware reports uptime only; no external sensor pin, heater, radio or credentials are configured.
- **Why:** isolate USB verification from electrical sensor risks. Nicholas's later actual photo and purchased ASIN supersede the earlier verbal bare-sensor description: the hardware is a Flying Fish-style four-pin MQ breakout with VCC/GND/DO/AO, comparator and trimmer. Its six sensor legs must not be separately wired or given a bare-sensor load network. Use serial initially; no external button/LED or assumed DHT11 breath gate is needed.
- **Verification boundary:** host USB fixture, real XIAO cross-build, verified-chip/flash identification, physical COM3 upload with flash hashes, and two physical serial monitor opens pass. These establish USB-only execution, not gas sensing or Wi-Fi. Fresh PC-side trusted HTTPS health/device-resolution/OpenAPI checks pass against the concurrently deployed backend; no device-authenticated ESP32 traffic or contract revision is claimed. Actual supply/protection parts and meter checks still gate sensor wiring; see `docs/HARDWARE_BRINGUP.md`.

## Physical Wi-Fi diagnostic without changing device/API semantics

Subsequent authenticated diagnostic: separate `xiao_device` adds the existing
device bearer, heartbeat10s/poll2s, exact bounded JSON validation and fail-closed
credential clearing. Reuse the existing operator credential over private SSH
and trusted local USB, not a new provisioning/rotation or human auth flow.
Pinned ArduinoJson6.21.6 is shared by real firmware and host validation tests.
All3targets build and the new image was flashed/hash-verified. After Nicholas
returned with his phone and requested a reopen, actual negative401, three
heartbeat200, six idle polls200 and independent live persisted ongoing heartbeat
readback pass. No sessions/measurements created; no sampling/uploads/API/iOS changes. Details:
`docs/DEVICE_CONNECTIVITY.md`.
- **Choice:** independent `xiao_wifi` source-filtered target, radio scan with no SSID logging, user-selected local masked-entry window, bounded USB credential framing, RAM-only SDK Wi-Fi config, SNTP before trusted TLS, exact public health response validation and one deliberate software reconnect.
- **Why:** prove actual radio-to-backend HTTPS without reading OS keys, storing hotspot passwords, disabling certificate validation, using captive-portal workarounds or claiming device-auth/upload completion. The public ISRG Root X1 certificate was checked against its official source and server chain; no private credential is compiled in.
- **Verified:** real scan, association/DHCP, DNS, SNTP, HTTP200 and post-disconnect second HTTP200. Host fixtures cover credential framing/timeouts/clearing and response validation; both firmware targets cross-build. See `docs/WIFI_CONNECTIVITY.md` for read-back evidence. Sensor/ADC/BLE and uploads remain disabled. Current image needs private network re-entry after reset; no production provisioning or long-term reliability claim.
