import base64
import json
from io import BytesIO

import pytest
from PIL import Image

from kickbac.db import connect


def test_new_profile_get_is_read_only_and_me_unchanged(world):
    c, u, _, _, path = world
    with connect(path) as db:
        before = list(db.iterdump())
    response = c.get("/v1/me/profile", headers=u["alice"])
    assert response.status_code == 200
    assert response.json() == {
        "user_id": "auth0|alice",
        "display_name": None,
        "profile_picture": None,
        "created_at": None,
        "updated_at": None,
    }
    assert response.headers["cache-control"] == "no-store"
    assert c.get("/v1/me", headers=u["alice"]).json() == {"user_id": "auth0|alice"}
    with connect(path) as db:
        assert list(db.iterdump()) == before


def test_put_name_persists_retries_and_isolates(world):
    from datetime import timedelta

    from fastapi.testclient import TestClient

    from kickbac.app import create_app
    from kickbac.settings import Settings

    c, u, _, now, path = world
    payload = {"display_name": "\u2003 Alice \u00a0", "profile_picture": None}
    first = c.put("/v1/me/profile", headers=u["alice"], json=payload)
    assert first.status_code == 200
    expected = {
        "user_id": "auth0|alice",
        "display_name": "Alice",
        "profile_picture": None,
        "created_at": now[0].isoformat(),
        "updated_at": now[0].isoformat(),
    }
    assert first.json() == expected
    assert first.headers["cache-control"] == "no-store"
    now[0] += timedelta(seconds=1)
    expected["updated_at"] = now[0].isoformat()
    assert c.put("/v1/me/profile", headers=u["alice"], json=payload).json() == expected
    assert c.get("/v1/me/profile", headers=u["bob"]).json()["display_name"] is None
    with TestClient(create_app(Settings(path), c.app.state.verifier)) as restarted:
        assert restarted.get("/v1/me/profile", headers=u["alice"]).json() == expected
    with connect(path) as db:
        assert db.execute("SELECT count(*) FROM profiles").fetchone()[0] == 1


def picture(fmt="PNG", size=(800, 400), color=(255, 0, 0, 0)):
    stream = BytesIO()
    image = Image.new("RGBA", size, color)
    if fmt == "JPEG":
        image = image.convert("RGB")
    image.save(stream, fmt)
    return {
        "content_type": "image/" + fmt.lower(),
        "data_base64": base64.b64encode(stream.getvalue()).decode("ascii"),
    }


def test_picture_normalized_replaced_removed_and_stored_in_blob(world):
    c, u, _, _, path = world
    body = {"display_name": "Alice", "profile_picture": picture()}
    first = c.put("/v1/me/profile", headers=u["alice"], json=body)
    assert first.status_code == 200
    photo = first.json()["profile_picture"]
    assert photo["content_type"] == "image/jpeg"
    raw = base64.b64decode(photo["data_base64"], validate=True)
    with Image.open(BytesIO(raw)) as normalized:
        assert normalized.format == "JPEG"
        assert normalized.size == (512, 256)
        assert normalized.getpixel((0, 0)) == (255, 255, 255)
        assert not normalized.getexif()
    with connect(path) as db:
        row = db.execute(
            "SELECT profile_picture,typeof(profile_picture) FROM profiles"
        ).fetchone()
        assert tuple(row) == (raw, "blob")
    body["profile_picture"] = picture("JPEG", (10, 20), (0, 0, 255, 255))
    replaced = c.put("/v1/me/profile", headers=u["alice"], json=body)
    assert replaced.status_code == 200
    assert replaced.json()["profile_picture"] != photo
    assert c.get("/v1/me/profile", headers=u["alice"]).json() == replaced.json()
    body["profile_picture"] = None
    assert (
        c.put("/v1/me/profile", headers=u["alice"], json=body).json()["profile_picture"]
        is None
    )


@pytest.mark.parametrize(
    "name",
    [
        "",
        " \u2003",
        "x" * 81,
        123,
        True,
        None,
        "\u0000Alice",
        "Al\nice",
        "Al\tice",
        "\ud800",
        "A\u007f",
        "A\u0085",
    ],
)
def test_invalid_name_cannot_replace_existing_profile(world, name):
    c, u, _, _, _ = world
    before = c.put(
        "/v1/me/profile",
        headers=u["alice"],
        json={"display_name": "Private Name", "profile_picture": None},
    ).json()
    response = c.put(
        "/v1/me/profile",
        headers={**u["alice"], "Content-Type": "application/json"},
        content=json.dumps({"display_name": name, "profile_picture": None}),
    )
    assert response.status_code == 422
    assert response.json() == {
        "error": {"code": "validation_error", "message": "Request validation failed."}
    }
    assert c.get("/v1/me/profile", headers=u["alice"]).json() == before


@pytest.mark.parametrize(
    "body",
    [
        {},
        {"display_name": "Alice"},
        {"profile_picture": None},
        {"display_name": "Alice", "profile_picture": None, "phone": "+15555550123"},
        {"display_name": "Alice", "profile_picture": None, "user_id": "auth0|bob"},
        {
            "display_name": "Alice",
            "profile_picture": {
                "content_type": "image/png",
                "data_base64": "AAAA",
                "url": "https://invalid",
            },
        },
        {"display_name": "Alice", "profile_picture": "https://invalid"},
    ],
)
def test_strict_profile_shape(world, body):
    c, u, _, _, path = world
    response = c.put("/v1/me/profile", headers=u["alice"], json=body)
    assert response.status_code == 422
    with connect(path) as db:
        assert db.execute("SELECT count(*) FROM profiles").fetchone()[0] == 0


