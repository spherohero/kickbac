# Battery / boost perfboard revision — commissioning hold

> **Historical proposal — not the current parts list.** Nicholas subsequently clarified that components are only placed on perfboard, not soldered or connected, with **no boost converter, no pressure sensor and no installed JP1**. The replacement MQ heater supply/final power topology is not established. Do not use this battery/boost document as authorization to add a converter or wire that obsolete proposal. Continue software-only backend/firmware communication tests independently; actual supply/protection checks apply before powered acquisition, not before host tests.

**PROPOSED ASSEMBLY; NOT ELECTRICALLY SIGNED OFF.** This reconciles Nicholas's
shared `kickBAC_firmware_hardware_pinout.md` and the practical pad-map in the
[teammate's shared wiring discussion](https://chatgpt.com/share/6ad43156-0ec0-83ea-8d6e-72c96b086058).
The discussion and drawing were inspected, not the physical assembly. They are
not component datasheets, measurements or firmware acceptance evidence.

## Which revision applies?

- The proposed build uses isolated-pad perfboard, a nominal 3.7 V LiPo feeding
  XIAO BAT and a separately switched 5 V boost branch feeding the MQ module.
  There is **no installed JP1** in this proposal. Actual construction is unknown.
- [Austin's original guide](AUSTIN_PERFBOARD_GUIDE.md) describes a different,
  USB-powered XIAO / external regulated sensor supply with a removable JP1.
  Its supply assumptions and shutdown instructions are not automatic sign-off
  for battery/boost operation. Do not combine the two positive supply schemes.
- Keep a removable ADC connection **physically open** during commissioning.
  Without a JP1 component, leave an insulated, labelled TP_ADC-to-D0 lead
  disconnected, or remove the socketed XIAO so D0 is electrically isolated.
  Do not solder that link permanently for initial testing. Removing USB alone
  does not isolate a battery-powered XIAO; turning the MQ switch off does not
  disconnect the battery from the XIAO.
- Pressure sensing is confirmed unavailable, not pending pin assignment. Leave
  the reserved header unwired. The last physically verified `xiao_device` image
  already supports Wi-Fi/authenticated heartbeat/polling, with ADC/sampling/uploads
  disabled. The attachment's USB-only/network-disabled status is historical.

## Electrical nets to check, independent of hole coordinates

| Net | Intended connections in the proposal |
| --- | --- |
| BAT+ | Protected, suitable single-cell rechargeable LiPo positive to XIAO underside BAT+; branch through MQ switch to boost IN+. Battery/protection ratings and polarity are unverified. |
| Common GND | Battery negative, XIAO BAT-/GND, verified boost IN-/OUT- common return, MQ GND, R2/C1/C2/C3 ground ends. Confirm actual converter terminals/topology first. |
| +5V_MQ | Boost OUT+ to MQ VCC, C2 100 nF supply end, C3 10 uF positive. Never connect to XIAO VBUS/5V, 3V3, BAT+ or a GPIO. |
| TP_AO | MQ AO to upper resistor R1, nominal 10 kOhm, 1%. DO remains unconnected. |
| TP_ADC | R1 other end, lower R2 10 kOhm to GND, C1 100 nF to GND. Removable connection to XIAO D0/A0 = GPIO1 = ADC1_CH0 stays open pending sign-off. |
| Sensor decoupling | C2 and C3 in parallel across MQ VCC/GND, near connector; C3 negative to GND. C1 near R2/D0. Verify capacitor voltage ratings and C3 polarity. |

Seeed documents BAT- nearer USB-C and BAT+ farther from USB-C; inspect actual
board markings before connection. The normal header 5V/3V3 pins are not BAT pads.
The standard board has no assigned onboard battery-voltage ADC. Firmware cannot
report real battery percentage or enforce cell protection with this wiring.

## Perfboard and drawing checks

The practical pad-map labels its component and mirrored solder sides and uses
blue bare solid-copper links versus magenta insulated wires. Each isolated pad
needs its intended copper/lead connection; solder bonds those conductors, not
long solder-only tracks. Insulate crossings; do not solder crossings together.

The map rotates the XIAO USB end toward the bottom and labels D0 at I29, not C21.
That coordinate is **specific to the drawing**, not a universal XIAO location or
verified fit on Austin's board. Dry-fit the actual sockets, board and connectors
unpowered. Trace by printed pin labels and a continuity meter. Do not derive
physical boost terminal order from the drawing's abstract VIN/VOUT box.

If the XIAO has battery leads soldered underneath, removing it from its sockets
may isolate D0 but does not itself remove battery power. Disconnect all energy
sources before soldering, rewiring, moving socketed parts or changing the ADC link.

## Power and protection gates

1. Obtain actual battery label/datasheet, protection-board identity and rated
   charge/discharge limits; verify connector/pad polarity and condition. The
   reported PKCELL LP503035 / 500 mAh description is not yet a physical check.
   Keep the cell away from the heater, sharp leads and hot soldering work.
2. Identify boost model, actual labelled terminals, input/output ratings,
   regulation tolerance, startup behavior and low-voltage cutoff. Review the
   combined XIAO/radio + heater/boost load against cell/protection ratings.
   An MQ-only switch is not a master disconnect or overdischarge protection.
3. Do not energize the assembled battery/boost revision until those parts and
   unpowered wiring are reviewed. A qualified hardware owner can characterize
   the identified converter separately using a suitable current-limited source
   and its actual specification. Do not test unknown parts directly on the cell.
4. Review charging/load paths. Keep the boost/MQ branch off during USB charging
   until simultaneous operation is assessed. This alone does not verify charger
   compatibility with the actual cell or all XIAO load behavior.
5. Establish maximum AO/boost voltage including credible startup/load-change
   behavior and resistor tolerance before approving the divider. A meter's low
   idle reading cannot exclude transients or establish worst-case protection.
   Record scope results if available; absent transient evidence stays unknown.
6. For two 10 kOhm 1% resistors, maximum divider ratio is 0.505. **If** maximum
   AO is established as 5.10 V, calculated TP_ADC maximum is 2.5755 V. Keep the
   original 2.60 V commissioning ceiling for that conditional design; do not
   assume a nominal "5 V" boost meets the premise. Reassess different parts/bounds.
7. Never power the heater from XIAO 3V3/GPIO or treat ADC attenuation as protection.
   Prevent the boost from driving an unpowered MCU input. A common battery is
   not a hardware interlock: rail sequencing, depletion and cutoffs may differ.

## Divider test and return report

With USB and battery disconnected, boost off, capacitors discharged, ADC link
open and both XIAO/MQ absent from the divider: check R1/R2, intended continuity,
no unintended shorts and C3 polarity. After approving a test source, temporarily
connect that source to TP_AO with power off. Apply power and record source and
TP_ADC voltages; require the expected measured-resistor ratio and ceiling.
Switch off, discharge and **remove the temporary full-scale test connection**.

Only after supply review, test the MQ module with D0 still physically isolated;
record loaded supply, current, AO, TP_ADC and independently observed heater-on
uptime. Investigate current limiting, unstable rails or abnormal heat before
continuing. Never place an ammeter across the supply.

Return this report plus clear component/solder-side and connector-label photos:

```text
Actual battery label / protection identity and ratings:
Battery polarity / measured voltage / condition:
Boost model / terminal labels / input-output ratings / cutoff:
Unpowered net checks and absent unintended bridges:
ADC link physically isolated by:
R1 / R2 measured ohms and tolerance:
Boost unloaded / loaded voltage and MQ current:
Verified worst-case output bounds / startup evidence or unknowns:
Full-scale test source V / TP_ADC V:
Temporary full-scale connection removed (yes/no):
Module AO V / TP_ADC V / observed heater-on uptime:
USB charging and concurrent-load review status:
Component side / solder side / battery-boost labels photos:
Abnormal heat, current limiting, instability or unresolved observations:
```

After acceptance only: change the removable signal connection with all power
removed, verify MCU supply before enabling boost, disable boost and discharge
sensor output before removing MCU power. Assess accidental power loss/cutoff as
well as normal sequencing; instructions alone are not an interlock.

## Firmware/API boundary

No driver, GPIO assignment change, battery telemetry, acquisition mode or API
change is authorized by this document. A manual MQ power switch has no GPIO
feedback: MCU uptime cannot establish heater uptime/conditioning. Raw ADC is not
BAC; MQ threshold time is not breath duration; no trigger means no result.
Protected serial-only ADC execution requires electrical sign-off and an identified
board/exclusive serial session. Measurement uploads remain disabled pending
truthful acquisition semantics and Nicholas's explicit duration decision.
No alcohol consumption, liquid/vapor application or flammable-gas test. Assess a
dry, hygienic air path before any exhalation experiment.

Sources: [Seeed standard board pinout and battery guidance](https://wiki.seeedstudio.com/xiao_esp32s3_getting_started/),
[existing electrical guide](AUSTIN_PERFBOARD_GUIDE.md), the group attachment and
shared discussion above. No physical assembly, battery, charging, heater, ADC or
new network result is established by this review.
