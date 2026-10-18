// Synthetic policy clocks and network actions; never a real Wi-Fi session.
#include <cassert>
#include <cstdint>
#include <iostream>
#include "network_runtime.hpp"

int main() {
    unsigned forced_disconnects = 0;
    assert(kickbac::finish_network_boot(true, [&]() { ++forced_disconnects; return false; }));
    assert(forced_disconnects == 0);
    assert(!kickbac::finish_network_boot(false, [&]() { ++forced_disconnects; return false; }));
    assert(forced_disconnects == 1);
    assert(kickbac::finish_network_boot(false, [&]() { ++forced_disconnects; return true; }));
    assert(forced_disconnects == 2);
    for (int status : {-1, -4, -5, -6, -7, -8, -9, -10, -11, 500, 502, 503, 504})
        assert(kickbac::retryable_device_status(status));
    for (int status : {-99, -3, -2, 0, 200, 301, 401, 403, 404, 409, 410, 422, 501, 505})
        assert(!kickbac::retryable_device_status(status));
    kickbac::DeviceRecovery recovery;
    std::uint32_t now = UINT32_MAX - 999U;
    for (unsigned index = 1; index <= 3; ++index) {
        assert(recovery.schedule(false, now));
        const std::uint32_t expected = 2000U << (index - 1);
        assert(recovery.active() && !recovery.heartbeat() && recovery.count() == index);
        assert(recovery.wait_ms() == expected && !recovery.due(now));
        assert(!recovery.due(now + expected - 1));
        now += expected;
        assert(recovery.due(now));
    }
    assert(!recovery.schedule(false, now));
    recovery.clear();
    assert(!recovery.active() && recovery.count() == 0);
    assert(recovery.schedule(true, now));
    assert(recovery.heartbeat() && recovery.count() == 1 && recovery.wait_ms() == 2000);
    std::cout << "PASS: operational boot skips forced reconnect; bounded2/4/8s device recovery, exact status classification and wrap (synthetic)\n";
}
