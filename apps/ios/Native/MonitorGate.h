#ifndef PM_MONITOR_GATE_H
#define PM_MONITOR_GATE_H
#include <stdbool.h>
#include <stdint.h>
#include "PCMQueue.h"

typedef struct PMMonitorGate PMMonitorGate;
typedef struct { bool armed, muted; float gain; } PMMonitorSettings;
PMMonitorGate *pm_monitor_create(void);
/* Retain/release only outside callbacks. Each capture context retains its gate. */
void pm_monitor_retain(PMMonitorGate *gate);
void pm_monitor_release(PMMonitorGate *gate);
uint64_t pm_monitor_generation(const PMMonitorGate *gate);
/* A route invalidation between validation and arming makes this fail. */
bool pm_monitor_arm(PMMonitorGate *gate, uint64_t generation, float gain, bool muted);
bool pm_monitor_level(PMMonitorGate *gate, float gain, bool muted);
void pm_monitor_inhibit(PMMonitorGate *gate);
PMMonitorSettings pm_monitor_settings(const PMMonitorGate *gate);
/* Single render consumer; source is unchanged. Mute/inhibit silence immediately.
   Other level changes ramp for at most 64 frames. Returns true if gate is open. */
bool pm_monitor_render(const PMMonitorGate *gate, const float *source, float *output,
    uint32_t frames, float *previous_gain);
#endif
