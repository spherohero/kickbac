import base64
import json
import logging
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from io import BytesIO
from threading import Barrier

import pytest
from fastapi.testclient import TestClient
from PIL import Image, PngImagePlugin
from test_profiles import picture

from kickbac.app import create_app
from kickbac.db import connect
from kickbac.settings import Settings


@pytest.mark.parametrize("method", ["GET", "PUT"])
@pytest.mark.parametrize(
    "credential", ["missing", "invalid", "device", "expired", "wrong_audience", "m2m"]
)
def test_profile_requires_valid_user_access_token(world, identity, method, credential):
    c, users, devices, _, path = world
    _, token = identity
    headers = {
        "missing": {},
        "invalid": {"Authorization": "Bearer invalid"},
        "device": devices["one"],
        "expired": {"Authorization": "Bearer " + token(exp=1)},
        "wrong_audience": {"Authorization": "Bearer " + token(aud="other")},
        "m2m": {"Authorization": "Bearer " + token(gty="client-credentials")},
    }[credential]
    response = c.request(
        method,
        "/v1/me/profile",
        headers=headers,
        **(
            {"json": {"display_name": "No", "profile_picture": None}}
            if method == "PUT"
            else {}
        ),
    )
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"
    assert response.headers["cache-control"] == "no-store"
    with connect(path) as db:
        assert db.execute("SELECT count(*) FROM profiles").fetchone()[0] == 0


def test_same_phone_claims_do_not_merge_subjects_and_relogin_persists(world, identity):
    c, _, _, _, path = world
    _, token = identity

    def headers(sub):
        return {
            "Authorization": "Bearer " + token(sub=sub, phone_number="+15555550123")
        }

    for subject, name in [("sms|one", "One"), ("auth0|other", "Other")]:
        response = c.put(
            "/v1/me/profile",
            headers=headers(subject),
            json={"display_name": name, "profile_picture": picture()},
        )
        assert response.status_code == 200 and response.json()["user_id"] == subject
    with TestClient(create_app(Settings(path), c.app.state.verifier)) as restarted:
        for subject, name in [("sms|one", "One"), ("auth0|other", "Other")]:
            result = restarted.get("/v1/me/profile", headers=headers(subject)).json()
            assert result["display_name"] == name
            assert result["profile_picture"]["content_type"] == "image/jpeg"


def test_exif_orientation_and_all_metadata_removed(world):
    c, u, *_ = world
    image = Image.new("RGB", (40, 20), "red")
    exif = Image.Exif()
    exif[274] = 6
    exif[270] = "private-exif-marker"
    stream = BytesIO()
    image.save(
        stream,
        "JPEG",
        exif=exif,
        icc_profile=b"private-icc-marker",
        comment=b"private-comment-marker",
    )
    response = c.put(
        "/v1/me/profile",
        headers=u["alice"],
        json={
            "display_name": "Alice",
            "profile_picture": {
                "content_type": "image/jpeg",
                "data_base64": base64.b64encode(stream.getvalue()).decode(),
            },
        },
    )
    assert response.status_code == 200
    raw = base64.b64decode(response.json()["profile_picture"]["data_base64"])
    assert b"private-" not in raw
    with Image.open(BytesIO(raw)) as result:
        assert result.size == (20, 40)
        assert not result.getexif()
        assert "icc_profile" not in result.info and "comment" not in result.info
    stream = BytesIO()
    info = PngImagePlugin.PngInfo()
    info.add_text("private-key", "private-png-marker")
    image.save(stream, "PNG", pnginfo=info)
    response = c.put(
        "/v1/me/profile",
        headers=u["alice"],
        json={
            "display_name": "Alice",
            "profile_picture": {
                "content_type": "image/png",
                "data_base64": base64.b64encode(stream.getvalue()).decode(),
            },
        },
    )
    assert response.status_code == 200
    assert b"private-" not in base64.b64decode(
        response.json()["profile_picture"]["data_base64"]
    )


def test_boundary_valid_image_and_decoded_bytes(world):
    c, u, *_ = world
    photo = picture("PNG", (2048, 2048))
    # PNG allows trailing bytes: exactly the decoded byte cap, before normalization.
    raw = base64.b64decode(photo["data_base64"])
    raw += b"\x00" * (512 * 1024 - len(raw))
    photo["data_base64"] = base64.b64encode(raw).decode()
    response = c.put(
        "/v1/me/profile",
        headers=u["alice"],
        json={"display_name": "Alice", "profile_picture": photo},
    )
    assert response.status_code == 200
    with Image.open(
        BytesIO(base64.b64decode(response.json()["profile_picture"]["data_base64"]))
    ) as image:
        assert image.size == (512, 512)


