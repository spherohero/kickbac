import json
from typing import Annotated

from fastapi import APIRouter, Query, Request, Response

from .db import connect
from .errors import fail
from .models import (
    HistoryResponse,
    MeasurementResponse,
    MeasurementUpload,
    ReadingSummaryResponse,
)
from .sessions import (
    Device,
    User,
    instant,
    log,
    measurement_response,
    session_transaction,
)

router = APIRouter()


@router.post(
    "/v1/device/measurements",
    response_model=MeasurementResponse,
    status_code=201,
    responses={
        200: {"model": MeasurementResponse, "description": "Identical upload replay"}
    },
)
def upload(
    body: MeasurementUpload, request: Request, response: Response, device_id: Device
):
    canonical = json.dumps(
        body.model_dump(mode="json"), sort_keys=True, separators=(",", ":")
    )
    session_id = str(body.session_id)
    measurement_id = str(body.measurement_id)
    with session_transaction(request) as db:
        existing = db.execute(
            "SELECT * FROM measurements WHERE id=?", (measurement_id,)
        ).fetchone()
        if existing:
            if existing["device_id"] != device_id:
                fail(404, "not_found")
            if existing["payload"] != canonical:
                fail(409, "idempotency_conflict")
            response.status_code = 200
            return measurement_response(existing)
        session = db.execute(
            "SELECT * FROM sessions WHERE id=? AND device_id=?", (session_id, device_id)
        ).fetchone()
        if session is None:
            fail(404, "not_found")
        if session["status"] == "EXPIRED":
            fail(410, "session_expired")
        if session["status"] not in ("ARMED", "SAMPLING"):
            fail(409, "invalid_state")
        received_at = instant(request).isoformat()
        db.execute(
            "INSERT INTO measurements(id,session_id,device_id,user_id,payload,received_at) VALUES (?,?,?,?,?,?)",
            (
                measurement_id,
                session_id,
                device_id,
                session["user_id"],
                canonical,
                received_at,
            ),
        )
        db.execute(
            "UPDATE sessions SET status='COMPLETE',completed_at=? WHERE id=?",
            (received_at, session_id),
        )
        result = db.execute(
            "SELECT * FROM measurements WHERE id=?", (measurement_id,)
        ).fetchone()
        log.info(
            "device=%s session=%s user=%s transition=COMPLETE measurement=%s",
            device_id,
            session_id,
            session["user_id"],
            measurement_id,
        )
        return measurement_response(result)


@router.get("/v1/me/reading-summary", response_model=ReadingSummaryResponse)
def reading_summary(request: Request, subject: User):
    """Exact lifetime count and latest accepted reading for the validated owner.

    Includes simulator and game-use readings; no profile or pagination dependency.
    Reads one SQL snapshot without persisting lazy session expiry or other writes.
    """
    with connect(request.app.state.settings.db_path) as db:
        db.execute("PRAGMA query_only=ON")
        db.execute("BEGIN")
        count = db.execute(
            "SELECT COUNT(*) FROM measurements WHERE user_id=?", (subject,)
        ).fetchone()[0]
        latest = db.execute(
            "SELECT * FROM measurements WHERE user_id=? "
            "ORDER BY received_at DESC,id DESC LIMIT 1",
            (subject,),
        ).fetchone()
    return {
        "user_id": subject,
        "saved_readings": count,
        "latest_measurement": measurement_response(latest) if latest else None,
    }


@router.get("/v1/measurements", response_model=HistoryResponse)
def history(
    request: Request,
    subject: User,
    limit: Annotated[int, Query(ge=0, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    with session_transaction(request) as db:
        rows = db.execute(
            "SELECT * FROM measurements WHERE user_id=? ORDER BY received_at DESC,id DESC LIMIT ? OFFSET ?",
            (subject, limit + 1, offset),
        ).fetchall()
        return {
            "items": [measurement_response(row) for row in rows[:limit]],
            "limit": limit,
            "offset": offset,
            "has_more": len(rows) > limit,
        }
