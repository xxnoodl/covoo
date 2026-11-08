#define NOMINMAX
#include "receiver_process.h"
#include <windows.h>
#include <shlobj.h>
#include <fstream>
#include <stdexcept>
#include <vector>

namespace covoo {
namespace {
const char moduleAnchor = 0;
struct Handle {
    HANDLE value = nullptr;
    ~Handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
};
std::wstring quote(const std::wstring& value) {
    std::wstring result = L"\"";
    std::size_t slashes = 0;
    for (auto ch : value) {
        if (ch == L'\\') { ++slashes; continue; }
        result.append(ch == L'"' ? slashes * 2 + 1 : slashes, L'\\');
        slashes = 0; result += ch;
    }
    result.append(slashes * 2, L'\\');
    return result + L"\"";
}
std::wstring widen(const std::string& value) { return {value.begin(), value.end()}; }
std::filesystem::path runtimeDirectory() {
    HMODULE module = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&moduleAnchor), &module)) throw std::runtime_error("Cannot locate plug-in module");
    std::vector<wchar_t> name(32768);
    const auto length = GetModuleFileNameW(module, name.data(), static_cast<DWORD>(name.size()));
    if (!length || length >= name.size()) throw std::runtime_error("Cannot locate plug-in runtime");
    return std::filesystem::path(name.data()).parent_path().parent_path() / L"Resources" / L"runtime";
}
}
bool validId(const std::string& value) {
    return value.size() == 32 && value.find_first_not_of("0123456789abcdef") == std::string::npos;
}
bool validAddress(const std::string& value) {
    unsigned parts = 0, number = 0, digits = 0;
    if (value.empty() || value.size() > 15 || value == "0.0.0.0") return false;
    for (char ch : value + '.') {
        if (ch == '.') {
            if (!digits || number > 255 || ++parts > 4) return false;
            number = digits = 0;
        } else {
            if (ch < '0' || ch > '9' || ++digits > 3) return false;
            number = number * 10 + static_cast<unsigned>(ch - '0');
        }
    }
    return parts == 4;
}
std::filesystem::path receiverRun(const std::string& instance) {
    if (!validId(instance)) throw std::runtime_error("Plug-in not active. Enable the device in Live first.");
#ifdef COVOO_VST3_TESTING
    if (const auto* testRoot = std::getenv("LOCALAPPDATA")) return std::filesystem::path(testRoot) / L"covoo/vst3-runs" / instance;
#endif
    PWSTR value = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &value))) throw std::runtime_error("Local app data unavailable");
    const auto path = std::filesystem::path(value) / L"covoo" / L"vst3-runs" / instance;
    CoTaskMemFree(value);
    return path;
}
ReceiverProcess::ReceiverProcess(const std::string& instance, const std::string& address, const std::string& profile) {
    if (!validId(instance) || !validId(profile) || !validAddress(address)) throw std::runtime_error("Choose a valid network interface");
    const auto runtime = runtimeDirectory();
    if (!std::filesystem::exists(runtime / L"plugin-session.ps1") || !std::filesystem::exists(runtime / L"covoo-receiver.exe"))
        throw std::runtime_error("Receiver runtime missing. Install the complete covoo_source.vst3 folder.");
    const auto directory = receiverRun(instance);
    directory_ = directory;
    std::filesystem::create_directories(directory);
    for (auto name : {L"stop", L"forget", L"pairing.bmp", L"view.txt"}) std::filesystem::remove(directory / name);
    wchar_t system[MAX_PATH]{};
    if (!GetSystemDirectoryW(system, MAX_PATH)) throw std::runtime_error("Windows system directory unavailable");
    const auto powershell = std::filesystem::path(system) / L"WindowsPowerShell/v1.0/powershell.exe";
    auto command = quote(powershell.wstring()) + L" -NoProfile -NonInteractive -File " + quote((runtime / L"plugin-session.ps1").wstring()) +
        L" -Instance " + quote(widen(instance)) + L" -Address " + quote(widen(address)) +
        L" -Profile " + quote(widen(profile)) + L" -RunDirectory " + quote(directory.wstring());
    Handle job;
    job.value = CreateJobObjectW(nullptr, nullptr);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!job.value || !SetInformationJobObject(job.value, JobObjectExtendedLimitInformation, &limits, sizeof(limits)))
        throw std::runtime_error("Cannot create receiver lifetime guard");
    STARTUPINFOW startup{}; startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESHOWWINDOW; startup.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(powershell.c_str(), command.data(), nullptr, nullptr, FALSE,
        CREATE_NO_WINDOW | CREATE_SUSPENDED, nullptr, runtime.c_str(), &startup, &process))
        throw std::runtime_error("Cannot start receiver runtime");
    Handle child, thread; child.value = process.hProcess; thread.value = process.hThread;
    if (!AssignProcessToJobObject(job.value, child.value)) {
        TerminateProcess(child.value, 1); WaitForSingleObject(child.value, 2000);
        throw std::runtime_error("Cannot guard receiver process; it was not started");
    }
    if (ResumeThread(thread.value) == static_cast<DWORD>(-1)) throw std::runtime_error("Cannot resume receiver runtime");
    try {
        worker_ = std::thread([this, directory, childHandle = child.value, jobHandle = job.value] {
            Handle ownedChild, ownedJob; ownedChild.value = childHandle; ownedJob.value = jobHandle;
            try {
            while (!stopping_.load() && WaitForSingleObject(ownedChild.value, 100) == WAIT_TIMEOUT) {}
            if (stopping_.load()) {
                std::ofstream(directory / L"stop") << "stop";
                if (WaitForSingleObject(ownedChild.value, 12000) == WAIT_TIMEOUT) {
                    std::ofstream(directory / L"view.txt") << "Receiver stop timed out. Recording integrity unverified.";
                }
            } else {
                DWORD exitCode = 0; GetExitCodeProcess(ownedChild.value, &exitCode);
                if (!std::filesystem::exists(directory / L"view.txt"))
                    std::ofstream(directory / L"view.txt") << "Receiver exited (" << exitCode << "). Check Windows script policy and the complete runtime bundle.";
            }
            } catch (...) {
                // Fail closed without letting a worker exception terminate the host.
                TerminateJobObject(ownedJob.value, 1);
            }
            finished_.store(true);
        });
    } catch (...) { TerminateJobObject(job.value, 1); throw; }
    child.value = job.value = nullptr;
}
ReceiverProcess::~ReceiverProcess() { stopping_.store(true); if (worker_.joinable()) worker_.join(); }
void ReceiverProcess::forget() {
    if (finished_.load()) throw std::runtime_error("Start the receiver before resetting its pairing.");
    std::ofstream file(directory_ / L"forget"); file << "forget"; file.close();
    if (!file) throw std::runtime_error("Cannot request pairing reset.");
    stopping_.store(true);
}
}
