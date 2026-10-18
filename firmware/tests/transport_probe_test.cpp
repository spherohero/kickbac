// Synthetic clock/socket fixtures. No real network, credentials or USB.
#include <cassert>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <vector>
#include "transport_probe.hpp"

struct Socket {
    int answer = 0;
    unsigned connects = 0;
    unsigned stops = 0;
    int connect(const char* host, std::uint16_t port, std::int32_t timeout) {
        assert(std::strcmp(host, "api.kickbac.vodka") == 0);
        assert(port == 443 && timeout == 7000);
        ++connects;
        return answer;
    }
    void stop() { ++stops; }
    // Deliberately no write()/print() method: probe cannot send application bytes.
};

int main() {
    for (const int answer : {0, 1}) {
        Socket socket;
        socket.answer = answer;
        unsigned clocks = 0;
        std::vector<kickbac::TransportBoundary> events;
        const auto clock = [&]() {
            kickbac::TransportStamp stamp;
            stamp.monotonic_ms = clocks++ == 0 ? UINT32_MAX - 999U : 6000U;
            stamp.utc_s = 1792300000;
            return stamp;
        };
        const auto report = [&](const kickbac::TransportBoundary& event) { events.push_back(event); };
        assert(kickbac::tcp_connect_probe(socket, clock, report) == answer);
        assert(socket.connects == 1 && socket.stops == 1 && clocks == 2);
        assert(events.size() == 2 && events[0].begin && !events[1].begin);
        assert(events[0].duration_ms == 0 && events[1].duration_ms == 7000);
        assert(events[1].status == answer && events[1].stamp.utc_s == 1792300000);
    }
    for (unsigned attempt = 1; attempt <= 4; ++attempt) {
        for (int status : {-11, -1, 0, 200, 302, 401, 502}) {
            assert(kickbac::should_probe_tcp(attempt, status) == (attempt == 2 && status <= 0));
        }
    }
    assert(kickbac::diagnostic_utc_seconds(0) == 0);
    assert(kickbac::diagnostic_utc_seconds(-1) == 0);
    assert(kickbac::diagnostic_utc_seconds(1792300000) == 1792300000);
    std::cout << "PASS: single bounded TCP443 connect/close, no payload interface, timestamp/duration wrap and reconnect-only policy (synthetic fixtures)\n";
}
