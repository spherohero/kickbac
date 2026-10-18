// Synthetic on-device auth store; no real credential, flash, USB or API.
#include <cassert>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>
#include "saved_auth.hpp"

struct Store {
    std::vector<std::uint8_t> blob;
    bool blocked = false, opened = false, readable = true, writable = true;
    unsigned writes = 0;
    bool begin(const char* ns, bool read_only) {
        assert(std::strcmp(ns, "kickbac_auth") == 0);
        opened = read_only ? readable : writable;
        return opened;
    }
    void end() { opened = false; }
    bool getBool(const char*, bool value) { assert(opened); return blocked || value; }
    std::size_t putBool(const char*, bool value) { assert(opened); ++writes; blocked = value; return 1; }
    std::size_t getBytesLength(const char*) { assert(opened); return blob.size(); }
    std::size_t getBytes(const char*, void* output, std::size_t count) {
        assert(opened && count >= blob.size());
        std::memcpy(output, blob.data(), blob.size()); return blob.size();
    }
    std::size_t putBytes(const char*, const void* data, std::size_t count) {
        assert(opened); ++writes;
        const auto* bytes = static_cast<const std::uint8_t*>(data);
        blob.assign(bytes, bytes + count); return count;
    }
};
void frame(kickbac::DeviceCredentialFrame& input, bool save) {
    for (char byte : std::string(save ? "KBA1" : "KBD1") + std::string(43, 'x'))
        input.feed(static_cast<std::uint8_t>(byte), 0);
    assert(input.ready() && input.save_requested() == save);
}
int main() {
    using namespace kickbac;
    Store store;
    DeviceCredentialFrame input;
    assert(load_device_auth(store, input) == SavedAuthState::Absent && !input.ready());
    frame(input, false);
    assert(!save_device_auth(store, input) && store.writes == 0); // default NEVER writes
    input.clear(); frame(input, true);
    assert(save_device_auth(store, input) && !store.opened && !store.blocked);
    const auto persisted = store.blob;
    const unsigned writes = store.writes;
    input.clear();
    assert(load_device_auth(store, input) == SavedAuthState::Loaded);
    assert(input.ready() && !input.save_requested() && std::strcmp(input.token(), std::string(43,'x').c_str()) == 0);
    assert(store.writes == writes); // boot does NOT rewrite
    for (std::size_t i = 0; i < persisted.size(); ++i) {
        store.blob = persisted; store.blob[i] ^= 1;
        input.clear();
        assert(load_device_auth(store, input) == SavedAuthState::Invalid && !input.ready());
    }
    store.blob = persisted;
    assert(block_saved_device_auth(store));
    input.clear();
    assert(load_device_auth(store, input) == SavedAuthState::Blocked && !input.ready());
    // Explicit authorized private opt-in repairs blocked state; never automatic.
    frame(input, true);
    assert(save_device_auth(store, input));
    input.clear(); assert(load_device_auth(store, input) == SavedAuthState::Loaded);
    store.blocked = true; // interruption between blob write and final enable is fail-closed
    input.clear(); assert(load_device_auth(store, input) == SavedAuthState::Blocked);
    store.writable = false;
    frame(input, true);
    assert(!save_device_auth(store, input));
    DeviceAuthRecord record;
    record.clear();
    for (std::size_t i = 0; i < DeviceAuthRecord::capacity; ++i) assert(record.bytes()[i] == 0);
    std::cout << "PASS: opt-in only identity-bound saved auth, restart/no boot writes, corruption/block/revocation persistence, interrupted-save fence and clearing (synthetic)\n";
}
