from typing import Literal

from pydantic import BaseModel, ConfigDict


class Empty(BaseModel):
    model_config = ConfigDict(extra="forbid")


class DeviceResponse(BaseModel):
    id: str
    state: Literal["AVAILABLE", "ARMED", "SAMPLING"]
    online: bool
    last_seen_at: str | None


class SessionResponse(BaseModel):
    id: str
    device_id: str
    user_id: str
    status: Literal["ARMED", "SAMPLING", "COMPLETE", "CANCELLED", "EXPIRED"]
    created_at: str
    expires_at: str
    completed_at: str | None
    measurement: dict | None


class DeviceSession(BaseModel):
    id: str
    device_id: str
    status: Literal["ARMED", "SAMPLING"]
    expires_at: str


class DevicePoll(BaseModel):
    device_id: str
    active_session: DeviceSession | None


class HeartbeatResponse(BaseModel):
    device_id: str
    online: bool
    last_seen_at: str
