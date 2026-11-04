#include "plugin.h"
#include "allocation_guard.h"
#include <array>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <iostream>
#include <thread>

int main(int argc, char** argv) {
    if (argc != 3) return 2;
    using namespace Steinberg;
    using namespace Steinberg::Vst;
    auto* processor = new covoo::Processor;
    const auto rate = std::stod(argv[1]);
    const auto stopFile = std::filesystem::path(argv[2]);
    ProcessSetup setup{kRealtime, kSample32, 1024, rate};
    if (processor->initialize(nullptr) != kResultOk || processor->setupProcessing(setup) != kResultOk ||
        processor->setActive(true) != kResultOk) return 3;
    processor->setProcessing(true);
    std::cout << processor->bridgeInstance() << std::endl;
    std::array<float, 256> left{}, right{};
    float* channels[]{left.data(), right.data()};
    AudioBusBuffers bus{}; bus.numChannels = 2; bus.channelBuffers32 = channels;
    ProcessData data{}; data.processMode = kRealtime; data.symbolicSampleSize = kSample32;
    data.numOutputs = 1; data.outputs = &bus; data.numSamples = 256;
    using Clock = std::chrono::steady_clock;
    auto next = Clock::now();
    const auto timeout = next + std::chrono::seconds(30);
    auto stopping = timeout;
    std::uint64_t audible = 0;
    bool valid = true;
    bool finalSilence = false;
    bool paused = false;
    bool offlined = false;
    while (Clock::now() < stopping && Clock::now() < timeout) {
        if (stopping == timeout && std::filesystem::exists(stopFile))
            stopping = Clock::now() + std::chrono::milliseconds(500);
        bool mustBeSilent = false;
        if (!paused && audible > 500) {
            // Simulate a host that stops requesting blocks without setProcessing.
            std::this_thread::sleep_for(std::chrono::milliseconds(200));
            next = Clock::now(); paused = true; mustBeSilent = true;
        }
        if (paused && !offlined && audible > 2000) {
            data.processMode = kOffline; mustBeSilent = true; offlined = true;
        }
        tresult result;
        { CallbackGuard guard; result = processor->process(data); }
        if (result != kResultOk) valid = false;
        finalSilence = true;
        for (std::size_t i = 0; i < left.size(); ++i) {
            if (!std::isfinite(left[i]) || left[i] != right[i] || std::abs(left[i]) > 1) valid = false;
            if (left[i] != 0) { ++audible; finalSilence = false; }
        }
        if (mustBeSilent && !finalSilence) valid = false;
        data.processMode = kRealtime;
        next += std::chrono::duration_cast<Clock::duration>(std::chrono::duration<double>(256.0 / rate));
        std::this_thread::sleep_until(next);
    }
    processor->setProcessing(false);
    const auto closeStart = Clock::now();
    processor->setActive(false);
    const auto closeTime = Clock::now() - closeStart;
    processor->terminate(); processor->release();
    std::cout << "Audible synthetic frames: " << audible << "; final silence: " << finalSilence << '\n';
    return valid && paused && offlined && audible > 2000 && finalSilence && closeTime < std::chrono::seconds(2) ? 0 : 4;
}
