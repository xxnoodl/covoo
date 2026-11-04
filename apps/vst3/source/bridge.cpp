#define NOMINMAX
#include "bridge.h"
#include <windows.h>
#include <bcrypt.h>
#include <sddl.h>
#include <shlobj.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <stdexcept>
#include <thread>
#include <vector>

namespace covoo {
namespace {
using Clock = std::chrono::steady_clock;
struct Handle {
    HANDLE value = INVALID_HANDLE_VALUE;
    explicit Handle(HANDLE value = INVALID_HANDLE_VALUE) : value(value) {}
    ~Handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
    Handle(const Handle&) = delete;
    Handle& operator=(const Handle&) = delete;
};
void check(bool ok, const char* operation) { if (!ok) throw std::runtime_error(operation); }
void randomBytes(void* target, ULONG count) {
    check(BCryptGenRandom(nullptr, static_cast<PUCHAR>(target), count, BCRYPT_USE_SYSTEM_PREFERRED_RNG) >= 0,
          "Bridge random generation failed");
}
std::string hex(const unsigned char* bytes, std::size_t size) {
    std::string result;
    for (std::size_t i = 0; i < size; ++i) {
        result += "0123456789abcdef"[bytes[i] >> 4];
        result += "0123456789abcdef"[bytes[i] & 15];
    }
    return result;
}
struct Descriptor {
    PSECURITY_DESCRIPTOR value = nullptr;
    Descriptor() {
        Handle token;
        check(OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token.value) != 0, "Bridge token query failed");
        DWORD size = 0;
        GetTokenInformation(token.value, TokenUser, nullptr, 0, &size);
        std::vector<unsigned char> bytes(size);
        check(GetTokenInformation(token.value, TokenUser, bytes.data(), size, &size) != 0,
              "Bridge user query failed");
        LPWSTR sid = nullptr;
        check(ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(bytes.data())->User.Sid, &sid) != 0,
              "Bridge SID conversion failed");
        const auto sddl = std::wstring(L"D:P(A;;GA;;;") + sid + L")";
        LocalFree(sid);
        check(ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(), SDDL_REVISION_1,
            &value, nullptr) != 0, "Bridge ACL creation failed");
    }
    ~Descriptor() { if (value) LocalFree(value); }
};
std::array<unsigned char, 32> mac(const std::array<unsigned char, 32>& key,
    const char* role, const unsigned char* client, const unsigned char* server) {
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    check(BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr,
        BCRYPT_ALG_HANDLE_HMAC_FLAG) >= 0, "Bridge HMAC provider failed");
    std::array<unsigned char, 80> input{};
    std::memcpy(input.data(), role, 15);
    std::memcpy(input.data() + 16, client, 32);
    std::memcpy(input.data() + 48, server, 32);
    std::array<unsigned char, 32> output{};
    const auto status = BCryptHash(algorithm, const_cast<PUCHAR>(key.data()), 32,
        input.data(), static_cast<ULONG>(input.size()), output.data(), 32);
    BCryptCloseAlgorithmProvider(algorithm, 0);
    check(status >= 0, "Bridge HMAC failed");
    return output;
}
bool equalMac(const unsigned char* a, const unsigned char* b) {
    volatile unsigned char difference = 0;
    for (std::size_t i = 0; i < 32; ++i) difference = difference | (a[i] ^ b[i]);
    return difference == 0;
}
template<class T, std::size_t N> void put(std::array<unsigned char, N>& bytes, std::size_t offset, T value) {
    static_assert(sizeof(T) <= N);
    std::memcpy(bytes.data() + offset, &value, sizeof(value)); // Windows x64 is little endian.
}
template<class T> T get(const unsigned char* bytes) {
    T value;
    std::memcpy(&value, bytes, sizeof(value));
    return value;
}
std::wstring defaultDirectory() {
    const auto size = GetEnvironmentVariableW(L"COVOO_VST3_LINK_DIRECTORY", nullptr, 0);
    if (size) {
        std::vector<wchar_t> buffer(size);
        const auto read = GetEnvironmentVariableW(L"COVOO_VST3_LINK_DIRECTORY", buffer.data(), size);
        check(read && read < size, "Bridge test directory changed");
        return buffer.data();
    }
    PWSTR appData = nullptr;
    check(SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_DEFAULT, nullptr, &appData)),
          "Bridge app data lookup failed");
    const auto directory = std::filesystem::path(appData) / L"covoo" / L"vst3-links";
    CoTaskMemFree(appData);
    return directory.wstring();
}
} // namespace

