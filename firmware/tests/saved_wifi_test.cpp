// Synthetic saved network/storage/radio clocks; NO real Wi-Fi credentials or USB.
#include <cassert>
#include <cstring>
#include <iostream>
#include <vector>
#include "saved_wifi.hpp"

void feed(kickbac::WifiFrameParser& parser, bool save, const char* name, const char* password) {
    std::vector<std::uint8_t> bytes{'K','B',static_cast<std::uint8_t>(save ? 'S' : 'W'),'1',
        static_cast<std::uint8_t>(std::strlen(name)),static_cast<std::uint8_t>(std::strlen(password))};
    bytes.insert(bytes.end(), name, name + std::strlen(name));
    bytes.insert(bytes.end(), password, password + std::strlen(password));
    for (auto byte : bytes) parser.feed(byte, 0);
    assert(parser.ready() && parser.save_requested() == save);
}

int main() {
    using namespace kickbac;
    WifiFrameParser original;
    feed(original, true, "fixture-one", "fixture-password");
    SavedWifiRecord record;
    assert(record.encode(original));
    std::vector<std::uint8_t> persistent(record.bytes(), record.bytes() + record.size());
    original.clear();
    WifiFrameParser cold_boot;
    SavedWifiRecord loaded;
    assert(loaded.assign(persistent.data(), persistent.size()) && loaded.decode(cold_boot));
    assert(!cold_boot.save_requested()); // restore never causes another write
    assert(std::strcmp(cold_boot.ssid(), "fixture-one") == 0);
    struct Radio {
        unsigned calls = 0;
        int begin(const char* name, const char* password) {
            ++calls;
            assert(std::strcmp(name, "fixture-one") == 0 && std::strcmp(password, "fixture-password") == 0);
            return calls == 1 ? 0 : 1; // first SDK config installation failed
        }
    } radio;
    WifiRamProfile active;
    assert(!active.begin(radio));
    assert(active.assign(cold_boot));
    cold_boot.clear();
    assert(active.begin(radio) && active.begin(radio) && radio.calls == 2);
    assert(active.matches("fixture-one") && !active.matches("previous-sdk-profile"));
    assert(loaded.decode(cold_boot));
    assert(std::strcmp(cold_boot.password(), "fixture-password") == 0);
    for (std::size_t pos = 0; pos < persistent.size(); ++pos) {
        auto corrupt = persistent;
        corrupt[pos] ^= 1U;
        SavedWifiRecord bad;
        WifiFrameParser rejected;
        assert(!bad.assign(corrupt.data(), corrupt.size()) || !bad.decode(rejected));
        assert(!rejected.ready());
    }
    assert(!loaded.assign(persistent.data(), persistent.size() - 1));
    feed(original, false, "fixture-ram", "fixture-password");
    assert(!record.encode(original)); // no opt-in -> no persistent record
    original.clear();
    feed(original, true, "fixture-replacement", "other-fixture-password");
    assert(record.encode(original));
    persistent.assign(record.bytes(), record.bytes() + record.size());
    cold_boot.clear();
    assert(loaded.assign(persistent.data(), persistent.size()) && loaded.decode(cold_boot));
    assert(std::strcmp(cold_boot.ssid(), "fixture-replacement") == 0); // one slot replaces, no fallback list
    loaded.clear();
    for (std::size_t pos = 0; pos < SavedWifiRecord::capacity; ++pos) assert(loaded.bytes()[pos] == 0);

    WifiReconnect loop;
    assert(!loop.begin_due(0)); // absent record waits for private provisioning
    loop.configure(UINT32_MAX - 999U);
    auto now = UINT32_MAX - 999U;
    assert(loop.begin_due(now));
    loop.started(now);
    assert(!loop.begin_due(now) && !loop.association_expired(now + 29999));
    assert(loop.association_expired(now + 30000));
    now += 30000;
    std::uint32_t previous_max = 0;
    for (unsigned failure = 0; failure < 1000; ++failure) {
        loop.failure(now, failure * 17U);
        assert(loop.wait_ms() >= 1000 && loop.wait_ms() <= 60000);
        assert(!loop.begin_due(now) && !loop.begin_due(now + loop.wait_ms() - 1));
        now += loop.wait_ms();
        assert(loop.begin_due(now));
        loop.started(now);
        if (failure > 10) assert(loop.attempts() > 10); // no finite give-up
        if (loop.wait_ms() > previous_max) previous_max = loop.wait_ms();
        now += 30000;
    }
    assert(previous_max <= 60000);
    loop.joined();
    assert(loop.validating());
    loop.online();
    assert(loop.is_online() && !loop.begin_due(now));
    loop.failure(now, 0); // hotspot lost -> retry same configuration
    assert(!loop.is_online() && loop.wait_ms() == 1000);
    now += loop.wait_ms();
    assert(loop.begin_due(now));
    loop.started(now);
    loop.joined();
    loop.online();
    assert(loop.is_online());
    WifiSetupCommand setup;
    bool requested = false;
    for (char byte : "WIFI_SETUP\n") requested = setup.feed(static_cast<std::uint8_t>(byte)) || requested;
    assert(requested);
    std::cout << "PASS: opt-in single saved network, cold-boot decode/replacement/corruption/clearing, bounded30s attempts and lifetime capped-jitter reconnect/wrap (synthetic)\n";
}
