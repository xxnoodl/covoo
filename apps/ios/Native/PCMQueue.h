#ifndef PM_PCM_QUEUE_H
#define PM_PCM_QUEUE_H
#include <stdbool.h>
#include <stdint.h>

#define PM_MAX_FRAMES 4096
#define PM_QUEUE_SLOTS 64

typedef struct PMQueue PMQueue;
typedef struct {
    uint64_t sequence;
    uint64_t sample_position;
    uint64_t host_time;
    double sample_time;
    uint32_t time_flags;
    uint32_t frames;
    uint64_t callback_ticks;
} PMBlockInfo;

typedef struct {
    uint64_t accepted_blocks;
    uint64_t dropped_blocks;
    uint64_t dropped_frames;
    uint64_t occupancy;
    uint64_t high_water;
} PMQueueStats;

/* One producer, one consumer. Create/destroy only while both are stopped.
   Copies into fixed slots; full queues reject newest blocks. */
PMQueue *pm_queue_create(void);
void pm_queue_destroy(PMQueue *queue);
bool pm_queue_push(PMQueue *queue, const float *samples, PMBlockInfo info);
bool pm_queue_pop(PMQueue *queue, float *samples, uint32_t capacity, PMBlockInfo *info);
PMQueueStats pm_queue_stats(const PMQueue *queue);
#endif