def test_name_unicode_boundary_and_trim(world):
    c, u, *_ = world
    name = "\U0001f40a" * 80
    response = c.put(
        "/v1/me/profile",
        headers=u["alice"],
        json={"display_name": "\u2003" + name + "\u00a0", "profile_picture": None},
    )
    assert response.status_code == 200
    assert response.json()["display_name"] == name


def invalid_picture(kind):
    photo = picture("PNG", (20, 10))
    raw = base64.b64decode(photo["data_base64"])
    if kind == "bad_base64":
        photo["data_base64"] = "!not-base64!"
    elif kind == "whitespace":
        photo["data_base64"] += "\n"
    elif kind == "excess_padding":
        photo["data_base64"] += "===="
    elif kind == "noncanonical":
        photo["data_base64"] = "Zh=="
    elif kind == "wrong_type":
        photo["content_type"] = "image/jpeg"
    elif kind == "truncated_png":
        photo["data_base64"] = base64.b64encode(raw[:-10]).decode()
    elif kind == "truncated_jpeg":
        photo = picture("JPEG", (20, 10))
        photo["data_base64"] = base64.b64encode(
            base64.b64decode(photo["data_base64"])[:-10]
        ).decode()
    elif kind == "invalid":
        photo["data_base64"] = base64.b64encode(b"not an image").decode()
    elif kind == "svg":
        photo["data_base64"] = base64.b64encode(
            b'<svg xmlns="http://www.w3.org/2000/svg"/>'
        ).decode()
    elif kind in ("GIF", "WEBP"):
        photo = picture(kind, (20, 10))
        photo["content_type"] = "image/png"
    elif kind == "side":
        photo = picture("PNG", (2049, 1))
    elif kind == "pixels":
        photo = picture("PNG", (2049, 2049))
    elif kind == "animated":
        stream = BytesIO()
        frames = [Image.new("RGB", (10, 10), color) for color in ("red", "blue")]
        frames[0].save(stream, "PNG", save_all=True, append_images=frames[1:])
        photo["data_base64"] = base64.b64encode(stream.getvalue()).decode()
    elif kind == "bomb":
        import struct
        import zlib

        data = struct.pack(">IIBBBBB", 100000, 100000, 8, 2, 0, 0, 0)
        raw = raw[:16] + data + struct.pack(">I", zlib.crc32(b"IHDR" + data)) + raw[33:]
        photo["data_base64"] = base64.b64encode(raw).decode()
    return photo


@pytest.mark.parametrize(
    "kind",
    [
        "bad_base64",
        "whitespace",
        "excess_padding",
        "noncanonical",
        "wrong_type",
        "truncated_png",
        "truncated_jpeg",
        "invalid",
        "svg",
        "GIF",
        "WEBP",
        "side",
        "pixels",
        "animated",
        "bomb",
    ],
)
def test_rejected_picture_preserves_entire_existing_row(world, kind):
    c, u, _, _, path = world
    c.put(
        "/v1/me/profile",
        headers=u["alice"],
        json={"display_name": "Original", "profile_picture": picture()},
    )
    with connect(path) as db:
        before = tuple(db.execute("SELECT * FROM profiles").fetchone())
    response = c.put(
        "/v1/me/profile",
        headers=u["alice"],
        json={"display_name": "Changed", "profile_picture": invalid_picture(kind)},
    )
    assert response.status_code == 422
    assert response.json() == {
        "error": {"code": "validation_error", "message": "Request validation failed."}
    }
    with connect(path) as db:
        assert tuple(db.execute("SELECT * FROM profiles").fetchone()) == before


@pytest.mark.parametrize("kind", ["encoded", "decoded"])
def test_picture_size_limit_is_generic_413_and_atomic(world, kind):
    c, u, _, _, path = world
    before = c.put(
        "/v1/me/profile",
        headers=u["alice"],
        json={"display_name": "Original", "profile_picture": None},
    ).json()
    encoded = base64.b64encode(b"x" * (512 * 1024 + 1)).decode()
    if kind == "encoded":
        encoded += "AAAA"
    response = c.put(
        "/v1/me/profile",
        headers=u["alice"],
        json={
            "display_name": "Changed",
            "profile_picture": {"content_type": "image/png", "data_base64": encoded},
        },
    )
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "payload_too_large"
    assert c.get("/v1/me/profile", headers=u["alice"]).json() == before


@pytest.mark.parametrize("length", [None, b"1", b"1048577"])
def test_streaming_body_limit_does_not_trust_content_length(world, length):
    import asyncio

    c, u, _, _, path = world
    headers = [
        (b"content-type", b"application/json"),
        (b"authorization", u["alice"]["Authorization"].encode()),
    ]
    if length is not None:
        headers.append((b"content-length", length))
    messages = []
    calls = []

    async def receive():
        calls.append(1)
        return {
            "type": "http.request",
            "body": b" " * 65536,
            "more_body": len(calls) < 20,
        }

    async def send(message):
        messages.append(message)

    asyncio.run(
        c.app(
            {
                "type": "http",
                "asgi": {"version": "3.0"},
                "http_version": "1.1",
                "method": "PUT",
                "scheme": "http",
                "path": "/v1/me/profile",
                "raw_path": b"/v1/me/profile",
                "query_string": b"",
                "headers": headers,
                "client": ("127.0.0.1", 123),
                "server": ("test", 80),
            },
            receive,
            send,
        )
    )
    assert messages[0]["status"] == 413
    assert dict(messages[0]["headers"])[b"cache-control"] == b"no-store"
    assert (
        json.loads(b"".join(m.get("body", b"") for m in messages))["error"]["code"]
        == "payload_too_large"
    )
    assert len(calls) <= 17
    with connect(path) as db:
        assert db.execute("SELECT count(*) FROM profiles").fetchone()[0] == 0
