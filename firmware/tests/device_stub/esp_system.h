#ifndef KICKBAC_TEST_ESP_SYSTEM_H
#define KICKBAC_TEST_ESP_SYSTEM_H
#include <cstddef>
#include <cstring>
// Synthetic entropy fixture ONLY; production resolves ESP-IDF esp_system.h.
inline void esp_fill_random(void* output, std::size_t size) { std::memset(output, 0x42, size); }
#endif
