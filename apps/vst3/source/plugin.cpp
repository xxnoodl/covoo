#include "plugin.h"
#include "pluginterfaces/base/ibstream.h"
#include <algorithm>
#include <cstring>
#ifdef _WIN32
#include "receiver_process.h"
#include "editor.h"
#endif

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
    // Instrument hosts such as Live require an event input even for a source
    // that produces audio without notes. Events do not gate phone audio.
    addEventInput(STR16("MIDI input"), 1);
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
        try {
            bridge_ = std::make_unique<Bridge>(source_);
            if (!receiverAddress_.empty() && !receiverProfile_.empty()) {
                try { bridge_->startReceiver(receiverAddress_, receiverProfile_); receiverError_.clear(); }
                catch (const std::exception& error) { receiverError_ = error.what(); }
            }
        }
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

// Projects store public address/profile selectors, never PCM or credentials.
static bool readText(IBStream* state, std::string& text, uint8 maximum) {
    uint8 length = 0; int32 read = 0;
    if (state->read(&length, 1, &read) != kResultOk || read != 1 || length > maximum) return false;
    text.resize(length);
    return length == 0 || (state->read(text.data(), length, &read) == kResultOk && read == length);
}
static tresult readConfiguration(IBStream* state, std::string& address, std::string& profile) {
    uint8 version = 0;
    int32 read = 0;
    if (!state || state->read(&version, 1, &read) != kResultOk || read != 1) return kResultFalse;
    if (version == 1) { address.clear(); profile.clear(); return kResultOk; }
    if (version != 2 || !readText(state, address, 15) || !readText(state, profile, 32)) return kResultFalse;
#ifdef _WIN32
    if ((!address.empty() && !validAddress(address)) || (!profile.empty() && !validId(profile)) ||
        (!address.empty() && profile.empty())) return kResultFalse;
#else
    if (!address.empty() || !profile.empty()) return kResultFalse;
#endif
    return kResultOk;
}

tresult PLUGIN_API Processor::setState(IBStream* state) {
    std::string address, profile;
    const auto result = readConfiguration(state, address, profile);
    if (result == kResultOk) {
#ifdef _WIN32
        const bool active = bridge_ != nullptr;
        if (active) bridge_.reset(); // Never keep feeding an earlier preset's voice.
#endif
        receiverAddress_ = address; receiverProfile_ = profile;
#ifdef _WIN32
        if (active) {
            try {
                bridge_ = std::make_unique<Bridge>(source_);
                if (!address.empty()) bridge_->startReceiver(address, profile);
                receiverError_.clear();
            } catch (const std::exception& error) { receiverError_ = error.what(); }
        }
#endif
    }
    return result;
}
tresult PLUGIN_API Controller::setComponentState(IBStream* state) {
    std::string profile;
    return readConfiguration(state, receiverAddress, profile);
}
tresult PLUGIN_API Processor::getState(IBStream* state) {
    const uint8 version = 2;
    int32 written = 0;
    if (!state || state->write(const_cast<uint8*>(&version), 1, &written) != kResultOk || written != 1) return kResultFalse;
    for (auto* text : {&receiverAddress_, &receiverProfile_}) {
        auto length = static_cast<uint8>(text->size());
        if (state->write(&length, 1, &written) != kResultOk || written != 1) return kResultFalse;
        if (length && (state->write(text->data(), length, &written) != kResultOk || written != length)) return kResultFalse;
    }
    return kResultOk;
}

static std::string messageText(IMessage* message, const char* key) {
    const void* bytes = nullptr; uint32 length = 0;
    if (message->getAttributes()->getBinary(key, bytes, length) != kResultOk || !bytes || length > 256) return "";
    return {static_cast<const char*>(bytes), length};
}
tresult PLUGIN_API Processor::notify(IMessage* message) {
    if (!message || !message->getMessageID() || std::strcmp(message->getMessageID(), "covoo.receiver")) return AudioEffect::notify(message);
#ifdef _WIN32
    const auto command = messageText(message, "command");
    try {
        if (command == "start") {
            if (!bridge_) throw std::runtime_error("Enable the source in Live first.");
            const auto address = messageText(message, "address");
            if (!validAddress(address)) throw std::runtime_error("Choose a network interface.");
            const auto profile = receiverProfile_.empty() ? bridge_->instance() : receiverProfile_;
            bridge_->startReceiver(address, profile);
            receiverAddress_ = address; receiverProfile_ = profile; receiverError_.clear();
        } else if (command == "stop") {
            if (bridge_) bridge_->stopReceiver();
            receiverAddress_.clear();
            receiverError_.clear();
        } else if (command == "forget") {
            if (!bridge_) throw std::runtime_error("Enable the source in Live first.");
            bridge_->forgetReceiver(); receiverAddress_.clear(); receiverError_.clear();
        }
    } catch (const std::exception& error) { receiverError_ = error.what(); }
    if (auto reply = owned(allocateMessage())) {
        reply->setMessageID("covoo.receiver.state");
        const auto id = bridgeInstance();
        reply->getAttributes()->setBinary("instance", id.data(), static_cast<uint32>(id.size()));
        reply->getAttributes()->setBinary("error", receiverError_.data(), static_cast<uint32>(receiverError_.size()));
        reply->getAttributes()->setBinary("address", receiverAddress_.data(), static_cast<uint32>(receiverAddress_.size()));
        sendMessage(reply);
    }
#endif
    return kResultOk;
}
void Controller::receiverCommand(const char* command, const std::string& address) {
    if (auto message = owned(allocateMessage())) {
        message->setMessageID("covoo.receiver");
        message->getAttributes()->setBinary("command", command, static_cast<uint32>(std::strlen(command)));
        message->getAttributes()->setBinary("address", address.data(), static_cast<uint32>(address.size()));
        sendMessage(message);
        if (std::strcmp(command, "status")) setDirty(true);
    }
}
tresult PLUGIN_API Controller::notify(IMessage* message) {
    if (!message || !message->getMessageID() || std::strcmp(message->getMessageID(), "covoo.receiver.state")) return EditController::notify(message);
    instance = messageText(message, "instance");
    receiverError = messageText(message, "error");
    receiverAddress = messageText(message, "address");
    return kResultOk;
}
IPlugView* PLUGIN_API Controller::createView(FIDString name) {
#ifdef _WIN32
    if (name && !std::strcmp(name, ViewType::kEditor)) return new Editor(*this);
#else
    (void)name;
#endif
    return nullptr;
}

} // namespace covoo
