# USB-C-only kickBAC — revised circuit and commissioning hold

**Current owner decision:** Nicholas has removed battery operation from this demo.
Use USB-C power only. This supersedes the battery/boost proposal and the older
separate-positive-supply layout for the proposed single-cable build. **It is not
an as-built report or approval to power an unchecked assembly.** Parts remain
placement-only in the latest report. No wiring, current or protected ADC trace
has been verified for this revision.

## Remove / keep

| Item | Action |
| --- | --- |
| PKCELL battery/batteries, battery leads/connectors, series/parallel pack | Omit; insulate each disconnected battery connector separately and store safely away from heater, sharp leads and soldering. Do not cut both leads together. |
| Proposed boost converter, battery switch, external charger/balancer | Not needed for USB-only. No converter was installed in the latest inventory. A sensor-branch switch is optional, not a required battery subsystem. |
| XIAO onboard charger | Leave untouched. BAT+ and BAT- pads remain unconnected; do not bridge them or connect them to USB 5 V. |
| XIAO, supplied antenna, MQ breakout | Keep. MQ DO remains disconnected; heater never uses GPIO/3V3. |
| Two reported 10 kOhm resistors | Keep for AO divider; values/tolerances and actual connections still require verification. Prefer 1% parts. |
| Two reported 10 uF ceramic capacitors | Keep available, not automatically approved. A verified suitable 10 uF ceramic can serve as MQ supply bulk decoupling. Check voltage rating and effective capacitance under 5 V DC bias. A second bulk ceramic is optional, not a required extra part. |
| Reported 100 nF electrolytic | Value/construction remain unverified; do not silently relabel it as 10 uF or assume it is unsuitable just because it is electrolytic. Read actual capacitance/voltage/polarity. Do not install it by guess. |
| Filtering / decoupling | Preferred simple build: one 100 nF ceramic at ADC node, one 100 nF ceramic at MQ supply, plus a suitable 10 uF bulk capacitor at MQ supply. Obtain verified 100 nF ceramics if actual stock does not include them; missing values are not created by rearranging parts. |
| Removable ADC connection | Still required as a disconnected insulated lead/socket link; an installed JP1 component is not required. Keep OPEN until sign-off. |
| Pressure sensor / DHT11 / external sample button | Not added. Pressure sensor unavailable; DHT11 unproven. USB serial is the initial operator interface. |

The earlier photo does not establish capacitor markings. Standard ceramic codes:
`104` = 100 nF = 0.1 uF; `106` = 10 uF. Printed `100 uF` is not 100 nF.
If actual parts differ, assess those parts explicitly. Do not force a prior chat's
parts list onto unidentified components.

## Proposed single-cable nets — conditional on power-path acceptance

Seeed documents the standard XIAO's 5V header as USB VBUS output, not 3V3-regulated
power. This makes the following a candidate **USB-powered** path, not proof of its
available current. Confirm the actual board revision, connector/trace/header path,
source and cable before accepting the combined load. Do not apply external power
to that header while USB is connected. No passive power-injection/Y cable.

```text
Laptop USB port -- suitable USB data cable --> XIAO USB-C
                                               |
XIAO 5V / VBUS ----------------------------- +5V_MQ --> MQ VCC
XIAO GND ---------------------------------- GND_STAR --> MQ GND
                                               |
                         divider and capacitor ground returns

MQ AO / TP_AO -- R1 10k --+-- TP_ADC -- [REMOVABLE OPEN LEAD] -- D0/A0
                         |                                      GPIO1
                         +-- R2 10k -- GND                        ADC1_CH0
                         +-- C_ADC 100nF ceramic -- GND

+5V_MQ -- C_HF 100nF ceramic -- GND       near MQ connector
+5V_MQ -- C_BULK suitable 10uF -- GND    near MQ connector

MQ DO: NC       XIAO 3V3: NC       XIAO BAT pads: NC
```

- Follow actual printed header labels. In the supplied MQ photo only, trimmer
  TOP/header RIGHT gives top-to-bottom VCC/GND/DO/AO. Opposite views are mirrored.
- Standard XIAO component/front view, USB at TOP: upper-right header pad 5V,
  next right GND, then 3V3; upper-left D0. Verify actual markings/pinout. This is
  not a perfboard hole map; component-side placement is not solder-side routing.
