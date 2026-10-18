#include <Arduino.h>
#include <HTTPClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <esp_log.h>
#include <esp_sntp.h>
#include <esp_wifi.h>
#if defined(KICKBAC_OPERATIONAL_NETWORK)
#include <Preferences.h>
#include <esp_system.h>
#include <atomic>
#include "saved_wifi.hpp"
#endif

#include <cstdint>
#include "tls_root.hpp"
#include "network_runtime.hpp"
#include "wifi_diagnostic.hpp"
#if defined(KICKBAC_DEVICE_DIAGNOSTIC)
#include "device_probe.hpp"
#endif

#if !defined(ARDUINO_XIAO_ESP32S3) || !defined(KICKBAC_WIFI_DIAGNOSTIC)
#error "Use the confirmed XIAO ESP32-S3 Wi-Fi diagnostic target."
#endif

namespace {
kickbac::WifiFrameParser provisioning;
bool radio_ready = false;
bool scan_done = false;
bool network_proven = false;
std::uint32_t last_ready_at = 0;
#if defined(KICKBAC_OPERATIONAL_NETWORK)
kickbac::WifiReconnect wifi_reconnect;
kickbac::WifiRamProfile active_profile;
std::atomic<bool> link_loss_seen{false};
bool wifi_setup_window = false;
std::uint32_t wifi_setup_since = 0;
#endif

void scan_radio() {
    Serial.printf("probe_scan state=started ssids=not_logged\n");
    int count = WiFi.scanNetworks(true, false, false, 180);
    const auto started = millis();
    while (count == WIFI_SCAN_RUNNING && millis() - started < 15000U) {
        delay(20);
        count = WiFi.scanComplete();
    }
    if (count >= 0) {
        int strongest = -127;
        int strongest_channel = 0;
        for (int i = 0; i < count; ++i) {
            if (WiFi.RSSI(i) > strongest) {
                strongest = WiFi.RSSI(i);
                strongest_channel = WiFi.channel(i);
            }
        }
        Serial.printf("probe_scan networks=%d strongest_rssi_dbm=%d strongest_channel=%d\n",
                      count, strongest, strongest_channel);
    } else {
        esp_wifi_scan_stop();
        Serial.printf("probe_scan state=failed code=%d\n", count);
    }
    WiFi.scanDelete();
}

#if !defined(KICKBAC_OPERATIONAL_NETWORK)
bool wait_joined() {
    const auto started = millis();
    while (millis() - started < 30000U) {
        if (WiFi.status() == WL_CONNECTED && WiFi.localIP() != IPAddress(0U)) return true;
        delay(50);
    }
    return false;
}
#endif

bool resolve_backend() {
    IPAddress address;
    // The installed core bounds its DNS wait at 15 seconds.
    const bool ok = WiFi.hostByName("api.kickbac.vodka", address) == 1 && address != IPAddress(0U);
    Serial.printf("probe_dns ok=%d\n", ok ? 1 : 0);
    return ok;
}

bool sync_clock() {
    configTime(0, 0, "time.cloudflare.com", "pool.ntp.org", "time.google.com");
    const auto started = millis();
    while (millis() - started < 25000U) {
        if (sntp_get_sync_status() == SNTP_SYNC_STATUS_COMPLETED) {
            Serial.printf("probe_clock sntp_synced=1\n");
            return true;
        }
        delay(100);
    }
    Serial.printf("probe_clock sntp_synced=0 tls_skipped=1\n");
    return false;
}

bool check_https(unsigned attempt) {
    WiFiClientSecure tls;
    tls.setCACert(KICKBAC_ISRG_ROOT_X1);
    tls.setHandshakeTimeout(12);
    HTTPClient http;
    http.setConnectTimeout(7000);
    http.setTimeout(7000);
    http.setFollowRedirects(HTTPC_DISABLE_FOLLOW_REDIRECTS);
    http.setReuse(false);
    if (!http.begin(tls, "https://api.kickbac.vodka/health")) return false;
    const auto request_started = static_cast<std::uint32_t>(millis());
    const int status = http.GET();
    if (status <= 0) {
        char description[128] = {}; // SDK buffer only; NEVER print error text/config.
        const int code = tls.lastError(description, sizeof(description));
        Serial.printf("probe_https_error attempt=%u tls_code=%d duration_ms=%lu\n", attempt, code,
                      static_cast<unsigned long>(static_cast<std::uint32_t>(millis()) - request_started));
    }
    bool ok = false;
    // Fixed endpoint has a tiny Content-Length; never accept a captive portal or large body.
    if (status == 200 && http.getSize() > 0 && http.getSize() <= 64) {
        String body = http.getString();
        body.trim();
        ok = kickbac::health_response_ok(status, body.c_str());
    }
    Serial.printf("probe_https attempt=%u status=%d trusted_tls=%d health_ok=%d\n",
                  attempt, status, status > 0 ? 1 : 0, ok ? 1 : 0);
    http.end();
    return ok;
}

#if !defined(KICKBAC_OPERATIONAL_NETWORK)
void fail(const char* stage) {
    provisioning.clear();
    WiFi.disconnect(false, true);  // RAM config only; never provision into NVS.
    Serial.printf("CONNECTIVITY_FAIL stage=%s sensor=disabled uploads=disabled\n", stage);
}

bool deliberate_reconnect_test() {
    // Exercise one real software disconnection/reassociation, not a claimed power-cycle.
    if (!WiFi.disconnect(false, false)) { fail("disconnect_request"); return false; }
    const auto started = millis();
    while (WiFi.status() == WL_CONNECTED && millis() - started < 3000U) delay(20);
    if (WiFi.status() == WL_CONNECTED) { fail("disconnect_not_observed"); return false; }
    Serial.printf("probe_disconnect observed=1\n");
    WiFi.begin();  // Reuse the same RAM-only SDK network config.
    if (!wait_joined()) { fail("reassociation_or_dhcp"); return false; }
    Serial.printf("probe_wifi rejoined=1 dhcp=1 rssi_dbm=%d channel=%d\n", WiFi.RSSI(), WiFi.channel());
    if (!resolve_backend() || !kickbac::reconnect_health_probe(
            [](unsigned attempt) { return check_https(attempt); },
            []() { delay(1000); })) { fail("reconnect_https"); return false; }
    Serial.printf("CONNECTIVITY_PASS wifi=1 dhcp=1 dns=1 trusted_https=1 reconnect=1 sensor=disabled uploads=disabled\n");
    return true;
}
#endif

#if defined(KICKBAC_OPERATIONAL_NETWORK)
void schedule_wifi_retry() {
    network_proven = false;
    wifi_reconnect.failure(static_cast<std::uint32_t>(millis()), esp_random());
    Serial.printf("wifi_connect state=waiting wait_ms=%lu\n", static_cast<unsigned long>(wifi_reconnect.wait_ms()));
}

void configure_network() {
    if (!provisioning.ready()) return;
    device_network_lost();
    network_proven = false;
    wifi_setup_window = false;
    bool saved = false;
    if (provisioning.save_requested()) {
        kickbac::SavedWifiRecord record;
        Preferences preferences;
        if (record.encode(provisioning) && preferences.begin("kickbac_wifi", false)) {
            saved = preferences.putBytes("network", record.bytes(), record.size()) == record.size();
            preferences.end();
        }
        Serial.printf("wifi_saved state=%s\n", saved ? "stored" : "write_failed");
    }
    wifi_reconnect.configure(static_cast<std::uint32_t>(millis()));
    wifi_reconnect.started(static_cast<std::uint32_t>(millis()));
    link_loss_seen.store(false);
    active_profile.assign(provisioning);
    provisioning.clear();
    active_profile.begin(WiFi); // retain exact profile even if SDK installation failed
    Serial.printf("wifi_config state=accepted saved=%d\n", saved ? 1 : 0);
    Serial.printf("wifi_connect state=started attempt=%lu timeout_ms=30000\n", static_cast<unsigned long>(wifi_reconnect.attempts()));
}

void load_saved_network() {
    Preferences preferences;
    if (!preferences.begin("kickbac_wifi", true)) { Serial.printf("wifi_saved state=absent\n"); return; }
    const std::size_t count = preferences.getBytesLength("network");
    std::uint8_t bytes[kickbac::SavedWifiRecord::capacity] = {};
    bool valid = false;
    kickbac::SavedWifiRecord record;
    if (count > 0 && count <= sizeof(bytes) && preferences.getBytes("network", bytes, count) == count)
        valid = record.assign(bytes, count) && record.decode(provisioning);
    preferences.end();
    volatile std::uint8_t* secret = bytes;
    for (std::size_t i = 0; i < sizeof(bytes); ++i) secret[i] = 0;
    Serial.printf("wifi_saved state=%s\n", valid ? "loaded" : (count == 0 ? "absent" : "invalid"));
    if (valid) configure_network(); // loaded profile is KBW1, never rewrites flash
}

void service_wifi_network() {
    const auto now = static_cast<std::uint32_t>(millis());
    if (device_take_wifi_setup()) {
        device_network_lost();
        network_proven = false;
        wifi_setup_window = true;
        wifi_setup_since = now;
        provisioning.clear();
        last_ready_at = now - 3000U;
    }
    if (wifi_setup_window) {
        if (now - wifi_setup_since < 30000U) return;
        wifi_setup_window = false;
        schedule_wifi_retry();
    }
    const bool disconnected_event = link_loss_seen.exchange(false);
    const bool connected = WiFi.status() == WL_CONNECTED && WiFi.localIP() != IPAddress(0U) &&
                           active_profile.matches(WiFi.SSID().c_str());
    if (network_proven && (disconnected_event || !connected)) {
        device_network_lost();
        Serial.printf("wifi_link state=lost acquisition=invalidated\n");
        schedule_wifi_retry();
        return;
    }
    if (wifi_reconnect.begin_due(now)) {
        if (connected) wifi_reconnect.joined(); // revalidate TLS without breaking a good association
        else {
            wifi_reconnect.started(now);
            active_profile.begin(WiFi); // always explicit single config, no old-SDK fallback
            Serial.printf("wifi_connect state=started attempt=%lu timeout_ms=30000\n", static_cast<unsigned long>(wifi_reconnect.attempts()));
        }
    }
    if (wifi_reconnect.connecting()) {
        if (connected) wifi_reconnect.joined();
        else if (wifi_reconnect.association_expired(now)) {
            WiFi.disconnect(false, false); // end this attempt, retain one RAM profile
            schedule_wifi_retry();
            return;
        }
    }
    if (wifi_reconnect.validating()) {
        Serial.printf("wifi_connect state=joined attempt=%lu\n", static_cast<unsigned long>(wifi_reconnect.attempts()));
        Serial.printf("probe_wifi joined=1 dhcp=1 rssi_dbm=%d channel=%d\n", WiFi.RSSI(), WiFi.channel());
        if (!resolve_backend() || !sync_clock() || !check_https(1) ||
            link_loss_seen.load() || WiFi.status() != WL_CONNECTED) {
            device_network_lost();
            schedule_wifi_retry();
            return;
        }
        wifi_reconnect.online();
        network_proven = true;
        Serial.printf("NETWORK_READY wifi=1 dhcp=1 dns=1 trusted_https=1 reconnect_test=skipped sensor=disabled uploads=disabled\n");
    }
}
#endif

void run_probe() {
#if defined(KICKBAC_OPERATIONAL_NETWORK)
    configure_network();
#else
    Serial.printf("probe_join state=started credentials=ram_only\n");
    WiFi.begin(provisioning.ssid(), provisioning.password());
    provisioning.clear();
    if (!wait_joined()) { fail("association_or_dhcp"); return; }
    Serial.printf("probe_wifi joined=1 dhcp=1 rssi_dbm=%d channel=%d\n", WiFi.RSSI(), WiFi.channel());
    if (!resolve_backend()) { fail("dns"); return; }
    if (!sync_clock()) { fail("time_sync"); return; }
    if (!check_https(1)) { fail("https"); return; }
#if defined(KICKBAC_OPERATIONAL_NETWORK)
    const bool operational = true;
#else
    const bool operational = false;
#endif
    network_proven = kickbac::finish_network_boot(operational, deliberate_reconnect_test);
    if (operational && network_proven) {
        Serial.printf("NETWORK_READY wifi=1 dhcp=1 dns=1 trusted_https=1 reconnect_test=skipped sensor=disabled uploads=disabled\n");
    }
#endif
}
}  // namespace

