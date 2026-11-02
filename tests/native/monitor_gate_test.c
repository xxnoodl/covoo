#include "MonitorGate.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#ifndef _WIN32
#include <pthread.h>
static void *change_levels(void *context) {
    PMMonitorGate *gate = context;
    for (unsigned i = 0; i < 100000; ++i) assert(pm_monitor_level(gate, (float)(i % 101) / 100.0f, (i & 1) != 0));
    pm_monitor_release(gate);
    return NULL;
}
#endif

int main(void) {
    PMMonitorGate *gate = pm_monitor_create();
    assert(gate);
    float input[128], output[128], previous = 0;
    for (unsigned i = 0; i < 128; ++i) input[i] = (float)i / 128.0f;
    assert(!pm_monitor_render(gate, input, output, 128, &previous));
    for (unsigned i = 0; i < 128; ++i) assert(output[i] == 0);
    uint64_t old_generation = pm_monitor_generation(gate);
    assert(pm_monitor_arm(gate, old_generation, 0.5f, false));
    assert(pm_monitor_render(gate, input, output, 128, &previous));
    for (unsigned i = 0; i < 128; ++i) {
        assert(input[i] == (float)i / 128.0f);
        assert(output[i] >= 0 && output[i] <= input[i]);
    }
    assert(fabsf(output[127] - input[127] * 0.5f) < 0.00002f);
    assert(pm_monitor_level(gate, 0.5f, true));
    assert(!pm_monitor_render(gate, input, output, 128, &previous));
    for (unsigned i = 0; i < 128; ++i) assert(output[i] == 0);
    assert(!pm_monitor_level(gate, NAN, false));
    assert(!pm_monitor_level(gate, 1.01f, false));
    assert(!pm_monitor_level(gate, -1, false));
    pm_monitor_inhibit(gate);
    assert(!pm_monitor_arm(gate, old_generation, 1, false));
    assert(pm_monitor_level(gate, 1, false)); // Level changes cannot re-arm a routed-away output.
    assert(!pm_monitor_settings(gate).armed);
    assert(!pm_monitor_render(gate, input, output, 128, &previous));
    assert(pm_monitor_arm(gate, pm_monitor_generation(gate), 1, false));
    pm_monitor_retain(gate);
    pm_monitor_release(gate); // Callback context's retain keeps the gate alive.
    assert(pm_monitor_render(gate, input, output, 128, &previous));
    for (unsigned i = 64; i < 128; ++i) assert(output[i] == input[i]);
    pm_monitor_inhibit(gate);
    assert(!pm_monitor_render(gate, input, output, 128, &previous));
    for (unsigned i = 0; i < 128; ++i) assert(output[i] == 0);
    pm_monitor_release(gate);
#ifndef _WIN32
    gate = pm_monitor_create();
    assert(gate);
    pthread_t changer;
    pm_monitor_retain(gate);
    assert(pthread_create(&changer, NULL, change_levels, gate) == 0);
    for (unsigned i = 0; i < 10000; ++i) {
        uint64_t generation = pm_monitor_generation(gate);
        assert(pm_monitor_arm(gate, generation, 1, false));
        pm_monitor_inhibit(gate);
        assert(!pm_monitor_arm(gate, generation, 1, false));
        assert(!pm_monitor_settings(gate).armed);
        assert(!pm_monitor_render(gate, input, output, 128, &previous));
        for (unsigned j = 0; j < 128; ++j) assert(output[j] == 0);
    }
    assert(pthread_join(changer, NULL) == 0);
    pm_monitor_release(gate);
#endif
    puts("monitor gate tests passed");
    return 0;
}
