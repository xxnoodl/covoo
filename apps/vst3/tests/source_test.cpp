#include "source.h"
#include "allocation_guard.h"
#include <algorithm>
#include <array>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <thread>

static void require(bool value, const char* message) {
    if (!value) throw std::runtime_error(message);
}

template<class Sample, std::size_t Size>
static bool render(covoo::Source& source, std::array<Sample, Size>& left,
    std::array<Sample, Size>& right, bool offline = false) {
    CallbackGuard guard;
    return source.render(left.data(), right.data(), static_cast<std::uint32_t>(Size), offline);
}

static void lifecycle() {
    covoo::Source source;
    std::array<float, 512> pcm;
    pcm.fill(0.25f);
    std::array<float, 128> left{}, right{};
    require(!source.connect(48000), "unconfigured source connected");
    require(source.configure(48000), "48 kHz rejected");
    require(!source.connect(44100), "wrong feeder rate connected");
    require(source.connect(48000), "matching feeder rejected");
    require(!source.publish(pcm.data(), 512), "stopped source accepted voice");
    { CallbackGuard guard; source.setRunning(true); }
    require(source.publish(pcm.data(), 512), "voice rejected");
    require(render(source, left, right), "voice missing");
    for (std::size_t i = 0; i < left.size(); ++i)
        require(left[i] == 0.25f && left[i] == right[i], "stereo PCM changed");
    source.disconnect();
    require(!render(source, left, right), "disconnect replayed voice");
    for (float value : left) require(value == 0, "disconnect not silent");
    require(source.connect(48000), "reconnect failed");
    require(source.publish(pcm.data(), 512), "reconnected voice rejected");
    { CallbackGuard guard; source.setRunning(false); source.setRunning(true); }
    require(!render(source, left, right), "stop/start replayed old PCM");
    pcm.fill(0.5f);
    require(source.publish(pcm.data(), 512), "fresh voice rejected");
    require(render(source, left, right), "fresh voice missing");
    require(left[0] == 0.5f, "old generation leaked");
    source.disconnect();
    require(source.connect(48000), "next take failed");
    pcm.fill(0.75f);
    require(source.publish(pcm.data(), 512), "next take rejected");
    require(render(source, left, right) && left[0] == 0.75f,
        "reconnect without intermediate render replayed previous take");
    require(!render(source, left, right, true), "offline bounce consumed live voice");
    require(!source.publish(pcm.data(), 512), "offline render accepted live voice");
    require(!render(source, left, right), "offline-to-live replayed queued voice");
    require(!source.configure(std::numeric_limits<double>::quiet_NaN()), "NaN rate accepted");
    require(!source.configure(0), "zero rate accepted");
    require(source.configure(96000), "96 kHz rejected");
    source.setRunning(true);
    require(!source.publish(pcm.data(), 512), "old feeder survived rate change");
    require(source.connect(96000), "host-rate feeder rejected");
    require(source.publish(pcm.data(), 512), "host-rate PCM rejected");
    std::array<double, 64> doubleLeft{}, doubleRight{};
    require(render(source, doubleLeft, doubleRight), "64-bit host got silence");
    require(doubleLeft[0] == 0.75 && doubleLeft == doubleRight, "64-bit stereo changed");
}

static void boundsAndStarvation() {
    covoo::Source source;
    source.configure(44100);
    source.setRunning(true);
    source.connect(44100);
    std::array<float, covoo::Source::capacity> pcm;
    for (std::size_t i = 0; i < pcm.size(); ++i) pcm[i] = static_cast<float>(i + 1);
    require(!source.publish(nullptr, 1), "null PCM accepted");
    require(!source.publish(pcm.data(), 0), "empty PCM accepted");
    require(!source.publish(pcm.data(), covoo::Source::capacity + 1), "oversized block accepted");
    pcm[17] = std::numeric_limits<float>::infinity();
    require(!source.publish(pcm.data(), 512), "non-finite PCM accepted");
    pcm[17] = 18;
    require(source.publish(pcm.data(), covoo::Source::capacity), "capacity block rejected");
    require(!source.publish(pcm.data(), 1), "queue overwrote unread PCM");
    require(source.rejectedFrames() == 1, "overflow not counted");
    std::array<float, 128> left{}, right{};
    require(render(source, left, right), "full queue silent");
    require(left[0] == 3585 && left[127] == 3712, "backlog trim/order incorrect");
    require(source.discardedFrames() == 3584, "trim not counted");
    for (int i = 0; i < 4; ++i) render(source, left, right);
    require(!render(source, left, right), "starvation replayed last sample");
    require(source.silenceFrames() >= 128, "starvation silence uncounted");
    require(source.publish(pcm.data(), 100), "small block rejected");
    require(!render(source, left, right), "unprimed source emitted PCM");
    require(source.publish(pcm.data() + 100, 284), "priming block rejected");
    require(render(source, left, right), "primed source stayed silent");
    require(left[0] == 1 && left[127] == 128, "priming reordered samples");
    covoo::Source other;
    other.configure(44100); other.setRunning(true); other.connect(44100);
    require(!render(other, left, right), "another instance inherited audio");
}

static void concurrent() {
    covoo::Source source;
    source.configure(48000); source.setRunning(true); source.connect(48000);
    constexpr std::uint32_t total = 1000000;
    std::atomic<bool> done{false};
    std::thread producer([&] {
        std::array<float, 127> block{};
        for (std::uint32_t sent = 0; sent < total;) {
            const auto count = std::min<std::uint32_t>(127, total - sent);
            for (std::uint32_t i = 0; i < count; ++i) block[i] = static_cast<float>(sent + i + 1);
            if (source.publish(block.data(), count)) sent += count;
            else std::this_thread::yield();
        }
        std::array<float, 384> padding{};
        while (!source.publish(padding.data(), 384)) std::this_thread::yield();
        done.store(true, std::memory_order_release);
    });
    float previous = 0;
    bool valid = true;
    std::uint64_t observed = 0;
    std::array<float, 63> left{}, right{};
    while (!done.load(std::memory_order_acquire) || previous < total) {
        render(source, left, right);
        for (std::size_t i = 0; i < left.size(); ++i) {
            if (left[i] != right[i]) valid = false;
            if (left[i] == 0) continue;
            if (left[i] <= previous || left[i] > total) valid = false;
            previous = left[i];
            ++observed;
        }
        std::this_thread::yield();
    }
    producer.join();
    require(valid && observed > 0 && previous == total, "concurrent queue reordered/replayed PCM");
    std::cout << "Concurrent frames observed: " << observed << ", discarded: " << source.discardedFrames() << '\n';
}

int main() {
    try {
        lifecycle(); boundsAndStarvation(); concurrent();
        std::cout << "Source lifecycle, bounds, rates, stereo, starvation and concurrency passed.\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << e.what() << '\n';
        return 1;
    }
}
