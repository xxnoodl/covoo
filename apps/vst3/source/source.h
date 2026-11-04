#pragma once

#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace covoo {

#ifdef _MSC_VER
#pragma warning(push)
#pragma warning(disable: 4324) // Intentional cache-line separation of SPSC cursors.
#endif

// One feeder worker and one host audio consumer. The host owns configure/render;
// the worker owns connect/disconnect/publish. Neither side resets the other's
// cursor. A lifecycle change invalidates tagged PCM rather than racing a clear.
class Source final {
public:
    static constexpr std::uint32_t capacity = 4096;
    static constexpr std::uint32_t primeFrames = 384;
    static constexpr std::uint32_t maxBacklog = 1536;
    static_assert(std::atomic<std::uint64_t>::is_always_lock_free);
    static_assert(std::atomic<std::uint32_t>::is_always_lock_free);
    static_assert(std::atomic<double>::is_always_lock_free);
    static_assert(std::atomic<bool>::is_always_lock_free);

    // Non-real-time setup; the feeder must convert to this exact host rate.
    bool configure(double rate) noexcept {
        if (!std::isfinite(rate) || rate <= 0 || rate > 2000000)
            return false;
        setRunning(false);
        rate_.store(rate, std::memory_order_release);
        return true;
    }

    // Also safe on the audio thread. Repeated calls intentionally invalidate PCM.
    void setRunning(bool running) noexcept {
        const auto previous = gate_.load(std::memory_order_relaxed);
        gate_.store(((previous & ~std::uint64_t{1}) + 2) | (running ? 1 : 0),
                    std::memory_order_release);
    }

    bool connect(double rate) noexcept {
        disconnect();
        if (rate == 0 || rate != rate_.load(std::memory_order_acquire))
            return false;
        producerRate_ = rate;
        generation_.store(++nextGeneration_, std::memory_order_release);
        return true;
    }

    void disconnect() noexcept { generation_.store(0, std::memory_order_release); }

    // Whole-block rejection; only the feeder worker touches producer state.
    bool publish(const float* pcm, std::uint32_t count, std::uint64_t expectedGate = 0) noexcept {
        const auto gate = gate_.load(std::memory_order_acquire);
        const auto generation = generation_.load(std::memory_order_acquire);
        if (!pcm || count == 0 || count > capacity || !(gate & 1) || generation == 0 ||
            (expectedGate != 0 && expectedGate != gate) ||
            offline_.load(std::memory_order_acquire) ||
            producerRate_ != rate_.load(std::memory_order_acquire))
            return false;
        const auto write = write_.load(std::memory_order_relaxed);
        const auto read = read_.load(std::memory_order_acquire);
        if (count > capacity - (write - read)) {
            rejected_.fetch_add(count, std::memory_order_relaxed);
            return false;
        }
        for (std::uint32_t i = 0; i < count; ++i)
            if (!std::isfinite(pcm[i]))
                return false;
        for (std::uint32_t i = 0; i < count; ++i)
            frames_[(write + i) % capacity] = {pcm[i], generation, gate};
        write_.store(write + count, std::memory_order_release);
        return true;
    }

