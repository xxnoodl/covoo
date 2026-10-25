#include "CaptureBridge.h"
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <stdlib.h>

struct PMCapture {
    AudioUnit unit;
    PMQueue *queue;
    float scratch[PM_MAX_FRAMES];
    uint64_t position;
    uint64_t sequence;
    _Atomic uint64_t callbacks, rendered_frames, render_errors, oversized_callbacks, max_callback_ticks;
    _Atomic int32_t last_status;
};

static void increment(_Atomic uint64_t *value, uint64_t amount) {
    atomic_store_explicit(value, atomic_load_explicit(value, memory_order_relaxed) + amount, memory_order_relaxed);
}

static OSStatus input_callback(void *context, AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *time, UInt32 bus, UInt32 frames, AudioBufferList *unused) {
    (void)bus; (void)unused;
    PMCapture *c = context;
    const uint64_t began = mach_absolute_time();
    increment(&c->callbacks, 1);
    uint64_t position = c->position;
    c->position += frames;
    uint64_t sequence = c->sequence++;
    if (frames == 0) return noErr;
    if (frames > PM_MAX_FRAMES) {
        increment(&c->oversized_callbacks, 1);
        atomic_store_explicit(&c->last_status, kAudioUnitErr_TooManyFramesToProcess, memory_order_relaxed);
        return kAudioUnitErr_TooManyFramesToProcess;
    }
    AudioBufferList buffers = { .mNumberBuffers = 1,
        .mBuffers = {{ .mNumberChannels = 1, .mDataByteSize = frames * sizeof(float), .mData = c->scratch }} };
    OSStatus status = AudioUnitRender(c->unit, flags, time, 1, frames, &buffers);
    if (status != noErr || buffers.mBuffers[0].mDataByteSize != frames * sizeof(float)) {
        if (status == noErr) status = kAudio_ParamError;
        increment(&c->render_errors, 1);
        atomic_store_explicit(&c->last_status, status, memory_order_relaxed);
        return status;
    }
    increment(&c->rendered_frames, frames);
    PMBlockInfo info = { sequence, position, time->mHostTime, time->mSampleTime,
        time->mFlags, frames, mach_absolute_time() - began };
    pm_queue_push(c->queue, c->scratch, info);
    uint64_t elapsed = mach_absolute_time() - began;
    if (elapsed > atomic_load_explicit(&c->max_callback_ticks, memory_order_relaxed))
        atomic_store_explicit(&c->max_callback_ticks, elapsed, memory_order_relaxed);
    return noErr;
}

PMCapture *pm_capture_create(AudioUnit unit) {
    PMCapture *c = calloc(1, sizeof(*c));
    if (!c) return NULL;
    c->unit = unit;
    atomic_init(&c->callbacks, 0);
    atomic_init(&c->rendered_frames, 0);
    atomic_init(&c->render_errors, 0);
    atomic_init(&c->oversized_callbacks, 0);
    atomic_init(&c->max_callback_ticks, 0);
    atomic_init(&c->last_status, 0);
    c->queue = pm_queue_create();
    if (!c->queue || !atomic_is_lock_free(&c->callbacks) || !atomic_is_lock_free(&c->rendered_frames)
        || !atomic_is_lock_free(&c->render_errors) || !atomic_is_lock_free(&c->oversized_callbacks)
        || !atomic_is_lock_free(&c->max_callback_ticks) || !atomic_is_lock_free(&c->last_status)) {
        pm_queue_destroy(c->queue); free(c); return NULL;
    }
    return c;
}

void pm_capture_destroy(PMCapture *c) {
    if (c) { pm_queue_destroy(c->queue); free(c); }
}
AURenderCallbackStruct pm_capture_callback(PMCapture *c) {
    AURenderCallbackStruct callback = { input_callback, c };
    return callback;
}
bool pm_capture_pop(PMCapture *c, float *samples, uint32_t capacity, PMBlockInfo *info) {
    return pm_queue_pop(c->queue, samples, capacity, info);
}
PMCaptureStats pm_capture_stats(const PMCapture *c) {
    PMCaptureStats s = {
        atomic_load_explicit(&c->callbacks, memory_order_relaxed),
        atomic_load_explicit(&c->rendered_frames, memory_order_relaxed),
        atomic_load_explicit(&c->render_errors, memory_order_relaxed),
        atomic_load_explicit(&c->oversized_callbacks, memory_order_relaxed),
        atomic_load_explicit(&c->max_callback_ticks, memory_order_relaxed),
        atomic_load_explicit(&c->last_status, memory_order_relaxed), pm_queue_stats(c->queue) };
    return s;
}
double pm_ticks_to_seconds(uint64_t ticks) {
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    return (double)ticks * (double)info.numer / (double)info.denom / 1e9;
}
