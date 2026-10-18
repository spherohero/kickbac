#ifndef KICKBAC_DEVICE_PROBE_HPP
#define KICKBAC_DEVICE_PROBE_HPP

// Called only after actual Wi-Fi/DNS/time/trusted-HTTPS acceptance.
void device_probe_loop();
// Main-loop network-loss fence; keeps RAM bearer, preserves/holds pending bytes.
void device_network_lost();
bool device_take_wifi_setup();
void device_restore_saved_auth();

#endif
