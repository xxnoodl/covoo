#include "plugin.h"
#include "allocation_guard.h"
#include "public.sdk/source/common/memorystream.h"
#include <array>
#include <iostream>
#include <stdexcept>

using namespace Steinberg;
using namespace Steinberg::Vst;

static void require(bool value, const char* message) {
    if (!value) throw std::runtime_error(message);
}

static void exercise(int32 sampleSize, double rate) {
    auto* processor = new covoo::Processor;
    require(processor->initialize(nullptr) == kResultOk, "initialize failed");
    require(processor->getBusCount(kAudio, kInput) == 0, "hardware input bus exposed");
    require(processor->getBusCount(kAudio, kOutput) == 1, "output bus missing");
    ProcessSetup setup{kRealtime, sampleSize, 1024, rate};
    require(processor->setupProcessing(setup) == kResultOk, "setup failed");
    require(processor->setActive(true) == kResultOk, "activation failed");
    { CallbackGuard guard; processor->setProcessing(true); }
    auto& source = processor->source();
    require(source.connect(static_cast<std::uint32_t>(rate)), "host-rate feeder rejected");
    std::array<float, 1024> input;
    for (std::size_t i = 0; i < input.size(); ++i) input[i] = static_cast<float>(i + 1) / 2048;
    require(source.publish(input.data(), 1024), "synthetic feeder failed");
    std::array<float, 2048> fLeft{}, fRight{};
    std::array<double, 2048> dLeft{}, dRight{};
    float* floats[]{fLeft.data(), fRight.data()};
    double* doubles[]{dLeft.data(), dRight.data()};
    AudioBusBuffers bus{};
    bus.numChannels = 2;
    if (sampleSize == kSample32) bus.channelBuffers32 = floats;
    else bus.channelBuffers64 = doubles;
    ProcessData data{};
    data.processMode = kRealtime;
    data.symbolicSampleSize = sampleSize;
    data.numOutputs = 1;
    data.outputs = &bus;
    std::size_t offset = 0;
    for (int32 block : {1, 63, 128, 256, 512}) {
        data.numSamples = block;
        tresult result;
        { CallbackGuard guard; result = processor->process(data); }
        require(result == kResultOk && bus.silenceFlags == 0, "processing failed or falsely silent");
        for (int32 i = 0; i < block; ++i) {
            const auto value = sampleSize == kSample32 ? fLeft[i] : dLeft[i];
            const auto right = sampleSize == kSample32 ? fRight[i] : dRight[i];
            require(value == input[offset + i] && value == right, "VST PCM/stereo mismatch");
        }
        offset += block;
    }
    source.disconnect();
    { CallbackGuard guard; processor->process(data); }
    require(bus.silenceFlags == 3, "disconnect silence flags wrong");
    for (int32 i = 0; i < data.numSamples; ++i)
        require((sampleSize == kSample32 ? fLeft[i] : dLeft[i]) == 0, "disconnect voice replayed");

    source.connect(static_cast<std::uint32_t>(rate));
    require(source.publish(input.data(), 1024), "offline input failed");
    data.processMode = kOffline;
    { CallbackGuard guard; processor->process(data); }
    require(bus.silenceFlags == 3, "offline bounce emitted live input");
    data.processMode = kRealtime;
    { CallbackGuard guard; processor->process(data); }
    require(bus.silenceFlags == 3, "offline return replayed voice");

    MemoryStream state;
    require(processor->getState(&state) == kResultOk, "state save failed");
    require(state.getSize() == 1, "state contains more than version marker");
    state.seek(0, IBStream::kIBSeekSet, nullptr);
    require(processor->setState(&state) == kResultOk, "state restore failed");
    require(processor->setState(nullptr) != kResultOk, "null state accepted");
    data.numSamples = 1025;
    { CallbackGuard guard; require(processor->process(data) == kInvalidArgument, "oversized block accepted"); }
    { CallbackGuard guard; processor->setProcessing(false); }
    processor->setActive(false);
    processor->terminate();
    processor->release();
}

int main() {
    try {
        for (auto size : {kSample32, kSample64})
            for (auto rate : {44100., 48000., 96000.}) exercise(size, rate);
        std::cout << "Actual VST processor PCM, block/rate, lifecycle, offline and state checks passed.\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << e.what() << '\n';
        return 1;
    }
}
