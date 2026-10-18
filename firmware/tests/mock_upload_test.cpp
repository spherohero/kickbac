// Synthetic values/clock/response fixtures, not sensor or production measurements.
#include <cassert>
#include <cstring>
#include <iostream>
#include <string>
#include "mock_upload.hpp"

const char* session = "3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b";
const char* measurement = "026af7c9-d605-4291-a1db-5b230e10ef43";
const char* ack = R"({"id":"026af7c9-d605-4291-a1db-5b230e10ef43","session_id":"3b0c0a9e-2604-4b78-a487-3fd8fa1d4a4b","device_id":"kb-demo-01","raw":{"sensor":"mq3","value":1200,"unit":"adc_counts"},"breath_duration_ms":2500,"source":"simulator","measured_at":null,"received_at":"2026-10-18T12:00:10.123456+00:00","estimated_bac_percent":null})";

int main() {
    using namespace kickbac;
    SessionFence fence;
    PollSnapshot snapshot;
    snapshot.state = PollState::Armed;
    std::strcpy(snapshot.id, session);
    std::strcpy(snapshot.expires_at, "2026-10-18T12:01:00Z");
    std::int64_t expiry = 0;
    assert(utc_epoch_ms(snapshot.expires_at, expiry));
    MockUpload mock;
    assert(!mock.start(fence, measurement, 100, expiry - 60000));
    assert(fence.observe(snapshot, 100, expiry - 60000));
    assert(mock.start(fence, measurement, 100, expiry - 60000));
    assert(std::strstr(mock.payload(), "\"source\":\"simulator\"") != nullptr);
    assert(std::strstr(mock.payload(), "\"measured_at\":null") != nullptr);
    assert(std::strstr(mock.payload(), "\"breath_duration_ms\":2500") != nullptr);
    const std::string original = mock.payload();
    assert(!mock.start(fence, measurement, 100, expiry - 60000));
    assert(mock.authorize_send(fence, 100, expiry - 60000));
    assert(mock.result(503, "", 200) == MockResult::Retry);
    fence.clear();
    assert(mock.pending() && std::string(mock.payload()) == original);
    assert(!mock.due(2199) && mock.due(2200));
    assert(mock.authorize_send(fence, 2200, expiry)); // unknown outcome: ORIGINAL replay only
    assert(mock.result(200, ack, 2300) == MockResult::Accepted);
    assert(!mock.pending() && mock.state() == MockState::Accepted);
    assert(std::strcmp(mock.measurement_id(), measurement) == 0);
    assert(std::strcmp(mock.session_id(), session) == 0);
    fence = SessionFence{};
    assert(fence.observe(snapshot, 100, expiry - 60000));
    assert(!mock.start(fence, measurement, 100, expiry - 60000)); // same consumed session

    for (const int status : {200, 201}) {
        MockUpload good;
        assert(good.start(fence, measurement, 100, expiry - 60000));
        assert(good.authorize_send(fence, 100, expiry - 60000));
        assert(good.result(status, ack, 200) == MockResult::Accepted);
    }
    for (const int status : {401, 403, 404, 409, 410, 422, -2, -3}) {
        MockUpload blocked;
        assert(blocked.start(fence, measurement, 100, expiry - 60000));
        assert(blocked.authorize_send(fence, 100, expiry - 60000));
        assert(blocked.result(status, ack, 200) == MockResult::Held);
        assert(blocked.pending() && std::string(blocked.payload()) == original && !blocked.due(99999));
    }
    for (const char* fragment : {"\"source\":\"device\"", "\"value\":1201", "\"breath_duration_ms\":true",
                               "\"estimated_bac_percent\":0", "\"device_id\":\"other\"", "\"measured_at\":\"2026-10-18T12:00:01Z\""}) {
        std::string bad = ack;
        const std::string token(fragment);
        const auto key_end = token.find(':');
        const std::string key = token.substr(0, key_end + 1);
        const auto pos = bad.find(key);
        const auto end = bad.find_first_of(",}", pos + key.size());
        bad.replace(pos, end - pos, token);
        assert(!mock_ack_ok(201, bad.c_str(), measurement, session));
    }
    assert(!mock_ack_ok(201, "{}", measurement, session));
    assert(!mock_ack_ok(201, ack, session, measurement));
    assert(!mock_ack_ok(201, nullptr, measurement, session));

    // Before first transmission, expiry/cancel/change/ticket loss MUST abort.
    for (unsigned fault = 0; fault < 4; ++fault) {
        SessionFence guarded;
        assert(guarded.observe(snapshot, 100, expiry - 60000));
        MockUpload unsent;
        assert(unsent.start(guarded, measurement, 100, expiry - 60000));
        if (fault == 0) guarded.clear();
        if (fault == 1) { PollSnapshot idle; idle.state = PollState::Idle; guarded.observe(idle, 101, expiry - 59999); }
        if (fault == 2) { PollSnapshot other = snapshot; other.id[0] = '4'; guarded.observe(other, 101, expiry - 59999); }
        assert(!unsent.authorize_send(guarded, fault == 3 ? 60100U : 101U, fault == 3 ? expiry : expiry - 59999));
        assert(unsent.state() == MockState::Held && unsent.pending());
    }
    MockUpload exhausted;
    assert(exhausted.start(fence, measurement, 100, expiry - 60000));
    std::uint32_t now = 100;
    for (unsigned attempt = 1; attempt <= 4; ++attempt) {
        assert(exhausted.authorize_send(fence, now, expiry - 60000));
        const auto result = exhausted.result(-11, "", now);
        assert(result == (attempt < 4 ? MockResult::Retry : MockResult::Held));
        if (attempt < 4) now += exhausted.wait_ms();
        assert(std::string(exhausted.payload()) == original);
    }
    MockCommand command;
    bool emitted = false;
    for (char c : std::string("notMOCK\nMOCK ") + session + "\n") emitted = command.feed(static_cast<std::uint8_t>(c), 0) || emitted;
    assert(emitted);
    assert(std::strcmp(command.session_id(), session) == 0);
    for (char c : std::string("MOCKextra\n")) assert(!command.feed(static_cast<std::uint8_t>(c), 0));
    assert(!command.feed('M', 1));
    assert(!command.feed('O', 2002));
    assert(!command.feed('C', 2002));
    assert(!command.feed('K', 2002));
    assert(!command.feed('\n', 2002));
    std::cout << "PASS: explicit mock payload/ack, immutable retries,200/201,session loss/expiry/cancel/change,terminal errors,exhaustion and bounded command (fixtures)\n";
}
