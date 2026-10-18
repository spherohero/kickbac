# kickBAC | Austin's perfboard wiring guide

> **Superseded for current power topology:** Nicholas now chooses **USB-C-only,
> no battery**. Use [the USB-only schematic and keep/remove/check list](USB_ONLY_COMMISSIONING.md)
> before wiring. Its single-cable VBUS branch requires source/cable/board-current
> review; it is not permission to connect an unchecked heater. The original
> separate-supply nets below are an alternate reference, not the current build.
> ADC connection remains physically OPEN; capacitor markings remain unverified.

> **Historical placement checkpoint:** parts were only placed in isolated-pad perfboard, not soldered or connected; **no boost converter, no pressure sensor, no installed JP1**. This is still the latest construction evidence, not the current power decision. Nicholas now chooses USB-C-only per the guide above; its actual source/current/path acceptance remains unresolved. Software communication testing does not require completed construction.

> **Historical revision boundary:** the original separate regulated 5 V supply/JP1 design below and the [subsequent battery/boost proposal](BATTERY_BOOST_COMMISSIONING.md) are both superseded for the current USB-only topology. Keep the ADC physically isolated by a removable disconnected lead/socket link; no installed JP1 is required by the current build. Do not mix positive-rail wiring from these alternatives.

**Build specification for review, not a tested sensor assembly.** The XIAO now runs the `xiao_device` diagnostic: real USB execution, Wi-Fi/trusted HTTPS, authenticated heartbeat/poll and persisted ongoing heartbeat are verified. MQ power, divider and ADC are NOT physically verified and remain disabled. Confirm actual parts, supply and meter checks below before connecting the ADC. This guide supersedes the earlier mistaken bare-sensor description. Current network/firmware evidence is in [DEVICE_CONNECTIVITY.md](DEVICE_CONNECTIVITY.md); earlier USB-only/PDF status text is historical, not a change to these wiring safeguards.

## 1. Circuit and exact connections

### Confirmed hardware

- Controller: standard Seeed Studio XIAO ESP32-S3, USB-C powered by Nicholas's PC.
- Sensor: photographed blue Flying Fish-style MQ breakout sold as EC Buying MQ-3, ASIN B0GW8C1V6N. It already contains the sensing element, load/comparator circuitry and adjustment trimmer. Do not wire its six sensor legs or add a bare-sensor load resistor.
- Separate sensor supply: regulated, appropriate isolated low-voltage 5 V DC source; verify source/rating first. Prefer a current-limited bench supply for commissioning. A 5 V / 1 A rated source provides supply headroom; it does not force 1 A through the sensor.
- No DHT11, pressure sensor, external sample button, buzzer or additional LED in this initial build.

### Module header orientation

Use the actual photo: blue trimmer at TOP, four header pins pointing RIGHT. From TOP to BOTTOM: **VCC, GND, DO, AO**. Follow printed labels if the module is rotated or flipped. This is not the order viewed from the opposite side. The can's exact maker/variant is not visible in that photo.

### Schematic

```text
PC USB-C ============================= XIAO USB-C
                                       XIAO 5V/VBUS: NO CONNECTION
External regulated 5V ---- +5V_MQ ---- MQ module VCC
External supply GND ------ GND_STAR --- MQ module GND
                              +------- XIAO GND
                              +------- all circuit ground below

MQ module AO ---- R1 10k ----+---- JP1 (OPEN initially) ---- XIAO D0/A0
                            |                               GPIO1 / ADC1_CH0
                            +---- TP_ADC
                            |
                            +---- R2 10k ---- GND
                            |
                            +---- C1 100nF -- GND

MQ module DO: NO CONNECTION
C2 100nF + C3 10uF: across +5V_MQ and GND near the module connector.
C3 is polarized: + to +5V_MQ; - to GND. C1/C2 ceramic are not polarized.
```

JP1 is a removable two-pin jumper or disconnectable signal link, NOT a wire permanently soldered closed. Keep it OPEN through initial testing. Label its two sides TP_ADC and D0. Keep TP_AO at the module's AO input to R1 and TP_GND at ground.

### Net-by-net connection table

