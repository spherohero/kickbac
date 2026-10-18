import math
import re
import secrets
import unicodedata
from datetime import datetime, timedelta
from typing import Annotated, Any, Literal
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, Query, Request, Response
from pydantic import BaseModel, Field, StrictStr, field_validator, model_validator

from .db import connect, transaction
from .errors import fail
from .models import Empty, ErrorEnvelope
from .sessions import User, instant

router = APIRouter(
    responses={
        413: {"model": ErrorEnvelope, "description": "Request exceeds 32768 bytes."}
    }
)
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


class PartyCreate(Empty):
    party_id: UUID
    name: StrictStr

    @field_validator("name")
    @classmethod
    def valid_name(cls, value):
        if any(unicodedata.category(c) in {"Cc", "Cs"} for c in value):
            raise ValueError("Invalid party name")
        value = value.strip()
        if not 1 <= len(value) <= 80:
            raise ValueError("Invalid party name")
        return value


class PartyResponse(BaseModel):
    party_id: str
    name: str
    created_at: str
    state: Literal["OPEN", "CLOSED"]
    closed_at: str | None
    role: Literal["host", "member"]
    member_count: int
    device_id: str | None
    join_code: str | None


class PartyList(BaseModel):
    items: list[PartyResponse]
    limit: int
    offset: int
    has_more: bool


class ActivePartyConflictDetail(BaseModel):
    code: Literal["active_party_conflict"]
    message: str
    current_parties: list[PartyResponse]
    has_more: bool


class ActivePartyConflict(BaseModel):
    error: ActivePartyConflictDetail


ACTIVE_CONFLICT: dict[int | str, dict[str, Any]] = {
    409: {"model": ActivePartyConflict | ErrorEnvelope}
}


def current_rows(db, subject):
    return db.execute(
        PARTY_SELECT
        + " WHERE p.state='OPEN' AND (p.host_user_id=? OR EXISTS (SELECT 1 FROM party_members m WHERE m.party_id=p.party_id AND m.user_id=? AND m.left_at IS NULL)) ORDER BY p.created_at DESC,p.party_id DESC LIMIT 101",
        (subject, subject),
    ).fetchall()


def check_current(db, subject, intended=None):
    rows = current_rows(db, subject)
    if rows and (len(rows) != 1 or rows[0]["party_id"] != intended):
        exc = HTTPException(409, "active_party_conflict")
        exc.authorized_party_context = {
            "current_parties": [party_response(r, subject) for r in rows[:100]],
            "has_more": len(rows) > 100,
        }
        raise exc
    return rows


PARTY_SELECT = """SELECT p.*,
 (SELECT COUNT(*) FROM party_members m WHERE m.party_id=p.party_id AND m.left_at IS NULL) AS member_count,
 (SELECT device_id FROM party_devices d WHERE d.party_id=p.party_id) AS device_id
 FROM parties p"""


def party_row(db, party_id):
    row = db.execute(PARTY_SELECT + " WHERE p.party_id=?", (str(party_id),)).fetchone()
    if row is None:
        fail(404, "not_found")
    return row


def require_member(db, party_id, subject):
    if (
        db.execute(
            "SELECT 1 FROM party_members WHERE party_id=? AND user_id=? AND left_at IS NULL",
            (str(party_id), subject),
        ).fetchone()
        is None
    ):
        fail(404, "not_found")


def party_response(row, subject):
    host = row["host_user_id"] == subject
    return {
        key: row[key]
        for key in (
            "party_id",
            "name",
            "created_at",
            "state",
            "closed_at",
            "member_count",
            "device_id",
        )
    } | {
        "role": "host" if host else "member",
        "join_code": row["join_code"] if host and row["state"] == "OPEN" else None,
    }


