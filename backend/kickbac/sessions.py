import json
import logging
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, Request, Response

from .auth import device_identity, user_subject
from .db import transaction
from .errors import fail
from .models import (
    DevicePoll,
    DeviceResponse,
    DeviceSession,
    Empty,
    HeartbeatResponse,
    ResolveResponse,
    SessionResponse,
)

router = APIRouter()
User = Annotated[str, Depends(user_subject)]
Device = Annotated[str, Depends(device_identity)]
log = logging.getLogger("kickbac.transitions")


def instant(request):
    now = request.app.state.clock()
    if now.tzinfo is None or now.utcoffset() is None:
        raise RuntimeError("Clock must be timezone aware")
    return now.astimezone(UTC)


@contextmanager
def session_transaction(request):
    """Serialize state checks/writes; retain lazy expiry on domain errors.

    HTTPException is only used for expected rejections, before business writes.
    Unexpected failures still roll back the entire operation.
    """
    with transaction(request.app.state.settings.db_path) as db:
        expired = db.execute(
            "UPDATE sessions SET status='EXPIRED' WHERE status IN ('ARMED','SAMPLING') AND expires_at<=? RETURNING id,device_id,user_id",
            (instant(request).isoformat(),),
        ).fetchall()
        for row in expired:
            log.info(
                "device=%s session=%s user=%s transition=EXPIRED",
                row["device_id"],
                row["id"],
                row["user_id"],
            )
        try:
            yield db
        except HTTPException:
            db.commit()
            raise


def device_row(db, device_id):
    row = db.execute("SELECT * FROM devices WHERE id=?", (device_id,)).fetchone()
    if row is None:
        fail(404, "not_found")
    return row


def measurement_response(row):
    payload = json.loads(row["payload"])
    return {
        key: value
        for key, value in {
            **payload,
            "id": row["id"],
            "device_id": row["device_id"],
            "received_at": row["received_at"],
            "estimated_bac_percent": None,
        }.items()
        if key != "measurement_id"
    }


def session_response(row, db):
    measurement = db.execute(
        "SELECT * FROM measurements WHERE session_id=?", (row["id"],)
    ).fetchone()
    return {
        **dict(row),
        "measurement": measurement_response(measurement) if measurement else None,
    }


@router.get("/d/{device_id}", response_model=ResolveResponse)
def resolve(device_id: str, request: Request):
    with session_transaction(request) as db:
        device_row(db, device_id)
    return {"device_id": device_id}


@router.get("/v1/devices/{device_id}", response_model=DeviceResponse)
def get_device(device_id: str, request: Request, subject: User):
    with session_transaction(request) as db:
        row = device_row(db, device_id)
        active = db.execute(
            "SELECT * FROM sessions WHERE device_id=? AND status IN ('ARMED','SAMPLING')",
            (device_id,),
        ).fetchone()
        online = (
            row["last_seen_at"] is not None
            and (
                instant(request) - datetime.fromisoformat(row["last_seen_at"])
            ).total_seconds()
            < 30
        )
        return {
            "id": device_id,
            "state": active["status"] if active else "AVAILABLE",
            "online": online,
            "last_seen_at": row["last_seen_at"],
        }


@router.post(
    "/v1/devices/{device_id}/sessions", response_model=SessionResponse, status_code=201
)
def arm(
    device_id: str, body: Empty, request: Request, response: Response, subject: User
):
    with session_transaction(request) as db:
        device_row(db, device_id)
        active = db.execute(
            "SELECT * FROM sessions WHERE device_id=? AND status IN ('ARMED','SAMPLING')",
            (device_id,),
        ).fetchone()
        if active:
            if active["user_id"] != subject:
                fail(409, "device_busy")
            response.status_code = 200
            return session_response(active, db)
        now = instant(request)
        session_id = str(uuid4())
        db.execute(
            "INSERT INTO sessions(id,device_id,user_id,status,created_at,expires_at) VALUES (?,?,?,'ARMED',?,?)",
            (
                session_id,
                device_id,
                subject,
                now.isoformat(),
                (now + timedelta(seconds=60)).isoformat(),
            ),
        )
        row = db.execute("SELECT * FROM sessions WHERE id=?", (session_id,)).fetchone()
        log.info(
            "device=%s session=%s user=%s transition=ARMED",
            device_id,
            session_id,
            subject,
        )
        return session_response(row, db)


@router.get("/v1/sessions/{session_id}", response_model=SessionResponse)
def get_session(session_id: UUID, request: Request, subject: User):
    with session_transaction(request) as db:
        row = db.execute(
            "SELECT * FROM sessions WHERE id=? AND user_id=?",
            (str(session_id), subject),
        ).fetchone()
        if row is None:
            fail(404, "not_found")
        return session_response(row, db)


def device_session(row):
    return {key: row[key] for key in ("id", "device_id", "status", "expires_at")}


@router.post("/v1/device/heartbeat", response_model=HeartbeatResponse)
def heartbeat(body: Empty, request: Request, device_id: Device):
    now = instant(request).isoformat()
    with session_transaction(request) as db:
        db.execute("UPDATE devices SET last_seen_at=? WHERE id=?", (now, device_id))
    return {"device_id": device_id, "online": True, "last_seen_at": now}


@router.get("/v1/device/session", response_model=DevicePoll)
def poll(request: Request, device_id: Device):
    with session_transaction(request) as db:
        active = db.execute(
            "SELECT * FROM sessions WHERE device_id=? AND status IN ('ARMED','SAMPLING')",
            (device_id,),
        ).fetchone()
        return {
            "device_id": device_id,
            "active_session": device_session(active) if active else None,
        }


@router.post("/v1/device/sessions/{session_id}/sampling", response_model=DeviceSession)
def sampling(session_id: UUID, body: Empty, request: Request, device_id: Device):
    with session_transaction(request) as db:
        row = db.execute(
            "SELECT * FROM sessions WHERE id=? AND device_id=?",
            (str(session_id), device_id),
        ).fetchone()
        if row is None:
            fail(404, "not_found")
        if row["status"] == "EXPIRED":
            fail(410, "session_expired")
        if row["status"] not in ("ARMED", "SAMPLING"):
            fail(409, "invalid_state")
        db.execute(
            "UPDATE sessions SET status='SAMPLING' WHERE id=?", (str(session_id),)
        )
        if row["status"] != "SAMPLING":
            log.info(
                "device=%s session=%s user=%s transition=SAMPLING",
                device_id,
                session_id,
                row["user_id"],
            )
        return {**device_session(row), "status": "SAMPLING"}


@router.post("/v1/sessions/{session_id}/cancel", response_model=SessionResponse)
def cancel(session_id: UUID, body: Empty, request: Request, subject: User):
    with session_transaction(request) as db:
        row = db.execute(
            "SELECT * FROM sessions WHERE id=? AND user_id=?",
            (str(session_id), subject),
        ).fetchone()
        if row is None:
            fail(404, "not_found")
        if row["status"] == "EXPIRED":
            fail(410, "session_expired")
        if row["status"] == "COMPLETE":
            fail(409, "invalid_state")
        if row["status"] != "CANCELLED":
            db.execute(
                "UPDATE sessions SET status='CANCELLED' WHERE id=?", (str(session_id),)
            )
            log.info(
                "device=%s session=%s user=%s transition=CANCELLED",
                row["device_id"],
                session_id,
                subject,
            )
        return {**session_response(row, db), "status": "CANCELLED"}