| From | To | Important detail |
| --- | --- | --- |
| PC USB-C data cable | XIAO USB-C | Powers/programs XIAO; keep port accessible. |
| External regulated +5 V | +5V_MQ; module VCC | Do NOT join to XIAO 5V/VBUS, 3V3, BAT or a GPIO. |
| External supply negative | GND_STAR | Common ground, not a second positive rail. |
| GND_STAR | Module GND; XIAO GND; R2/C1/C2/C3 ground ends | Separate heater return and signal-ground routing to the common node. |
| Module AO / TP_AO | R1 first end | Never connect directly to D0. |
| R1 other end | TP_ADC; R2 top; C1 top; JP1 sensor side | Protected divider node. |
| R2 bottom; C1 bottom | Ground near XIAO | R2 is essential; a series resistor alone does not divide voltage. |
| JP1 controller side | XIAO D0/A0 = GPIO1 | Component/front view with USB at TOP: D0 is upper-left side pad. |
| C2/C3 positive side | +5V_MQ | C2 is ceramic; C3 positive lead must face +5V_MQ. |
| Module DO; XIAO 5V/VBUS, 3V3, BAT | Unconnected | DO may have 5 V pull-up. Do not attach it. |

### Why these resistor values

R1 = R2 = **10 kOhm, 1%**, preferably fixed resistors. Nominal ADC-node voltage is AO/2. At an ASSUMED maximum AO of 5.1 V, the calculated worst case from 1% resistor tolerances is **2.5755 V**. This is a calculation, not a measured supply/output. Reassess if supply or parts differ. Use a conservative commissioning ceiling of **2.60 V** at TP_ADC with this specified design.

The divider presents roughly 20 kOhm load to AO; it can alter module response. Leave the network unchanged while collecting baselines. C1 goes close to D0/R2 and reduces sampling noise. Later firmware will explicitly select 12-bit ADC and per-pin ADC_11db. Attenuation is NOT 5 V protection; raw readings are ADC counts at this node, not BAC.

## 2. Parts and perfboard assembly

### Historical separate-supply parts list — not current USB-only BOM

| Ref | Part | Quantity / notes |
| --- | --- | --- |
| U1 | XIAO ESP32-S3 | 1; use removable sockets, not soldered permanently to carrier. |
| U2 | Existing MQ-3 breakout module | 1; keep replaceable and ventilated. |
| R1, R2 | 10 kOhm, 1%, >= 1/8 W | 2; measure before soldering. No trim-pot substitute. |
| C1 | 100 nF ceramic | 1; ADC node to GND, near D0/R2. |
| C2 | 100 nF ceramic, >= 10 V | 1; supply decoupling near MQ connector. |
| C3 | 10 uF electrolytic, >= 10 V | 1; + to +5V_MQ, - to GND. |
| JP1 | 2-pin removable jumper + shunt | 1; normally OPEN until commissioning passes. |
| Connectors | Two XIAO 1x7 socket rows; MQ 4-wire connector; 2-wire power entry | Dry-fit actual boards/pitch before soldering. Use keyed/clearly labeled power connector. |
| Board/wire | Isolated-pad perfboard; insulated hookup wire; spacers/strain relief | Avoid uncut stripboard. Shorted strips would join unrelated pins. |
| Tools | Multimeter, soldering iron, magnification, USB data cable | Bench supply with current limit preferred; no mains wiring on perfboard. |

Do not substitute parts silently. If resistor values/tolerance, supply bounds or module differ, send them back to Nicholas for an updated calculation/check.

### Suggested component-side placement (NOT a drill template)

```text
                 USB cable exits enclosure
                          UP
+-------------------------------------------------------+
|       USB-C                                           |
|    [ XIAO ]            antenna connector / cable       |
| D0 o     o 5V (NC)     keep clear, strain-relieved      |
|    o     o GND                                        |
|    o     o 3V3 (NC)    FPC antenna at enclosure edge    |
|    [sockets]          away from metal / MQ heater      |
|       |                                               |
|     JP1      TP_ADC -- R1 -- TP_AO -- MQ connector      |
|    OPEN         |                        AO DO GND VCC |
|              R2 + C1                    labels govern |
|                 |                                     |
|             TP_GND        C2 C3     +5V_MQ power entry |
|                 +---- GND_STAR ---- GND power entry    |
+-------------------------------------------------------+
MQ module on insulated standoffs / short harness near a vent.
The connector text above is NET labeling, not physical header order.
```

