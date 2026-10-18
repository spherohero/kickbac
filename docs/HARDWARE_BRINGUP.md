# Physical bring-up checkpoint — XIAO + MQ module

## Actual hardware evidence

- Nicholas identifies XIAO ESP32-S3 and says it is connected alone by USB.
- Windows enumerated one serial target: COM3, USB VID:PID 303A:1001. Always
  re-enumerate before later flashes; a port name is not a permanent identity.
- Read-only esptool connection identifies ESP32-S3 QFN56 revision v0.2, 40 MHz
  crystal, embedded 8 MB PSRAM; separate flash-ID probe reports 8 MB quad flash.
- PlatformIO `xiao_usb` upload to that verified COM3 target returned SUCCESS;
  bootloader, partitions, boot image and application all reported verified hashes.
- Actual serial capture at 115200 received four one-second status lines during
  each of two monitor opens. Second open restarted uptime; monitor control lines
  can reset this board. No cable-disconnect/power-cycle test was performed.
- Upload log: `firmware/build/xiao-usb-upload.log`; physical serial log:
  `firmware/build/xiao-usb-serial.log` (ignored local evidence).
- Actual observed line: `kickBAC mode=usb_bringup uptime_ms=1000 sensor=disabled network=disabled`.
  This is physical firmware execution, **not** sensor or Wi-Fi proof.

### Later Wi-Fi checkpoint (supersedes USB-only current-image status)

**Subsequent current image:** `xiao_device` is now flashed/hash-verified; actual
device-authenticated heartbeat/poll and independent persisted ongoing heartbeat
readback pass. Sensor ADC/sampling/uploads remain disabled. See
`docs/DEVICE_CONNECTIVITY.md`. Prior Wi-Fi evidence below remains historical.

The separate `xiao_wifi` diagnostic was flashed at that checkpoint. Actual board scan found 46
access points; private local entry enabled association/DHCP at -34 dBm on
channel 6. DNS and SNTP succeeded, trusted-HTTPS `/health` returned200; controlled
disconnect/reassociation at -36 dBm and a second trusted HTTP200 passed.
See `docs/WIFI_CONNECTIVITY.md` for trace, commands and limitations. Wi-Fi config
is RAM-only and needs re-entry after reset. Sensor pins/ADC/BLE/device auth and
uploads are still disabled; the electrical assembly instructions are unchanged.

## Sensor correction: breakout module, NOT bare sensor

Nicholas's photo `IMG_2204.jpeg` visibly shows a blue **MQ Sensor / Flying Fish-style
breakout PCB**, four-pin header, adjustment potentiometer, indicator LEDs and
8-pin comparator circuitry, with the sensor solder connections on this side.
This supersedes the earlier verbal bare-metal-can identification. Do not remove
or separately wire the sensor's six legs; no new bare-sensor load network is needed.

Purchased listing: https://www.amazon.com/dp/B0GW8C1V6N?ref=ppx_yo2ov_dt_b_fed_asin_title
(ASIN B0GW8C1V6N, EC Buying 5Pcs MQ-3 module). Listing specifies 5 V supply,
analog and digital outputs. The PCB photo itself says generic “MQ Sensor”; the
can's exact maker/variant is not visible, so the listing is not a calibration
certificate or a uniquely matched sensing-element datasheet.

In the supplied photo orientation (trimmer at TOP, four header pins pointing
RIGHT), header labels TOP to BOTTOM are:

1. **VCC** — module supply, specified 5 V by seller.
2. **GND** — module ground.
3. **DO** — comparator digital output; leave disconnected.
4. **AO** — analog output; never directly connect to the XIAO ADC at 5 V supply.

Follow actual printed labels if rotating/flipping the board; never reuse this
order from the opposite viewing direction. Typical module potentiometer sets the
DO comparator threshold; it is not the firmware's baseline-relative MQ threshold
and does not make AO safe for a 3.3 V MCU. Leave its setting unchanged initially.

## Next electrical gate — gather parts; do not connect AO yet

