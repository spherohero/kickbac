#ifndef KICKBAC_DEVICE_DIAGNOSTIC_HPP
#define KICKBAC_DEVICE_DIAGNOSTIC_HPP

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <ArduinoJson.h>

namespace kickbac {

enum class PollState { Invalid, Idle, Armed, Sampling };

inline bool utc_timestamp(const char* text) {
    if (text == nullptr) return false;
    const std::size_t size = std::strlen(text);
    if (size < 20 || size >= 40) return false;
    for (std::size_t i = 0; i < 19; ++i) {
        const char separator = i == 4 || i == 7 ? '-' :
                               (i == 10 ? 'T' : (i == 13 || i == 16 ? ':' : '\0'));
        if (separator ? text[i] != separator : (text[i] < '0' || text[i] > '9')) return false;
    }
    std::size_t suffix = 19;
    if (text[suffix] == '.') {
        const std::size_t first_digit = ++suffix;
        while (text[suffix] >= '0' && text[suffix] <= '9') ++suffix;
        if (suffix == first_digit || suffix - first_digit > 6) return false;
    }
    return std::strcmp(text + suffix, "Z") == 0 || std::strcmp(text + suffix, "+00:00") == 0;
}

// Identity- and type-bound diagnostic validation. Never print response bodies.
inline bool heartbeat_response_ok(int status, const char* body, char (&seen)[40]) {
    seen[0] = '\0';
    if (status != 200 || body == nullptr || std::strlen(body) > 768) return false;
    StaticJsonDocument<1024> document;
    if (deserializeJson(document, body, DeserializationOption::NestingLimit(3))) return false;
    const JsonObjectConst root = document.as<JsonObjectConst>();
    if (root.size() != 3 || root["device_id"] != "kb-demo-01" ||
        !root["online"].is<bool>() || !root["online"].as<bool>() ||
        !root["last_seen_at"].is<const char*>()) return false;
    const char* timestamp = root["last_seen_at"].as<const char*>();
    if (!utc_timestamp(timestamp)) return false;
    std::strcpy(seen, timestamp);
    return true;
}

inline PollState poll_response(int status, const char* body) {
    if (status != 200 || body == nullptr || std::strlen(body) > 768) return PollState::Invalid;
    StaticJsonDocument<1024> document;
    if (deserializeJson(document, body, DeserializationOption::NestingLimit(3))) return PollState::Invalid;
    const JsonObjectConst root = document.as<JsonObjectConst>();
    if (root.size() != 2 || root["device_id"] != "kb-demo-01" ||
        !root.containsKey("active_session")) return PollState::Invalid;
    if (root["active_session"].isNull()) return PollState::Idle;
    const JsonObjectConst active = root["active_session"].as<JsonObjectConst>();
    if (active.size() != 4 || active["device_id"] != "kb-demo-01" ||
        !active["id"].is<const char*>() || !active["expires_at"].is<const char*>()) return PollState::Invalid;
    const char* id = active["id"].as<const char*>();
    if (std::strlen(id) != 36) return PollState::Invalid;
    for (std::size_t i = 0; i < 36; ++i) {
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if (id[i] != '-') return PollState::Invalid;
        } else if (!((id[i] >= '0' && id[i] <= '9') || (id[i] >= 'a' && id[i] <= 'f') ||
                     (id[i] >= 'A' && id[i] <= 'F'))) return PollState::Invalid;
    }
    if (!utc_timestamp(active["expires_at"].as<const char*>())) return PollState::Invalid;
    if (active["status"] == "ARMED") return PollState::Armed;
    if (active["status"] == "SAMPLING") return PollState::Sampling;
    return PollState::Invalid;
}

// Current operator-issued token_urlsafe(32) bearer, relayed over trusted local USB.
// Diagnostic transport only, not an API authentication/schema change.
class DeviceCredentialFrame {
public:
    ~DeviceCredentialFrame() { clear(); }
    bool ready() const { return ready_; }
    const char* token() const { return token_; }

    void clear() {
        volatile char* bytes = token_;
        for (std::size_t i = 0; i < sizeof(token_); ++i) bytes[i] = 0;
        position_ = 0;
        last_byte_at_ = 0;
        ready_ = false;
    }

    bool expire(std::uint32_t now) {
        if (!ready_ && position_ != 0 && now - last_byte_at_ > 3000U) {
            clear();
            return true;
        }
        return false;
    }

    bool feed(std::uint8_t value, std::uint32_t now) {
        if (ready_) return false;
        expire(now);
        last_byte_at_ = now;
        static const char magic[] = "KBD1";
        if (position_ < 4) {
            position_ = value == static_cast<std::uint8_t>(magic[position_])
                            ? position_ + 1 : (value == 'K' ? 1U : 0U);
            return false;
        }
        if (!((value >= 'A' && value <= 'Z') || (value >= 'a' && value <= 'z') ||
              (value >= '0' && value <= '9') || value == '_' || value == '-')) {
            clear();
            return false;
        }
        token_[position_ - 4] = static_cast<char>(value);
        ++position_;
        ready_ = position_ == 47;
        return ready_;
    }

private:
    char token_[44] = {};
    std::size_t position_ = 0;
    std::uint32_t last_byte_at_ = 0;
    bool ready_ = false;
};

}  // namespace kickbac
#endif
