#ifndef KICKBAC_SESSION_SAFETY_HPP
#define KICKBAC_SESSION_SAFETY_HPP

#include "device_diagnostic.hpp"

namespace kickbac {

struct SessionTicket {
    std::uint64_t generation = 0;
    char id[37] = {};
};

// Local fail-closed fence, NOT a server session lifecycle or breath detector.
// Caller supplies current synchronized UTC upper bound and uint32 millis().
// A conservative UTC upper bound avoids extending expiry through clock rounding.
class SessionFence {
public:
    static constexpr std::uint32_t freshness_ms = 5000;

    void clear() {
        snapshot_ = PollSnapshot{};
        ++generation_;
        remaining_ms_ = 0;
    }

    bool tick(std::uint32_t now, std::int64_t utc_upper_ms) {
        // Keep a monotonic UTC high-water anchor even across clear(). UTC rollback
        // must not resurrect an expired session by issuing a fresh ticket.
        if (clock_ready_) clock_ms_ += now - clock_at_ms_;
        if (utc_upper_ms > clock_ms_) clock_ms_ = utc_upper_ms;
        clock_at_ms_ = now;
        clock_ready_ = true;
        if (snapshot_.state != PollState::Armed && snapshot_.state != PollState::Sampling) return false;
        if (utc_upper_ms <= 0 || clock_ms_ >= expiry_ms_ ||
            now - origin_ms_ >= remaining_ms_ || now - last_poll_ms_ >= freshness_ms) {
            clear();
            return false;
        }
        return true;
    }

    bool observe(const PollSnapshot& incoming, std::uint32_t now, std::int64_t utc_upper_ms) {
        tick(now, utc_upper_ms);
        std::int64_t expiry = 0;
        if ((incoming.state != PollState::Armed && incoming.state != PollState::Sampling) ||
            !uuid_text(incoming.id) || !utc_epoch_ms(incoming.expires_at, expiry) ||
            utc_upper_ms <= 0 || expiry <= clock_ms_ || expiry - clock_ms_ > 60000) {
            clear();
            return false;
        }
        const bool same = snapshot_.state != PollState::Invalid && std::strcmp(snapshot_.id, incoming.id) == 0;
        if (same && (std::strcmp(snapshot_.expires_at, incoming.expires_at) != 0 ||
                     (snapshot_.state == PollState::Sampling && incoming.state == PollState::Armed))) {
            clear();
            return false;
        }
        if (!same) {
            clear();
            origin_ms_ = now;
            remaining_ms_ = static_cast<std::uint32_t>(expiry - clock_ms_);
        } else {
            // Never move the original monotonic deadline later, even after UTC steps backwards.
            const auto candidate = static_cast<std::uint32_t>(expiry - clock_ms_);
            const auto elapsed = now - origin_ms_;
            if (candidate < remaining_ms_ - elapsed) remaining_ms_ = elapsed + candidate;
        }
        snapshot_ = incoming;
        expiry_ms_ = expiry;
        last_poll_ms_ = now;
        return true;
    }

    bool begin(SessionTicket& ticket, std::uint32_t now, std::int64_t utc_upper_ms) {
        ticket = SessionTicket{};
        if (!tick(now, utc_upper_ms) || snapshot_.state != PollState::Armed) return false;
        ticket.generation = generation_;
        std::strcpy(ticket.id, snapshot_.id);
        return true;
    }

    bool matches(const SessionTicket& ticket, std::uint32_t now, std::int64_t utc_upper_ms) {
        return tick(now, utc_upper_ms) && ticket.generation == generation_ &&
               std::strcmp(ticket.id, snapshot_.id) == 0;
    }

    const PollSnapshot& snapshot() const { return snapshot_; }

private:
    PollSnapshot snapshot_;
    std::uint64_t generation_ = 0;
    std::int64_t expiry_ms_ = 0;
    std::uint32_t origin_ms_ = 0;
    std::uint32_t remaining_ms_ = 0;
    std::uint32_t last_poll_ms_ = 0;
    bool clock_ready_ = false;
    std::int64_t clock_ms_ = 0;
    std::uint32_t clock_at_ms_ = 0;
};

// Transport-neutral immutable pending bytes, deliberately NOT an uploader or a
// schema/acquisition validator. No UUID generation, ADC or request is performed.
// An unknown outcome must keep these ORIGINAL bytes/IDs, even if polling goes
// idle or a new session appears. Only exact server acceptance clears the slot.
// RAM only: reset loses the pending record; durable retry is not established.
class FrozenUpload {
public:
    bool ready() const { return body_[0] != '\0'; }
    const char* body() const { return body_; }
    const char* session_id() const { return session_id_; }
    const char* measurement_id() const { return measurement_id_; }

    bool seal(const char* session, const char* measurement, const char* payload) {
        if (ready() || !uuid_text(session) || !uuid_text(measurement) || payload == nullptr ||
            std::strlen(payload) == 0 || std::strlen(payload) > 768) return false;
        StaticJsonDocument<1536> document;
        if (deserializeJson(document, payload, DeserializationOption::NestingLimit(4))) return false;
        const JsonObjectConst root = document.as<JsonObjectConst>();
        if (!root["session_id"].is<const char*>() || !root["measurement_id"].is<const char*>() ||
            std::strcmp(root["session_id"].as<const char*>(), session) != 0 ||
            std::strcmp(root["measurement_id"].as<const char*>(), measurement) != 0) return false;
        std::strcpy(session_id_, session);
        std::strcpy(measurement_id_, measurement);
        std::strcpy(body_, payload);
        return true;
    }

    bool acknowledge(int status, const char* measurement, const char* session) {
        if (!ready() || (status != 200 && status != 201) || measurement == nullptr || session == nullptr ||
            std::strcmp(measurement_id_, measurement) != 0 || std::strcmp(session_id_, session) != 0) return false;
        std::memset(body_, 0, sizeof(body_));
        std::memset(session_id_, 0, sizeof(session_id_));
        std::memset(measurement_id_, 0, sizeof(measurement_id_));
        return true;
    }

private:
    char body_[769] = {};
    char session_id_[37] = {};
    char measurement_id_[37] = {};
};

}  // namespace kickbac
#endif