def test_concurrent_replacements_never_mix_name_and_picture(world):
    c, u, _, now, path = world
    bodies = [
        {"display_name": name, "profile_picture": picture("PNG", (10, 10), color)}
        for name, color in [("Red", (255, 0, 0, 255)), ("Blue", (0, 0, 255, 255))]
    ]
    gate = Barrier(2)

    def put(body):
        gate.wait(timeout=5)
        response = c.put("/v1/me/profile", headers=u["alice"], json=body)
        assert response.status_code == 200
        return response.json()

    with ThreadPoolExecutor(2) as pool:
        results = list(pool.map(put, bodies))
    for result in results:
        with Image.open(
            BytesIO(base64.b64decode(result["profile_picture"]["data_base64"]))
        ) as image:
            r, _, b = image.getpixel((0, 0))
            assert (r > b) == (result["display_name"] == "Red")
    assert c.get("/v1/me/profile", headers=u["alice"]).json() in results
    with connect(path) as db:
        assert db.execute("SELECT count(*) FROM profiles").fetchone()[0] == 1


def test_storage_failure_rolls_back_both_fields_and_timestamps(world):
    c, u, _, now, path = world
    original = c.put(
        "/v1/me/profile",
        headers=u["alice"],
        json={"display_name": "Original", "profile_picture": picture()},
    ).json()
    with connect(path) as db:
        db.execute(
            "CREATE TRIGGER fail_profile BEFORE UPDATE ON profiles BEGIN SELECT RAISE(ABORT,'private-storage-marker'); END"
        )
    now[0] += timedelta(seconds=10)
    with TestClient(c.app, raise_server_exceptions=False) as safe:
        response = safe.put(
            "/v1/me/profile",
            headers=u["alice"],
            json={"display_name": "Changed", "profile_picture": None},
        )
    assert response.status_code == 500 and "private-storage-marker" not in response.text
    assert response.headers["cache-control"] == "no-store"
    assert c.get("/v1/me/profile", headers=u["alice"]).json() == original


def test_profile_sensitive_fields_never_logged(world, caplog):
    c, u, *_ = world
    photo = picture("PNG", (20, 20))
    with caplog.at_level(logging.DEBUG):
        assert (
            c.put(
                "/v1/me/profile",
                headers=u["alice"],
                json={"display_name": "private-name-marker", "profile_picture": photo},
            ).status_code
            == 200
        )
        assert c.get("/v1/me/profile", headers=u["alice"]).status_code == 200
        assert (
            c.put(
                "/v1/me/profile",
                headers=u["alice"],
                json={
                    "display_name": "private-name-marker",
                    "profile_picture": {
                        "content_type": "image/png",
                        "data_base64": "private-bad-image",
                    },
                },
            ).status_code
            == 422
        )
    for private in [
        "private-name-marker",
        photo["data_base64"],
        "private-bad-image",
        u["alice"]["Authorization"],
        "data_base64",
        "display_name",
    ]:
        assert private not in caplog.text


def test_body_boundary_and_malformed_json_are_generic(world):
    c, u, *_ = world
    valid = json.dumps({"display_name": "Alice", "profile_picture": None}).encode()
    response = c.put(
        "/v1/me/profile",
        headers={**u["alice"], "Content-Type": "application/json"},
        content=valid + b" " * (1024 * 1024 - len(valid)),
    )
    assert response.status_code == 200
    too_big = c.put(
        "/v1/me/profile", headers=u["alice"], content=b"x" * (1024 * 1024 + 1)
    )
    assert too_big.status_code == 413
    invalid = c.put("/v1/me/profile", headers=u["alice"], content=b'{"private-marker":')
    assert invalid.status_code == 422 and "private-marker" not in invalid.text


def test_get_profile_does_not_lazily_expire_sessions_or_touch_stored_profile(world):
    c, u, _, now, path = world
    body = {"display_name": "Alice", "profile_picture": picture()}
    first = c.put("/v1/me/profile", headers=u["alice"], json=body)
    assert first.status_code == 200
    retry = c.put("/v1/me/profile", headers=u["alice"], json=body)
    assert retry.status_code == 200 and retry.json() == first.json()
    assert (
        c.post("/v1/devices/one/sessions", headers=u["alice"], json={}).status_code
        == 201
    )
    now[0] += timedelta(seconds=61)
    with connect(path) as db:
        before = list(db.iterdump())
    for user in ("alice", "bob"):
        response = c.get("/v1/me/profile", headers=u[user])
        assert response.status_code == 200
        assert response.headers["cache-control"] == "no-store"
    with connect(path) as db:
        assert list(db.iterdump()) == before
