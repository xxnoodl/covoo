#include "MonitorGate.h"
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define ARMED (UINT64_C(1) << 16)
#define MUTED (UINT64_C(1) << 17)
#define GENERATION_STEP (UINT64_C(1) << 18)
#define GENERATION_MAX (UINT64_MAX >> 18)
struct PMMonitorGate { _Atomic uint64_t state, owners; };

PMMonitorGate *pm_monitor_create(void) {
    PMMonitorGate *gate = calloc(1, sizeof(*gate));
    if (!gate) return NULL;
    atomic_init(&gate->state, 0);
    atomic_init(&gate->owners, 1);
    if (!atomic_is_lock_free(&gate->state) || !atomic_is_lock_free(&gate->owners)) {
        free(gate); return NULL;
    }
    return gate;
}
void pm_monitor_retain(PMMonitorGate *gate) {
    if (gate) atomic_fetch_add_explicit(&gate->owners, 1, memory_order_relaxed);
}
void pm_monitor_release(PMMonitorGate *gate) {
    if (gate && atomic_fetch_sub_explicit(&gate->owners, 1, memory_order_acq_rel) == 1) free(gate);
}
uint64_t pm_monitor_generation(const PMMonitorGate *gate) {
    return atomic_load_explicit(&gate->state, memory_order_acquire) >> 18;
}
static bool change_level(PMMonitorGate *gate, bool arm, uint64_t generation, float gain, bool muted) {
    if (!gate || !isfinite(gain) || gain < 0 || gain > 1) return false;
    uint64_t level = (uint64_t)(gain * 65535.0f + 0.5f);
    uint64_t before = atomic_load_explicit(&gate->state, memory_order_acquire);
    do {
        if (arm && ((before >> 18) != generation || generation == GENERATION_MAX)) return false;
        uint64_t after = (before & ~(UINT64_C(65535) | MUTED)) | level | (muted ? MUTED : 0);
        if (arm) after |= ARMED;
        if (atomic_compare_exchange_weak_explicit(&gate->state, &before, after,
            memory_order_acq_rel, memory_order_acquire)) return true;
    } while (true);
}
bool pm_monitor_arm(PMMonitorGate *gate, uint64_t generation, float gain, bool muted) {
    return change_level(gate, true, generation, gain, muted);
}
bool pm_monitor_level(PMMonitorGate *gate, float gain, bool muted) {
    return change_level(gate, false, 0, gain, muted);
}
void pm_monitor_inhibit(PMMonitorGate *gate) {
    if (!gate) return;
    uint64_t before = atomic_load_explicit(&gate->state, memory_order_acquire);
    do {
        uint64_t after = before & ~ARMED;
        // Exhaustion fails closed instead of wrapping and accepting an old lease.
        if ((before >> 18) != GENERATION_MAX) after += GENERATION_STEP;
        if (atomic_compare_exchange_weak_explicit(&gate->state, &before, after,
            memory_order_acq_rel, memory_order_acquire)) return;
    } while (true);
}
PMMonitorSettings pm_monitor_settings(const PMMonitorGate *gate) {
    uint64_t state = atomic_load_explicit(&gate->state, memory_order_acquire);
    PMMonitorSettings result = { (state & ARMED) != 0, (state & MUTED) != 0,
        (float)(state & UINT64_C(65535)) / 65535.0f };
    return result;
}
bool pm_monitor_render(const PMMonitorGate *gate, const float *source, float *output,
    uint32_t frames, float *previous_gain) {
    if (!gate || !source || !output || !previous_gain || frames > PM_MAX_FRAMES) return false;
    PMMonitorSettings settings = pm_monitor_settings(gate);
    if (!settings.armed || settings.muted || settings.gain == 0) {
        memset(output, 0, frames * sizeof(float)); *previous_gain = 0; return false;
    }
    uint32_t ramp = frames < 64 ? frames : 64;
    float before = *previous_gain;
    for (uint32_t i = 0; i < frames; ++i) {
        float gain = i < ramp ? before + (settings.gain - before) * (float)(i + 1) / (float)ramp : settings.gain;
        output[i] = source[i] * gain;
    }
    if (frames) *previous_gain = settings.gain;
    return true;
}
