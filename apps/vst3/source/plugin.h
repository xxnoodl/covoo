#pragma once

#include "source.h"
#include "public.sdk/source/vst/vstaudioeffect.h"
#include "public.sdk/source/vst/vsteditcontroller.h"

namespace covoo {

inline const Steinberg::FUID processorId(0x8E1241F6, 0x684D4654, 0xA67C4F4B, 0x163793AD);
inline const Steinberg::FUID controllerId(0x137258EB, 0xC19048EB, 0xBE5AACD0, 0x70121342);

class Processor final : public Steinberg::Vst::AudioEffect {
public:
    Processor();
    static Steinberg::FUnknown* create(void*) {
        return static_cast<Steinberg::Vst::IAudioProcessor*>(new Processor);
    }
    Steinberg::tresult PLUGIN_API initialize(Steinberg::FUnknown*) override;
    Steinberg::tresult PLUGIN_API setBusArrangements(Steinberg::Vst::SpeakerArrangement*, Steinberg::int32,
        Steinberg::Vst::SpeakerArrangement*, Steinberg::int32) override;
    Steinberg::tresult PLUGIN_API canProcessSampleSize(Steinberg::int32) override;
    Steinberg::tresult PLUGIN_API setupProcessing(Steinberg::Vst::ProcessSetup&) override;
    Steinberg::tresult PLUGIN_API setActive(Steinberg::TBool) override;
    Steinberg::tresult PLUGIN_API setProcessing(Steinberg::TBool) override;
    Steinberg::tresult PLUGIN_API process(Steinberg::Vst::ProcessData&) override;
    Steinberg::tresult PLUGIN_API getState(Steinberg::IBStream*) override;
    Steinberg::tresult PLUGIN_API setState(Steinberg::IBStream*) override;

    // C++ feeder interface, not a host API or exported authentication bypass.
    // This foundation has no IPC worker; only the offline harness feeds it.
    Source& source() noexcept { return source_; }
private:
    Source source_;
    bool configured_{false};
};

class Controller final : public Steinberg::Vst::EditController {
public:
    static Steinberg::FUnknown* create(void*) {
        return static_cast<Steinberg::Vst::IEditController*>(new Controller);
    }
    Steinberg::tresult PLUGIN_API setComponentState(Steinberg::IBStream*) override;
};

} // namespace covoo
