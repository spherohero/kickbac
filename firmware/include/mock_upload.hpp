#ifndef KICKBAC_MOCK_UPLOAD_HPP
#define KICKBAC_MOCK_UPLOAD_HPP
#include <cstdio>
#include "network_runtime.hpp"
#include "session_safety.hpp"

namespace kickbac {

// Legacy simulator contract: these constants are SYNTHETIC, never sensor output.
inline bool mock_ack_ok(int status, const char* body, const char* measurement, const char* session) {
    if ((status != 200 && status != 201) || body == nullptr || std::strlen(body) > 768 ||
        !uuid_text(measurement) || !uuid_text(session)) return false;
    StaticJsonDocument<1536> document;
    if (deserializeJson(document, body, DeserializationOption::NestingLimit(4))) return false;
    const JsonObjectConst root = document.as<JsonObjectConst>();
    if (root.size() != 9 || root["id"] != measurement || root["session_id"] != session ||
        root["device_id"] != "kb-demo-01" || root["source"] != "simulator" ||
        !root["breath_duration_ms"].is<int>() || root["breath_duration_ms"].as<int>() != 2500 ||
        !root.containsKey("measured_at") || !root["measured_at"].isNull() ||
        !root.containsKey("estimated_bac_percent") || !root["estimated_bac_percent"].isNull() ||
        !root["received_at"].is<const char*>()) return false;
    const JsonObjectConst raw = root["raw"].as<JsonObjectConst>();
    std::int64_t received = 0;
    return raw.size() == 3 && raw["sensor"] == "mq3" && raw["unit"] == "adc_counts" &&
           raw["value"].is<int>() && raw["value"].as<int>() == 1200 &&
           utc_epoch_ms(root["received_at"].as<const char*>(), received);
}

enum class MockState { Empty, Queued, InFlight, RetryWait, Accepted, Held };
enum class MockResult { Accepted, Retry, Held };

// One RAM-only immutable transaction. Never automatically begins from a poll.
// Once attempted, an unknown outcome can replay ONLY original bytes, even if the
// session is now terminal; backend idempotency decides acceptance/replay/errors.
// Reset loses this record: do not reset while unknown outcome is unresolved.
class MockUpload {
public:
    bool can_start(const char* session) const {
        return !pending_.ready() && (state_ == MockState::Empty || state_ == MockState::Accepted) &&
               uuid_text(session) && std::strcmp(session_, session) != 0;
    }
    bool start(SessionFence& fence, const char* id, std::uint32_t now, std::int64_t utc) {
        SessionTicket ticket;
        if (!uuid_text(id) || !fence.begin(ticket, now, utc) || !can_start(ticket.id)) return false;
        char payload[512] = {};
        const int size = std::snprintf(payload, sizeof(payload),
            "{\"measurement_id\":\"%s\",\"session_id\":\"%s\",\"raw\":{\"sensor\":\"mq3\",\"value\":1200,\"unit\":\"adc_counts\"},"
            "\"breath_duration_ms\":2500,\"source\":\"simulator\",\"measured_at\":null}", id, ticket.id);
        if (size <= 0 || static_cast<std::size_t>(size) >= sizeof(payload) || !pending_.seal(ticket.id, id, payload)) return false;
        ticket_ = ticket;
        std::strcpy(measurement_, id);
        std::strcpy(session_, ticket.id);
        attempts_ = 0;
        state_ = MockState::Queued;
        return true;
    }
    bool due(std::uint32_t now) const {
        return state_ == MockState::Queued || (state_ == MockState::RetryWait && now - retry_at_ >= wait_ms_);
    }
    bool authorize_send(SessionFence& fence, std::uint32_t now, std::int64_t utc) {
        if (!due(now) || !pending_.ready()) return false;
        if (attempts_ == 0 && !fence.matches(ticket_, now, utc)) { hold(); return false; }
        ++attempts_;
        state_ = MockState::InFlight;
        return true;
    }
    MockResult result(int status, const char* body, std::uint32_t now) {
        if (attempts_ == 0 || !pending_.ready() || state_ != MockState::InFlight) return MockResult::Held;
        if (mock_ack_ok(status, body, measurement_, session_)) {
            pending_.acknowledge(status, measurement_, session_);
            state_ = MockState::Accepted;
            return MockResult::Accepted;
        }
        if (retryable_device_status(status) && attempts_ <= 3) {
            wait_ms_ = 2000U << (attempts_ - 1);
            retry_at_ = now;
            state_ = MockState::RetryWait;
            return MockResult::Retry;
        }
        hold();
        return MockResult::Held;
    }
    void hold() { if (pending_.ready()) state_ = MockState::Held; }
    MockState state() const { return state_; }
    bool pending() const { return pending_.ready(); }
    const char* payload() const { return pending_.body(); }
    const char* measurement_id() const { return measurement_; }
    const char* session_id() const { return session_; }
    unsigned attempts() const { return attempts_; }
    std::uint32_t wait_ms() const { return wait_ms_; }
private:
    FrozenUpload pending_;
    SessionTicket ticket_;
    MockState state_ = MockState::Empty;
    char measurement_[37] = {};
    char session_[37] = {};
    unsigned attempts_ = 0;
    std::uint32_t retry_at_ = 0;
    std::uint32_t wait_ms_ = 0;
};

// Exact bounded line, no substring matches. Stale partial lines are discarded
// through their newline so a late tail cannot trigger a later user's session.
class MockCommand {
public:
    bool feed(std::uint8_t byte, std::uint32_t now) {
        if (position_ != 0 && now - last_ > 1000U) invalid_ = true;
        last_ = now;
        if (byte == '\n') {
            buffer_[position_] = '\0';
            const bool accepted = !invalid_ && position_ == 41 &&
                std::strncmp(buffer_, "MOCK ", 5) == 0 && uuid_text(buffer_ + 5);
            if (accepted) std::strcpy(session_, buffer_ + 5);
            position_ = 0; invalid_ = false;
            return accepted;
        }
        if (position_ < 41) buffer_[position_++] = static_cast<char>(byte);
        else invalid_ = true;
        return false;
    }
    const char* session_id() const { return session_; }
private:
    char buffer_[42] = {};
    char session_[37] = {};
    unsigned position_ = 0;
    bool invalid_ = false;
    std::uint32_t last_ = 0;
};
} // namespace kickbac
#endif
