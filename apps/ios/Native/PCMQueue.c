#include "PCMQueue.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct { PMBlockInfo info; float samples[PM_MAX_FRAMES]; } PMSlot;
struct PMQueue {
    _Atomic uint64_t write_index;
    _Atomic uint64_t read_index;
    _Atomic uint64_t dropped_blocks;
    _Atomic uint64_t dropped_frames;
    _Atomic uint64_t high_water;
    PMSlot slots[PM_QUEUE_SLOTS];
};

static bool queue_atomics_are_lock_free(PMQueue *q) {
    return atomic_is_lock_free(&q->write_index) && atomic_is_lock_free(&q->read_index)
        && atomic_is_lock_free(&q->dropped_blocks) && atomic_is_lock_free(&q->dropped_frames)
        && atomic_is_lock_free(&q->high_water);
}

PMQueue *pm_queue_create(void) {
    PMQueue *q = calloc(1, sizeof(*q));
    if (!q) return NULL;
    atomic_init(&q->write_index, 0);
    atomic_init(&q->read_index, 0);
    atomic_init(&q->dropped_blocks, 0);
    atomic_init(&q->dropped_frames, 0);
    atomic_init(&q->high_water, 0);
    if (!queue_atomics_are_lock_free(q)) {
        free(q);
        return NULL;
    }
    return q;
}

void pm_queue_destroy(PMQueue *q) { free(q); }

bool pm_queue_push(PMQueue *q, const float *samples, PMBlockInfo info) {
    if (!q || !samples || info.frames == 0 || info.frames > PM_MAX_FRAMES) return false;
    uint64_t w = atomic_load_explicit(&q->write_index, memory_order_relaxed);
    uint64_t r = atomic_load_explicit(&q->read_index, memory_order_acquire);
    if (w - r == PM_QUEUE_SLOTS) {
        atomic_store_explicit(&q->dropped_blocks,
            atomic_load_explicit(&q->dropped_blocks, memory_order_relaxed) + 1, memory_order_relaxed);
        atomic_store_explicit(&q->dropped_frames,
            atomic_load_explicit(&q->dropped_frames, memory_order_relaxed) + info.frames, memory_order_relaxed);
        return false;
    }
    PMSlot *slot = &q->slots[w % PM_QUEUE_SLOTS];
    slot->info = info;
    memcpy(slot->samples, samples, info.frames * sizeof(float));
    uint64_t occupancy = w - r + 1;
    if (occupancy > atomic_load_explicit(&q->high_water, memory_order_relaxed))
        atomic_store_explicit(&q->high_water, occupancy, memory_order_relaxed);
    atomic_store_explicit(&q->write_index, w + 1, memory_order_release);
    return true;
}

bool pm_queue_pop(PMQueue *q, float *samples, uint32_t capacity, PMBlockInfo *info) {
    if (!q || !samples || !info) return false;
    uint64_t r = atomic_load_explicit(&q->read_index, memory_order_relaxed);
    uint64_t w = atomic_load_explicit(&q->write_index, memory_order_acquire);
    if (r == w) return false;
    const PMSlot *slot = &q->slots[r % PM_QUEUE_SLOTS];
    if (capacity < slot->info.frames) return false;
    *info = slot->info;
    memcpy(samples, slot->samples, info->frames * sizeof(float));
    atomic_store_explicit(&q->read_index, r + 1, memory_order_release);
    return true;
}

PMQueueStats pm_queue_stats(const PMQueue *q) {
    /* Diagnostic snapshot, not a transactional read while producer is running. */
    uint64_t r = atomic_load_explicit(&q->read_index, memory_order_acquire);
    uint64_t w = atomic_load_explicit(&q->write_index, memory_order_acquire);
    PMQueueStats s = { w,
        atomic_load_explicit(&q->dropped_blocks, memory_order_relaxed),
        atomic_load_explicit(&q->dropped_frames, memory_order_relaxed),
        w - r, atomic_load_explicit(&q->high_water, memory_order_relaxed) };
    return s;
}