    // Host-rate mono PCM duplicated to stereo. No allocation, locks, IPC, clock
    // queries, file access or waiting. Output starvation is silence, never replay.
    template<class Sample>
    bool render(Sample* left, Sample* right, std::uint32_t count, bool offline) noexcept {
        if (offline != consumerOffline_) {
            if (offline) offline_.store(true, std::memory_order_release);
            const auto previous = gate_.load(std::memory_order_relaxed);
            gate_.store(((previous & ~std::uint64_t{1}) + 2) | (previous & 1),
                        std::memory_order_release);
            if (!offline) offline_.store(false, std::memory_order_release);
            consumerOffline_ = offline;
        }
        const auto gate = gate_.load(std::memory_order_acquire);
        const auto generation = generation_.load(std::memory_order_acquire);
        auto read = read_.load(std::memory_order_relaxed);
        const auto write = write_.load(std::memory_order_acquire);
        if (gate != consumerGate_ || generation != consumerGeneration_) {
            primed_ = false;
            consumerGate_ = gate;
            consumerGeneration_ = generation;
        }
        bool audible = false;
        const bool enabled = (gate & 1) && generation != 0 && !offline;
        if (!enabled) {
            read = write;
            primed_ = false;
        } else {
            const auto beforeStale = read;
            while (read != write && !matches(frames_[read % capacity], generation, gate)) {
                ++read;
            }
            discarded_.fetch_add(read - beforeStale, std::memory_order_relaxed);
            const auto available = write - read;
            // The consumer alone may trim excessive backlog. Keep enough for
            // this host block plus a startup target; never overwrite unread PCM.
            if (available > maxBacklog && available > count + primeFrames) {
                const auto trim = available - count - primeFrames;
                read += trim;
                discarded_.fetch_add(trim, std::memory_order_relaxed);
            }
            if (!primed_ && write - read >= primeFrames)
                primed_ = true;
        }
        std::uint32_t silence = 0;
        for (std::uint32_t i = 0; i < count; ++i) {
            float value = 0;
            if (enabled && primed_ && read != write &&
                matches(frames_[read % capacity], generation, gate)) {
                value = frames_[read++ % capacity].value;
            } else {
                primed_ = false;
                ++silence;
            }
            left[i] = right[i] = static_cast<Sample>(value);
            audible = audible || value != 0;
        }
        // A concurrent disconnect invalidates this block too. A change after
        // this check becomes visible at the next callback boundary.
        if (generation_.load(std::memory_order_acquire) != generation ||
            gate_.load(std::memory_order_acquire) != gate) {
            for (std::uint32_t i = 0; i < count; ++i)
                left[i] = right[i] = 0;
            primed_ = false;
            audible = false;
        }
        read_.store(read, std::memory_order_release);
        if ((gate & 1) && !offline) {
            clock_.fetch_add(count, std::memory_order_relaxed);
            block_.store(count, std::memory_order_relaxed);
        }
        if (enabled)
            silence_.fetch_add(silence, std::memory_order_relaxed);
        return audible;
    }

    std::uint64_t silenceFrames() const noexcept { return silence_.load(std::memory_order_relaxed); }
    std::uint64_t rejectedFrames() const noexcept { return rejected_.load(std::memory_order_relaxed); }
    std::uint64_t discardedFrames() const noexcept { return discarded_.load(std::memory_order_relaxed); }
    struct Feedback {
        double rate;
        std::uint64_t gate, clock;
        std::uint32_t queued, block;
        bool running;
    };
    Feedback feedback() const noexcept {
        const auto gate = gate_.load(std::memory_order_acquire);
        const auto rate = rate_.load(std::memory_order_acquire);
        const auto read = read_.load(std::memory_order_acquire);
        const auto queued = write_.load(std::memory_order_acquire) - read;
        return {rate, gate, clock_.load(std::memory_order_relaxed),
            queued > capacity ? capacity : queued, block_.load(std::memory_order_relaxed),
            (gate & 1) && !offline_.load(std::memory_order_acquire) &&
                gate == gate_.load(std::memory_order_acquire)};
    }

private:
    struct Frame { float value; std::uint64_t generation; std::uint64_t gate; };
    static bool matches(const Frame& f, std::uint64_t generation, std::uint64_t gate) noexcept {
        return f.generation == generation && f.gate == gate;
    }
    std::array<Frame, capacity> frames_{};
    alignas(64) std::atomic<std::uint32_t> write_{0};
    alignas(64) std::atomic<std::uint32_t> read_{0};
    std::atomic<std::uint64_t> generation_{0}, gate_{0};
    std::atomic<double> rate_{0};
    std::atomic<bool> offline_{false};
    std::atomic<std::uint64_t> clock_{0};
    std::atomic<std::uint32_t> block_{0};
    std::atomic<std::uint64_t> silence_{0}, rejected_{0}, discarded_{0};
    std::uint64_t nextGeneration_{0}; // producer only
    double producerRate_{0}; // producer only
    std::uint64_t consumerGate_{0}, consumerGeneration_{0}; // consumer only
    bool primed_{false}; // consumer only
    bool consumerOffline_{false}; // consumer only
};

#ifdef _MSC_VER
#pragma warning(pop)
#endif

} // namespace covoo
