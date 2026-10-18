// Actual device adapter through synthetic persistent Preferences and network.
#define KICKBAC_PERSIST_DEVICE_AUTH 1
#define KICKBAC_MOCK_ADAPTER_LIBRARY 1
#include "mock_adapter_test.cpp"

void reboot_ram() {
    reset_fixture();
    mock_upload = kickbac::MockUpload{};
    mock_command = kickbac::MockCommand{};
    last_mock_ready = 0;
    saved_auth_active = false;
    fixture_upload_payloads.clear();
    fixture_upload_override.clear();
    fixture_upload_status = 201;
}
void save_fixture_auth() {
    reboot_ram();
    Serial.input = "KBA1" + std::string(43, 'x');
    device_probe_loop();
    assert(credential.ready() && saved_auth_active);
    assert(!Preferences::memory().blob.empty() && !Preferences::memory().blocked);
}
int main() {
    Preferences::memory() = Preferences::Memory{};
    save_fixture_auth();
    const auto record = Preferences::memory().blob;
    const auto writes = Preferences::memory().writes;
    reboot_ram();
    device_restore_saved_auth();
    assert(credential.ready() && saved_auth_active && Serial.input.empty());
    device_probe_loop();
    assert(negative_checked && heartbeats == 1 && polls == 1);
    assert(Preferences::memory().writes == writes && fixture_upload_payloads.empty());
    arm_mock_fixture();
    assert(fixture_upload_payloads.empty()); // boot or ARMED alone does not upload

    fixture_now = 4000;
    fixture_status = 401;
    device_probe_loop();
    assert(failed && !credential.ready() && Preferences::memory().blocked);
    reboot_ram();
    device_restore_saved_auth();
    device_probe_loop();
    assert(!credential.ready() && fixture_gets == 0 && fixture_posts == 0);
    assert(fixture_upload_payloads.empty()); // reset cannot bypass revoked credential block

    save_fixture_auth(); // explicit authorized opt-in repairs block
    fixture_now = 0;
    device_probe_loop();
    fixture_now = 2000;
    fixture_override_body = true; fixture_override_heartbeat = false;
    fixture_response_body = "{}";
    device_probe_loop();
    assert(failed && Preferences::memory().blocked);
    reboot_ram(); device_restore_saved_auth();
    assert(!credential.ready()); // schema fault not silently recovered after reboot

    Preferences::memory().blocked = false;
    Preferences::memory().blob = record;
    Preferences::memory().blob.back() ^= 1U;
    reboot_ram(); device_restore_saved_auth(); device_probe_loop();
    assert(!credential.ready() && fixture_posts == 0 && fixture_gets == 0);
    for (const auto& line : fixture_lines) assert(line.find(std::string(43,'x')) == std::string::npos);
    std::cout << "PASS: actual adapter privately saves auth, automatic restart without relay/no auto upload, persistent revocation/schema fence and corrupt-record rejection (fixtures)\n";
}
