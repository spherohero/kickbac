#ifndef KICKBAC_SAVED_AUTH_HPP
#define KICKBAC_SAVED_AUTH_HPP
#include "device_diagnostic.hpp"

namespace kickbac {
// CRC/version/device-id integrity only, NOT encryption or anti-tamper protection.
// This reusable bearer is recoverable by someone who can read unprotected NVS.
class DeviceAuthRecord {
public:
    static constexpr std::size_t identity_size = sizeof("kb-demo-01");
    static constexpr std::size_t capacity = 4U + identity_size + 43U + 4U;
    ~DeviceAuthRecord() { clear(); }
    void clear() {
        volatile std::uint8_t* bytes = data_;
        for (std::size_t i = 0; i < capacity; ++i) bytes[i] = 0;
    }
    const std::uint8_t* bytes() const { return data_; }
    bool encode(const DeviceCredentialFrame& frame) {
        clear();
        if (!frame.ready() || !frame.save_requested()) return false;
        std::memcpy(data_, "KBC1", 4);
        std::memcpy(data_ + 4, "kb-demo-01", identity_size);
        std::memcpy(data_ + 4 + identity_size, frame.token(), 43);
        const auto crc = checksum(data_, capacity - 4);
        for (unsigned i = 0; i < 4; ++i) data_[capacity - 4 + i] = static_cast<std::uint8_t>(crc >> (i * 8U));
        return true;
    }
    bool decode(const std::uint8_t* bytes, std::size_t size, DeviceCredentialFrame& frame) {
        frame.clear(); clear();
        if (bytes == nullptr || size != capacity || std::memcmp(bytes, "KBC1", 4) != 0 ||
            std::memcmp(bytes + 4, "kb-demo-01", identity_size) != 0) return false;
        const auto crc = checksum(bytes, capacity - 4);
        for (unsigned i = 0; i < 4; ++i)
            if (bytes[capacity - 4 + i] != static_cast<std::uint8_t>(crc >> (i * 8U))) return false;
        for (const char* p = "KBD1"; *p; ++p) frame.feed(static_cast<std::uint8_t>(*p), 0);
        for (std::size_t i = 0; i < 43; ++i) frame.feed(bytes[4 + identity_size + i], 0);
        if (!frame.ready()) { frame.clear(); return false; }
        return true; // decoded credential is RAM-only, never a new implicit save
    }
private:
    static std::uint32_t checksum(const std::uint8_t* bytes, std::size_t count) {
        std::uint32_t crc = UINT32_MAX;
        for (std::size_t i = 0; i < count; ++i) {
            crc ^= bytes[i];
            for (unsigned bit = 0; bit < 8; ++bit) crc = (crc >> 1U) ^ ((crc & 1U) ? 0xedb88320U : 0U);
        }
        return ~crc;
    }
    std::uint8_t data_[capacity] = {};
};

enum class SavedAuthState { Absent, Loaded, Invalid, Blocked };

template <typename Store>
SavedAuthState load_device_auth(Store& store, DeviceCredentialFrame& frame) {
    frame.clear();
    if (!store.begin("kickbac_auth", true)) return SavedAuthState::Absent;
    if (store.getBool("blocked", false)) { store.end(); return SavedAuthState::Blocked; }
    const std::size_t size = store.getBytesLength("credential");
    std::uint8_t bytes[DeviceAuthRecord::capacity] = {};
    DeviceAuthRecord record;
    const bool valid = size == sizeof(bytes) && store.getBytes("credential", bytes, sizeof(bytes)) == size &&
                       record.decode(bytes, size, frame);
    store.end();
    volatile std::uint8_t* secret = bytes;
    for (std::size_t i = 0; i < sizeof(bytes); ++i) secret[i] = 0;
    return valid ? SavedAuthState::Loaded : (size == 0 ? SavedAuthState::Absent : SavedAuthState::Invalid);
}

template <typename Store>
bool save_device_auth(Store& store, const DeviceCredentialFrame& frame) {
    DeviceAuthRecord record;
    if (!record.encode(frame) || !store.begin("kickbac_auth", false)) return false;
    // Fence interruption: never enable half-written/stale credentials after boot.
    bool ok = store.putBool("blocked", true) == 1 &&
              store.putBytes("credential", record.bytes(), DeviceAuthRecord::capacity) == DeviceAuthRecord::capacity;
    std::uint8_t readback[DeviceAuthRecord::capacity] = {};
    if (ok) ok = store.getBytesLength("credential") == sizeof(readback) &&
                 store.getBytes("credential", readback, sizeof(readback)) == sizeof(readback) &&
                 std::memcmp(readback, record.bytes(), sizeof(readback)) == 0;
    if (ok) ok = store.putBool("blocked", false) == 1;
    store.end();
    volatile std::uint8_t* secret = readback;
    for (std::size_t i = 0; i < sizeof(readback); ++i) secret[i] = 0;
    return ok;
}

template <typename Store>
bool block_saved_device_auth(Store& store) {
    if (!store.begin("kickbac_auth", false)) return false;
    const bool ok = store.putBool("blocked", true) == 1;
    store.end(); return ok;
}
} // namespace kickbac
#endif
