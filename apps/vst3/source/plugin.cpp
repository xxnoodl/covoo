#include "plugin.h"
#include "pluginterfaces/base/ibstream.h"
#include <algorithm>

namespace covoo {
using namespace Steinberg;
using namespace Steinberg::Vst;

Processor::Processor(bool enableBridge) : enableBridge_(enableBridge) { setControllerClass(controllerId); }
Processor::~Processor() = default;
std::string Processor::bridgeInstance() const {
#ifdef _WIN32
    return bridge_ ? bridge_->instance() : "";
#else
    return "";
#endif
}

tresult PLUGIN_API Processor::initialize(FUnknown* context) {
    const auto result = AudioEffect::initialize(context);
    if (result != kResultOk)
        return result;
    addAudioOutput(STR16("Phone audio"), SpeakerArr::kStereo);
    return kResultOk;
}

tresult PLUGIN_API Processor::setBusArrangements(SpeakerArrangement*, int32 numIns,
    SpeakerArrangement* outputs, int32 numOuts) {
    return numIns == 0 && numOuts == 1 && outputs && outputs[0] == SpeakerArr::kStereo
        ? kResultOk : kResultFalse;
}

tresult PLUGIN_API Processor::canProcessSampleSize(int32 size) {
    return size == kSample32 || size == kSample64 ? kResultOk : kResultFalse;
}

tresult PLUGIN_API Processor::setupProcessing(ProcessSetup& setup) {
    configured_ = false;
    source_.setRunning(false);
    if (canProcessSampleSize(setup.symbolicSampleSize) != kResultOk ||
        setup.maxSamplesPerBlock < 1 || setup.maxSamplesPerBlock > 32768 ||
        (setup.processMode != kRealtime && setup.processMode != kPrefetch && setup.processMode != kOffline) ||
        !source_.configure(setup.sampleRate))
        return kInvalidArgument;
    const auto result = AudioEffect::setupProcessing(setup);
    configured_ = result == kResultOk;
    return result;
}

tresult PLUGIN_API Processor::setActive(TBool state) {
    if (!state) {
        source_.setRunning(false);
#ifdef _WIN32
        bridge_.reset();
#endif
    }
#ifdef _WIN32
    if (state && enableBridge_ && !bridge_) {
        try { bridge_ = std::make_unique<Bridge>(source_); }
        catch (...) { return kResultFalse; }
    }
#endif
    return AudioEffect::setActive(state);
}

tresult PLUGIN_API Processor::setProcessing(TBool state) {
    source_.setRunning(state != 0 && configured_);
    return kResultOk;
}

tresult PLUGIN_API Processor::process(ProcessData& data) {
    if (data.numSamples < 0 || data.numSamples > 32768 ||
        canProcessSampleSize(data.symbolicSampleSize) != kResultOk)
        return kInvalidArgument;
    // Hosts can flush parameter/event changes without an audio bus or samples.
    if (data.numSamples == 0 || data.numOutputs == 0)
        return kResultOk;
    if (data.numOutputs != 1 || !data.outputs || data.outputs[0].numChannels != 2)
        return kInvalidArgument;
    auto& bus = data.outputs[0];
    const bool invalid = !configured_ || data.numSamples > processSetup.maxSamplesPerBlock ||
        data.symbolicSampleSize != processSetup.symbolicSampleSize;
    const bool offline = invalid || data.processMode != kRealtime || processSetup.processMode != kRealtime;
    bool audible;
    if (data.symbolicSampleSize == kSample32) {
        if (!bus.channelBuffers32 || !bus.channelBuffers32[0] || !bus.channelBuffers32[1])
            return kInvalidArgument;
        audible = source_.render(bus.channelBuffers32[0], bus.channelBuffers32[1],
            static_cast<uint32>(data.numSamples), offline);
    } else {
        if (!bus.channelBuffers64 || !bus.channelBuffers64[0] || !bus.channelBuffers64[1])
            return kInvalidArgument;
        audible = source_.render(bus.channelBuffers64[0], bus.channelBuffers64[1],
            static_cast<uint32>(data.numSamples), offline);
    }
    bus.silenceFlags = audible ? 0 : 3;
    return invalid ? kInvalidArgument : kResultOk;
}

// Projects contain only a version marker, never PCM, phone or bridge credentials.
static tresult readVersion(IBStream* state) {
    uint8 version = 0;
    int32 read = 0;
    return state && state->read(&version, 1, &read) == kResultOk && read == 1 && version == 1
        ? kResultOk : kResultFalse;
}

tresult PLUGIN_API Processor::setState(IBStream* state) { return readVersion(state); }
tresult PLUGIN_API Controller::setComponentState(IBStream* state) { return readVersion(state); }
tresult PLUGIN_API Processor::getState(IBStream* state) {
    uint8 version = 1;
    int32 written = 0;
    return state && state->write(&version, 1, &written) == kResultOk && written == 1
        ? kResultOk : kResultFalse;
}

} // namespace covoo
