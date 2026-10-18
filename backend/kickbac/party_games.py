"""Private party game instances and immutable completion context."""

from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Query, Request, Response

from .errors import fail
from pydantic import BaseModel

from .db import connect, transaction
from .games import GameID
from .models import Empty
from .sessions import User, instant

router = APIRouter()


def host_party(db, party_id, subject):
    row = db.execute("SELECT * FROM parties WHERE party_id=? AND host_user_id=?", (party_id, subject)).fetchone()
    if row is None:
        fail(404, 'not_found')
    return row


def game_row(db, game_instance_id):
    row = db.execute("SELECT * FROM party_games WHERE game_instance_id=?", (game_instance_id,)).fetchone()
    if row is None:
        fail(404, "not_found")
    return row


def member_party(db, party_id, subject):
    row = db.execute("SELECT p.* FROM parties p JOIN party_members m ON m.party_id=p.party_id WHERE p.party_id=? AND m.user_id=? AND m.left_at IS NULL", (party_id, subject)).fetchone()
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
def list_games(party_id: UUID, request: Request, subject: User,
               limit: Annotated[int, Query(ge=1, le=100)] = 50,
               offset: Annotated[int, Query(ge=0)] = 0):
    with connect(request.app.state.settings.db_path) as db:
        db.execute("PRAGMA query_only=ON")
        member_party(db, str(party_id), subject)
        rows = db.execute("SELECT * FROM party_games WHERE party_id=? ORDER BY created_at DESC,game_instance_id DESC LIMIT ? OFFSET ?", (str(party_id), limit+1, min(offset, 2**63-1))).fetchall()
    return {"items":[dict(row) for row in rows[:limit]],"limit":limit,"offset":offset,"has_more":len(rows)>limit}


@router.post("/v1/parties/{party_id}/games", response_model=PartyGameResponse, status_code=201)
def create_game(party_id: UUID, body: GameCreate, request: Request, response: Response, subject: User):
    with transaction(request.app.state.settings.db_path) as db:
        party = host_party(db, str(party_id), subject)
        row = db.execute("SELECT * FROM party_games WHERE game_instance_id=?", (str(body.game_instance_id),)).fetchone()
        if row:
            if row['party_id'] != str(party_id):
                fail(404, 'not_found')
            if row['game_id'] != body.game_id:
                fail(409, 'idempotency_conflict')
            response.status_code = 200
            return dict(row)
        if party['state'] != 'OPEN' or db.execute("SELECT 1 FROM party_games WHERE party_id=? AND state='OPEN'", (str(party_id),)).fetchone():
            fail(409, 'invalid_state')
        device = db.execute("SELECT device_id FROM party_devices WHERE party_id=?", (str(party_id),)).fetchone()
        db.execute("INSERT INTO party_games VALUES (?,?,?,?,?,'OPEN',NULL)",
                   (str(body.game_instance_id), str(party_id), body.game_id, device[0] if device else None, instant(request).isoformat()))
        return dict(db.execute("SELECT * FROM party_games WHERE game_instance_id=?", (str(body.game_instance_id),)).fetchone())

@router.post("/v1/party-games/{game_instance_id}/close", response_model=PartyGameResponse)
def close_game(game_instance_id: UUID, body: Empty, request: Request, subject: User):
    with transaction(request.app.state.settings.db_path) as db:
        row = game_row(db, str(game_instance_id))
        host_party(db, row["party_id"], subject)
        if row["state"] == "OPEN":
            db.execute("UPDATE party_games SET state='CLOSED',closed_at=? WHERE game_instance_id=?", (instant(request).isoformat(), str(game_instance_id)))
        return dict(game_row(db, str(game_instance_id)))



