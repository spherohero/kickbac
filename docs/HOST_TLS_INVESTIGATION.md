# Host-side investigation of the device reconnect failure

## Finding — read-only, not a firmware fix

Backend owner investigated the existing authorized Ubuntu host at
**2026-10-18T08:11:54 UTC**, with historical journal window
**07:45:00–08:08:00 UTC**. No service, firewall, proxy, certificate, rate-limit,
logging or database setting was changed. No credential entry, serial operation,
new real user, arm or measurement was performed. Firmware owns physical diagnosis.

**One concrete API rollout interruption is established:**

- API stop was requested at07:55:18.536323 and completed07:55:18.686984,
  systemd started the replacement at07:55:18.811291, the Uvicorn process announced
  itself07:55:19.557308, and application startup completed07:55:19.559551 UTC.
  These are journal observations, not inferred from public response timing.
- Caddy logged **one502** at **07:55:19.012930 UTC** on a request classified as
  `GET /v1/device/session`, with loopback127.0.0.1:8000 connection refused.
  Duration0.000398253seconds. Host-side extraction whitelisted timestamp,
  status, endpoint class and error category only; private request headers/client
  identity/raw request records were not emitted or published.
- The flashed diagnostic's `firmware/src/device_probe.cpp:120–124` treats an
  invalid poll response as `stop_probe("poll", status)`. Lines36–40 clear its
  session fence/credential and latch failure; line80 returns on all later loops.
  Therefore a502 can permanently stop this diagnostic's heartbeat/poll loop.
  This is source evidence of a mechanism, **not proof that the logged request was
  the exact board or that its unobserved failure was502**. The earlier short-helper
  stale heartbeat happened before this rollout and is not explained by it.
- The last physical heartbeat07:55:16.264437 predates the short rollout interval;
  the later stale readback is consistent with this mechanism. Caddy remained
  active from October17 at22:29:20 UTC, with no Caddy restart during the interval.
  API and Caddy report zero automatic restarts; API is active on the new release.

## HTTPS / firewall / capacity evidence

- Public trusted HTTPS `/health` returned200/`{"status":"ok"}` during the
  investigation. Public OpenAPI still has33operations/manual fields. These PC
  requests establish current reachability from that path, not the ESP32 path.
- Current TCP443 listener is public, TCP8000 is loopback only; both receive queues
  were0. Listen backlog counters `ListenOverflows`, `ListenDrops`,
  `TCPReqQFullDoCookies`, `TCPReqQFullDrop`, `SyncookiesSent` and
  `SyncookiesFailed` were0. These are cumulative counters, not packet proof for
  a particular failed attempt.
- UFW is active: incoming default deny/outgoing allow, explicit TCP443 ALLOW from
  Anywhere for IPv4 and IPv6. nftables confirms dedicated443 accept rules; their
  observed packet counters were1238IPv4/0IPv6. No new rule or rate setting was added.
- Kernel journal contains69UFW block records in the historical window. Properly
  decoding journald byte-array MESSAGE values shows all69were TCP to other
  destination ports: **none to443**. Log absence is not proof every packet arrived;
  log rate limiting and upstream/cloud/network components can hide losses.
- No Caddy rate-limit handler/directive is configured; adapted HTTP handlers are
  subroute, headers and reverse_proxy. Existing nft limit expressions are in UFW
  logging/helper chains, not evidence of a per-source HTTPS application throttle.
  Fail2ban is not active. No handshake/timeout/rate-limit/429 event was found in the
  selected Caddy/API journal window; the one error was the rollout502 above.
- Caddy access logs are intentionally disabled for privacy. Historical source-IP
  traffic, successful health requests and pre-HTTP TCP/TLS stages cannot be
  reconstructed from access logs that do not exist. Cloud firewall/source-path
  state was not established by this host-only investigation.

## What remains unproved

The final serial capture shows initial health200, rejoin/DNS success, then three
reconnect checks returning HTTPClient-1/SDK-1 in7001/7002/7002ms. The captured
lines have no synchronized absolute UTC for each request. File modification time
07:58:58.100914 UTC is a capture-file timestamp, not a request timestamp. These
failures must not be silently equated with the earlier HTTP502:

- HTTP502 proves an HTTP connection reached Caddy but its upstream was restarting.
- HTTPClient-1 alone does not distinguish failed TCP connect, TLS setup, timeout,
  device state or a path fault. Root cause of the later reconnect remains unknown.
- No contemporaneous packet trace exists here. Do not disable certificate/hostname
  verification, widen firewall access, turn on private request logging, add retries
  indiscriminately or claim a certificate failure based only on-1.

## Next bounded owner action

Firmware owner should separate two cases: (1) diagnostic terminal handling of a
transient authenticated5xx, and (2) the later pre-auth reconnect failure. Any
recovery change must invalidate the acquisition ticket on fault, preserve original
session/expiry and immutable pending upload bytes, and never reassign a sample to
another user/session. No backend schema/cadence change is proposed by this report.

For the latter case, first add/test safe stage evidence that distinguishes TCP
connect from TLS setup, with actual UTC/monotonic request boundaries, no bearer,
Wi-Fi credential, private response or raw packet payload. If another physical
run is justified, coordinate a bounded header-only/source-filtered host TCP trace
at that exact time rather than repeat uncorrelated private-entry attempts.
`tcpdump` is already installed, but **no capture was started in this investigation**.
No firmware implementation, new run or electrical acceptance is implied.

## Reproduction / retained evidence

Operator read-only probes used host-key-verified existing SSH, `systemctl show`,
`journalctl -o json` for the two services/kernel and bounded UTC window,
`caddy adapt`, `ss -ltnH`/`ss -tanH`, `ufw status verbose`,
`nft -j list ruleset` and `/proc/net/{netstat,snmp}`. Commands were run inside a
whitelist-only extractor: raw journals/Caddy errors can contain private request
headers and must not be printed or pasted. Journald MESSAGE may be text or byte
array; decode both before classifying firewall protocols/ports. An unparsed byte
array must not be reported as an unknown network protocol.

Sanitized primary local report retained in the backend profile scratch as
`KICKBAC_HOST_TLS_READONLY.json`; supplementary in-memory extraction established
endpoint class/502, UFW TCP destination classification and logging-chain limits.
Source/physical evidence remains in
[DEVICE_SESSION_VERIFICATION.md](DEVICE_SESSION_VERIFICATION.md).
Deployment proof: [BACKEND_RELEASE_VERIFICATION.md](BACKEND_RELEASE_VERIFICATION.md).

## Liam / iOS impact

**NON-BREAKING; no client change required by this investigation.** Auth, paths,
request/response schemas, examples,60second sessions,30second online freshness,
raw units and nullable BAC remain unchanged. Report offline/error honestly; an
armed session is not proof hardware is ready. Nicholas has returned all remaining
iOS work/native acceptance to Liam; backend is not continuing the client takeover.
