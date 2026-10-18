from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Query, Request, Response
from pydantic import BaseModel, Field, StrictInt, field_validator

from .db import connect, transaction
from .errors import fail
from .models import Empty, ErrorEnvelope
from .sessions import User, instant

router = APIRouter(
    responses={
        413: {"model": ErrorEnvelope},
        429: {
            "model": ErrorEnvelope,
            "headers": {"Retry-After": {"schema": {"type": "integer", "minimum": 1}}},
        },
    }
)


class AppReadingReceipt(BaseModel):
    reading_id: str
    user_id: str
    value: float
    recorded_at: str
    duration_ms: int
    source: Literal["app_generated"]
    received_at: str


class AppReadingPage(BaseModel):
    items: list[AppReadingReceipt]
    limit: int
    offset: int
    has_more: bool


@router.get("/v1/me/app-readings", response_model=AppReadingPage)
def history(
    request: Request,
    subject: User,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    with connect(request.app.state.settings.db_path) as db:
        db.execute("PRAGMA query_only=ON")
        rows = db.execute(
            "SELECT * FROM app_readings WHERE user_id=? ORDER BY recorded_at DESC,reading_id DESC LIMIT ? OFFSET ?",
            (subject, limit + 1, min(offset, 2**63 - 1)),
        ).fetchall()
    return {
        "items": [dict(r) for r in rows[:limit]],
        "limit": limit,
        "offset": offset,
        "has_more": len(rows) > limit,
    }


class AppReadingSummary(BaseModel):
    user_id: str
    source: Literal["app_generated"]
    saved_readings: int
    latest_reading: AppReadingReceipt | None


@router.get("/v1/me/app-reading-summary", response_model=AppReadingSummary)
def summary(request: Request, subject: User):
    with connect(request.app.state.settings.db_path) as db:
        db.execute("PRAGMA query_only=ON")
        db.execute("BEGIN")
        count = db.execute(
            "SELECT COUNT(*) FROM app_readings WHERE user_id=?", (subject,)
        ).fetchone()[0]
        latest = db.execute(
            "SELECT * FROM app_readings WHERE user_id=? ORDER BY recorded_at DESC,reading_id DESC LIMIT 1",
            (subject,),
        ).fetchone()
        return {
            "user_id": subject,
            "source": "app_generated",
            "saved_readings": count,
            "latest_reading": dict(latest) if latest else None,
        }


class AppReadingPut(Empty):
    reading_id: UUID
    value: Annotated[float, Field(ge=0, le=1, allow_inf_nan=False)]
    recorded_at: datetime
    duration_ms: Annotated[StrictInt, Field(ge=1, le=60000)]
    source: Literal["app_generated"]

    @field_validator("value", mode="before")
    @classmethod
    def strict_number(cls, value):
        if type(value) not in (int, float):
            raise ValueError("Expected JSON number")
        return value

    @field_validator("recorded_at", mode="before")
    @classmethod
    def aware_iso_string(cls, value):
        if not isinstance(value, str):
            raise ValueError("Expected ISO8601 string")
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            raise ValueError("Expected ISO8601 string") from None
        if parsed.tzinfo is None or parsed.utcoffset() is None:
            raise ValueError("Expected timezone")
        try:
            return parsed.astimezone(UTC)
        except (ValueError, OverflowError):
            raise ValueError("Expected representable UTC date") from None


@router.post(
    "/v1/me/app-readings",
    response_model=AppReadingReceipt,
    status_code=201,
    responses={
        200: {"model": AppReadingReceipt, "description": "Identical canonical replay"}
    },
)
def save(body: AppReadingPut, request: Request, response: Response, subject: User):
    with transaction(request.app.state.settings.db_path) as db:
        row = db.execute(
            "SELECT * FROM app_readings WHERE reading_id=?", (str(body.reading_id),)
        ).fetchone()
        if row is not None:
            if row["user_id"] != subject:
                fail(404, "not_found")
            if (
                row["value"],
                row["recorded_at"],
                row["duration_ms"],
                row["source"],
            ) != (
                body.value,
                body.recorded_at.isoformat(),
                body.duration_ms,
                body.source,
            ):
                fail(409, "idempotency_conflict")
            response.status_code = 200
            return dict(row)
        now = instant(request)
        stamp = now.timestamp()
        window = db.execute(
            "SELECT * FROM app_reading_save_windows WHERE user_id=?", (subject,)
        ).fetchone()
        if window is not None and stamp < window["window_started"] + 60:
            if window["accepted"] >= 60:
                import math

                from fastapi import HTTPException

                raise HTTPException(
                    429,
                    "rate_limited",
                    headers={
                        "Retry-After": str(
                            max(1, math.ceil(window["window_started"] + 60 - stamp))
                        )
                    },
                )
            db.execute(
                "UPDATE app_reading_save_windows SET accepted=accepted+1 WHERE user_id=?",
                (subject,),
            )
        else:
            db.execute(
                "INSERT INTO app_reading_save_windows VALUES (?,?,1) ON CONFLICT(user_id) DO UPDATE SET window_started=excluded.window_started,accepted=1",
                (subject, stamp),
            )
        db.execute(
            "INSERT INTO app_readings VALUES (?,?,?,?,?,?,?)",
            (
                str(body.reading_id),
                subject,
                body.value,
                body.recorded_at.isoformat(),
                body.duration_ms,
                body.source,
                now.isoformat(),
            ),
        )
        return dict(
            db.execute(
                "SELECT * FROM app_readings WHERE reading_id=?", (str(body.reading_id),)
            ).fetchone()
        )
