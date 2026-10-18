// Synthetic USB credential frames, not real Wi-Fi credentials.
#include "wifi_diagnostic.hpp"
#include <cstdlib>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

static void check(bool value, const char* message) {
    if (!value) { std::cerr << "FAIL: " << message << '\n'; std::exit(1); }
}
static std::vector<std::uint8_t> frame(const std::string& ssid, const std::string& password) {
    std::vector<std::uint8_t> result{'K','B','W','1',static_cast<std::uint8_t>(ssid.size()),static_cast<std::uint8_t>(password.size())};
    result.insert(result.end(),ssid.begin(),ssid.end());
    result.insert(result.end(),password.begin(),password.end());
    return result;
}
int main() {
    kickbac::WifiFrameParser parser;
    const auto payload=frame("fixture-network","fixture-password");
    std::uint32_t t=0;
    for (std::size_t i=0;i<payload.size();++i) {
        const bool ready=parser.feed(payload[i],++t);
        check(ready==(i+1==payload.size()),"only a complete valid frame becomes ready");
    }
    check(std::string(parser.ssid())=="fixture-network","SSID preserved for adapter");
    check(std::string(parser.password())=="fixture-password","password preserved for adapter");
    parser.clear();
    check(!parser.ready() && parser.ssid()[0]=='\0' && parser.password()[0]=='\0',"clear wipes credential arrays");
    std::cout << "PASS: bounded credential framing and memory clearing (fixture)\n";

    const auto maximum=frame(std::string(32,'s'),std::string(63,'p'));
    for (auto byte:maximum) parser.feed(byte,++t);
    check(parser.ready() && std::string(parser.ssid()).size()==32 &&
          std::string(parser.password()).size()==63,"maximum frame fits bounded buffers");
    parser.clear();
    for (const auto& invalid: {frame("", "fixture-password"),frame(std::string(33,'s'),"fixture-password"),
                              frame("fixture","short"),frame("fixture",std::string(64,'p')),
                              frame("fixture",std::string("bad\npassword")),
                              frame(std::string("bad\0ssid",8),"fixture-password")}) {
        for (auto byte:invalid) check(!parser.feed(byte,++t),"invalid frames cannot become ready");
        parser.clear();
    }
    for (std::size_t i=0;i<payload.size()-1;++i) parser.feed(payload[i],++t);
    check(!parser.expire(t+3000),"exact partial-frame timeout boundary retained");
    check(parser.expire(t+3001),"partial credentials cleared even with no next USB byte");
    check(parser.ssid()[0]=='\0' && parser.password()[0]=='\0',"timeout wipes partial secrets");
    parser.clear();
    t=0xFFFFFFF0U;
    for (auto byte:payload) parser.feed(byte,++t);
    check(parser.ready(),"frame timing supports unsigned wrap");
    parser.clear();
    check(kickbac::health_response_ok(200,"{\"status\":\"ok\"}"),"expected health response accepted");
    check(!kickbac::health_response_ok(302,"{\"status\":\"ok\"}") &&
          !kickbac::health_response_ok(200,"login required") &&
          !kickbac::health_response_ok(200,nullptr),"redirect/captive portal/wrong body fail");
    std::cout << "PASS: malformed/partial frames, timeout/wrap and health validation (fixture)\n";
}
