#!/usr/bin/env bash
# Host-only synthetic tests. This script never flashes a board.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p firmware/build
"${CXX:-g++}" -std=c++11 -Wall -Wextra -Werror -Wconversion -Wshadow -pedantic \
  -fno-exceptions -fno-rtti -I firmware/include \
  firmware/tests/signal_trigger_test.cpp -o firmware/build/signal_trigger_tests.exe
./firmware/build/signal_trigger_tests.exe
"${CXX:-g++}" -std=c++11 -Wall -Wextra -Werror -Wconversion -Wshadow -pedantic \
  -fno-exceptions -fno-rtti -DKICKBAC_USB_ONLY=1 -I firmware/tests/arduino_stub \
  firmware/tests/usb_bringup_test.cpp firmware/src/main.cpp \
  -o firmware/build/usb_bringup_tests.exe
./firmware/build/usb_bringup_tests.exe
"${CXX:-g++}" -std=c++11 -Wall -Wextra -Werror -Wconversion -Wshadow -pedantic \
  -fno-exceptions -fno-rtti -I firmware/include \
  firmware/tests/wifi_diagnostic_test.cpp -o firmware/build/wifi_diagnostic_tests.exe
./firmware/build/wifi_diagnostic_tests.exe
python -m unittest discover -s firmware/tests -p test_wifi_provision.py -v
"${CXX:-g++}" -std=c++11 -Wall -Wextra -Werror -Wconversion -Wshadow -pedantic \
  -fno-exceptions -fno-rtti -I firmware/include \
  -I firmware/.pio/libdeps/xiao_device/ArduinoJson/src \
  firmware/tests/device_diagnostic_test.cpp -o firmware/build/device_diagnostic_tests.exe
./firmware/build/device_diagnostic_tests.exe
"${CXX:-g++}" -std=c++11 -Wall -Wextra -Werror -Wconversion -Wshadow -pedantic \
  -fno-exceptions -fno-rtti -DARDUINO_XIAO_ESP32S3=1 -DKICKBAC_DEVICE_DIAGNOSTIC=1 \
  -I firmware/tests/device_stub -I firmware/include \
  -I firmware/.pio/libdeps/xiao_device/ArduinoJson/src \
  firmware/tests/device_adapter_test.cpp -o firmware/build/device_adapter_tests.exe
./firmware/build/device_adapter_tests.exe
python -m unittest discover -s firmware/tests -p test_device_provision.py -v
