#pragma once
#include <atomic>
#include <filesystem>
#include <string>
#include <thread>

namespace covoo {
bool validId(const std::string& value);
bool validAddress(const std::string& value);
std::filesystem::path receiverRun(const std::string& instance);
class ReceiverProcess {
public:
    ReceiverProcess(const std::string& instance, const std::string& address, const std::string& profile);
    ~ReceiverProcess();
    void stop() { stopping_.store(true); }
    void forget();
    bool finished() const { return finished_.load(); }
private:
    std::atomic<bool> stopping_{false}, finished_{false};
    std::thread worker_;
    std::filesystem::path directory_;
};
}
