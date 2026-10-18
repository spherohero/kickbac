# Firmware duration / manual acquisition — implementation contract

**Approved direction for implementation; NOT IMPLEMENTED/DEPLOYED yet.** Nicholas
authorizes truthful unvalidated acquisition with a notice and, until 04:00 Eastern
on October18, necessary iOS implementation in parallel. Backend owner is working
on `backend/manual-timed-acquisition`, base3fd50c7. Firmware owns physical work.
Existing live API remains unchanged; do not send this format until deployed
OpenAPI and exact acceptance are verified. Older proposal wording below is
historical where superseded by this freeze.

## Frozen bounded implementation

- Keep all paths/auth/session states/60-second expiry/ownership unchanged.
- `breath_duration_ms` stays required. Legacy mode accepts the existing strict
  integer1..60000 with omitted/null acquisition metadata. Manual mode requires
  explicit null duration, `acquisition_method:"manual_timed"` and strict measured
  `sample_duration_ms`1..60000. Reject mixed/missing/unknown mode metadata.
- Return manual metadata with manual measurements everywhere they are nested:
  upload, session, reading history/summary, check-ins and rich game history.
  Existing legacy response JSON stays exact: omit the two new metadata keys for
  legacy records, without omitting existing null acquisition time/BAC fields.
- Preserve legacy stored JSON/canonical retries byte-for-byte; omitted and paired
  null new metadata normalize to legacy omission. Manual retries retain original
  UUID/session/payload/time through completion/expiry/restart, with changed payload
  conflict and foreign-owner/device denial. No SQL schema change is needed for
  JSON payload metadata; retain reviewed explicit schema6 upgrade requirements.
- SAMPLING means sensor acquisition, not validated breath. Explicit app ARMED
  session precedes a separate deliberate USB start in the initial physical mode;
  no sample solely because a lease exists. Firmware chooses/documents an actual
  measured acquisition window/raw-summary from safe traces, not a BAC conversion.
- Always show "Timed sensor sample — breath not validated" for manual mode,
  including accessibility. BAC stays null; no trigger, timeout, rails or invalid
  trace never becomes a completed zero-alcohol result.
- **BREAKING:** nullable duration requires coordinated iOS model and view changes.
  Refreshed `liam/party-setup@0e5a6e4` still requires Int and renders breath
  duration. Isolated client work may now change those owned paths before04:00;
  never force-push or overwrite concurrent edits. Runtime release waits for
  compatible client source/fixtures and actual device-upload readiness.

### Current execution boundaries

Nicholas confirms COM3 exclusive and permits firmware open/reset/flash; he
declines additional electrical measurements/photos. This is not independent
electrical sign-off. Request the reviewed no-ADC USB/network/session diagnostic
flash first; do not mark skipped protection checks passed. Firmware owner must
report actual image/connection evidence separately from source CI. No live
synthetic user/measurement or arbitrary profile assignment is authorized.

## === BACKEND CONTRACT CHANGE ===

### Why this is necessary

The pressure sensor is confirmed unavailable. A baseline-relative MQ signal event
is not proof of exhalation, and time above its threshold is not breath duration.
A DHT11 is unconfirmed and its slow humidity response cannot be assumed to solve
this. No trigger/timeout must never become a valid zero-alcohol result.

Recommend an operator-started **manual timed sensor sample** fallback if actual
experiments cannot establish breath presence. Until approved, keep this local and
do not call sampling/upload based on the heuristic or an arbitrary timer.

### Existing behavior / exact affected endpoints

- `POST /v1/device/sessions/{session_id}/sampling` accepts `{}` and is documented
  as valid-breath sampling start. It returns device-safe status `SAMPLING`.
- `POST /v1/device/measurements` requires integer `breath_duration_ms` 1..60000.
- Measurement responses, `GET /v1/sessions/{session_id}` and
  `GET /v1/measurements` expose integer `breath_duration_ms`.
- Backend rejects null duration and unknown properties. The following proposed
  request will therefore fail on the unchanged server; do not send it yet.

Existing illustrative request (from the contract, NOT physical evidence):

```json
{
  "measurement_id": "026af7c9-d605-4291-a1db-5b230e10ef43",
  "session_id": "3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b",
  "raw": {"sensor": "mq3", "value": 1200, "unit": "adc_counts"},
  "breath_duration_ms": 2500,
  "source": "simulator",
  "measured_at": null
}
```

