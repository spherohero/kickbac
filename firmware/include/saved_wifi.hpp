#ifndef KICKBAC_SAVED_WIFI_HPP
#define KICKBAC_SAVED_WIFI_HPP
#include "wifi_diagnostic.hpp"

namespace kickbac {
// Exactly one RAM profile. Always retry explicit config, never an old SDK slot.
class WifiRamProfile {
public:
    ~WifiRamProfile() { clear(); }
    void clear() {
        volatile char* name = ssid_; volatile char* secret = password_;
        for (std::size_t i = 0; i < sizeof(ssid_); ++i) name[i] = 0;
        for (std::size_t i = 0; i < sizeof(password_); ++i) secret[i] = 0;
        ready_ = false;
    }
    bool assign(const WifiFrameParser& frame) {
        if (!frame.ready()) return false;
        clear();
        std::strcpy(ssid_, frame.ssid()); std::strcpy(password_, frame.password());
        ready_ = true;
        return true;
    }
    template <typename Radio> bool begin(Radio& radio) const {
        if (!ready_) return false;
        radio.begin(ssid_, password_);
        return true; // actual association/DHCP is independently verified
    }
    bool matches(const char* ssid) const { return ready_ && ssid != nullptr && std::strcmp(ssid_, ssid) == 0; }
private:
    char ssid_[33] = {};
    char password_[64] = {};
    bool ready_ = false;
};

class WifiSetupCommand {
public:
    bool feed(std::uint8_t byte) {
        if (byte == '\n') {
            const bool accepted = !invalid_ && position_ == 10;
            clear(); return accepted;
        }
        const char command[] = "WIFI_SETUP";
        if (position_ >= 10 || byte != static_cast<std::uint8_t>(command[position_])) invalid_ = true;
        if (position_ < 11) ++position_;
        return false;
    }
    void clear() { position_ = 0; invalid_ = false; }
private:
    unsigned position_ = 0;
    bool invalid_ = false;
};

// Versioned integrity-checked blob. CRC is NOT encryption/access control.
// Caller writes exactly ONE NVS key only after explicit KBS1 opt-in.
class SavedWifiRecord {
public:
    static constexpr std::size_t capacity = 4U + 2U + 32U + 63U + 4U;
    ~SavedWifiRecord() { clear(); }
    void clear() {
        volatile std::uint8_t* data = bytes_;
        for (std::size_t i = 0; i < capacity; ++i) data[i] = 0;
        size_ = 0;
    }
    const std::uint8_t* bytes() const { return bytes_; }
    std::size_t size() const { return size_; }
    bool encode(const WifiFrameParser& profile) {
        clear();
        if (!profile.ready() || !profile.save_requested()) return false;
        const auto ssid = std::strlen(profile.ssid()), password = std::strlen(profile.password());
        bytes_[0] = 'K'; bytes_[1] = 'B'; bytes_[2] = 'N'; bytes_[3] = '1';
        bytes_[4] = static_cast<std::uint8_t>(ssid);
        bytes_[5] = static_cast<std::uint8_t>(password);
        std::memcpy(bytes_ + 6, profile.ssid(), ssid);
        std::memcpy(bytes_ + 6 + ssid, profile.password(), password);
        size_ = 6 + ssid + password + 4;
        const std::uint32_t crc = checksum(bytes_, size_ - 4);
        for (unsigned i = 0; i < 4; ++i) bytes_[size_ - 4 + i] = static_cast<std::uint8_t>(crc >> (i * 8U));
        return true;
    }
    bool assign(const std::uint8_t* input, std::size_t count) {
        clear();
        if (input == nullptr || count < 6U + 1U + 8U + 4U || count > capacity ||
            input[0] != 'K' || input[1] != 'B' || input[2] != 'N' || input[3] != '1' ||
            input[4] < 1 || input[4] > 32 || input[5] < 8 || input[5] > 63 ||
            count != 6U + input[4] + input[5] + 4U) return false;
        const std::uint32_t crc = checksum(input, count - 4);
        for (unsigned i = 0; i < 4; ++i)
            if (input[count - 4 + i] != static_cast<std::uint8_t>(crc >> (i * 8U))) return false;
        std::memcpy(bytes_, input, count);
        size_ = count;
        return true;
    }
    bool decode(WifiFrameParser& profile) const {
        profile.clear();
        if (size_ == 0) return false;
        const std::uint8_t magic[] = {'K','B','W','1'}; // restore does NOT opt into another write
        for (auto byte : magic) profile.feed(byte, 0);
        for (std::size_t i = 4; i < size_ - 4; ++i) profile.feed(bytes_[i], 0);
        if (!profile.ready()) { profile.clear(); return false; }
        return true;
    }
private:
    static std::uint32_t checksum(const std::uint8_t* bytes, std::size_t count) {
        std::uint32_t crc = UINT32_MAX;
        for (std::size_t i = 0; i < count; ++i) {
            crc ^= bytes[i];
            for (unsigned bit = 0; bit < 8; ++bit)
                crc = (crc >> 1U) ^ ((crc & 1U) ? 0xedb88320U : 0U);
        }
        return ~crc;
    }
    std::uint8_t bytes_[capacity] = {};
    std::size_t size_ = 0;
};

// Lifetime policy: one configured network; finite individual association attempts,
// exponential equal-jitter backoff bounded1..60s, NEVER a retry-count give-up.
class WifiReconnect {
public:
    void configure(std::uint32_t now) { configured_ = true; failures_ = 0; phase_ = Phase::Waiting; since_ = now; wait_ = 0; }
    bool configured() const { return configured_; }
    bool begin_due(std::uint32_t now) const { return configured_ && phase_ == Phase::Waiting && now - since_ >= wait_; }
    void started(std::uint32_t now) { phase_ = Phase::Connecting; since_ = now; if (attempts_ != UINT32_MAX) ++attempts_; }
    bool connecting() const { return phase_ == Phase::Connecting; }
    bool association_expired(std::uint32_t now) const { return connecting() && now - since_ >= 30000U; }
    void joined() { phase_ = Phase::Validating; }
    bool validating() const { return phase_ == Phase::Validating; }
    void online() { phase_ = Phase::Online; failures_ = 0; }
    bool is_online() const { return phase_ == Phase::Online; }
    void failure(std::uint32_t now, std::uint32_t random) {
        if (!configured_) return;
        if (failures_ < 6) ++failures_;
        const std::uint32_t ceiling = failures_ == 6 ? 60000U : (2000U << (failures_ - 1));
        wait_ = ceiling / 2U + random % (ceiling / 2U + 1U);
        since_ = now;
        phase_ = Phase::Waiting;
    }
    std::uint32_t wait_ms() const { return wait_; }
    std::uint32_t attempts() const { return attempts_; }
private:
    enum class Phase { Dormant, Waiting, Connecting, Validating, Online };
    bool configured_ = false;
    Phase phase_ = Phase::Dormant;
    unsigned failures_ = 0;
    std::uint32_t attempts_ = 0;
    std::uint32_t since_ = 0;
    std::uint32_t wait_ = 0;
};
} // namespace kickbac
#endif
