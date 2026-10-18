#ifndef KICKBAC_NETWORK_RUNTIME_HPP
#define KICKBAC_NETWORK_RUNTIME_HPP
#include <cstdint>

namespace kickbac {
// Called ONLY after initial association/DNS/SNTP/trusted health all passed.
// Operational boot must never deliberately break that connection.
template <typename ReconnectTest>
bool finish_network_boot(bool operational, ReconnectTest reconnect_test) {
    return operational || reconnect_test();
}

inline bool retryable_device_status(int status) {
    // -2/-3 are this adapter's malformed-length/body sentinels: terminal.
    // Other recognized negative HTTPClient transport failures retain TLS checks.
    return status == -1 || (status <= -4 && status >= -11) ||
           status == 500 || status == 502 || status == 503 || status == 504;
}

// No request, credential or session is stored here. Retry the SAME failed
// heartbeat/poll endpoint only; at most3 retries, completion-relative2/4/8s waits.
class DeviceRecovery {
public:
    bool schedule(bool heartbeat, std::uint32_t now) {
        if (count_ == 3) return false;
        ++count_;
        heartbeat_ = heartbeat;
        since_ = now;
        wait_ = 2000U << (count_ - 1);
        active_ = true;
        return true;
    }
    bool due(std::uint32_t now) const { return active_ && now - since_ >= wait_; }
    bool active() const { return active_; }
    bool heartbeat() const { return heartbeat_; }
    unsigned count() const { return count_; }
    std::uint32_t wait_ms() const { return wait_; }
    void clear() { active_ = false; count_ = 0; }
private:
    bool active_ = false;
    bool heartbeat_ = false;
    unsigned count_ = 0;
    std::uint32_t since_ = 0;
    std::uint32_t wait_ = 0;
};
} // namespace kickbac
#endif
