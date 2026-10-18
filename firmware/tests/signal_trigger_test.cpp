// Synthetic inputs only. These values are NOT hardware configuration.
#include "signal_trigger.hpp"

#include <cstdlib>
#include <iostream>
#include <limits>

void check(bool value, const char* message) {
    if (!value) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}

int main() {
    // All tuning must eventually come from actual board/sensor experiments.
    const kickbac::TriggerConfig fixture{50.0, 15.0, 300, 500, 1000, 150, 1.0};
    kickbac::SignalTrigger trigger(fixture);
    check(trigger.state() == kickbac::SignalState::Uncalibrated,
          "boot must not imply a conditioned sensor or accepted baseline");
    for (unsigned t = 0; t < 2000; t += 100) {
        check(!trigger.update(t, 1000).signal_event,
              "uncalibrated input must not produce events");
    }
    check(trigger.set_baseline(2000, 1000.0), "operator baseline accepted");
    for (unsigned t = 2100; t < 6000; t += 100) {
        check(!trigger.update(t, 1000).signal_event,
              "idle/no trigger is not a measurement or zero result");
    }
    check(trigger.state() == kickbac::SignalState::Ready, "idle stays ready");
    std::cout << "PASS: explicit baseline and no-trigger behavior (synthetic)\n";

    unsigned events = 0;
    for (unsigned t = 6000; t <= 8000; t += 100) {
        const auto sample = trigger.update(t, 1060);
        if (sample.signal_event) {
            check(t == 6400, "median delay plus full sustain determines exact event time");
            ++events;
        }
    }
    check(events == 1, "sustained signal produces exactly one event, not repeated samples");
    check(trigger.state() == kickbac::SignalState::Recovering,
          "residual exposure locks trigger until recovery");
    std::cout << "PASS: sustained crossing and one-event residual lockout (synthetic)\n";

    check(!trigger.set_baseline(8000, 1060.0),
          "cannot erase residual exposure by rebaselining during recovery");
    for (unsigned t = 8100; t <= 9000; t += 100) {
        check(!trigger.update(t, 1020).signal_event, "hysteresis band is not recovery");
    }
    check(trigger.state() == kickbac::SignalState::Recovering,
          "signal between release and onset thresholds stays locked");
    for (unsigned t = 9100; t <= 9800; t += 100) {
        check(!trigger.update(t, 1000).signal_event, "recovery does not create an event");
        if (t < 9700) {
            check(trigger.state() == kickbac::SignalState::Recovering,
                  "return to baseline must be sustained");
        } else {
            check(trigger.state() == kickbac::SignalState::Ready,
                  "recovery finishes at the exact configured boundary");
        }
    }
    check(trigger.state() == kickbac::SignalState::Ready, "recovered signal rearms");
    unsigned repeated = 0;
    for (unsigned t = 9900; t <= 10600; t += 100) {
        repeated += trigger.update(t, 1060).signal_event ? 1U : 0U;
    }
    check(repeated == 1, "a distinct post-recovery crossing can trigger again");
    std::cout << "PASS: hysteresis, sustained recovery, and repeated signal (synthetic)\n";

    kickbac::SignalTrigger cooldown(fixture);
    cooldown.set_baseline(0, 1000.0);
    for (unsigned t = 100; t <= 600; t += 100) cooldown.update(t, 1060);
    for (unsigned t = 700; t <= 1200; t += 100) cooldown.update(t, 1000);
    check(cooldown.state() == kickbac::SignalState::Recovering,
          "cooldown still applies after an early return to baseline");
    for (unsigned t = 1300; t <= 1700; t += 100) cooldown.update(t, 1000);
    check(cooldown.state() == kickbac::SignalState::Ready, "cooldown eventually completes");
    std::cout << "PASS: independent cooldown (synthetic)\n";

    auto smoothing_config = fixture;
    smoothing_config.alpha = 0.5;
    kickbac::SignalTrigger smoothing(smoothing_config);
    smoothing.set_baseline(0, 1000.0);
    check(smoothing.update(100, 1300).filtered_counts == 1000.0,
          "median-of-three removes an isolated impulse");
    check(smoothing.update(200, 1300).filtered_counts == 1150.0,
          "EWMA smooths a sustained step after the median");
    check(smoothing.update(300, 1300).filtered_counts == 1225.0,
          "filter coefficient is configurable");
    std::cout << "PASS: median plus configurable EWMA (synthetic)\n";

    kickbac::SignalTrigger gap(fixture);
    gap.set_baseline(0, 1000.0);
    gap.update(100, 1100);
    gap.update(200, 1100);
    check(!gap.update(1000, 1100).signal_event,
          "unobserved time cannot satisfy a sustained crossing");
    check(gap.state() == kickbac::SignalState::Fault,
          "sampling gap invalidates the experiment instead of guessing continuity");
    check(!gap.update(1100, 1100).signal_event, "fault is sticky");
    std::cout << "PASS: missing telemetry fails closed (synthetic)\n";

    for (int raw : {-1, 0, 4095, 4096}) {
        kickbac::SignalTrigger bad_input(fixture);
        bad_input.set_baseline(0, 1000.0);
        check(!bad_input.update(100, raw).signal_event, "invalid or rail ADC cannot trigger");
        check(bad_input.state() == kickbac::SignalState::Fault, "rail ADC latches a fault");
    }
    for (double baseline : {0.0, 4044.0, 4044.5, 4050.0, -1.0,
                            std::numeric_limits<double>::quiet_NaN()}) {
        kickbac::SignalTrigger bad_baseline(fixture);
        check(!bad_baseline.set_baseline(0, baseline),
              "baseline must be finite, non-rail, with onset headroom");
    }
    for (double alpha : {0.0, -1.0, 1.01,
                         std::numeric_limits<double>::quiet_NaN(),
                         std::numeric_limits<double>::infinity()}) {
        auto invalid = fixture;
        invalid.alpha = alpha;
        kickbac::SignalTrigger bad_config(invalid);
        check(bad_config.state() == kickbac::SignalState::Fault,
              "invalid filter configuration fails closed");
        check(!bad_config.set_baseline(0, 1000.0), "baseline cannot bypass bad configuration");
    }
    auto invalid = fixture;
    invalid.off_delta_counts = invalid.on_delta_counts;
    check(kickbac::SignalTrigger(invalid).state() == kickbac::SignalState::Fault,
          "release threshold must be lower than onset");
    invalid = fixture;
    invalid.sustain_ms = 0;
    check(kickbac::SignalTrigger(invalid).state() == kickbac::SignalState::Fault,
          "sustain cannot be zero");
    invalid = fixture;
    invalid.max_gap_ms = 0x80000000U;
    check(kickbac::SignalTrigger(invalid).state() == kickbac::SignalState::Fault,
          "timer intervals must stay below the unsigned half-range");
    std::cout << "PASS: invalid configuration, baseline, and ADC fail closed (synthetic)\n";

    auto higher_minimum = fixture;
    higher_minimum.on_delta_counts = 80.0;
    kickbac::SignalTrigger lower(fixture), higher(higher_minimum);
    lower.set_baseline(0, 1000.0);
    higher.set_baseline(0, 1000.0);
    unsigned lower_events = 0, higher_events = 0;
    for (unsigned t = 100; t <= 2000; t += 100) {
        lower_events += lower.update(t, 1060).signal_event ? 1U : 0U;
        higher_events += higher.update(t, 1060).signal_event ? 1U : 0U;
    }
    check(lower_events == 1 && higher_events == 0,
          "raising the minimum can miss a weaker signal, not identify a sober breath");
    std::cout << "PASS: higher minimum sensitivity tradeoff (synthetic)\n";

    kickbac::SignalTrigger rollover(fixture);
    const std::uint32_t start = 0xFFFFFF00U;
    rollover.set_baseline(start, 1000.0);
    unsigned rollover_events = 0;
    for (std::uint32_t dt = 100; dt <= 700; dt += 100) {
        rollover_events += rollover.update(start + dt, 1060).signal_event ? 1U : 0U;
    }
    check(rollover_events == 1, "timer rollover preserves observed sustained crossing");
    for (std::uint32_t dt = 800; dt <= 1900; dt += 100) {
        rollover.update(start + dt, 1000);
    }
    check(rollover.state() == kickbac::SignalState::Ready,
          "timer rollover preserves recovery and cooldown");
    std::cout << "PASS: unsigned timer rollover (synthetic)\n";

    kickbac::SignalTrigger interrupted(fixture);
    interrupted.set_baseline(0, 1000.0);
    for (unsigned t = 100; t <= 300; t += 100) interrupted.update(t, 1060);
    check(!interrupted.set_baseline(300, 1060.0), "cannot rebaseline a candidate");
    for (unsigned t = 400; t <= 600; t += 100) interrupted.update(t, 1000);
    check(interrupted.state() == kickbac::SignalState::Ready,
          "sub-sustain excursion resets the candidate");
    unsigned restarted_events = 0;
    for (unsigned t = 700; t <= 1200; t += 100) {
        if (interrupted.update(t, 1060).signal_event) {
            check(t == 1100, "second crossing starts a fresh sustain interval");
            ++restarted_events;
        }
    }
    check(restarted_events == 1, "second candidate produces one sustained event");
    check(!interrupted.update(1200, 1000).signal_event,
          "duplicate sample time cannot advance persistence");
    check(interrupted.state() == kickbac::SignalState::Fault,
          "duplicate timestamp is invalid telemetry");
    check(!interrupted.set_baseline(1300, 1000.0), "cannot rebaseline a latched fault");
    std::cout << "PASS: interrupted crossing and duplicate timestamp (synthetic)\n";

    kickbac::SignalTrigger headroom(fixture);
    check(headroom.set_baseline(0, 4043.5), "fractional baseline with usable headroom accepted");
    unsigned headroom_events = 0;
    for (unsigned t = 100; t <= 700; t += 100) {
        headroom_events += headroom.update(t, 4094).signal_event ? 1U : 0U;
    }
    check(headroom_events == 1, "accepted near-rail baseline still has a reachable onset");
    invalid = fixture;
    invalid.on_delta_counts = 4094.0;
    check(kickbac::SignalTrigger(invalid).state() == kickbac::SignalState::Fault,
          "onset itself must leave space for a positive baseline");
    std::cout << "PASS: fractional baseline headroom (synthetic)\n";

    for (int excursion : {900, 1080}) {
        kickbac::SignalTrigger recovery_reset(fixture);
        recovery_reset.set_baseline(0, 1000.0);
        for (unsigned t = 100; t <= 700; t += 100) recovery_reset.update(t, 1060);
        for (unsigned t = 800; t <= 1100; t += 100) recovery_reset.update(t, 1000);
        for (unsigned t = 1200; t <= 1400; t += 100) recovery_reset.update(t, excursion);
        for (unsigned t = 1500; t <= 2100; t += 100) {
            check(!recovery_reset.update(t, 1000).signal_event, "recovery has no new event");
            check(recovery_reset.state() == (t < 2100 ? kickbac::SignalState::Recovering
                                                     : kickbac::SignalState::Ready),
                  "positive or negative excursion restarts full recovery interval");
        }
    }
    std::cout << "PASS: interrupted recovery in both directions (synthetic)\n";

    kickbac::SignalTrigger gap_boundary(fixture);
    gap_boundary.set_baseline(0, 1000.0);
    gap_boundary.update(150, 1000);
    check(gap_boundary.state() == kickbac::SignalState::Ready, "exact maximum gap is allowed");
    gap_boundary.update(301, 1000);
    check(gap_boundary.state() == kickbac::SignalState::Fault, "maximum gap plus one faults");
    kickbac::SignalTrigger backward(fixture);
    backward.set_baseline(100, 1000.0);
    backward.update(90, 1000);
    check(backward.state() == kickbac::SignalState::Fault, "backward time faults");
    kickbac::SignalTrigger recovery_gap(fixture);
    recovery_gap.set_baseline(0, 1000.0);
    for (unsigned t = 100; t <= 700; t += 100) recovery_gap.update(t, 1060);
    recovery_gap.update(800, 1000);
    recovery_gap.update(900, 1000);
    recovery_gap.update(1200, 1000);
    check(recovery_gap.state() == kickbac::SignalState::Fault,
          "recovery cannot bridge unobserved time");
    std::cout << "PASS: exact gap boundary, backward time, and recovery gap (synthetic)\n";

    kickbac::SignalTrigger rebaseline(smoothing_config);
    rebaseline.set_baseline(0, 1000.0);
    rebaseline.update(100, 1010);
    rebaseline.update(200, 1010);
    check(rebaseline.set_baseline(300, 1500.0), "explicit Ready rebaseline allowed");
    const auto reseeded = rebaseline.update(400, 1500);
    check(reseeded.filtered_counts == 1500.0 && reseeded.delta_counts == 0.0 &&
          !reseeded.signal_event, "new baseline resets median and EWMA history");
    std::cout << "PASS: explicit Ready rebaseline resets filters (synthetic)\n";

    for (std::uint32_t pre_wrap_ms : {350U, 1000U, 700U}) {
        kickbac::SignalTrigger spans_wrap(fixture);
        const std::uint32_t origin = std::numeric_limits<std::uint32_t>::max() - pre_wrap_ms;
        spans_wrap.set_baseline(origin, 1000.0);
        unsigned wrapped_events = 0;
        for (std::uint32_t dt = 100; dt <= 700; dt += 100) {
            if (spans_wrap.update(origin + dt, 1060).signal_event) {
                check(dt == 500, "candidate sustain spans wrap without early event");
                ++wrapped_events;
            }
        }
        check(wrapped_events == 1, "one event across rollover");
        for (std::uint32_t dt = 800; dt <= 1500; dt += 100) {
            spans_wrap.update(origin + dt, 1000);
            check(spans_wrap.state() == (dt < 1500 ? kickbac::SignalState::Recovering
                                                 : kickbac::SignalState::Ready),
                  "recovery and cooldown spanning wrap honor exact boundaries");
        }
    }
    std::cout << "PASS: candidate, recovery, and cooldown timers spanning wrap (synthetic)\n";
}