### Proposed changes, subject to explicit approval

For a manual timed sample, allow null breath duration and add explicit acquisition
metadata. Example values below are illustrative, NOT a recorded sample or
selected hardware window/threshold:

```json
{
  "measurement_id": "026af7c9-d605-4291-a1db-5b230e10ef43",
  "session_id": "3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b",
  "raw": {"sensor": "mq3", "value": 1200, "unit": "adc_counts"},
  "breath_duration_ms": null,
  "acquisition_method": "manual_timed",
  "sample_duration_ms": 5000,
  "source": "device",
  "measured_at": null
}
```

Proposed matching measurement response (also used inside session/history):

```json
{
  "id": "026af7c9-d605-4291-a1db-5b230e10ef43",
  "session_id": "3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b",
  "device_id": "kb-demo-01",
  "raw": {"sensor": "mq3", "value": 1200, "unit": "adc_counts"},
  "breath_duration_ms": null,
  "acquisition_method": "manual_timed",
  "sample_duration_ms": 5000,
  "source": "device",
  "measured_at": null,
  "received_at": "2026-10-17T01:00:05Z",
  "estimated_bac_percent": null
}
```

- `sample_duration_ms` means measured local acquisition-window time, NOT time
  exhaling. Proposed bound is a positive integer up to 60000; the server-owned
  session expiry still applies and does not extend for a sampling window.
- Manual samples require method `manual_timed`, a measured sample duration and
  null breath duration. Mixed or missing metadata should fail validation.
- Proposed compatibility: preserve existing valid uploads with integer breath
  duration and omitted acquisition metadata. Expose null acquisition metadata for
  legacy rows; do not backfill an unsupported validation claim. Verify canonical
  payload replay compatibility for existing persisted rows before implementation.
- Reword `SAMPLING` for this mode to mean sensor acquisition, not confirmed breath.
  No new route, authentication rule or status enum is proposed. The unchanged `{}`
  sampling body alone does not convey acquisition method before completion; Liam
  must not show a validated-breath claim while sampling. If the product needs a
  live method indicator, coordinate that separately before adding fields/routes.
- Raw ADC stays integer 0..4095 in `adc_counts`, never numeric BAC. Actual hardware
  readings use `device`; synthetic fixtures remain `simulator`. Unknown real UTC
  stays null. Window length and raw-sample selection need actual acquisition
  experiments and documentation; this proposal does not select them.
- Heartbeat, polling, correct-user/device ownership, 60-second exclusive session,
  terminal/expiry behavior, errors and UUID/identical-payload idempotency remain.
- No exposure/trigger yields no heuristic result. A manual sample exists only
  after explicit operator action and actual acquisition, labeled unvalidated;
  it must not be invented from timeout or presented as zero alcohol.

**BREAKING:** nullable measurement breath duration and changed sampling meaning
can break existing decoders and UX even if legacy requests remain accepted. API
models, response generation, legacy stored JSON, idempotency, simulator, docs and
client compatibility must be handled together. No migration or code is applied.

## === LIAM / iOS IMPACT ===

1. **What would change:** an explicitly unvalidated manual sample could complete
   a session with null breath duration and a separately measured sensor window.
2. **Why:** missing pressure sensing; neither MQ response nor a DHT11 assumption
   provides truthful breath duration.
3. **Liam needs:** review/acknowledge the proposal, decode nullable breath duration
   and acquisition metadata, and display “Timed sensor sample—breath not
   validated.” Do not show BAC from ADC, inferred zero, a confirmed-breath badge,
   or “keep blowing until detected” as a guaranteed sober-breath workflow.
4. **Endpoints/payloads:** unchanged paths above; request/response examples above;
   private session/history measurements carry the same proposed nullable fields.
   While `SAMPLING`, show sensor acquisition, not validated breath detection.
5. **Compatibility:** BREAKING until coordinated and tested. No SwiftUI source,
   auth/login behavior, Figma object or current API contract changed here.

## Approval / verification still needed

Nicholas's explicit contract decision and Liam coordination; physical board/module
inventory; safe electrical design; actual stable ADC traces; chosen timed
acquisition behavior; tests for legacy rows/replays, null/mixed metadata,
expiry/retry/isolation; reachable authenticated backend and TLS; real reading
persisted and read back for the correct session/user. None is silently complete.