@router.post(
    "/v1/parties",
    status_code=201,
    response_model=PartyResponse,
    responses={200: {"model": PartyResponse}, **ACTIVE_CONFLICT},
)
def create_party(
    body: PartyCreate, request: Request, response: Response, subject: User
):
    with transaction(request.app.state.settings.db_path) as db:
        existing = db.execute(
            "SELECT * FROM parties WHERE party_id=?", (str(body.party_id),)
        ).fetchone()
        if existing is not None:
            if existing["host_user_id"] != subject:
                fail(404, "not_found")
            if existing["name"] != body.name:
                fail(409, "idempotency_conflict")
            response.status_code = 200
            return party_response(party_row(db, body.party_id), subject)
        check_current(db, subject)
        now = instant(request).isoformat()
        while True:
            code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(8))
            if (
                db.execute(
                    "SELECT 1 FROM parties WHERE join_code=?", (code,)
                ).fetchone()
                is None
            ):
                break
        db.execute(
            "INSERT INTO parties VALUES (?,?,?,?,?,'OPEN',NULL)",
            (str(body.party_id), subject, body.name, code, now),
        )
        db.execute(
            "INSERT INTO party_members VALUES (?,?,?,NULL)",
            (str(body.party_id), subject, now),
        )
        return party_response(party_row(db, body.party_id), subject)


class PartyJoin(Empty):
    join_code: StrictStr | None = None
    device_id: StrictStr | None = None

    @model_validator(mode="after")
    def selector(self):
        if self.model_fields_set not in ({"join_code"}, {"device_id"}):
            raise ValueError("Exactly one selector required")
        if "join_code" in self.model_fields_set:
            if self.join_code is None:
                raise ValueError("Code required")
            self.join_code = self.join_code.strip().upper()
            if len(self.join_code) != 8 or any(
                c not in CODE_ALPHABET for c in self.join_code
            ):
                raise ValueError("Invalid code")
        elif self.device_id is None or not re.fullmatch(
            r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}", self.device_id
        ):
            raise ValueError("Invalid device ID")
        return self


@router.post(
    "/v1/parties/join",
    response_model=PartyResponse,
    responses={
        **ACTIVE_CONFLICT,
        429: {
            "model": ErrorEnvelope,
            "headers": {
                "Retry-After": {
                    "schema": {"type": "integer", "minimum": 1},
                    "description": "Seconds until this subject's fixed join window resets.",
                }
            },
        },
    },
)
def join_party(body: PartyJoin, request: Request, subject: User):
    # Deliberately committed before lookup so rejected invitations consume attempts.
    with transaction(request.app.state.settings.db_path) as db:
        now = instant(request)
        db.execute(
            "DELETE FROM party_join_attempts WHERE window_started<=?",
            ((now - timedelta(seconds=60)).isoformat(),),
        )
        attempt = db.execute(
            "SELECT * FROM party_join_attempts WHERE user_id=?", (subject,)
        ).fetchone()
        if attempt is not None and attempt["attempts"] >= 10:
            retry = max(
                1,
                math.ceil(
                    (
                        datetime.fromisoformat(attempt["window_started"])
                        + timedelta(seconds=60)
                        - now
                    ).total_seconds()
                ),
            )
            raise HTTPException(
                429, "rate_limited", headers={"Retry-After": str(retry)}
            )
        db.execute(
            "INSERT INTO party_join_attempts VALUES (?,?,1) ON CONFLICT(user_id) DO UPDATE SET attempts=attempts+1",
            (subject, now.isoformat()),
        )
    with transaction(request.app.state.settings.db_path) as db:
        if body.join_code is not None:
            row = db.execute(
                "SELECT party_id FROM parties WHERE join_code=? AND state='OPEN'",
                (body.join_code,),
            ).fetchone()
        else:
            row = db.execute(
                "SELECT p.party_id FROM parties p JOIN party_devices d ON d.party_id=p.party_id WHERE d.device_id=? AND p.state='OPEN'",
                (body.device_id,),
            ).fetchone()
        if row is None:
            fail(404, "not_found")
        party_id = row["party_id"]
        check_current(db, subject, party_id)
        db.execute(
            "INSERT INTO party_members VALUES (?,?,?,NULL) ON CONFLICT(party_id,user_id) DO UPDATE SET left_at=NULL",
            (party_id, subject, instant(request).isoformat()),
        )
        return party_response(party_row(db, party_id), subject)


