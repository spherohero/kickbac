import json
import math
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Query, Request, Response
from pydantic import BaseModel, Field, StrictInt, StrictStr, field_validator

from .db import connect, transaction
from .errors import fail
from .models import Empty, ErrorEnvelope
from .sessions import User, instant

PRIVATE_HEADERS = {"Cache-Control": {"schema": {"type": "string", "const": "no-store"}}}
router = APIRouter(
    responses={
        200: {"headers": PRIVATE_HEADERS},
        413: {
            "model": ErrorEnvelope,
            "description": "Request exceeds 32768 bytes or canonical data exceeds 4096 UTF-8 bytes.",
        },
    }
)

GameID = Annotated[StrictStr, Field(pattern=r"^[a-z][a-z0-9_-]{0,63}$")]
Outcome = Literal["win", "loss", "draw", "completed"]


def canonical_data(data):
    return json.dumps(
        data, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False
    )


def validate_data(data):
    """Bound the JSON tree before serialization; root counts as node at depth 0."""
    if type(data) is not dict:
        raise ValueError("Expected JSON object")
    nodes = 0

    def visit(value, depth):
        nonlocal nodes
        nodes += 1
        if nodes > 128 or depth > 4:
            raise ValueError("JSON tree exceeds limits")
        if type(value) is dict:
            for key, child in value.items():
                if type(key) is not str or not 1 <= len(key) <= 64:
                    raise ValueError("Invalid object key")
                key.encode("utf-8")
                visit(child, depth + 1)
        elif type(value) is list:
            if len(value) > 64:
                raise ValueError("JSON list exceeds limit")
            for child in value:
                visit(child, depth + 1)
        elif type(value) is str:
            if len(value) > 512:
                raise ValueError("JSON string exceeds limit")
            value.encode("utf-8")
        elif type(value) in (int, float):
            if abs(value) > 1e12 or not math.isfinite(value):
                raise ValueError("Invalid JSON number")
        elif value is not None and type(value) is not bool:
            raise ValueError("Expected JSON value")

    visit(data, 0)
    if len(canonical_data(data).encode("utf-8")) > 4096:
        fail(413, "payload_too_large")
    return data


class GameResultPut(Empty):
    result_id: UUID
    game_id: GameID
    score: Annotated[StrictInt, Field(ge=0, le=1000000)]
    outcome: Outcome
    data: Annotated[
        dict,
        Field(
            description=(
                "Strict JSON object, canonical sorted-key compact ensure_ascii=False serialization <=4096 UTF-8 bytes; "
                "<=128 value nodes including root (depth 0), maximum depth 4; "
                "object keys 1..64 codepoints, lists <=64 items, strings <=512 codepoints; "
                "finite numbers with absolute value <=1e12. Invalid tree: 422; encoded size overflow: 413."
            )
        ),
    ]

    @field_validator("data", mode="before")
    @classmethod
    def bounded_json(cls, value):
        return validate_data(value)


class GameResultResponse(BaseModel):
    result_id: str
    user_id: str
    game_id: str
    score: int
    outcome: Outcome
    data: dict
    awarded_points: Literal[10]
    scoring_policy: Literal["completion_v1"]
    source: Literal["client_reported"]
    created_at: str


def result_response(row):
    return {**dict(row), "data": json.loads(row["data"])}


@router.post(
    "/v1/me/game-results",
    response_model=GameResultResponse,
    status_code=201,
    responses={
        200: {
            "model": GameResultResponse,
            "description": "Identical replay",
            "headers": PRIVATE_HEADERS,
        },
        201: {"headers": PRIVATE_HEADERS},
    },
)
def store_result(
    body: GameResultPut, request: Request, response: Response, subject: User
):
    """Store a client-reported completed game, owned only by the validated subject.

    Server awards 10 participation points per unique UUID under completion_v1,
    independent of score or outcome. This is not verified gameplay or anti-cheat.
    Every field is required; extra owner/points/phone fields are rejected.
    Identical canonical replay returns the original result/timestamp (200).
    Changed accepted fields return 409; another owner's UUID returns 404.
    Body is bounded to 32768 bytes, even when Content-Length is missing/false.
    No profile, reading history, device, session, or mutable points total is changed.
    """
    data = canonical_data(body.data)
    with transaction(request.app.state.settings.db_path) as db:
        row = db.execute(
            "SELECT * FROM game_results WHERE result_id=?", (str(body.result_id),)
        ).fetchone()
        if row is not None:
            if row["user_id"] != subject:
                fail(404, "not_found")
            if (row["game_id"], row["score"], row["outcome"], row["data"]) != (
                body.game_id,
                body.score,
                body.outcome,
                data,
            ):
                fail(409, "idempotency_conflict")
            response.status_code = 200
        else:
            db.execute(
                "INSERT INTO game_results VALUES (?,?,?,?,?,?,10,'completion_v1','client_reported',?)",
                (
                    str(body.result_id),
                    subject,
                    body.game_id,
                    body.score,
                    body.outcome,
                    data,
                    instant(request).isoformat(),
                ),
            )
            row = db.execute(
                "SELECT * FROM game_results WHERE result_id=?", (str(body.result_id),)
            ).fetchone()
        return result_response(row)


class GameStats(BaseModel):
    game_id: str
    total_points: int
    games_played: int
    wins: int
    best_score: int


class GameHistoryResponse(BaseModel):
    items: list[GameResultResponse]
    limit: int
    offset: int
    has_more: bool


@router.get("/v1/me/game-results", response_model=GameHistoryResponse)
def history(
    request: Request,
    subject: User,
    game_id: GameID | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    """Private read-only ledger, ordered by created_at DESC, result_id DESC."""
    with connect(request.app.state.settings.db_path) as db:
        db.execute("PRAGMA query_only=ON")
        where = "user_id=?"
        args = [subject]
        if game_id is not None:
            where += " AND game_id=?"
            args.append(game_id)
        rows = db.execute(
            "SELECT * FROM game_results WHERE "
            + where
            + " ORDER BY created_at DESC,result_id DESC LIMIT ? OFFSET ?",
            (*args, limit + 1, min(offset, 2**63 - 1)),
        ).fetchall()
    return {
        "items": [result_response(row) for row in rows[:limit]],
        "limit": limit,
        "offset": offset,
        "has_more": len(rows) > limit,
    }


class StatsResponse(BaseModel):
    user_id: str
    total_points: int
    games_played: int
    wins: int
    per_game: list[GameStats]


@router.get("/v1/me/stats", response_model=StatsResponse)
def stats(request: Request, subject: User):
    """Read-only points/counts derived from the immutable owner ledger.

    Unplayed users receive zero totals and an empty per_game array. Per-game
    aggregates are ordered by game_id ASC; best_score is MAX of raw score.
    No parties count, public leaderboard or verified gameplay claims.
    """
    with connect(request.app.state.settings.db_path) as db:
        db.execute("PRAGMA query_only=ON")
        rows = db.execute(
            "SELECT game_id,SUM(awarded_points) AS total_points,COUNT(*) AS games_played,"
            "SUM(outcome='win') AS wins,MAX(score) AS best_score FROM game_results "
            "WHERE user_id=? GROUP BY game_id ORDER BY game_id ASC",
            (subject,),
        ).fetchall()
    return {
        "user_id": subject,
        "total_points": sum(row["total_points"] for row in rows),
        "games_played": sum(row["games_played"] for row in rows),
        "wins": sum(row["wins"] for row in rows),
        "per_game": [dict(row) for row in rows],
    }
