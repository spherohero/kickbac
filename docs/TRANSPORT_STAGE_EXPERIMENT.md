# Next bounded transport experiment — prepared, NOT flashed

Firmware owner branch `firmware/transport-stage-diagnostic`, base
`a0bd77bcb79766f91de6746e0ab02fa992f4b337`. Exact publishing PR/head determines
source status. This is a diagnostic artifact, NOT a completed physical experiment
or a fix for the offline board. The last flashed image remains `17ed04b`; its
latest observed reconnect exhausted attempts before device authentication.

## Two separate failure cases

Read [HOST_TLS_INVESTIGATION.md](HOST_TLS_INVESTIGATION.md). Caddy's actual poll502
at07:55:19.012930UTC during API replacement establishes a concrete service-side
interruption. Existing device adapter clears credentials/fence and latches stop
on502. The extended host matrix now explicitly reproduces502 at BOTH heartbeat
and polling with live session tickets, then verifies ticket invalidation, cleared
credential, no further requests, and no restart from another USB bearer frame.
This is synthetic proof of the mechanism, not attribution of the Caddy request to
this exact board. Earlier stale heartbeat before rollout remains unexplained.

The later reconnect HTTPClient-1/SDK-1 around7seconds is a different unresolved
failure. Installed core source maps multiple connect/socket/TLS paths to failure;
-1 alone does not identify certificate rejection. No API/hosting/TLS protection
change or authenticated retry recovery is implemented by this branch.

## Instrumented test artifact

The no-ADC Wi-Fi/device diagnostics now emit exact allowlisted BEGIN/END lines
around each `http.GET()` at the PUBLIC health endpoint:

```text
probe_transport stage=HTTPS attempt=N phase=BEGIN|END monotonic_ms=M utc_s=S status=K duration_ms=D
```

The line above is a FORMAT, not real output. UTC is actual whole epoch seconds
from the SNTP-synchronized clock;0means unavailable. Do not invent fractional UTC
precision, use file modification time as request time or call this acquisition
time. Monotonic durations support uint32 wrap. UTC can step; compare both clocks
and allow whole-second/SNTP uncertainty when correlating server evidence.

`HTTPS` boundaries include DNS/connect/TLS/HTTP header processing inside GET,
not separate internal transport phases, response-body consumption or teardown.
They are NOT proof of where the original request failed.

After closing a failed HTTPS attempt2 ONLY, one separate `WiFiClient` control
connects to the fixed official hostname onTCP443 with a7000ms socket-connect
parameter, then closes. It sends ZERO application payload bytes, bearer, HTTP
request or TLS handshake and cannot declare connectivity pass. It reports matching
numeric `stage=TCP` boundaries. Never use this unauthenticated control as an API
transport or disable TLS for real requests.

The hostname overload may do another DNS lookup (installed core DNS wait up to
15seconds) before the7second socket connect;7seconds is NOT a total wall-clock
bound. Existing HTTPS connect/handshake/read bounds are likewise separate. The
extra control perturbs timing and has a distinct connection/port: a later TCP
success cannot prove the preceding HTTPS TCP connection succeeded. A TCP failure
cannot by itself distinguish DNS/local resources/path/server loss. Packet
correlation is necessary before drawing a stage/root-cause conclusion.

## Tests/review actually executed

- Test-first: new C++ test failed for missing header; new helper-allowlist test
  rejected the new line before implementation. Implemented and reran GREEN.
- `bash firmware/test_host.sh` passes: single connect/close and fixed destination/
  port/timeout, success/failure/clock-wrap boundaries, one-control policy across
  attempt/status combinations, exact allowlisting/privacy, explicit502 live-fence
  fault cases, and existing tests. Fake socket deliberately has no write()/print()
  method, preventing application-byte transmission by the helper interface.
- Pinned Ruff helper lint/format passes; all three pinned XIAO cross-builds pass.
  No upload target was run, no serial opened and no private-entry dialog shown.
- Independent read-only review approved this scoped no-ADC diagnostic; it stressed
  separate-control limitations and DNS+connect versus aggregate bound. No reviewer
  performed a physical run. Published CI is a separate exact-head gate.

## Proposed single coordinated physical run — not started

1. Backend owner confirms a short no-deploy window and a bounded observation
   method. Do not collect unfiltered traffic or add permanent access logging.
2. If packet observation is justified, agree one privately verified source filter,
   publicTCP443 only, maximum120seconds AND packet-count cap. Prefer control flags/
   metadata only. Never use payload/hex/ASCII dumps, packet-file saving, raw request
   headers, credential-bearing logs or publish client addresses. Backend owns
   vetted capture/parser and any separate authorization required. If exact source
   filtering cannot be established, do not substitute a broad capture silently.
3. Re-enumerate the actual target, coordinate fresh exclusive serial access, and
   flash this reviewed no-ADC build only for that run. Existing private operator
   entry remains required after reset; do not reuse OS passwords/chat credentials.
4. Coordinate the capture only AFTER the private entry is ready, not during an
   unbounded credential-wait window. Record actual host/device UTC and monotonic
   boundaries and exact image identity. No live arming, ADC or measurement upload.
5. Run the existing initial HTTPS/reconnect diagnostic once. On failure compare
   original HTTPS connection and later TCP control separately using the bounded
   host metadata; do not equate the two connections. Classify SYN arrival/reply,
   completed TCP, TLS bytes/closure only to the degree metadata actually proves.
6. Stop capture/helper, release serial; retain only sanitized evidence. Abort
   rather than start an uncorrelated private-entry/reset loop. If authentication
   subsequently passes, read back exact persisted device heartbeat after helper
   exit without creating sessions/users/measurements.

No capture or new physical attempt has been requested to start automatically.
The next concrete coordination question is whether backend can arrange the
private-source-filtered bounded observation and a no-deploy window for ONE run.

## === BACKEND CONTRACT CHANGE ===

**NON-BREAKING; no API change.** Same public health, device heartbeat/poll endpoints,
methods/fields/examples,10second/2second nominal completion-relative cadence and
60second server session ownership/expiry. Extra diagnostics are serial-only.
Existing transient authenticated5xx remains terminal in this diagnostic; recovery
would need its own tested safety policy preserving original UUID/expiry/pending
bytes and invalidating acquisition tickets. It is not slipped into this patch.
Backend action is bounded observation coordination only, not hosting changes.

## === LIAM / iOS IMPACT ===

**NON-BREAKING; no app action.** Liam retains ALL remaining iOS control. No app/
Figma/profile changes, session reassignment, acquisition semantics or fabricated
results. ADC/sampling/uploads remain disabled; no electrical acceptance inferred.
Live manual-timed backend support is established separately, not a reason to
bypass physical safety or represent no-trigger as zero.