@router.post("/v1/parties/{party_id}/leave", response_model=PartyResponse)
def leave_party(party_id: UUID, body: Empty, request: Request, subject: User):
    with transaction(request.app.state.settings.db_path) as db:
        row = party_row(db, party_id)
        if (
            db.execute(
                "SELECT 1 FROM party_members WHERE party_id=? AND user_id=?",
                (str(party_id), subject),
            ).fetchone()
            is None
        ):
            fail(404, "not_found")
        if row["host_user_id"] == subject:
            fail(409, "invalid_state")
        db.execute(
            "UPDATE party_members SET left_at=COALESCE(left_at,?) WHERE party_id=? AND user_id=?",
            (instant(request).isoformat(), str(party_id), subject),
        )
        return party_response(party_row(db, party_id), subject)


def require_idle(db, device_ids, now):
    for device_id in set(device_ids) - {None}:
        sessions = db.execute(
            "SELECT expires_at FROM sessions WHERE device_id=? AND status IN ('ARMED','SAMPLING')",
            (device_id,),
        ).fetchall()
        if any(
            datetime.fromisoformat(session["expires_at"]) > now for session in sessions
        ):
            fail(409, "device_busy")


class PartyDevice(Empty):
    device_id: Annotated[StrictStr, Field(pattern=r"^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$")]


class PartyResolve(PartyDevice):
    request_id: UUID
    name: StrictStr = "Party"

    valid_name = field_validator("name")(PartyCreate.valid_name.__func__)


class PartyResolveResponse(BaseModel):
    action: Literal["created", "joined"]
    party: PartyResponse


@router.post(
    "/v1/parties/resolve",
    status_code=201,
    response_model=PartyResolveResponse,
    responses={200: {"model": PartyResolveResponse}, **ACTIVE_CONFLICT},
)
def resolve_party(
    body: PartyResolve, request: Request, response: Response, subject: User
):
    with transaction(request.app.state.settings.db_path) as db:
        accepted = db.execute(
            "SELECT * FROM party_resolve_requests WHERE request_id=?",
            (str(body.request_id),),
        ).fetchone()
        if accepted is not None:
            if accepted["user_id"] != subject:
                fail(404, "not_found")
            if (accepted["device_id"], accepted["name"]) != (body.device_id, body.name):
                fail(409, "idempotency_conflict")
            response.status_code = 200
            return {
                "action": accepted["action"],
                "party": party_response(party_row(db, accepted["party_id"]), subject),
            }
        if (
            db.execute("SELECT 1 FROM devices WHERE id=?", (body.device_id,)).fetchone()
            is None
        ):
            fail(404, "not_found")
        assigned = db.execute(
            "SELECT p.party_id FROM parties p JOIN party_devices d ON d.party_id=p.party_id WHERE d.device_id=? AND p.state='OPEN'",
            (body.device_id,),
        ).fetchone()
        if assigned is not None:
            party_id = assigned["party_id"]
            check_current(db, subject, party_id)
            db.execute(
                "INSERT INTO party_members VALUES (?,?,?,NULL) ON CONFLICT(party_id,user_id) DO UPDATE SET left_at=NULL",
                (party_id, subject, instant(request).isoformat()),
            )
            db.execute(
                "INSERT INTO party_resolve_requests VALUES (?,?,?,?,?,?)",
                (
                    str(body.request_id),
                    subject,
                    body.device_id,
                    body.name,
                    party_id,
                    "joined",
                ),
            )
            response.status_code = 200
            return {
                "action": "joined",
                "party": party_response(party_row(db, party_id), subject),
            }
        check_current(db, subject)
        require_idle(db, [body.device_id], instant(request))
        party_id = str(uuid4())
        now = instant(request).isoformat()
        while True:
            code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(8))
            if (
                db.execute(
                    "SELECT 1 FROM parties WHERE join_code=?", (code,)
                ).fetchone()
                is None
            ):
                break
        db.execute(
            "INSERT INTO parties VALUES (?,?,?,?,?,'OPEN',NULL)",
            (party_id, subject, body.name, code, now),
        )
        db.execute(
            "INSERT INTO party_members VALUES (?,?,?,NULL)", (party_id, subject, now)
        )
        db.execute("INSERT INTO party_devices VALUES (?,?)", (party_id, body.device_id))
        db.execute(
            "INSERT INTO party_resolve_requests VALUES (?,?,?,?,?,?)",
            (
                str(body.request_id),
                subject,
                body.device_id,
                body.name,
                party_id,
                "created",
            ),
        )
        return {
            "action": "created",
            "party": party_response(party_row(db, party_id), subject),
        }


