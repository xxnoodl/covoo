#include "PCMQueue.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#ifndef _WIN32
#include <pthread.h>
#include <sched.h>
#endif

static void boundaries(void) {
    PMQueue *q = pm_queue_create();
    assert(q);
    float input[PM_MAX_FRAMES], output[PM_MAX_FRAMES];
    for (int i = 0; i < PM_MAX_FRAMES; ++i) input[i] = (float)i / 4096.0f;
    PMBlockInfo info = {0}, result = {0};
    assert(!pm_queue_pop(q, output, PM_MAX_FRAMES, &result));
    assert(!pm_queue_push(q, input, info));
    info.frames = PM_MAX_FRAMES + 1;
    assert(!pm_queue_push(q, input, info));
    info.frames = PM_MAX_FRAMES;
    for (uint64_t i = 0; i < PM_QUEUE_SLOTS; ++i) {
        info.sequence = i;
        info.sample_position = i * PM_MAX_FRAMES;
        info.host_time = i + 10;
        assert(pm_queue_push(q, input, info));
    }
    assert(!pm_queue_push(q, input, info));
    assert(!pm_queue_pop(q, output, PM_MAX_FRAMES - 1, &result));
    PMQueueStats stats = pm_queue_stats(q);
    assert(stats.dropped_blocks == 1 && stats.dropped_frames == PM_MAX_FRAMES);
    assert(stats.occupancy == PM_QUEUE_SLOTS && stats.high_water == PM_QUEUE_SLOTS);
    for (uint64_t i = 0; i < PM_QUEUE_SLOTS; ++i) {
        assert(pm_queue_pop(q, output, PM_MAX_FRAMES, &result));
        assert(result.sequence == i && result.sample_position == i * PM_MAX_FRAMES);
        assert(result.host_time == i + 10 && result.frames == PM_MAX_FRAMES);
        for (int j = 0; j < PM_MAX_FRAMES; ++j) assert(input[j] == output[j]);
    }
    for (uint64_t i = 0; i < 100000; ++i) {
        info.frames = 1;
        info.sequence = i;
        assert(pm_queue_push(q, input, info));
        assert(pm_queue_pop(q, output, PM_MAX_FRAMES, &result));
        assert(result.sequence == i && output[0] == input[0]);
    }
    assert(!pm_queue_pop(q, output, PM_MAX_FRAMES, &result));
    assert(pm_queue_stats(q).occupancy == 0);
    pm_queue_destroy(q);
}

#ifndef _WIN32
static void *produce(void *context) {
    PMQueue *q = context;
    for (uint64_t i = 0; i < 100000; ++i) {
        float samples[3] = {(float)i, -(float)i, 0.25f};
        PMBlockInfo info = { .sequence = i, .sample_position = i * 3, .frames = 3 };
        while (!pm_queue_push(q, samples, info)) sched_yield();
    }
    return NULL;
}
static void concurrent(void) {
    PMQueue *q = pm_queue_create();
    assert(q);
    pthread_t producer;
    assert(pthread_create(&producer, NULL, produce, q) == 0);
    for (uint64_t i = 0; i < 100000; ++i) {
        float samples[3];
        PMBlockInfo info;
        while (!pm_queue_pop(q, samples, 3, &info)) sched_yield();
        assert(info.sequence == i && info.sample_position == i * 3 && info.frames == 3);
        assert(samples[0] == (float)i && samples[1] == -(float)i && samples[2] == 0.25f);
    }
    assert(pthread_join(producer, NULL) == 0);
    assert(pm_queue_stats(q).occupancy == 0);
    pm_queue_destroy(q);
}
#endif

static void independent_fanout(void) {
    PMQueue *archive = pm_queue_create(), *network = pm_queue_create();
    assert(archive && network);
    float input[2] = {0.25f, -0.5f}, output[2];
    PMBlockInfo info = {.frames = 2}, received;
    for (uint64_t i = 0; i < PM_QUEUE_SLOTS + 20; ++i) {
        info.sequence = i;
        pm_queue_fanout(archive, network, input, info);
        assert(pm_queue_pop(network, output, 2, &received));
        assert(received.sequence == i && output[0] == input[0] && output[1] == input[1]);
    }
    assert(pm_queue_stats(archive).dropped_blocks == 20);
    assert(pm_queue_stats(network).dropped_blocks == 0);
    for (uint64_t i = 0; i < PM_QUEUE_SLOTS; ++i)
        assert(pm_queue_pop(archive, output, 2, &received));
    for (uint64_t i = 0; i < PM_QUEUE_SLOTS + 20; ++i) {
        pm_queue_fanout(archive, network, input, info);
        assert(pm_queue_pop(archive, output, 2, &received));
    }
    assert(pm_queue_stats(network).dropped_blocks == 20);
    pm_queue_destroy(archive); pm_queue_destroy(network);
}

int main(void) {
    boundaries();
    independent_fanout();
#ifndef _WIN32
    concurrent();
#endif
    puts("pcm queue tests passed");
    return 0;
}
