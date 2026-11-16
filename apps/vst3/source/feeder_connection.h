#pragma once
#include "source.h"

namespace covoo {
// Owned by the bridge worker, never the host audio callback.
class FeederConnection final {
public:
    void update(Source& source, const Source::Feedback& info, bool ready) noexcept {
        if (!ready) {
            source.disconnect();
            gate_ = 0;
            rate_ = 0;
        } else if (info.gate != gate_ || info.rate != rate_) {
            source.disconnect();
            if (source.connect(info.rate)) {
                gate_ = info.gate;
                rate_ = info.rate;
            }
        }
    }
private:
    std::uint64_t gate_ = 0;
    double rate_ = 0;
};
} // namespace covoo
