import base64

import pytest
from test_profiles import picture


@pytest.mark.parametrize("damage", ["cut1", "cut2", "cut3", "cut4", "iend_crc"])
def test_incomplete_or_corrupt_png_end_cannot_replace_profile(world, damage):
    client, users, *_ = world
    headers = users["alice"]
    before = client.put(
        "/v1/me/profile",
        headers=headers,
        json={"display_name": "Original", "profile_picture": None},
    ).json()
    photo = picture("PNG", (10, 10))
    raw = base64.b64decode(photo["data_base64"])
    if damage.startswith("cut"):
        raw = raw[: -int(damage[-1])]
    else:
        raw = raw[:-1] + bytes([raw[-1] ^ 1])
    photo["data_base64"] = base64.b64encode(raw).decode("ascii")
    response = client.put(
        "/v1/me/profile",
        headers=headers,
        json={"display_name": "Rejected", "profile_picture": photo},
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"
    assert client.get("/v1/me/profile", headers=headers).json() == before
