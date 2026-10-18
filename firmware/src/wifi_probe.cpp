#include <Arduino.h>
#include <HTTPClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <esp_log.h>
#include <esp_sntp.h>
#include <esp_wifi.h>

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

bool wait_joined() {
    const auto started = millis();
    while (millis() - started < 30000U) {
        if (WiFi.status() == WL_CONNECTED && WiFi.localIP() != IPAddress(0U)) return true;
        delay(50);
    }
    return false;
}

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

void run_probe() {
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
}
}  // namespace

void setup() {
    Serial.begin(115200);
    esp_log_level_set("wifi", ESP_LOG_NONE);
    WiFi.persistent(false);  // Must precede WiFi mode/init.
    radio_ready = WiFi.mode(WIFI_STA) && esp_wifi_set_storage(WIFI_STORAGE_RAM) == ESP_OK;
    WiFi.setAutoReconnect(false);
}

void loop() {
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