- Ground is common. Route MQ heater return directly toward the common power
  ground; keep its current out of the ADC's local R2/C_ADC return where practical.
- If C_BULK is electrolytic, positive to +5V_MQ and negative stripe to GND.
  Ceramics have no polarity. Do not confuse positive supply and AO.
- No direct AO-to-D0 wire. R1 alone is not a divider; R2 must be connected.
- Leave USB access, reset/BOOT and antenna clear. Keep heater away from battery
  storage, plastic, skin and liquids. Use secure insulated connections, not loose
  powered parts on perfboard.

## Power budget — not yet measured or signed off

The MQ heater is the important additional load; capacitor values do not establish
power availability. No measured module current or exact XIAO peak current exists
for this assembly. Do not quote a runtime or approved port current from estimates.

1. Identify laptop/hub port and cable, its available/advertised current and any
   USB configuration limitation. A USB-C connector or high-wattage charger label
   alone does not establish the current available to this USB device at 5 V.
   Never trigger a higher USB-PD voltage for this circuit.
2. Review the actual XIAO VBUS connector/board/header path for the combined load.
   The manufacturer wiki calls 5V a USB output but does not establish an MQ-load
   rating. A schematic for an unconfirmed revision is not a physical path rating.
3. Use `I_source_required >= I_XIAO_peak + I_MQ_peak + margin`, including startup
   and radio bursts. **Illustrative planning only:** reserving 300 mA for XIAO and
   250 mA for the module gives 550 mA before margin, 687.5 mA with 25% headroom.
   These are not measured/spec-confirmed loads. They do not approve a 500 mA port
   or prove that a 1 A source/board path is sufficient.
4. Measure the module current with a proper series/current instrument, never an
   ammeter across VBUS/GND. Measure total USB current during startup and Wi-Fi
   operation; record meter limits (a basic meter may miss short peaks). Observe
   both source and module voltage, reset/disconnect behavior and abnormal heating.
5. If source/path cannot be established, or rails sag/reset/heat occurs, STOP.
   Use a suitable protected/current-limited USB supply arrangement or separately
   powered MQ branch after review. Do not tie two USB positive rails together.
   The old separate-supply guide applies only after explicitly selecting that
   alternate topology and its sequencing; it is not the single-cable schematic.

For initial module commissioning retain the earlier conservative **4.90–5.10 V
loaded MQ supply target** pending the exact module specification. This is a project
test target, not a claim that every USB port meets it. If the actual USB source
bounds exceed it, reassess the module supply and divider before proceeding.

## Divider bounds and capacitor placement

`V_ADC = V_AO * R2/(R1+R2)`. With two 10 kOhm 1% parts the maximum ratio is 0.505:

| Assumed maximum AO | Calculated maximum node | Status |
| --- | --- | --- |
| 5.10 V | 2.5755 V | Original conditional design; commissioning ceiling 2.60 V. |
| 5.25 V | 2.65125 V | Exceeds old 2.60 V ceiling; requires explicit revised review, not automatically unsafe silicon or approved module operation. |

USB-only does **not** preserve the old 5.10 V assumption automatically. Do not
raise a ceiling simply to pass a meter reading. At 5.10 V with 5% resistors the
maximum is 2.6775 V, so nominal 10 kOhm alone is not enough for the old criterion.
Measure resistor values and source bounds; a low idle AO is not full-scale proof.
ADC attenuation is not protection, and a voltage within ADC range does not prove
that power sequencing or all transients are safe.

A 10 uF capacitor is not a silent substitute for the proposed 100 nF ADC filter.
For the unloaded equal-resistor divider the Thevenin resistance is 5 kOhm;
100 nF gives nominal RC 0.5 ms, while 10 uF gives 50 ms, before sensor/ADC effects.
That changes the observed signal and experimental timing. Supply bulk and ADC
filter capacitors have different jobs. Keep the chosen network documented/fixed.

## Commissioning sequence — ADC lead physically disconnected

All rewiring, capacitor changes and removable-link changes occur with USB unplugged
and capacitors discharged. Battery remains absent throughout.

1. **Unpowered:** verify part values/ratings, capacitor polarity and both perfboard
   sides. Remove XIAO and MQ while soldering/checking divider. Trace intended nets;
   verify no shorts or unintended connection to 3V3/BAT/DO, and no continuity
   across the OPEN ADC lead. Isolated perfboard pads require deliberate wiring.