- This is a component-side concept; the solder side is mirrored. Mark USB direction, +5V_MQ, GND, AO, TP_ADC, D0, JP1 and DO-NC on the actual board. Do not copy positions as electrical connections.
- On the actual XIAO front/component view with USB at top: upper-left pad D0/GPIO1; upper-right pad 5V/VBUS; next right pad GND; next 3V3. Double-check Seeed's pinout before soldering. Do not mirror the pin map accidentally.
- Dry-fit both XIAO socket rows using the actual board unpowered. Preserve USB connector, reset/BOOT access and antenna connector clearance. Check under-board clearance and no contact with exposed pads/shield.
- Solder sockets/connectors and passive components with XIAO and MQ module removed. Use insulated wire for intentional nets; every isolated perfboard pad needs its own planned connection. Inspect solder bridges and trim sharp leads.
- Put R1/R2/C1/JP1 near the XIAO ADC end, not near the heater. Make AO run short and route away from supply wires, antenna and USB; keep heater current out of the local ADC-ground return path.
- Put C2/C3 near the MQ supply connector. Use an appropriate pair for module supply/return; 22-24 AWG hookup wire is practical for these short bench connections. Keep hot module mechanically separate from the carrier and plastics.
- Use sockets/strain relief or insulated standoffs. No hot glue, silicone sealant or adhesives on/over the sensing mesh; chemical vapors and condensation can contaminate sensors. Leave vent, sensor mesh and trimmer accessible. No sealed heated box.
- Mount the FPC antenna at a nonmetallic enclosure edge, following Seeed's antenna guidance. Do not pinch coax, pull the tiny connector or place the antenna against metal/ground planes. This is not a validated RF layout.

## 3. Meter checks and first power-up

**Default: JP1 OPEN, both supplies OFF. Never rewire while powered.** This design has separate PC USB and module supplies: power XIAO first, module second; switch module OFF first during shutdown. Open JP1 before unplugging USB or making wiring changes. There is no hardware interlock against accidental USB loss while the module drives a connected ADC.

### A. Unpowered inspection

1. Remove XIAO and unplug MQ harness. Disconnect USB and external supply; discharge capacitors. Photograph both perfboard sides before installation.
2. Measure R1 and R2 individually before assembly (10 kOhm +/-1%). Verify the divider connections and C3 polarity. JP1 must be open-circuit end-to-end with the shunt removed.
3. Verify the GND net is continuous to intended ground points. Verify +5V_MQ has NO connection to XIAO VBUS/5V, 3V3, BAT or D0 socket pads. No unintended low-ohm path between supply rails/ground; capacitor charging can cause a temporary meter indication. Investigate sustained shorts.
4. With boards disconnected, JP1 OPEN and C1 discharged, TP_ADC to GND should settle near R2's 10 kOhm. ADC node to AO passes through R1. Do not use the module's internal circuitry to infer the divider's values.
5. Inspect magnified solder side for bridges, reversed connectors and exposed leads touching standoffs/enclosure. Mark the actual module header labels and XIAO orientation.

### B. Full-scale divider test — MQ and XIAO absent

1. Keep JP1 OPEN and both boards disconnected. Verify the external source separately at **5.00 V**; allowed design range is **4.90-5.10 V** at the module. Never put a meter in current mode across a supply.
2. With power OFF, add a clearly marked temporary test wire from +5V_MQ to TP_AO; keep the MQ unplugged. Apply power and measure supply and TP_ADC relative to TP_GND. Expected TP_ADC is about half measured supply; for 1% parts the ratio is 0.495-0.505. At 5.00 V nominal expect about 2.50 V; do not connect D0 if TP_ADC exceeds **2.60 V**.
3. Switch power OFF. Remove the temporary +5V_MQ-to-TP_AO test wire and confirm it is gone before plugging the MQ module in. This test is essential: a low idle AO reading alone cannot prove protection.

### C. Module-only electrical test — ADC link still open

