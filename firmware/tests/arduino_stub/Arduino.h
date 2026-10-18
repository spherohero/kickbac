#ifndef KICKBAC_TEST_ARDUINO_H
#define KICKBAC_TEST_ARDUINO_H

// Test-only USB API. No GPIO, ADC or Wi-Fi API is available to this build.
struct TestSerial {
    unsigned long baud = 0;
    void begin(unsigned long value);
    void printf(const char* format, ...);
};
extern TestSerial Serial;
unsigned long millis();
void delay(unsigned long milliseconds);

#endif
