#define KICKBAC_MOCK_UPLOAD 1
#define KICKBAC_ADAPTER_LIBRARY 1
#include "device_adapter_test.cpp"

int fixture_upload_status = 201;
std::string fixture_upload_override;
std::vector<std::string> fixture_upload_payloads;

void reset_mock_fixture() {
    reset_fixture();
    mock_upload = kickbac::MockUpload{};
    mock_command = kickbac::MockCommand{};
    last_mock_ready = 0;
    fixture_upload_status = 201;
    fixture_upload_override.clear();
    fixture_upload_payloads.clear();
    provision_fixture();
}

const std::string mock_session = "3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b";
void arm_mock_fixture(const std::string& id = mock_session) {
    const std::time_t deadline = std::time(nullptr) + 45;
    char expiry[40] = {};
    assert(std::strftime(expiry, sizeof(expiry), "%Y-%m-%dT%H:%M:%SZ", std::gmtime(&deadline)) > 0);
    fixture_override_body = true;
    fixture_override_heartbeat = false;
    fixture_response_body = "{\"device_id\":\"kb-demo-01\",\"active_session\":{\"id\":\"" + id +
        "\",\"device_id\":\"kb-demo-01\",\"status\":\"ARMED\",\"expires_at\":\"" + expiry + "\"}}";
    fixture_now += 2000;
    device_probe_loop();
}
void trigger_mock() {
    Serial.input = "MOCK " + mock_session + "\n";
    for (int i = 0; i < 3; ++i) device_probe_loop(); // bounded32byte USB draining
}

int main() {
    reset_mock_fixture();
    trigger_mock();
    assert(fixture_upload_payloads.empty());
    arm_mock_fixture();
    assert(fixture_upload_payloads.empty()); // ARMED alone NEVER uploads
    trigger_mock();
    assert(fixture_upload_payloads.size() == 1 && mock_upload.state() == kickbac::MockState::Accepted);
    assert(fixture_upload_payloads[0].find("\"source\":\"simulator\"") != std::string::npos);
    assert(fixture_upload_payloads[0].find(mock_session) != std::string::npos);
    trigger_mock();
    assert(fixture_upload_payloads.size() == 1); // duplicate operator command cannot create another result

    for (unsigned fault = 0; fault < 3; ++fault) {
        reset_mock_fixture();
        arm_mock_fixture();
        if (fault == 0) fixture_response_body = "{\"device_id\":\"kb-demo-01\",\"active_session\":null}";
        if (fault == 1) fixture_response_body.replace(fixture_response_body.find(mock_session), 1, "4");
        if (fault == 2) fixture_response_body.replace(fixture_response_body.find("ARMED"), 5, "SAMPLING");
        trigger_mock();
        assert(fixture_upload_payloads.empty()); // fresh confirmation lost/changed/cancelled session
    }
    reset_mock_fixture();
    arm_mock_fixture("4b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b");
    trigger_mock();
    assert(fixture_upload_payloads.empty()); // delayed USB command NEVER chooses another user's session

    reset_mock_fixture();
    arm_mock_fixture();
    fixture_upload_status = -11;
    trigger_mock();
    assert(fixture_upload_payloads.size() == 1 && mock_upload.pending());
    const std::string original = fixture_upload_payloads[0];
    assert(session_fence.snapshot().id[0] == '\0');
    // Server could already have committed. Poll idle/new session must not retarget replay.
    fixture_upload_status = 200;
    arm_mock_fixture("4b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b");
    fixture_now += 2000;
    device_probe_loop();
    assert(fixture_upload_payloads.size() >= 2);
    for (const auto& payload : fixture_upload_payloads) assert(payload == original);
    assert(mock_upload.state() == kickbac::MockState::Accepted && !mock_upload.pending());

    for (const int status : {401, 403, 409, 410, 422}) {
        reset_mock_fixture();
        arm_mock_fixture();
        fixture_upload_status = status;
        trigger_mock();
        assert(fixture_upload_payloads.size() == 1 && mock_upload.pending());
        assert(mock_upload.state() == kickbac::MockState::Held);
        assert((status == 401 || status == 403) == failed);
        assert((status == 401 || status == 403) != credential.ready());
    }
    for (const std::string& bad : {std::string("{}"), std::string("{malformed"), std::string(769, 'x')}) {
        reset_mock_fixture();
        arm_mock_fixture();
        fixture_upload_override = bad;
        trigger_mock();
        assert(mock_upload.state() == kickbac::MockState::Held && mock_upload.pending());
        assert(fixture_upload_payloads.size() == 1);
    }
    reset_mock_fixture();
    arm_mock_fixture();
    fixture_upload_status = 503;
    trigger_mock();
    for (unsigned wait : {2000U, 4000U, 8000U}) { fixture_now += wait; device_probe_loop(); }
    assert(fixture_upload_payloads.size() == 4 && mock_upload.state() == kickbac::MockState::Held);
    for (const auto& payload : fixture_upload_payloads) assert(payload == fixture_upload_payloads.front());
    assert(!failed && credential.ready()); // bounded mock failure does NOT kill heartbeat/poll
    reset_mock_fixture();
    arm_mock_fixture();
    fixture_upload_status = -11;
    trigger_mock();
    const std::string unresolved = mock_upload.payload();
    const std::string unresolved_id = mock_upload.measurement_id();
    fixture_wifi_status = 0;
    device_probe_loop();
    assert(!failed && credential.ready());
    assert(mock_upload.pending() && mock_upload.state() == kickbac::MockState::Held);
    assert(std::string(mock_upload.payload()) == unresolved && mock_upload.measurement_id() == unresolved_id);
    fixture_wifi_status = WL_CONNECTED;
    fixture_upload_status = 201;
    fixture_now += 2000;
    device_probe_loop();
    assert(fixture_upload_payloads.size() == 1); // hotspot return cannot auto-send unresolved sample
    assert(mock_upload.pending() && std::string(mock_upload.payload()) == unresolved);
    for (const auto& line : fixture_lines) {
        assert(line.find(std::string(43, 'x')) == std::string::npos);
        assert(line.find("{\"measurement_id\"") == std::string::npos); // never dump payload
    }
    std::cout << "PASS: actual adapter explicit session-bound MOCK only, trusted path/201/replay200, no reassignment, bounded failures and invalid acknowledgements (fixtures)\n";
}
