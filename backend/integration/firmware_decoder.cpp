// Host-only bridge: decode actual loopback API responses with firmware code.
// No Wi-Fi, USB, GPIO, credentials or replacement protocol implementation.
#include <cstdlib>
#include <iostream>
#include <iterator>
#include <string>

#include "device_diagnostic.hpp"

int main(int argc, char** argv) {
    if (argc != 3) return 2;
    const int status = std::atoi(argv[2]);
    const std::string body((std::istreambuf_iterator<char>(std::cin)),
                           std::istreambuf_iterator<char>());
    if (body.size() > 768 || body.find('\0') != std::string::npos) {
        std::cout << "INVALID\n";
        return 0;
    }
    const std::string mode(argv[1]);
    if (mode == "heartbeat") {
        char seen[40] = {};
        std::cout << (kickbac::heartbeat_response_ok(status, body.c_str(), seen)
                          ? "HEARTBEAT_OK" : "INVALID") << '\n';
        return 0;
    }
    if (mode != "poll") return 2;
    switch (kickbac::poll_response(status, body.c_str())) {
        case kickbac::PollState::Idle: std::cout << "IDLE\n"; break;
        case kickbac::PollState::Armed: std::cout << "ARMED\n"; break;
        case kickbac::PollState::Sampling: std::cout << "SAMPLING\n"; break;
        case kickbac::PollState::Invalid: std::cout << "INVALID\n"; break;
    }
}
