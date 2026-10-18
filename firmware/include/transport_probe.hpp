#ifndef KICKBAC_TRANSPORT_PROBE_HPP
#define KICKBAC_TRANSPORT_PROBE_HPP

#include <cstdint>

namespace kickbac {

struct TransportStamp {
    std::uint32_t monotonic_ms = 0;
    std::int64_t utc_s = 0; // actual whole UTC seconds; 0 means unavailable, not acquisition time
};
struct TransportBoundary {
    bool begin = true;
    TransportStamp stamp;
    int status = 0; // BEGIN status is a placeholder, not a response
    std::uint32_t duration_ms = 0;
};

inline std::int64_t diagnostic_utc_seconds(std::int64_t seconds) {
    return seconds > 0 ? seconds : 0;
}

inline bool should_probe_tcp(unsigned attempt, int https_status) {
    return attempt == 2 && https_status <= 0;
}

// ONE separate TCP control experiment after the first failed reconnect HTTPS.
// Uses no bearer, emits no address, and sends ZERO application payload bytes.
// TCP success here does not prove the PRECEDING HTTPS connection reached TCP/TLS.
// connect(host) may do DNS internally; duration includes that separate resolution.
template <typename Client, typename Clock, typename Report>
int tcp_connect_probe(Client& client, Clock clock, Report report) {
    TransportBoundary boundary;
    boundary.stamp = clock();
    const std::uint32_t start = boundary.stamp.monotonic_ms;
    report(boundary);
    const int result = client.connect("api.kickbac.vodka", 443, 7000);
    boundary.stamp = clock();
    boundary.begin = false;
    boundary.status = result;
    boundary.duration_ms = boundary.stamp.monotonic_ms - start;
    client.stop();
    report(boundary);
    return result;
}

} // namespace kickbac
#endif
