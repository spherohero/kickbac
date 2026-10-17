from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    StrictInt,
    field_validator,
)


class Empty(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ErrorDetail(BaseModel):
    code: str
    message: str


class ErrorEnvelope(BaseModel):
    error: ErrorDetail


class MeResponse(BaseModel):
    user_id: str


class ResolveResponse(BaseModel):
    device_id: str


class DeviceResponse(BaseModel):
    id: str
    state: Literal["AVAILABLE", "ARMED", "SAMPLING"]
    online: bool
    last_seen_at: str | None


class RawReading(Empty):
    sensor: Literal["mq3"]
    value: Annotated[StrictInt, Field(ge=0, le=4095)]
    unit: Literal["adc_counts"]


class MeasurementUpload(Empty):
    measurement_id: UUID
    session_id: UUID
    raw: RawReading
    breath_duration_ms: Annotated[StrictInt, Field(ge=1, le=60000)]
    source: Literal["device", "simulator"]
    measured_at: AwareDatetime | None = None

    @field_validator("measured_at", mode="before")
    @classmethod
    def iso_string_only(cls, value):
        if value is not None and not isinstance(value, str):
            raise ValueError("Expected timezone-aware ISO timestamp")
        if value is not None:
            datetime.fromisoformat(value.replace("Z", "+00:00"))
        return value

    @field_validator("measured_at")
    @classmethod
    def normalize_time(cls, value):
        return value.astimezone(UTC) if value is not None else None


class MeasurementResponse(BaseModel):
    id: str
    session_id: str
    device_id: str
    raw: RawReading
    breath_duration_ms: int
    source: Literal["device", "simulator"]
    measured_at: str | None
    received_at: str
    estimated_bac_percent: None = None


class HistoryResponse(BaseModel):
    items: list[MeasurementResponse]
    limit: int
    offset: int
    has_more: bool


class SessionResponse(BaseModel):
    id: str
    device_id: str
    user_id: str
    status: Literal["ARMED", "SAMPLING", "COMPLETE", "CANCELLED", "EXPIRED"]
    created_at: str
    expires_at: str
    completed_at: str | None
    measurement: MeasurementResponse | None


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
