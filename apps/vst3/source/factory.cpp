#include "plugin.h"
#include "public.sdk/source/main/pluginfactory.h"

BEGIN_FACTORY_DEF("covoo", "https://github.com/xxnoodl/covoo", "")
DEF_CLASS2(INLINE_UID_FROM_FUID(covoo::processorId), Steinberg::PClassInfo::kManyInstances,
    kVstAudioEffectClass, "covoo source", 0, "Instrument", "0.1.0", kVstVersionString,
    covoo::Processor::create)
DEF_CLASS2(INLINE_UID_FROM_FUID(covoo::controllerId), Steinberg::PClassInfo::kManyInstances,
    kVstComponentControllerClass, "covoo source controller", 0, "", "0.1.0", kVstVersionString,
    covoo::Controller::create)
END_FACTORY