Needed: multimeter, breadboard/jumpers, two 10 kOhm resistors (1% preferred),
100 nF ceramic capacitor if available, and a regulated 5 V supply with verified
rating/output (a current-limited bench supply is preferred for initial checks).
Nicholas said these categories can be obtained; exact parts/tolerance and actual
supply source/rating/output have **not** yet been confirmed.

Conditional signal design for those exact parts, subject to supply/meter checks:

- Candidate ADC target is XIAO **D0/A0 = GPIO1 = ADC1 channel 0**, checked against
  Seeed's pin map and the installed XIAO variant/ESP32-S3 ADC-channel headers.
  No ADC firmware or GPIO is enabled by the current USB-only image.
- AO -> 10 kOhm upper resistor -> protected ADC node -> 10 kOhm lower resistor -> GND.
- Optional 100 nF from protected node to GND. Later connect protected node to
  D0 only after measuring/verifying the complete circuit with ADC disconnected.
- Nominal scaling is one half. At an ASSUMED maximum 5.1 V AO and two 1%
  resistors, calculated worst-case node is 2.5755 V; with 5% it is 2.6775 V.
  These are design calculations, not actual measured voltages or confirmation of
  the supply's maximum. Rescale/reassess if actual parts or supply bounds differ.
- Two 10 kOhm resistors load AO by about 20 kOhm and can change its response.
  Keep the divider fixed for all baseline/noise experiments. Counts remain actual
  12-bit ADC readings at the protected node, not unscaled module voltage or BAC.
- Use the installed core's 12-bit readout and per-pin `ADC_11db` only in a later,
  explicitly enabled telemetry image. Attenuation is NOT 5 V protection. The
  ESP32-S3 documentation gives roughly 150..3100 mV measurable range at this
  setting; range/linearity/calibration are not electrical absolute-maximum ratings.

Power topology remains conditional until supply details are confirmed:

- XIAO stays powered by its PC USB data cable. No MQ heater on GPIO or 3V3.
- Prefer separately regulated/current-limited 5 V for module VCC. Do NOT tie that
  positive supply to XIAO 5V/VBUS or the PC's USB supply. Common low-voltage GND
  is required for measurement; check that the supply is appropriate/isolated.
- Keep the sensor circuit and ADC node disconnected/unpowered while assembling.
  Verify resistance/continuity, polarity and no short between supply and ground.
- First verify supply output without the module, then module voltage/current
  with AO isolated from the MCU. Check protected-node voltage/wiring before any
  D0 connection. One low idle AO reading does not verify worst-case scaling.
- Power both circuits down before changing wiring; avoid driving an unpowered
  ESP32 input. Later power-up/down order and shared-ground wiring must be checked.
- Keep hot sensor away from skin, liquid/condensation and flammable material.
  No alcohol consumption, liquid application or flammable-vapor test is required.

The seller's “>=20 seconds” warm-up text is not evidence of completed conditioning.
MQ-family datasheets specify much longer initial conditioning under their test
conditions, and the exact element here is unverified. Early ADC traces must be
labeled warm-up/unconditioned until drift/recovery and requirements are assessed.
Do not declare ready merely because a timer elapsed.

## Integration boundary / next acceptance

No sensor connection, heater current, ADC voltage/count, stable baseline, actual
MQ response, breath duration or device upload is verified. Wi-Fi/DHCP/DNS and
public trusted HTTPS are separately verified in the later checkpoint above.
No API, auth, units, lifecycle or SwiftUI source changed; the required
`breath_duration_ms` remains unresolved and unaltered. No-trigger remains no result,
not zero. DHT11 is omitted initially. No external sample button/LED is required.

Next: confirm actual protection parts and 5 V supply; inspect unpowered wiring;
verify voltages/current; build/enable serial ADC telemetry, collect real idle and
warm-up traces, then tune experiments. Retain original physical traces separately
from synthetic fixtures. Native login remains Liam's work.

Sources: [Seeed XIAO docs](https://wiki.seeedstudio.com/xiao_esp32s3_getting_started/),
[Espressif ADC API](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/adc.html),
purchased listing and Nicholas's actual photo. A generic module tutorial is not
proof of this exact PCB schematic or electrical measurements.