@router.put("/v1/parties/{party_id}/device", response_model=PartyResponse)
def assign_device(party_id: UUID, body: PartyDevice, request: Request, subject: User):
    with transaction(request.app.state.settings.db_path) as db:
        row = party_row(db, party_id)
        require_host(row, subject)
        if row["state"] != "OPEN":
            fail(409, "invalid_state")
        if (
            db.execute(
                "SELECT 1 FROM device_party_hosts h JOIN devices d ON d.id=h.device_id WHERE h.device_id=? AND h.user_id=?",
                (body.device_id, subject),
            ).fetchone()
            is None
        ):
            fail(404, "not_found")
        other = db.execute(
            "SELECT party_id FROM party_devices WHERE device_id=?", (body.device_id,)
        ).fetchone()
        if other is not None and other["party_id"] != str(party_id):
            fail(409, "device_assigned")
        if row["device_id"] != body.device_id:
            require_idle(db, [row["device_id"], body.device_id], instant(request))
        db.execute(
            "INSERT INTO party_devices VALUES (?,?) ON CONFLICT(party_id) DO UPDATE SET device_id=excluded.device_id",
            (str(party_id), body.device_id),
        )
        return party_response(party_row(db, party_id), subject)


@router.delete("/v1/parties/{party_id}/device", response_model=PartyResponse)
def remove_device(party_id: UUID, request: Request, subject: User):
    with transaction(request.app.state.settings.db_path) as db:
        row = party_row(db, party_id)
        require_host(row, subject)
        require_idle(db, [row["device_id"]], instant(request))
        db.execute("DELETE FROM party_devices WHERE party_id=?", (str(party_id),))
        return party_response(party_row(db, party_id), subject)


def require_host(row, subject):
    if row["host_user_id"] != subject:
        fail(404, "not_found")


@router.post("/v1/parties/{party_id}/close", response_model=PartyResponse)
def close_party(party_id: UUID, body: Empty, request: Request, subject: User):
    with transaction(request.app.state.settings.db_path) as db:
        row = party_row(db, party_id)
        require_host(row, subject)
        if row["state"] == "OPEN":
            require_idle(db, [row["device_id"]], instant(request))
            now = instant(request).isoformat()
            db.execute(
                "UPDATE parties SET state='CLOSED',closed_at=? WHERE party_id=?",
                (now, str(party_id)),
            )
            db.execute(
                "UPDATE party_games SET state='CLOSED',closed_at=? WHERE party_id=? AND state='OPEN'",
                (now, str(party_id)),
            )
            db.execute("DELETE FROM party_devices WHERE party_id=?", (str(party_id),))
        return party_response(party_row(db, party_id), subject)


@router.get("/v1/parties/{party_id}", response_model=PartyResponse)
def get_party(party_id: UUID, request: Request, subject: User):
    with connect(request.app.state.settings.db_path) as db:
        db.execute("PRAGMA query_only=ON")
        require_member(db, party_id, subject)
        return party_response(party_row(db, party_id), subject)


@router.get(
    "/v1/me/parties/current",
    response_model=PartyResponse | None,
    responses=ACTIVE_CONFLICT,
)
def current_party(request: Request, subject: User):
    with connect(request.app.state.settings.db_path) as db:
        db.execute("PRAGMA query_only=ON")
        db.execute("BEGIN")
        rows = current_rows(db, subject)
        if len(rows) > 1:
            check_current(db, subject)
        return party_response(rows[0], subject) if rows else None


@router.get("/v1/me/parties", response_model=PartyList)
def list_parties(
    request: Request,
    subject: User,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    with connect(request.app.state.settings.db_path) as db:
        db.execute("PRAGMA query_only=ON")
        rows = db.execute(
            PARTY_SELECT
            + " JOIN party_members own ON own.party_id=p.party_id WHERE own.user_id=? AND own.left_at IS NULL ORDER BY p.created_at DESC,p.party_id DESC LIMIT ? OFFSET ?",
            (subject, limit + 1, min(offset, 2**63 - 1)),
        ).fetchall()
        return {
            "items": [party_response(row, subject) for row in rows[:limit]],
            "limit": limit,
            "offset": offset,
            "has_more": len(rows) > limit,
        }
