#ifndef KICKBAC_WIFI_DIAGNOSTIC_HPP
#define KICKBAC_WIFI_DIAGNOSTIC_HPP

#include <cstddef>
#include <cstdint>
#include <cstring>

namespace kickbac {

// Local USB provisioning only. Never echo frame contents or persist credentials.
class WifiFrameParser {
public:
    ~WifiFrameParser() { clear(); }

    bool ready() const { return ready_; }
    const char* ssid() const { return ssid_; }
    const char* password() const { return password_; }

    bool expire(std::uint32_t now) {
        if (!ready_ && position_ != 0 && now - last_byte_at_ > 3000U) {
            clear();
            return true;
        }
        return false;
    }

    void clear() {
        volatile char* s = ssid_;
        volatile char* p = password_;
        for (std::size_t i = 0; i < sizeof(ssid_); ++i) s[i] = 0;
        for (std::size_t i = 0; i < sizeof(password_); ++i) p[i] = 0;
        position_ = 0;
        ssid_length_ = 0;
        password_length_ = 0;
        last_byte_at_ = 0;
        ready_ = false;
    }

    bool feed(std::uint8_t value, std::uint32_t now) {
        if (ready_) return false;
        expire(now);
        last_byte_at_ = now;
        static const char magic[] = "KBW1";
        if (position_ < 4) {
            position_ = value == static_cast<std::uint8_t>(magic[position_])
                            ? position_ + 1 : (value == 'K' ? 1U : 0U);
            return false;
        }
        if (position_ == 4) {
            if (value < 1 || value > 32) { clear(); return false; }
            ssid_length_ = value;
        } else if (position_ == 5) {
            if (value < 8 || value > 63) { clear(); return false; }
            password_length_ = value;
        } else {
            const std::size_t payload = position_ - 6;
            if (value == 0 || (payload >= ssid_length_ && (value < 32 || value > 126))) {
                clear();
                return false;
            }
            if (payload < ssid_length_) ssid_[payload] = static_cast<char>(value);
            else password_[payload - ssid_length_] = static_cast<char>(value);
        }
        ++position_;
        ready_ = position_ == 6U + ssid_length_ + password_length_;
        return ready_;
    }

private:
    char ssid_[33] = {};
    char password_[64] = {};
    std::size_t position_ = 0;
    std::uint8_t ssid_length_ = 0;
    std::uint8_t password_length_ = 0;
    std::uint32_t last_byte_at_ = 0;
    bool ready_ = false;
};

inline bool health_response_ok(int status, const char* body) {
    return status == 200 && body != nullptr && std::strcmp(body, "{\"status\":\"ok\"}") == 0;
}

// Public read-only reconnect diagnostic only, not authenticated request retries.
// The callback must repeat the SAME trusted HTTPS/health validation each time.
template <typename Check, typename Wait>
bool reconnect_health_probe(Check check, Wait wait) {
    for (unsigned attempt = 2; attempt <= 4; ++attempt) {
        if (attempt != 2) wait();
        if (check(attempt)) return true;
    }
    return false;
}

}  // namespace kickbac
#endif
