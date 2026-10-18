import base64
import binascii
import warnings
import zlib
from io import BytesIO

from fastapi import APIRouter, Request, Response
from PIL import Image, ImageOps

from .db import connect, transaction
from .errors import fail
from .models import MAX_PICTURE_BYTES, ErrorEnvelope, ProfilePut, ProfileResponse
from .sessions import User, instant

router = APIRouter(
    responses={
        413: {
            "model": ErrorEnvelope,
            "description": "Request exceeds 1 MiB or decoded picture exceeds 512 KiB.",
        },
        200: {
            "headers": {
                "Cache-Control": {"schema": {"type": "string", "const": "no-store"}}
            }
        },
    }
)


def verify_png_chunks(raw):
    """Require complete chunk framing/CRCs through IEND, which Pillow may skip."""
    offset = 8  # Caller has checked the PNG signature.
    while offset + 12 <= len(raw):
        size = int.from_bytes(raw[offset : offset + 4], "big")
        end = offset + 12 + size
        if end > len(raw):
            fail(422, "validation_error")
        checksum = int.from_bytes(raw[end - 4 : end], "big")
        if zlib.crc32(raw[offset + 4 : end - 4]) != checksum:
            fail(422, "validation_error")
        if raw[offset + 4 : offset + 8] == b"IEND":
            if size != 0:
                fail(422, "validation_error")
            return
        offset = end
    fail(422, "validation_error")


def normalize_picture(picture):
    if picture is None:
        return None
    try:
        raw = base64.b64decode(picture.data_base64, validate=True)
        if len(raw) > MAX_PICTURE_BYTES:
            fail(413, "payload_too_large")
        if base64.b64encode(raw).decode("ascii") != picture.data_base64:
            fail(422, "validation_error")
        if raw.startswith(b"\x89PNG\r\n\x1a\n"):
            verify_png_chunks(raw)
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(BytesIO(raw), formats=("JPEG", "PNG")) as source:
                if (
                    Image.MIME[source.format] != picture.content_type
                    or getattr(source, "n_frames", 1) != 1
                    or max(source.size) > 2048
                    or source.width * source.height > 4194304
                ):
                    fail(422, "validation_error")
                source.verify()
            with Image.open(BytesIO(raw), formats=("JPEG", "PNG")) as source:
                source.load()
                image = ImageOps.exif_transpose(source).convert("RGBA")
                image.thumbnail((512, 512), Image.Resampling.LANCZOS)
                background = Image.new("RGB", image.size, "white")
                background.paste(image, mask=image.getchannel("A"))
                output = BytesIO()
                background.save(output, "JPEG", quality=85)
                return output.getvalue()
    except (
        binascii.Error,
        ValueError,
        OSError,
        SyntaxError,
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
    ):
        fail(422, "validation_error")


def profile_response(row, subject):
    if row is None:
        return {
            "user_id": subject,
            "display_name": None,
            "profile_picture": None,
            "created_at": None,
            "updated_at": None,
        }
    result = dict(row)
    picture = result["profile_picture"]
    result["profile_picture"] = (
        {
            "content_type": "image/jpeg",
            "data_base64": base64.b64encode(picture).decode("ascii"),
        }
        if picture is not None
        else None
    )
    return result


@router.get("/v1/me/profile", response_model=ProfileResponse)
def get_profile(request: Request, response: Response, subject: User):
    """Read only this token subject's profile; uninitialized fields are null.

    No row is inserted and no session expiration writes occur on this GET.
    Phone identity is managed by Auth0, never supplied through this API.
    """
    response.headers["Cache-Control"] = "no-store"
    with connect(request.app.state.settings.db_path) as db:
        db.execute("PRAGMA query_only=ON")
        row = db.execute(
            "SELECT * FROM profiles WHERE user_id=?", (subject,)
        ).fetchone()
    return profile_response(row, subject)


@router.put("/v1/me/profile", response_model=ProfileResponse)
def put_profile(body: ProfilePut, request: Request, response: Response, subject: User):
    """Atomically replace display name and picture for the validated token subject.

    Both fields are required; null explicitly removes the picture. No phone,
    owner ID, URL or onboarding policy fields are accepted. Name is a strict
    string, Unicode-whitespace trimmed, 1..80 codepoints; controls/surrogates
    are rejected. Picture is strict canonical base64 of JPEG/PNG, <=512 KiB,
    <=2048 per side and <=4,194,304 pixels, not animated or truncated, matching
    its declared MIME type. Output is metadata-free JPEG with EXIF orientation
    applied, alpha flattened on white, longest edge <=512 (never upscaled).
    Retries replace one row; created_at is preserved, updated_at is server UTC.
    The request body is bounded to 1 MiB even without Content-Length.
    """
    picture = normalize_picture(body.profile_picture)
    with transaction(request.app.state.settings.db_path) as db:
        now = instant(request).isoformat()
        db.execute(
            "INSERT INTO profiles(user_id,display_name,profile_picture,created_at,updated_at) "
            "VALUES (?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET "
            "display_name=excluded.display_name, profile_picture=excluded.profile_picture, "
            "updated_at=excluded.updated_at",
            (subject, body.display_name, picture, now, now),
        )
        row = db.execute(
            "SELECT * FROM profiles WHERE user_id=?", (subject,)
        ).fetchone()
    response.headers["Cache-Control"] = "no-store"
    return profile_response(row, subject)
