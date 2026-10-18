"""Private party game instances and immutable completion context."""

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Query, Request, Response
from pydantic import BaseModel, Field, StrictInt

from .db import connect, transaction
from .errors import fail
from .games import (
    GameID,
    GameResultPut,
    GameResultResponse,
    canonical_data,
    result_response,
)
from .models import Empty, ErrorEnvelope, MeasurementResponse
from .sessions import User, instant, measurement_response

router = APIRouter()


class HistoryParty(BaseModel):
    party_id: str
    name: str
    created_at: str


class RichGameResult(GameResultResponse):
    party: HistoryParty | None
    game_instance_id: str | None
    placement: int | None
    measurement: MeasurementResponse | None


class RichGameHistory(BaseModel):
    items: list[RichGameResult]
    limit: int
    offset: int
    has_more: bool


@router.get("/v1/me/game-history", response_model=RichGameHistory)
def rich_history(
    request: Request,
    subject: User,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    with connect(request.app.state.settings.db_path) as db:
        db.execute("PRAGMA query_only=ON")
        rows = db.execute(
            "SELECT r.*,c.game_instance_id,c.placement,c.measurement_id,p.party_id,p.name AS party_name,p.created_at AS party_created_at FROM game_results r LEFT JOIN party_result_context c ON c.result_id=r.result_id AND c.user_id=r.user_id LEFT JOIN party_games g ON g.game_instance_id=c.game_instance_id LEFT JOIN parties p ON p.party_id=g.party_id WHERE r.user_id=? ORDER BY r.created_at DESC,r.result_id DESC LIMIT ? OFFSET ?",
            (subject, limit + 1, min(offset, 2**63 - 1)),
        ).fetchall()
        items = []
        for row in rows[:limit]:
            measurement = db.execute(
                "SELECT * FROM measurements WHERE id=? AND user_id=?",
                (row["measurement_id"], subject),
            ).fetchone()
            items.append(
                {
                    **result_response(row),
                    "party": {
                        "party_id": row["party_id"],
                        "name": row["party_name"],
                        "created_at": row["party_created_at"],
                    }
                    if row["party_id"]
                    else None,
                    "measurement": measurement_response(measurement)
                    if measurement
                    else None,
                }
            )
    return {
        "items": items,
        "limit": limit,
        "offset": offset,
        "has_more": len(rows) > limit,
    }


class PartyResultPut(GameResultPut):
    measurement_id: UUID | None = None
    placement: Annotated[StrictInt, Field(ge=1, le=10000)] | None = None


@router.post(
    "/v1/party-games/{game_instance_id}/results",
    response_model=GameResultResponse,
    status_code=201,
    responses={
        200: {"model": GameResultResponse, "description": "Identical accepted retry"},
        413: {
            "model": ErrorEnvelope,
            "description": "Request or canonical data exceeds byte limit",
        },
    },
)
def store_party_result(
    game_instance_id: UUID,
    body: PartyResultPut,
    request: Request,
    response: Response,
    subject: User,
):
    with transaction(request.app.state.settings.db_path) as db:
        game = game_row(db, str(game_instance_id))
        row = db.execute(
            "SELECT * FROM game_results WHERE result_id=?", (str(body.result_id),)
        ).fetchone()
        if row:
            if row["user_id"] != subject:
                fail(404, "not_found")
            context = db.execute(
                "SELECT * FROM party_result_context WHERE result_id=? AND user_id=?",
                (str(body.result_id), subject),
            ).fetchone()
            # Historical membership is enough for conflict checks, not new writes.
            if (
                not context or context["game_instance_id"] != str(game_instance_id)
            ) and not db.execute(
                "SELECT 1 FROM party_members WHERE party_id=? AND user_id=?",
                (game["party_id"], subject),
            ).fetchone():
                fail(404, "not_found")
            accepted = (row["game_id"], row["score"], row["outcome"], row["data"])
            submitted = (
                body.game_id,
                body.score,
                body.outcome,
                canonical_data(body.data),
            )
            link = str(body.measurement_id) if body.measurement_id else None
            if (
                not context
                or accepted != submitted
                or (
                    context["game_instance_id"],
                    context["measurement_id"],
                    context["placement"],
                )
                != (str(game_instance_id), link, body.placement)
            ):
                fail(409, "idempotency_conflict")
            response.status_code = 200
            return result_response(row)
        party = member_party(db, game["party_id"], subject)
        if game["state"] != "OPEN" or party["state"] != "OPEN":
            fail(409, "invalid_state")
        if game["game_id"] != body.game_id:
            fail(422, "validation_error")
        if db.execute(
            "SELECT 1 FROM party_result_context WHERE game_instance_id=? AND user_id=?",
            (str(game_instance_id), subject),
        ).fetchone():
            fail(409, "already_completed")
        if body.measurement_id is not None:
            measurement = db.execute(
                "SELECT m.*,s.created_at AS session_created_at FROM measurements m JOIN sessions s ON s.id=m.session_id AND s.user_id=m.user_id WHERE m.id=? AND m.user_id=?",
                (str(body.measurement_id), subject),
            ).fetchone()
            if measurement is None:
                fail(404, "not_found")
            check_in = db.execute(
                "SELECT party_id,game_instance_id FROM party_check_ins WHERE session_id=?",
                (measurement["session_id"],),
            ).fetchone()
            if check_in is not None and (
                check_in["party_id"],
                check_in["game_instance_id"],
            ) != (game["party_id"], str(game_instance_id)):
                fail(422, "validation_error")
            if db.execute(
                "SELECT 1 FROM party_result_context WHERE measurement_id=?",
                (str(body.measurement_id),),
            ).fetchone():
                fail(409, "idempotency_conflict")
            if (
                game["device_id"] is None
                or measurement["device_id"] != game["device_id"]
                or datetime.fromisoformat(measurement["session_created_at"])
                < datetime.fromisoformat(game["created_at"])
                or datetime.fromisoformat(measurement["received_at"]) > instant(request)
            ):
                fail(422, "validation_error")
        db.execute(
            "INSERT INTO game_results (result_id,user_id,game_id,score,outcome,data,awarded_points,scoring_policy,source,created_at) VALUES (?,?,?,?,?,?,10,'completion_v1','client_reported',?)",
            (
                str(body.result_id),
                subject,
                body.game_id,
                body.score,
                body.outcome,
                canonical_data(body.data),
                instant(request).isoformat(),
            ),
        )
        db.execute(
            "INSERT INTO party_result_context (result_id,game_instance_id,user_id,measurement_id,placement) VALUES (?,?,?,?,?)",
            (
                str(body.result_id),
                str(game_instance_id),
                subject,
                str(body.measurement_id) if body.measurement_id else None,
                body.placement,
            ),
        )
        return result_response(
            db.execute(
                "SELECT * FROM game_results WHERE result_id=?", (str(body.result_id),)
            ).fetchone()
        )


def host_party(db, party_id, subject):
    row = db.execute(
        "SELECT * FROM parties WHERE party_id=? AND host_user_id=?", (party_id, subject)
    ).fetchone()
    if row is None:
        fail(404, "not_found")
    return row


def game_row(db, game_instance_id):
    row = db.execute(
        "SELECT * FROM party_games WHERE game_instance_id=?", (game_instance_id,)
    ).fetchone()
    if row is None:
        fail(404, "not_found")
    return row


def member_party(db, party_id, subject):
    row = db.execute(
        "SELECT p.* FROM parties p JOIN party_members m ON m.party_id=p.party_id WHERE p.party_id=? AND m.user_id=? AND m.left_at IS NULL",
        (party_id, subject),
    ).fetchone()
    if row is None:
        fail(404, "not_found")
    return row


class GameCreate(Empty):
    game_instance_id: UUID
    game_id: GameID


class PartyGameResponse(BaseModel):
    game_instance_id: str
    party_id: str
    game_id: str
    created_at: str
    state: Literal["OPEN", "CLOSED"]
    closed_at: str | None
    device_id: str | None


class PartyGamesResponse(BaseModel):
    items: list[PartyGameResponse]
    limit: int
    offset: int
    has_more: bool


@router.get("/v1/parties/{party_id}/games", response_model=PartyGamesResponse)
def list_games(
    party_id: UUID,
    request: Request,
    subject: User,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    with connect(request.app.state.settings.db_path) as db:
        db.execute("PRAGMA query_only=ON")
        member_party(db, str(party_id), subject)
        rows = db.execute(
            "SELECT * FROM party_games WHERE party_id=? ORDER BY created_at DESC,game_instance_id DESC LIMIT ? OFFSET ?",
            (str(party_id), limit + 1, min(offset, 2**63 - 1)),
        ).fetchall()
    return {
        "items": [dict(row) for row in rows[:limit]],
        "limit": limit,
        "offset": offset,
        "has_more": len(rows) > limit,
    }


@router.post(
    "/v1/parties/{party_id}/games",
    response_model=PartyGameResponse,
    status_code=201,
    responses={
        200: {"model": PartyGameResponse, "description": "Identical accepted retry"},
        413: {"model": ErrorEnvelope, "description": "Request exceeds 32768 bytes"},
    },
)
def create_game(
    party_id: UUID,
    body: GameCreate,
    request: Request,
    response: Response,
    subject: User,
):
    with transaction(request.app.state.settings.db_path) as db:
        party = host_party(db, str(party_id), subject)
        row = db.execute(
            "SELECT * FROM party_games WHERE game_instance_id=?",
            (str(body.game_instance_id),),
        ).fetchone()
        if row:
            if row["party_id"] != str(party_id):
                fail(404, "not_found")
            if row["game_id"] != body.game_id:
                fail(409, "idempotency_conflict")
            response.status_code = 200
            return dict(row)
        if (
            party["state"] != "OPEN"
            or db.execute(
                "SELECT 1 FROM party_games WHERE party_id=? AND state='OPEN'",
                (str(party_id),),
            ).fetchone()
        ):
            fail(409, "invalid_state")
        device = db.execute(
            "SELECT device_id FROM party_devices WHERE party_id=?", (str(party_id),)
        ).fetchone()
        db.execute(
            "INSERT INTO party_games VALUES (?,?,?,?,?,'OPEN',NULL)",
            (
                str(body.game_instance_id),
                str(party_id),
                body.game_id,
                device[0] if device else None,
                instant(request).isoformat(),
            ),
        )
        return dict(
            db.execute(
                "SELECT * FROM party_games WHERE game_instance_id=?",
                (str(body.game_instance_id),),
            ).fetchone()
        )


@router.post(
    "/v1/party-games/{game_instance_id}/close", response_model=PartyGameResponse
)
def close_game(game_instance_id: UUID, body: Empty, request: Request, subject: User):
    with transaction(request.app.state.settings.db_path) as db:
        row = game_row(db, str(game_instance_id))
        host_party(db, row["party_id"], subject)
        if row["state"] == "OPEN":
            db.execute(
                "UPDATE party_games SET state='CLOSED',closed_at=? WHERE game_instance_id=?",
                (instant(request).isoformat(), str(game_instance_id)),
            )
        return dict(game_row(db, str(game_instance_id)))
