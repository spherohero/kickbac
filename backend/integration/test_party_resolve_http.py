"""Actual HTTP device-party resolve/current/delete acceptance; isolated identities."""

import time
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from threading import Barrier
from uuid import uuid4

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from kickbac.app import create_app
from kickbac.auth import JWTVerifier
from kickbac.cli import provision_device
from kickbac.db import connect, initialize
from kickbac.settings import Settings
from kickbac.simulator import serve


class PrivateWorld(tuple):
    def __repr__(self):
        return "<isolated HTTP fixture; credentials withheld>"


@pytest.fixture
def resolve_world(tmp_path):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    issuer, audience = "https://resolve-http-fixture.invalid/", "resolve-http-fixture"
    verifier = JWTVerifier(issuer, audience, lambda _: key.public_key())
    settings = Settings(tmp_path / "resolve-http.sqlite3")
    initialize(settings.db_path)
    devices = {}
    for device_id in ("resolve-one", "resolve-two", "resolve-busy"):
        secret = tmp_path / (device_id + ".secret")
        provision_device(settings.db_path, device_id, secret)
        devices[device_id] = {"Authorization": "Bearer " + secret.read_text().strip()}
    users = {}
    for name in ("host", "member", "third", "outsider"):
        token = jwt.encode(
            {
                "iss": issuer,
                "aud": audience,
                "sub": "resolve-fixture|" + name,
                "exp": int(time.time()) + 600,
            },
            key,
            algorithm="RS256",
        )
        users[name] = {"Authorization": "Bearer " + token}
    now = [datetime.now(UTC)]

    def app():
        return create_app(settings, verifier=verifier, clock=lambda: now[0])

    return PrivateWorld((settings, devices, users, app))


def checked(client, method, path, headers, status=200, **kwargs):
    response = client.request(method, path, headers=headers, **kwargs)
    assert response.status_code == status, (
        method,
        path,
        response.status_code,
        response.text,
    )
    if path.startswith(("/v1/parties", "/v1/me/parties")):
        assert response.headers.get("Cache-Control") == "no-store"
    return response.json()