2. **Source/divider full scale:** after power-path review, use a verified,
   suitably current-limited test source with both boards absent and ADC link open.
   With power OFF, temporarily connect the approved source to TP_AO. Apply power;
   record source and TP_ADC, compare measured-resistor ratio and approved maximum.
   Test at the approved maximum AO/source bound, or use the measured ratio to
   calculate the node at that bound with measurement uncertainty included; a
   lower test voltage alone does not establish worst-case protection. Static
   testing does not establish startup/shutdown transient behavior.
   Then power OFF, discharge and REMOVE the temporary AO-to-supply test wire.
   If no suitable test source/instrument is available, this gate is not passed;
   do not probe a loose circuit with an unprotected laptop supply as a shortcut.
3. **XIAO only:** inspect, install unpowered, connect USB with MQ branch still
   disconnected. Confirm normal MCU supply/operation and VBUS. Re-enumerate the
   actual USB identity and coordinate exclusive serial access before diagnostics.
4. **MQ branch, ADC still OPEN:** unplug USB before connecting module power/ground
   and divider; then power from the one accepted USB source. Record loaded module
   voltage, module/total current, AO/node, heater-on uptime and any abnormalities.
   Stop for current limiting, rail collapse, resets, smoke or abnormal heating.
5. **Return report below.** Only after electrical sign-off, prepare the separately
   selected serial-only ADC image. Change the ADC lead with USB unplugged. A single
   source reduces independent-supply mistakes but does not prove that the ADC can
   never drive a decaying/unpowered MCU during USB loss. Review shutdown behavior;
   disconnecting the ADC while unpowered remains the commissioning default.

```text
Laptop/hub/USB source and cable identity / available 5V current:
Actual XIAO revision / VBUS path review:
R1, R2 measured ohms and tolerances:
Each capacitor's printed code/value/rating and assigned net:
Unpowered continuity/short checks; both-side photos:
ADC lead physically OPEN; BAT and DO unconnected:
Full-scale test source V / TP_ADC V / temporary link removed:
USB VBUS unloaded / MQ loaded supply V:
MQ current / total USB startup and Wi-Fi current / meter limitations:
MQ AO V / TP_ADC V / independently observed heater-on uptime:
Abnormal heat, sag, reset or remaining uncertainty:
```

## Firmware, backend and Liam boundary

**NON-BREAKING; no client action, no API/schema/example/auth change.** USB supplies
power/serial; backend communication remains Wi-Fi. Last physically verified
`xiao_device` image has ADC/sampling/uploads disabled. No new flash/network/sensor
execution or native acceptance is established here. RAM-only Wi-Fi/device
credentials require private re-entry after reset/unplug; do not put them in chat.
No battery-percentage feature is implied or needed by this hardware revision.

After electrical acceptance collect real serial-only warm-up/idle/noise/drift/
recovery traces. No-trigger is no result, never zero alcohol. Missing pressure
sensing remains; [duration proposal](FIRMWARE_DURATION_PROPOSAL.md) is unapproved.
No sample window is fabricated as breath duration. No alcohol consumption, vapor
spraying, liquid application or flammable-gas test. Any exhalation experiment needs
an assessed dry, hygienic air path. Raw ADC is not calibrated BAC.

## Sources / evidence level

- Nicholas's group decision: USB-C-only demo, no battery; latest placement and
  reported values, IMG_2206/IMG_2207. Photos identify layout/battery, not nets,
  current ratings or readable capacitor values. Do not need these private local
  photo paths to follow the portable commissioning requirements above.
- [Seeed standard XIAO ESP32-S3 pinout, power pins and battery limitations](https://wiki.seeedstudio.com/xiao_esp32s3_getting_started/).
- [Original external-supply guide](AUSTIN_PERFBOARD_GUIDE.md) and
  [historical battery proposal](BATTERY_BOOST_COMMISSIONING.md): reference only,
  superseded for current power topology.
- [Real device connectivity evidence](DEVICE_CONNECTIVITY.md),
  [current firmware startup](FIRMWARE_BOT_STARTUP.md), [API examples](API.md).

This document contains proposed wiring, calculations and a measurement procedure,
not measured results or approval of an unseen assembly.
