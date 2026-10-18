#include <Arduino.h>

#include <cstdint>

#if !defined(KICKBAC_USB_ONLY) || KICKBAC_USB_ONLY != 1
#error "Only the USB-only bring-up mode is implemented."
#endif

#if defined(ARDUINO) && !defined(ARDUINO_XIAO_ESP32S3)
#error "This bring-up target is for the confirmed XIAO ESP32-S3 only."
#endif

// No sensor GPIOs, ADC, heater, radio, credentials or backend operations here.
void setup() {
    Serial.begin(115200);
    // Do not wait for a connected USB host: startup must remain bounded.
}

void loop() {
    static std::uint32_t last_report_ms = 0;
    const auto now = static_cast<std::uint32_t>(millis());
    if (now - last_report_ms >= 1000U) {
        last_report_ms = now;
        Serial.printf("kickBAC mode=usb_bringup uptime_ms=%lu sensor=disabled network=disabled\n",
                      static_cast<unsigned long>(now));
    }
    delay(1);
}
