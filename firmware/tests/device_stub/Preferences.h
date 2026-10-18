#ifndef KICKBAC_TEST_PREFERENCES_H
#define KICKBAC_TEST_PREFERENCES_H
// Synthetic NVS ONLY. Production resolves Arduino Preferences, not this stub.
#include <cassert>
#include <cstdint>
#include <cstring>
#include <vector>
class Preferences {
public:
    struct Memory { std::vector<std::uint8_t> blob; bool blocked = false; unsigned writes = 0; };
    static Memory& memory() { static Memory value; return value; }
    bool begin(const char* name, bool readonly) {
        assert(std::strcmp(name, "kickbac_auth") == 0); readonly_ = readonly; open_ = true; return true;
    }
    void end() { open_ = false; }
    bool getBool(const char* key, bool fallback) { assert(open_ && std::strcmp(key,"blocked") == 0); return memory().blocked || fallback; }
    std::size_t putBool(const char* key, bool value) { assert(open_ && !readonly_ && std::strcmp(key,"blocked") == 0); memory().blocked = value; ++memory().writes; return 1; }
    std::size_t getBytesLength(const char* key) { assert(open_ && std::strcmp(key,"credential") == 0); return memory().blob.size(); }
    std::size_t getBytes(const char* key, void* output, std::size_t count) {
        assert(open_ && std::strcmp(key,"credential") == 0 && count >= memory().blob.size());
        std::memcpy(output,memory().blob.data(),memory().blob.size()); return memory().blob.size();
    }
    std::size_t putBytes(const char* key, const void* input, std::size_t count) {
        assert(open_ && !readonly_ && std::strcmp(key,"credential") == 0);
        const auto* bytes=static_cast<const std::uint8_t*>(input); memory().blob.assign(bytes,bytes+count); ++memory().writes; return count;
    }
private: bool open_ = false; bool readonly_ = true;
};
#endif
