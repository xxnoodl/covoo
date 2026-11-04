#pragma once
#include "source.h"
#include <atomic>
#include <memory>
#include <string>

namespace covoo {
// Windows-only transport worker. Construction/destruction are control-thread
// operations. All OS I/O, authentication and connection ownership stay here.
class Bridge final {
public:
    explicit Bridge(Source& source, const std::wstring& directory = L"");
    ~Bridge();
    Bridge(const Bridge&) = delete;
    Bridge& operator=(const Bridge&) = delete;
    const std::string& instance() const noexcept;
private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
} // namespace covoo
