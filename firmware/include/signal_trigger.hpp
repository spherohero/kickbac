#ifndef KICKBAC_SIGNAL_TRIGGER_HPP
#define KICKBAC_SIGNAL_TRIGGER_HPP

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>

namespace kickbac {

// No hardware defaults: obtain tuning from labeled physical experiments.
struct TriggerConfig {
    double on_delta_counts;
    double off_delta_counts;
    std::uint32_t sustain_ms;
    std::uint32_t recovery_ms;
    std::uint32_t cooldown_ms;
    std::uint32_t max_gap_ms;
    double alpha;
};

enum class SignalState { Uncalibrated, Ready, Candidate, Recovering, Fault };

struct TriggerResult {
    bool signal_event;
    double filtered_counts;
    double delta_counts;
};

// Local signal heuristic only. No breath validity, BAC, duration or upload API.
class SignalTrigger {
public:
    explicit SignalTrigger(TriggerConfig config) : config_(config) {
        if (!valid_config(config)) state_ = SignalState::Fault;
    }

    SignalState state() const { return state_; }

    bool set_baseline(std::uint32_t now, double counts) {
        if (state_ != SignalState::Uncalibrated && state_ != SignalState::Ready) {
            return false;
        }
        // 4095 is a rejected rail; leave onset headroom below usable 4094.
        if (!std::isfinite(counts) || counts <= 0.0 ||
            counts + config_.on_delta_counts >= 4094.0) {
            state_ = SignalState::Fault;
            return false;
        }
        baseline_ = counts;
        filtered_ = counts;
        samples_.fill(counts);
        sample_index_ = 0;
        last_sample_at_ = now;
        state_ = SignalState::Ready;
        return true;
    }

    TriggerResult update(std::uint32_t now, int raw) {
        if (state_ == SignalState::Uncalibrated || state_ == SignalState::Fault) {
            return {false, static_cast<double>(raw), 0.0};
        }
        const std::uint32_t elapsed = now - last_sample_at_;
        if (elapsed == 0 || elapsed > config_.max_gap_ms || raw <= 0 || raw >= 4095) {
            state_ = SignalState::Fault;
            return {false, filtered_, filtered_ - baseline_};
        }
        last_sample_at_ = now;
        samples_[sample_index_] = raw;
        sample_index_ = (sample_index_ + 1) % samples_.size();
        auto ordered = samples_;
        std::sort(ordered.begin(), ordered.end());
        filtered_ += config_.alpha * (ordered[1] - filtered_);
        const double delta = filtered_ - baseline_;
        bool event = false;
        if (state_ == SignalState::Ready && delta >= config_.on_delta_counts) {
            state_ = SignalState::Candidate;
            candidate_since_ = now;
        } else if (state_ == SignalState::Candidate) {
            if (delta < config_.on_delta_counts) {
                state_ = SignalState::Ready;
            } else if (now - candidate_since_ >= config_.sustain_ms) {
                state_ = SignalState::Recovering;
                event_at_ = now;
                near_baseline_ = false;
                event = true;
            }
        } else if (state_ == SignalState::Recovering) {
            if (std::fabs(delta) > config_.off_delta_counts) {
                near_baseline_ = false;
            } else if (!near_baseline_) {
                near_baseline_ = true;
                recovery_since_ = now;
            } else if (now - recovery_since_ >= config_.recovery_ms &&
                       now - event_at_ >= config_.cooldown_ms) {
                state_ = SignalState::Ready;
            }
        }
        return {event, filtered_, delta};
    }

private:
    static bool valid_interval(std::uint32_t duration) {
        return duration > 0 && duration < 0x80000000U;
    }

    static bool valid_config(const TriggerConfig& config) {
        return std::isfinite(config.on_delta_counts) &&
               std::isfinite(config.off_delta_counts) &&
               config.off_delta_counts > 0.0 &&
               config.on_delta_counts > config.off_delta_counts &&
               config.on_delta_counts < 4094.0 &&
               std::isfinite(config.alpha) && config.alpha > 0.0 && config.alpha <= 1.0 &&
               valid_interval(config.sustain_ms) && valid_interval(config.recovery_ms) &&
               valid_interval(config.cooldown_ms) && valid_interval(config.max_gap_ms) &&
               config.max_gap_ms <= config.sustain_ms &&
               config.max_gap_ms <= config.recovery_ms;
    }

    TriggerConfig config_;
    SignalState state_ = SignalState::Uncalibrated;
    double baseline_ = 0.0;
    double filtered_ = 0.0;
    std::array<double, 3> samples_{{0.0, 0.0, 0.0}};
    std::size_t sample_index_ = 0;
    std::uint32_t candidate_since_ = 0;
    std::uint32_t last_sample_at_ = 0;
    std::uint32_t event_at_ = 0;
    std::uint32_t recovery_since_ = 0;
    bool near_baseline_ = false;
};

}  // namespace kickbac
#endif
