"""Compatibility checks using simulated signed identities, not live SMS/Auth0."""

from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from kickbac.app import create_app
from kickbac.auth import JWTVerifier
from kickbac.cli import provision_device
from kickbac.db import initialize
from kickbac.settings import Settings

AUDIENCE = "https://kickbac-api"
ISSUER = "https://fixture.invalid/"


def test_sms_access_token_identifies_user_without_email(tmp_path, identity):
    private, token = identity
    path = tmp_path / "sms.sqlite3"
    initialize(path)
    verifier = JWTVerifier(ISSUER, AUDIENCE, lambda _: private.public_key())
    headers = {
        "Authorization": "Bearer "
        + token(sub="sms|fixture-user", aud=AUDIENCE, scope="openid profile")
    }
    with TestClient(create_app(Settings(path), verifier=verifier)) as client:
        response = client.get("/v1/me", headers=headers)
    assert response.status_code == 200
    assert response.json() == {"user_id": "sms|fixture-user"}


@pytest.mark.parametrize("audience", [AUDIENCE + "/", "native-client-id"])
def test_sms_subject_does_not_bypass_audience_validation(tmp_path, identity, audience):
    private, token = identity
    path = tmp_path / "sms.sqlite3"
    initialize(path)
    verifier = JWTVerifier(ISSUER, AUDIENCE, lambda _: private.public_key())
    headers = {"Authorization": "Bearer " + token(sub="sms|fixture-user", aud=audience)}
    with TestClient(create_app(Settings(path), verifier=verifier)) as client:
        response = client.get("/v1/me", headers=headers)
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
    assert response.json()["error"]["code"] == "unauthorized"


@pytest.mark.parametrize("value", ["123456", "+12025550123"])
def test_code_or_phone_number_is_not_a_backend_bearer_token(tmp_path, identity, value):
    private, _ = identity
    path = tmp_path / "sms.sqlite3"
    initialize(path)
    verifier = JWTVerifier(ISSUER, AUDIENCE, lambda _: private.public_key())
    with TestClient(create_app(Settings(path), verifier=verifier)) as client:
        response = client.get("/v1/me", headers={"Authorization": "Bearer " + value})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"


def test_sms_history_is_not_auto_linked_by_phone_and_survives_restart(
    tmp_path, identity
):
    private, token = identity
    path = tmp_path / "sms.sqlite3"
    initialize(path)
    credential_file = tmp_path / "device.secret"
    provision_device(path, "sms-demo", credential_file)
    device = {"Authorization": "Bearer " + credential_file.read_text().strip()}
    verifier = JWTVerifier(ISSUER, AUDIENCE, lambda _: private.public_key())
    # This reserved example phone number is a local JWT claim only; no SMS is sent.
    contact = {"phone_number": "+12025550123", "phone_number_verified": True}

    def user(subject):
        return {
            "Authorization": "Bearer " + token(sub=subject, aud=AUDIENCE, **contact)
        }

    sms_user = user("sms|fixture-user")
    database_user = user("auth0|fixture-user")
    other_sms_user = user("sms|another-fixture-user")
    measurement_id = str(uuid4())
    with TestClient(create_app(Settings(path), verifier=verifier)) as client:
        armed = client.post("/v1/devices/sms-demo/sessions", headers=sms_user, json={})
        assert armed.status_code == 201
        session = armed.json()
        assert session["user_id"] == "sms|fixture-user"
        session_path = "/v1/sessions/" + session["id"]
        uploaded = client.post(
            "/v1/device/measurements",
            headers=device,
            json={
                "measurement_id": measurement_id,
                "session_id": session["id"],
                "raw": {"sensor": "mq3", "value": 1200, "unit": "adc_counts"},
                "breath_duration_ms": 2500,
                "source": "simulator",
                "measured_at": None,
            },
        )
        assert uploaded.status_code == 201
        assert client.get(session_path, headers=sms_user).json()["status"] == "COMPLETE"
        for stranger in (database_user, other_sms_user):
            assert client.get(session_path, headers=stranger).status_code == 404
            assert (
                client.get("/v1/measurements", headers=stranger).json()["items"] == []
            )

    # Fresh app and freshly signed fixture token over the same persistent DB.
    with TestClient(create_app(Settings(path), verifier=verifier)) as restarted:
        new_sms_token = user("sms|fixture-user")
        assert restarted.get("/v1/me", headers=new_sms_token).json() == {
            "user_id": "sms|fixture-user"
        }
        history = restarted.get("/v1/measurements", headers=new_sms_token)
        assert history.status_code == 200
        assert [item["id"] for item in history.json()["items"]] == [measurement_id]
        assert restarted.get(session_path, headers=new_sms_token).json()["status"] == (
            "COMPLETE"
        )
        assert restarted.get(session_path, headers=database_user).status_code == 404