struct Bridge::Impl {
    Source& source;
    std::string id;
    std::array<unsigned char, 32> key{};
    std::filesystem::path link;
    Handle pipe;
    std::atomic<bool> stop{false};
    std::thread worker;

    Impl(Source& source, const std::wstring& directory) : source(source) {
        std::array<unsigned char, 16> randomId{};
        randomBytes(randomId.data(), 16);
        randomBytes(key.data(), 32);
        id = hex(randomId.data(), 16);
        const auto name = std::wstring(L"\\\\.\\pipe\\covoo-vst3-") + std::wstring(id.begin(), id.end());
        Descriptor descriptor;
        SECURITY_ATTRIBUTES attributes{sizeof(attributes), descriptor.value, FALSE};
        pipe.value = CreateNamedPipeW(name.c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED |
            FILE_FLAG_FIRST_PIPE_INSTANCE, PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT |
            PIPE_REJECT_REMOTE_CLIENTS, 1, 16384, 16384, 0, &attributes);
        check(pipe.value != INVALID_HANDLE_VALUE, "Bridge pipe creation failed");
        const auto root = std::filesystem::path(directory.empty() ? defaultDirectory() : directory);
        std::filesystem::create_directories(root);
        link = root / (id + ".link");
        Handle file(CreateFileW(link.c_str(), GENERIC_WRITE, 0, &attributes, CREATE_NEW,
            FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
        check(file.value != INVALID_HANDLE_VALUE, "Bridge link creation failed");
        std::array<unsigned char, 76> record{};
        std::memcpy(record.data(), "CVLINK1\0", 8);
        std::memcpy(record.data() + 8, id.data(), 32);
        std::memcpy(record.data() + 40, key.data(), 32);
        put(record, 72, static_cast<std::uint32_t>(GetCurrentProcessId()));
        DWORD written = 0;
        if (!WriteFile(file.value, record.data(), static_cast<DWORD>(record.size()), &written, nullptr) ||
            written != record.size()) {
            file.value = (CloseHandle(file.value), INVALID_HANDLE_VALUE);
            DeleteFileW(link.c_str());
            throw std::runtime_error("Bridge link write failed");
        }
        // Closing the link before publication allows the receiver to read it.
        CloseHandle(file.value);
        file.value = INVALID_HANDLE_VALUE;
        try { worker = std::thread([this] { run(); }); }
        catch (...) { DeleteFileW(link.c_str()); throw; }
    }
    ~Impl() {
        stop.store(true, std::memory_order_release);
        if (worker.joinable()) worker.join();
        DeleteFileW(link.c_str());
        SecureZeroMemory(key.data(), key.size());
    }

    // Every pending operation owns its OVERLAPPED storage until completion or
    // cancellation has drained. The worker alone owns/uses the pipe handle.
    bool complete(OVERLAPPED& pending, DWORD& transferred, Clock::time_point deadline) {
        while (!stop.load(std::memory_order_acquire) && Clock::now() < deadline) {
            if (WaitForSingleObject(pending.hEvent, 10) == WAIT_OBJECT_0)
                return GetOverlappedResult(pipe.value, &pending, &transferred, FALSE) != 0;
        }
        CancelIoEx(pipe.value, &pending);
        GetOverlappedResult(pipe.value, &pending, &transferred, TRUE);
        return false;
    }
    bool transfer(void* bytes, DWORD count, bool write, Clock::time_point deadline) {
        auto* cursor = static_cast<unsigned char*>(bytes);
        while (count && !stop.load(std::memory_order_acquire) && Clock::now() < deadline) {
            Handle event(CreateEventW(nullptr, TRUE, FALSE, nullptr));
            if (!event.value) return false;
            OVERLAPPED pending{};
            pending.hEvent = event.value;
            DWORD moved = 0;
            const auto success = write ? WriteFile(pipe.value, cursor, count, &moved, &pending)
                                       : ReadFile(pipe.value, cursor, count, &moved, &pending);
            if (!success && (GetLastError() != ERROR_IO_PENDING || !complete(pending, moved, deadline)))
                return false;
            if (!moved) return false;
            cursor += moved;
            count -= moved;
        }
        return count == 0;
    }
    bool authenticate() {
        const auto deadline = Clock::now() + std::chrono::milliseconds(500);
        std::array<unsigned char, 40> hello{};
        if (!transfer(hello.data(), 40, false, deadline) || std::memcmp(hello.data(), "CVB1", 4) ||
            get<std::uint32_t>(hello.data() + 4) != 1) return false;
        std::array<unsigned char, 72> reply{};
        std::memcpy(reply.data(), "CVB1", 4);
        put(reply, 4, std::uint32_t{1});
        randomBytes(reply.data() + 8, 32);
        const auto signature = mac(key, "covoo-server-v1", hello.data() + 8, reply.data() + 8);
        std::memcpy(reply.data() + 40, signature.data(), 32);
        if (!transfer(reply.data(), 72, true, deadline)) return false;
        std::array<unsigned char, 32> proof{};
        if (!transfer(proof.data(), 32, false, deadline)) return false;
        const auto expected = mac(key, "covoo-client-v1", hello.data() + 8, reply.data() + 8);
        if (!equalMac(proof.data(), expected.data())) return false;
        std::array<char, 4> ok{'O', 'K', 'A', 'Y'};
        return transfer(ok.data(), 4, true, deadline);
    }
    void session() {
        if (!authenticate()) return;
        std::uint64_t sequence = 0, connectedGate = 0;
        double connectedRate = 0;
        std::uint64_t lastClock = 0;
        auto lastProgress = Clock::now();
        while (!stop.load(std::memory_order_acquire)) {
            const auto info = source.feedback();
            if (info.clock != lastClock) { lastClock = info.clock; lastProgress = Clock::now(); }
            const bool ready = info.running && info.rate >= 8000 && info.rate <= 192000 &&
                               std::floor(info.rate) == info.rate && info.block <= 2048 &&
                               Clock::now() - lastProgress < std::chrono::milliseconds(100);
            if (!ready) source.disconnect();
            if (info.gate != connectedGate || info.rate != connectedRate) {
                source.disconnect();
                if (ready) source.connect(info.rate);
                connectedGate = ready ? info.gate : 0;
                connectedRate = info.rate;
            }
            const auto target = std::max<std::uint32_t>(Source::primeFrames, info.block + 256);
            const auto request = ready && info.queued < target ? std::min<std::uint32_t>(512, target - info.queued) : 0;
            std::array<unsigned char, 64> feedback{};
            std::memcpy(feedback.data(), "CVF1", 4);
            put(feedback, 8, info.gate); put(feedback, 16, info.rate);
            put(feedback, 24, info.clock); put(feedback, 32, info.queued);
            put(feedback, 36, request); put(feedback, 40, source.silenceFrames());
            put(feedback, 48, source.discardedFrames()); put(feedback, 56, std::uint32_t(ready));
            put(feedback, 60, info.block);
            const auto deadline = Clock::now() + std::chrono::milliseconds(250);
            if (!transfer(feedback.data(), 64, true, deadline)) return;
            std::array<unsigned char, 24> response{};
            if (!transfer(response.data(), 24, false, deadline) || std::memcmp(response.data(), "CVP1", 4)) return;
            const auto frames = get<std::uint32_t>(response.data() + 4);
            const auto gate = get<std::uint64_t>(response.data() + 8);
            if (frames > request || frames > 512 || gate != info.gate ||
                get<std::uint64_t>(response.data() + 16) != sequence++) return;
            if (frames) {
                std::array<float, 512> pcm{};
                if (!transfer(pcm.data(), frames * 4, false, deadline)) return;
                for (std::uint32_t i = 0; i < frames; ++i)
                    if (!std::isfinite(pcm[i]) || std::abs(pcm[i]) > 1) return;
                source.publish(pcm.data(), frames, gate);
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
        }
    }
    void run() noexcept {
        while (!stop.load(std::memory_order_acquire)) {
            Handle event(CreateEventW(nullptr, TRUE, FALSE, nullptr));
            if (!event.value) break;
            OVERLAPPED pending{}; pending.hEvent = event.value;
            DWORD ignored = 0;
            const auto connected = ConnectNamedPipe(pipe.value, &pending);
            const auto error = connected ? ERROR_SUCCESS : GetLastError();
            const bool accepted = connected || error == ERROR_PIPE_CONNECTED ||
                (error == ERROR_IO_PENDING && complete(pending, ignored, Clock::now() + std::chrono::hours(24)));
            if (accepted) {
                try { session(); } catch (...) { /* Fail closed; no credentials in logs. */ }
            }
            source.disconnect();
            DisconnectNamedPipe(pipe.value);
            if (!accepted && error != ERROR_IO_PENDING && error != ERROR_NO_DATA) break;
        }
        source.disconnect();
    }
};

Bridge::Bridge(Source& source, const std::wstring& directory) : impl_(std::make_unique<Impl>(source, directory)) {}
Bridge::~Bridge() = default;
const std::string& Bridge::instance() const noexcept { return impl_->id; }
} // namespace covoo
