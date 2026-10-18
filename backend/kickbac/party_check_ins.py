"""Atomic authenticated NFC check-ins; device wire protocol remains unchanged."""

from datetime import timedelta
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, Query, Request, Response
from pydantic import BaseModel, Field, StrictStr

from .db import connect
from .errors import fail
from .models import Empty, ErrorEnvelope, SessionResponse
from .sessions import User, session_response, session_transaction

router = APIRouter()


class CheckInPut(Empty):
    check_in_id: UUID
    device_id: Annotated[StrictStr, Field(pattern=r"^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$")]
    game_instance_id: UUID | None = None


class CheckInResponse(BaseModel):
    check_in_id: str
    party_id: str
    game_instance_id: str | None
    session: SessionResponse


def check_in_response(row, db):
    session = db.execute(
        "SELECT * FROM sessions WHERE id=?", (row["session_id"],)
    ).fetchone()
    return {k: row[k] for k in ("check_in_id", "party_id", "game_instance_id")} | {
        "session": session_response(session, db)
    }


class CheckInList(BaseModel):
    items: list[CheckInResponse]
    limit: int
    offset: int
    has_more: bool


@router.get("/v1/me/check-ins", response_model=CheckInList)
def check_in_history(
    request: Request,
    subject: User,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    with connect(request.app.state.settings.db_path) as db:
        db.execute("PRAGMA query_only=ON")
        db.execute("BEGIN")
        rows = db.execute(
            "SELECT c.* FROM party_check_ins c JOIN sessions s ON s.id=c.session_id AND s.user_id=c.user_id AND s.device_id=c.device_id WHERE c.user_id=? ORDER BY s.created_at DESC,c.check_in_id DESC LIMIT ? OFFSET ?",
            (subject, limit + 1, min(offset, 2**63 - 1)),
        ).fetchall()
        items = [check_in_response(row, db) for row in rows[:limit]]
    return {
        "items": items,
        "limit": limit,
        "offset": offset,
        "has_more": len(rows) > limit,
    }


@router.post(
    "/v1/parties/{party_id}/check-ins",
    status_code=201,
    response_model=CheckInResponse,
    responses={
        200: {
            "model": CheckInResponse,
            "description": "Exact accepted retry; current session state",
        },
        413: {"model": ErrorEnvelope, "description": "Request exceeds 32768 bytes"},
        422: {"model": ErrorEnvelope},
    },
)
def check_in(
    party_id: UUID,
    body: CheckInPut,
    request: Request,
    response: Response,
    subject: User,
):
    with session_transaction(request, with_now=True) as (db, now):
        game_id = str(body.game_instance_id) if body.game_instance_id else None
        existing = db.execute(
            "SELECT * FROM party_check_ins WHERE check_in_id=?",
            (str(body.check_in_id),),
        ).fetchone()
        if existing is not None:
            if existing["user_id"] != subject:
                fail(404, "not_found")
            if (
                existing["party_id"] != str(party_id)
                and not db.execute(
                    "SELECT 1 FROM party_members WHERE party_id=? AND user_id=?",
                    (str(party_id), subject),
                ).fetchone()
            ):
                fail(404, "not_found")
            if (
                existing["party_id"],
                existing["device_id"],
                existing["game_instance_id"],
            ) != (str(party_id), body.device_id, game_id):
                fail(409, "idempotency_conflict")
            response.status_code = 200
            return check_in_response(existing, db)
        from .party_games import member_party

        party = member_party(db, str(party_id), subject)
        if party["state"] != "OPEN":
            fail(409, "invalid_state")
        if not db.execute(
            "SELECT 1 FROM party_devices d JOIN devices u ON u.id=d.device_id WHERE d.party_id=? AND d.device_id=?",
            (str(party_id), body.device_id),
        ).fetchone():
            fail(404, "not_found")
        if game_id is not None:
            game = db.execute(
                "SELECT * FROM party_games WHERE game_instance_id=?", (game_id,)
            ).fetchone()
            if (
                game is None
                or game["party_id"] != str(party_id)
                or game["state"] != "OPEN"
                or game["device_id"] != body.device_id
            ):
                fail(409, "invalid_state")
        if db.execute(
            "SELECT 1 FROM sessions WHERE device_id=? AND status IN ('ARMED','SAMPLING')",
            (body.device_id,),
        ).fetchone():
            fail(409, "device_busy")
        session_id = str(uuid4())
        db.execute(
            "INSERT INTO sessions(id,device_id,user_id,status,created_at,expires_at) VALUES (?,?,?,'ARMED',?,?)",
            (
                session_id,
                body.device_id,
                subject,
                now.isoformat(),
                (now + timedelta(seconds=60)).isoformat(),
            ),
        )
        db.execute(
            "INSERT INTO party_check_ins VALUES (?,?,?,?,?,?)",
            (
                str(body.check_in_id),
                session_id,
                str(party_id),
                str(body.game_instance_id) if body.game_instance_id else None,
                subject,
                body.device_id,
            ),
        )
        return check_in_response(
            db.execute(
                "SELECT * FROM party_check_ins WHERE check_in_id=?",
                (str(body.check_in_id),),
            ).fetchone(),
            db,
        )