def test_resolve_real_http_bind_join_conflict_close_new_party_and_restart(
    resolve_world,
):
    settings, devices, users, app = resolve_world
    host, member, third, outsider = (
        users[x] for x in ("host", "member", "third", "outsider")
    )
    original = {"request_id": str(uuid4()), "device_id": "resolve-one", "name": "Grub"}
    with serve(app()) as client:
        created = checked(
            client, "POST", "/v1/parties/resolve", host, 201, json=original
        )
        party = created["party"]
        pid, code = party["party_id"], party["join_code"]
        assert created["action"] == "created" and party["device_id"] == "resolve-one"
        assert party["role"] == "host" and party["member_count"] == 1 and len(code) == 8
        assert checked(client, "GET", "/v1/me/parties/current", host) == party
        assert (
            checked(client, "POST", "/v1/parties/resolve", host, json=original)
            == created
        )
        assert checked(client, "GET", "/v1/me/parties/current", member) is None
        joined = checked(
            client,
            "POST",
            "/v1/parties/resolve",
            member,
            json={"request_id": str(uuid4()), "device_id": "resolve-one"},
        )
        assert joined["action"] == "joined" and joined["party"]["party_id"] == pid
        assert joined["party"]["name"] == "Grub" and joined["party"]["role"] == "member"
        assert (
            joined["party"]["join_code"] is None
            and joined["party"]["member_count"] == 2
        )
        game_id = str(uuid4())
        checked(
            client,
            "POST",
            f"/v1/parties/{pid}/games",
            host,
            201,
            json={"game_instance_id": game_id, "game_id": "trivia"},
        )
        check_in = checked(
            client,
            "POST",
            f"/v1/parties/{pid}/check-ins",
            member,
            201,
            json={
                "check_in_id": str(uuid4()),
                "device_id": "resolve-one",
                "game_instance_id": game_id,
            },
        )
        sid = check_in["session"]["id"]
        # Code joining an existing party is allowed during acquisition, not arming.
        by_code = checked(
            client, "POST", "/v1/parties/join", third, json={"join_code": code}
        )
        assert by_code["party_id"] == pid and by_code["role"] == "member"
        assert (
            checked(client, "GET", "/v1/device/session", devices["resolve-one"])[
                "active_session"
            ]["id"]
            == sid
        )
        checked(client, "POST", f"/v1/parties/{pid}/close", host, 409, json={})
        conflict = checked(
            client,
            "POST",
            "/v1/parties/resolve",
            member,
            409,
            json={"request_id": str(uuid4()), "device_id": "resolve-two"},
        )
        assert conflict["error"]["code"] == "active_party_conflict"
        assert {p["party_id"] for p in conflict["error"]["current_parties"]} == {pid}
        assert all(p["join_code"] is None for p in conflict["error"]["current_parties"])
        checked(
            client,
            "POST",
            "/v1/parties",
            member,
            409,
            json={"party_id": str(uuid4()), "name": "Another"},
        )
        # Busy unassigned units cannot accumulate a newly-created party.
        busy = checked(
            client, "POST", "/v1/devices/resolve-busy/sessions", third, 201, json={}
        )
        checked(
            client,
            "POST",
            "/v1/parties/resolve",
            outsider,
            409,
            json={"request_id": str(uuid4()), "device_id": "resolve-busy"},
        )
        checked(client, "POST", f"/v1/sessions/{busy['id']}/cancel", third, json={})
        checked(
            client,
            "POST",
            "/v1/parties/resolve",
            outsider,
            404,
            json={"request_id": str(uuid4()), "device_id": "unknown-unit"},
        )
        checked(
            client,
            "POST",
            "/v1/parties/resolve",
            outsider,
            422,
            json={"request_id": str(uuid4()), "device_id": "resolve-two", "name": None},
        )
        checked(client, "POST", "/v1/parties/resolve", outsider, 404, json=original)
        checked(
            client,
            "POST",
            "/v1/parties/resolve",
            host,
            409,
            json={**original, "name": "Changed"},
        )
        measurement = checked(
            client,
            "POST",
            "/v1/device/measurements",
            devices["resolve-one"],
            201,
            json={
                "measurement_id": str(uuid4()),
                "session_id": sid,
                "raw": {"sensor": "mq3", "value": 1200, "unit": "adc_counts"},
                "breath_duration_ms": 2500,
                "source": "simulator",
                "measured_at": None,
            },
        )
        result_body = {
            "result_id": str(uuid4()),
            "game_id": "trivia",
            "score": 3,
            "outcome": "completed",
            "data": {},
            "measurement_id": measurement["id"],
            "placement": 1,
        }
        checked(
            client,
            "POST",
            f"/v1/party-games/{game_id}/results",
            member,
            201,
            json=result_body,
        )
        checked(client, "POST", f"/v1/parties/{pid}/close", member, 404, json={})
        closed = checked(client, "POST", f"/v1/parties/{pid}/close", host, json={})
        assert (
            closed["state"] == "CLOSED"
            and closed["device_id"] is None
            and closed["join_code"] is None
        )
        assert (
            checked(client, "POST", f"/v1/parties/{pid}/close", host, json={}) == closed
        )
        assert checked(client, "GET", "/v1/me/parties/current", host) is None
        assert checked(client, "GET", "/v1/me/parties/current", member) is None
        assert (
            checked(client, "GET", f"/v1/parties/{pid}/games", host)["items"][0][
                "state"
            ]
            == "CLOSED"
        )
        checked(
            client, "POST", "/v1/parties/join", outsider, 404, json={"join_code": code}
        )
        new_body = {"request_id": str(uuid4()), "device_id": "resolve-one"}
        newer = checked(client, "POST", "/v1/parties/resolve", host, 201, json=new_body)
        assert newer["party"]["party_id"] != pid and newer["party"]["join_code"] != code
        assert newer["party"]["name"] == "Party"
        late = checked(client, "POST", "/v1/parties/resolve", host, json=original)
        assert (
            late["action"] == "created"
            and late["party"]["party_id"] == pid
            and late["party"]["state"] == "CLOSED"
        )
        assert checked(client, "GET", "/v1/me/parties/current", host) == newer["party"]
        assert checked(client, "GET", "/v1/measurements", member)["items"] == [
            measurement
        ]
        rich = checked(client, "GET", "/v1/me/game-history", member)
        assert (
            rich["items"][0]["measurement"] == measurement
            and rich["items"][0]["party"]["party_id"] == pid
        )
        checked(client, "GET", "/v1/me/parties/current", {}, 401)
        checked(client, "POST", "/v1/parties/resolve", {}, 401, json=original)
        huge = client.post(
            "/v1/parties/resolve",
            headers={**outsider, "Content-Type": "application/json"},
            content=b"{" + b" " * 32768 + b"}",
        )
        assert huge.status_code == 413 and huge.headers["Cache-Control"] == "no-store"
    with serve(app()) as client:
        assert (
            checked(client, "POST", "/v1/parties/resolve", host, json=original) == late
        )
        assert (
            checked(client, "POST", "/v1/parties/resolve", host, json=new_body) == newer
        )
        assert checked(client, "GET", "/v1/me/parties/current", host) == newer["party"]
        assert checked(client, "GET", "/v1/measurements", member)["items"] == [
            measurement
        ]
        assert checked(client, "GET", "/v1/me/game-history", member) == rich
    with connect(settings.db_path) as db:
        assert db.execute("SELECT count(*) FROM parties").fetchone()[0] == 2
        assert db.execute("SELECT count(*) FROM measurements").fetchone()[0] == 1
        assert db.execute("SELECT count(*) FROM game_results").fetchone()[0] == 1
        assert db.execute("SELECT count(*) FROM device_party_hosts").fetchone()[0] == 0


@pytest.mark.parametrize(
    "same_user", [False, True], ids=["two-users-one-unit", "one-user-two-units"]
)
def test_resolve_concurrent_real_http_single_party_or_membership(
    resolve_world, same_user
):
    settings, _, users, app = resolve_world
    barrier = Barrier(2)
    with serve(app()) as client:

        def resolve(index):
            body = {
                "request_id": str(uuid4()),
                "device_id": "resolve-two" if same_user and index else "resolve-one",
            }
            headers = users["host"] if same_user or index == 0 else users["member"]
            barrier.wait(timeout=5)
            return client.post("/v1/parties/resolve", headers=headers, json=body)

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(resolve, range(2)))
        assert sorted(r.status_code for r in results) == (
            [201, 409] if same_user else [200, 201]
        )
        accepted = [r.json() for r in results if r.status_code in (200, 201)]
        if not same_user:
            assert accepted[0]["party"]["party_id"] == accepted[1]["party"]["party_id"]
            assert {r["action"] for r in accepted} == {"created", "joined"}
            assert {r["party"]["role"] for r in accepted} == {"host", "member"}
        assert (
            checked(client, "GET", "/v1/me/parties/current", users["host"])["state"]
            == "OPEN"
        )
    with connect(settings.db_path) as db:
        assert db.execute("SELECT count(*) FROM parties").fetchone()[0] == 1
        assert db.execute("SELECT count(*) FROM party_devices").fetchone()[0] == 1
        assert db.execute("SELECT count(*) FROM party_members").fetchone()[0] == (
            1 if same_user else 2
        )
