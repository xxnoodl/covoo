/* macOS SDK test. Substitute input rendering; never create/start a hardware unit. */
#include "CaptureBridge.h"
#include <assert.h>
#include <math.h>
#include <mach/mach_time.h>
#include <stdio.h>

static bool fail_render;
static bool mark_silent;
static unsigned renders;
static float sample(unsigned i) { return (float)((int)(i % 31) - 15) / 32.0f; }

OSStatus AudioUnitRender(AudioUnit unit, AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *time, UInt32 bus, UInt32 frames, AudioBufferList *data) {
    (void)unit; (void)time;
    ++renders;
    assert(bus == 1 && data->mNumberBuffers == 1);
    if (fail_render) return kAudio_ParamError;
    float *output = data->mBuffers[0].mData;
    if (mark_silent) *flags |= kAudioUnitRenderAction_OutputIsSilence;
    for (UInt32 i = 0; i < frames; ++i) output[i] = mark_silent ? 0 : sample(i);
    return noErr;
}

int main(void) {
    PMMonitorGate *gate = pm_monitor_create();
    PMQueue *network = pm_queue_create();
    PMCapture *capture = pm_capture_create((AudioUnit)(uintptr_t)1);
    assert(gate && network && capture);
    pm_capture_set_monitor(capture, gate);
    pm_capture_set_network_queue(capture, network);
    pm_monitor_release(gate); // Capture's reference owns its lifetime from here.
    assert(pm_monitor_arm(gate, pm_monitor_generation(gate), 0.25f, false));
    AURenderCallbackStruct callback = pm_capture_callback(capture);
    float output[128], archived[128], received[128];
    AudioBufferList buffers = { .mNumberBuffers = 1,
        .mBuffers = {{ .mNumberChannels = 1, .mDataByteSize = sizeof(output), .mData = output }} };
    AudioTimeStamp time = {0};
    time.mHostTime = mach_absolute_time();
    time.mFlags = kAudioTimeStampHostTimeValid | kAudioTimeStampSampleTimeValid;
    for (unsigned block = 0; block < 2; ++block) {
        if (block) assert(pm_monitor_level(gate, 0.25f, true));
        time.mSampleTime = block * 128;
        AudioUnitRenderActionFlags flags = 0;
        assert(callback.inputProc(callback.inputProcRefCon, &flags, &time, 0, 128, &buffers) == noErr);
        PMBlockInfo info;
        assert(pm_capture_pop(capture, archived, 128, &info) && info.sample_position == block * 128);
        assert(pm_queue_pop(network, received, 128, &info));
        for (unsigned i = 0; i < 128; ++i) {
            assert(archived[i] == sample(i) && received[i] == sample(i));
            if (block) assert(output[i] == 0);
            else if (i >= 64) assert(fabsf(output[i] - sample(i) * 0.25f) < 0.00002f);
        }
        assert(((flags & kAudioUnitRenderAction_OutputIsSilence) != 0) == (block != 0));
    }
    fail_render = true;
    AudioUnitRenderActionFlags flags = 0;
    assert(callback.inputProc(callback.inputProcRefCon, &flags, &time, 0, 128, &buffers) == kAudio_ParamError);
    assert(flags & kAudioUnitRenderAction_OutputIsSilence);
    for (unsigned i = 0; i < 128; ++i) assert(output[i] == 0);
    unsigned before = renders;
    buffers.mBuffers[0].mNumberChannels = 2;
    assert(callback.inputProc(callback.inputProcRefCon, &flags, &time, 0, 128, &buffers) == kAudio_ParamError);
    assert(renders == before); // Bad output topology must not touch input/render memory.
    PMCaptureStats stats = pm_capture_stats(capture);
    assert(stats.rendered_frames == 256 && stats.monitor_frames == 256);
    assert(stats.monitor_silent_frames == 128 && stats.render_errors == 2);
    pm_capture_destroy(capture);
    // Default record-only callback keeps input flags and fanout behavior.
    capture = pm_capture_create((AudioUnit)(uintptr_t)1);
    assert(capture);
    pm_capture_set_network_queue(capture, network);
    callback = pm_capture_callback(capture);
    fail_render = false; mark_silent = true; flags = 0;
    assert(callback.inputProc(callback.inputProcRefCon, &flags, &time, 1, 128, NULL) == noErr);
    assert(flags & kAudioUnitRenderAction_OutputIsSilence);
    PMBlockInfo info;
    assert(pm_capture_pop(capture, archived, 128, &info));
    assert(pm_queue_pop(network, received, 128, &info));
    for (unsigned i = 0; i < 128; ++i) assert(archived[i] == 0 && received[i] == 0);
    assert(pm_capture_stats(capture).monitor_frames == 0);
    pm_capture_destroy(capture);
    pm_queue_destroy(network);
    puts("capture bridge synthetic monitoring tests passed");
    return 0;
}