void setup() {
    Serial.begin(115200);
    esp_log_level_set("wifi", ESP_LOG_NONE);
    WiFi.persistent(false);  // Must precede WiFi mode/init.
    radio_ready = WiFi.mode(WIFI_STA) && esp_wifi_set_storage(WIFI_STORAGE_RAM) == ESP_OK;
    WiFi.setAutoReconnect(false);
#if defined(KICKBAC_OPERATIONAL_NETWORK)
    device_restore_saved_auth();
    WiFi.onEvent([](WiFiEvent_t, WiFiEventInfo_t) { link_loss_seen.store(true); }, ARDUINO_EVENT_WIFI_STA_DISCONNECTED);
    if (radio_ready) load_saved_network();
    scan_done = true; // one configured network; no diagnostic AP scan needed at boot
#endif
}

void loop() {
#if defined(KICKBAC_OPERATIONAL_NETWORK)
    if (radio_ready) service_wifi_network();
#endif
#if defined(KICKBAC_DEVICE_DIAGNOSTIC)
    if (network_proven) {
        device_probe_loop();
        delay(1);
        return;
    }
#endif
    const auto now = static_cast<std::uint32_t>(millis());
    if (!radio_ready) {
        if (now - last_ready_at >= 3000U) {
            last_ready_at = now;
            Serial.printf("probe_fatal radio_init=failed sensor=disabled\n");
        }
        delay(5);
        return;
    }
    if (!scan_done && now >= 1200U) {
        scan_radio();
        scan_done = true;
    }
    if (scan_done && now - last_ready_at >= 3000U) {
        last_ready_at = now;
        Serial.printf("probe_ready private_usb_provisioning=1 sensor=disabled uploads=disabled\n");
    }
    provisioning.expire(now);
    if (scan_done) {
        while (Serial.available() > 0) {
            const int value = Serial.read();
            if (value >= 0 && provisioning.feed(static_cast<std::uint8_t>(value),
                                               static_cast<std::uint32_t>(millis()))) {
                run_probe();
                break;
            }
        }
    }
    delay(1);
}
