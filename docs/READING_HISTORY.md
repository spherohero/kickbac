# Private per-person reading history

Every **accepted completed test** is persisted in SQLite `measurements`, linked to its unique session/device and the session's verified Auth0 subject. The private profile uses the same subject. History is not stored in the mutable name/photo fields, and does not depend on creating the profile first. No extra user table or duplicate history store is needed.

## Manual acquisition compatibility — deployed, physical acceptance separate

Manual readings retain `breath_duration_ms:null`, `acquisition_method:"manual_timed"`
and actual `sample_duration_ms`, distinct from measured breath duration. Show
"Timed sensor sample — breath not validated" visibly and for accessibility.
Legacy records retain exact integer-duration wire JSON and omit new metadata;
neither migration nor profile edits rewrite their payloads. No trigger or an
invalid window is no result, never zero BAC. Exact frozen validation/retry and
rollout gates: [FIRMWARE_DURATION_PROPOSAL.md](FIRMWARE_DURATION_PROPOSAL.md).

## Exact summary and game-use readings — deployed

`GET /v1/me/reading-summary` supplies an owner-scoped exact SQL count and latest
saved measurement in one read-only snapshot; details in
[API.md](API.md#private-reading-summary). It includes ordinary, game-use and
simulator readings independently of profile existence or loaded pages. The new
party result context references an existing owned measurement; it does not
remove it from this history, create a second reading, award test points or make
its unavailable BAC numeric. NFC ARM-time context is implemented locally and
retained before/without completion via private `GET /v1/me/check-ins`; exact
semantics are in [NFC_CHECK_IN.md](NFC_CHECK_IN.md). Existing live history below
is unchanged; native NFC and physical samples are not established by this source.

## === LIAM / iOS IMPACT ===

**NON-BREAKING — existing API; explicit integration for Me → Reading history.**

Use the same API access token as `/v1/me/profile`:

```http
GET /v1/measurements?limit=50&offset=0
Authorization: Bearer <API_A...KEN>
```

Illustrative **simulator** response, not measured BAC:

```json
{
  "items": [
    {
      "id": "026af7c9-d605-4291-a1db-5b230e10ef43",
      "session_id": "3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b",
      "device_id": "kb-demo-01",
      "raw": {"sensor":"mq3","value":1200,"unit":"adc_counts"},
      "breath_duration_ms": 2500,
      "source": "simulator",
      "measured_at": null,
      "received_at": "2026-10-17T23:00:05+00:00",
      "estimated_bac_percent": null
    }
  ],
  "limit": 50,
  "offset": 0,
  "has_more": false
}
```

- Limit defaults50, allowed0–100; offset defaults0 and is nonnegative. Use a positive page size. Newest server `received_at` first, ID descending for ties; honor `has_more`, do not invent a total. Refresh from offset0 when new tests arrive.
- Owner comes from the validated token, not a client `user_id`/phone/display name parameter. Separate Auth0 subjects remain separate even when contact claims match. Switch/clear local cached history on logout/account change.
- Session detail is `GET /v1/sessions/{session_id}` and includes the measurement. There is **no separate measurement-detail route** in this contract.
- Successful profile creation/edits, relogin with the same identity and service restart preserve past measurements. Phone remains Auth0-owned.
- Identical device UUID/payload retries return the original measurement; they do not create extra tests. A consumed session cannot be reused for a new measurement. Only the device submits measurements; iOS never receives its credential.
- Invalid/rejected uploads, cancellation/expiry and no usable breath trigger are not completed measurements and are **not saved as sober/zero results**. There is no separate unsuccessful-attempt history API.
- Current uncalibrated MQ-3 `estimated_bac_percent` is **null**. Display unavailable, never0.00 or ADC counts as BAC; distinguish `source: simulator|device`. No safe-to-drive, medical or police-grade accuracy claims. `measured_at` is optional acquisition time; `received_at` is server receive time. Required duration metadata does not validate breath quality; hardware contract changes need separate coordination.

## Verification

`backend/tests/test_profile_reading_history.py` persists two different completed simulator tests **before** creating the profile, verifies them after both photo/name replacement and removal, then starts a fresh app over the same SQLite DB with a fresh signed identity token. The same owner retains both records; another owner has empty history and cannot access either private session. The test also asserts BAC stays unavailable rather than fabricating numeric estimates. Existing device/session tests cover reconnect retry deduplication, expiration, one-time completion and malformed readings.

This regression is published with [profile PR #3](https://github.com/spherohero/kickbac/pull/3). Isolated signed fixtures are not proof of a real iPhone/Auth0/sensor run; Liam owns native save/relaunch/relogin/history acceptance. SQLite and online snapshots contain these private readings; no account deletion/retention/off-host disaster-recovery guarantee is implemented.