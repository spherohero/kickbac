import unicodedata
from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    StrictInt,
    StrictStr,
    field_validator,
    model_serializer,
    model_validator,
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


MAX_PICTURE_BYTES = 512 * 1024
MAX_PICTURE_BASE64 = 4 * ((MAX_PICTURE_BYTES + 2) // 3)


class ProfilePicture(Empty):
    content_type: Literal["image/jpeg", "image/png"]
    data_base64: Annotated[StrictStr, Field(max_length=MAX_PICTURE_BASE64)]

    @field_validator("data_base64", mode="before")
    @classmethod
    def bound_encoded_length(cls, value):
        if isinstance(value, str) and len(value) > MAX_PICTURE_BASE64:
            from .errors import fail

            fail(413, "payload_too_large")
        return value


class ProfilePictureResponse(BaseModel):
    content_type: Literal["image/jpeg"]
    data_base64: str


class ProfileResponse(BaseModel):
    user_id: str
    display_name: str | None
    profile_picture: ProfilePictureResponse | None
    created_at: str | None
    updated_at: str | None


class ProfilePut(Empty):
    display_name: Annotated[StrictStr, Field(min_length=1, max_length=80)]
    profile_picture: ProfilePicture | None

    @field_validator("display_name", mode="before")
    @classmethod
    def trim_name(cls, value):
        if not isinstance(value, str):
            raise ValueError("Expected display name")
        if any(unicodedata.category(char) in ("Cc", "Cs") for char in value):
            raise ValueError("Invalid display name")
        return value.strip()


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


class AcquisitionMetadata(BaseModel):
    acquisition_method: Literal["manual_timed"] | None = None
    sample_duration_ms: Annotated[StrictInt, Field(ge=1, le=60000)] | None = None

    @model_serializer(mode="wrap")
    def serialize_acquisition(self, handler):
        result = handler(self)
        if self.acquisition_method is None and self.sample_duration_ms is None:
            result.pop("acquisition_method", None)
            result.pop("sample_duration_ms", None)
        return result


class MeasurementUpload(AcquisitionMetadata, Empty):
    measurement_id: UUID
    session_id: UUID
    raw: RawReading
    breath_duration_ms: Annotated[StrictInt, Field(ge=1, le=60000)] | None
    source: Literal["device", "simulator"]
    measured_at: AwareDatetime | None = None

    @model_validator(mode="after")
    def require_manual_metadata_for_null_duration(self):
        if self.breath_duration_ms is None and (
            self.acquisition_method != "manual_timed" or self.sample_duration_ms is None
        ):
            raise ValueError(
                "Null breath duration requires manual acquisition metadata"
            )
        if self.breath_duration_ms is not None:
            metadata_fields = {"acquisition_method", "sample_duration_ms"}
            supplied = self.model_fields_set & metadata_fields
            if (
                self.acquisition_method is not None
                or self.sample_duration_ms is not None
                or supplied not in (set(), metadata_fields)
            ):
                raise ValueError(
                    "Legacy duration requires omitted or paired-null metadata"
                )
        return self

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


class MeasurementResponse(AcquisitionMetadata):
    id: str
    session_id: str
    device_id: str
    raw: RawReading
    breath_duration_ms: int | None
    source: Literal["device", "simulator"]
    measured_at: str | None
    received_at: str
    estimated_bac_percent: None = None


class ReadingSummaryResponse(BaseModel):
    user_id: str
    saved_readings: int
    latest_measurement: MeasurementResponse | None


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
