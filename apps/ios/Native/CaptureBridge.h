#ifndef PM_CAPTURE_BRIDGE_H
#define PM_CAPTURE_BRIDGE_H
#include "PCMQueue.h"
#include <AudioToolbox/AudioToolbox.h>

typedef struct PMCapture PMCapture;
typedef struct {
    uint64_t callbacks;
    uint64_t rendered_frames;
    uint64_t render_errors;
    uint64_t oversized_callbacks;
    uint64_t max_callback_ticks;
    int32_t last_status;
    PMQueueStats queue;
} PMCaptureStats;

PMCapture *pm_capture_create(AudioUnit unit);
/* Call only after AudioOutputUnitStop and AudioComponentInstanceDispose. */
void pm_capture_destroy(PMCapture *capture);
AURenderCallbackStruct pm_capture_callback(PMCapture *capture);
bool pm_capture_pop(PMCapture *capture, float *samples, uint32_t capacity, PMBlockInfo *info);
PMCaptureStats pm_capture_stats(const PMCapture *capture);
double pm_ticks_to_seconds(uint64_t ticks);
#endif