1. Install the MQ module/harness with power OFF; keep XIAO unplugged and JP1 OPEN. Use the verified 5 V source. For a bench source, an initial **0.25 A current limit** is a cautious bring-up setting, not a measured module-current specification. If it limits, voltage collapses, or the module is abnormal, turn OFF and investigate; do not simply raise the limit.
2. Measure module VCC-to-GND, total current with a proper series/current measurement, TP_AO and TP_ADC. Record powered uptime. TP_ADC must track about half TP_AO, remain nonnegative, and never exceed **2.60 V** within the verified supply bounds. Readings near the meter noise floor need proportionate interpretation.
3. Heater warming is expected; smoke, burning smell, melting or unstable supply is NOT. Turn OFF on abnormalities. DO remains disconnected. Do not turn the trimmer to solve an analog-voltage or breath-detection problem.
4. Early values are WARM-UP / UNCONDITIONED. Seller's ">=20 seconds" statement is not evidence of initial conditioning or accuracy; exact sensing-element requirements remain unverified.

### D. Controller integration gate — return to Nicholas

1. Power everything OFF; open JP1; remove temporary test wires. Send both-side perfboard photos and measurements below to Nicholas before connecting D0.
2. After sign-off, install XIAO into correctly oriented sockets, keep JP1 OPEN, attach USB first and verify serial status for the selected diagnostic image. Current `xiao_device` firmware needs private provisioning after reset; an absent USB-only uptime line is not itself a hardware failure. Then power module; repeat voltage checks with common ground established.
3. Once measurements are accepted, turn module power OFF, then USB OFF. Close JP1 with BOTH supplies OFF. Restart with USB first, then module power. For shutdown, turn module power OFF first, then USB; open JP1 while unpowered before leaving the assembly or changing wiring. Never unplug USB first while the module is driving a connected ADC.
4. Current flashed `xiao_device` firmware has ADC/sampling/uploads disabled; networking is enabled and verified independently. Nicholas must prepare a separate serial ADC telemetry image after electrical sign-off; no sensor readings in the current diagnostic are expected. Log actual raw ADC/time, drift/noise and recovery before tuning the trigger. Do not accept a timeout as zero or invent breath duration.

### Austin's report-back checklist

```text
Actual supply source/rating: ___________________________
Measured supply unloaded / at module: ______ V / ______ V
Measured module current + powered uptime: ______ mA / ______
R1 / R2 measured: ______ ohm / ______ ohm
Full-scale divider test: supply ______ V; TP_ADC ______ V
Module-only test: TP_AO ______ V; TP_ADC ______ V
JP1 is OPEN: yes / no      DO is disconnected: yes / no
No external +5 V tied to XIAO 5V/3V3/BAT: confirmed / not confirmed
Photos attached: component side / solder side / connector labels
Unexpected heat, current limiting or instability: ___________
```

## 4. Mechanical boundaries, status and sources

Keep sensor heat away from skin/plastic/antenna. Keep electronics dry; do not route wet breath/condensation onto PCB or ESP32. Any mouth-contact path must be detachable, cleanable and hygienic; no shared unsanitized mouthpiece. Do not spray/pour alcohol, use lighter gas or drink for testing. Austin owns fit/ventilation/harness work; Nicholas owns electrical sign-off, firmware and subsequent sensor experiments. Airflow/pressure validation is absent; MQ response alone cannot establish sober breath or actual exhalation duration. No calibrated BAC or safe-to-drive claim.

**Not a contract change:** existing device heartbeat/poll API is unchanged; no SwiftUI/Figma edits. Firmware is network-enabled but sensor/ADC/sampling/uploads remain disabled. No manual-timed upload or fabricated breath duration is authorized by this assembly guide. Sensor performance and the completed perfboard still require physical verification.

References: Seeed XIAO ESP32-S3 pinout/power/antenna guide https://wiki.seeedstudio.com/xiao_esp32s3_getting_started/ ; Espressif ADC API https://docs.espressif.com/projects/arduino-esp32/en/latest/api/adc.html ; purchased module https://www.amazon.com/dp/B0GW8C1V6N ; actual photo IMG_2204.jpeg; project checkpoint docs/HARDWARE_BRINGUP.md. Follow labels on the actual boards, not an unrelated MQ module diagram.
