#define NOMINMAX
#include "plugin.h"
#include "receiver_process.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "public.sdk/source/common/memorystream.h"
#include <windows.h>
#include <chrono>
#include <fstream>
#include <iostream>
#include <thread>

using namespace Steinberg;
using namespace Steinberg::Vst;
static void require(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
static std::string read(const std::filesystem::path& file) {
    std::ifstream stream(file); return {std::istreambuf_iterator<char>(stream), {}};
}
static bool waitFor(const std::filesystem::path& file, const std::string& text, int seconds = 15) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(seconds);
    while (std::chrono::steady_clock::now() < deadline) {
        MSG message{};
        while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
        if (read(file).find(text) != std::string::npos) return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    return false;
}
int main() {
    try {
        require(!covoo::validAddress("1.2.3.999") && !covoo::validAddress("0.0.0.0") && !covoo::validId("../secret"), "untrusted selectors accepted");
        auto* host = new HostApplication;
        auto* processor = new covoo::Processor;
        auto* controller = new covoo::Controller;
        require(processor->initialize(host) == kResultOk && controller->initialize(host) == kResultOk, "host init failed");
        processor->connect(controller); controller->connect(processor);
        ProcessSetup setup{kRealtime, kSample32, 256, 48000};
        require(processor->setupProcessing(setup) == kResultOk && processor->setActive(true) == kResultOk, "source activation failed");
        processor->setProcessing(true);
        auto* view = controller->createView(ViewType::kEditor);
        require(view != nullptr, "editor missing");
        auto parent = CreateWindowExW(0, L"STATIC", L"covoo isolated editor test", WS_OVERLAPPEDWINDOW,
            0, 0, 700, 680, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
        require(parent && view->attached(parent, kPlatformTypeHWND) == kResultOk, "editor attach failed");
        controller->receiverCommand("status");
        const auto instance = controller->instance;
        require(covoo::validId(instance), "controller did not receive processor identity");
        auto child = GetWindow(parent, GW_CHILD);
        auto combo = GetDlgItem(child, 101);
        auto index = SendMessageW(combo, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"127.0.0.1 | isolated loopback"));
        SendMessageW(combo, CB_SETCURSEL, index, 0);
        SendMessageW(child, WM_COMMAND, MAKEWPARAM(103, BN_CLICKED), 0);
        const auto directory = covoo::receiverRun(instance);
        const auto status = directory / L"view.txt";
        require(waitFor(status, "Waiting for phone connection"), ("managed receiver failed: " + read(status) + controller->receiverError).c_str());
        require(waitFor(directory / L"pairing.bmp", "BM", 5), "QR not published");
        MemoryStream state;
        require(processor->getState(&state) == kResultOk && state.getSize() == 44, "public receiver configuration not saved");
        const auto recordings = read(directory / L"recordings.txt");
        const auto config = read(directory.parent_path().parent_path() / L"vst3-receivers" / instance / L"connection.json");
        require(!recordings.empty() && config.find("port") != std::string::npos, "recordings location/remembered port missing");
        view->removed(); view->release();
        require(read(status).find("Waiting for phone") != std::string::npos, "closing view stopped the receiver");
        processor->setProcessing(false); processor->setActive(false);
        require(waitFor(status, "Receiver stopped", 5), "deactivation did not stop receiver");
        require(!std::filesystem::exists(directory / L"pairing.bmp"), "stop retained QR credentials");
        // Restoring public project configuration starts the same protected receiver
        // with a fresh plug-in instance; the phone pin and port must persist.
        state.seek(0, IBStream::kIBSeekSet, nullptr);
        require(processor->setState(&state) == kResultOk && processor->setActive(true) == kResultOk, "project restore failed");
        controller->receiverCommand("status");
        require(controller->instance != instance, "reactivation reused bridge identity");
        const auto secondStatus = covoo::receiverRun(controller->instance) / L"view.txt";
        require(waitFor(secondStatus, "Waiting for phone connection"), "project did not auto-reconnect receiver");
        const auto restoredConfig = read(directory.parent_path().parent_path() / L"vst3-receivers" / instance / L"connection.json");
        require(config == restoredConfig, "restored receiver changed pairing port");
        controller->receiverCommand("forget");
        require(waitFor(secondStatus, "Pairing reset"), "pairing reset failed");
        require(!std::filesystem::exists(directory.parent_path().parent_path() / L"vst3-receivers" / instance / L"pairing.dpapi"), "pairing reset retained credentials");
        processor->setActive(false);
        processor->disconnect(controller); controller->disconnect(processor);
        processor->terminate(); controller->terminate(); processor->release(); controller->release(); host->release();
        DestroyWindow(parent);
        std::cout << "Native editor, managed receiver, QR, DPAPI bootstrap, project restore and graceful lifecycle passed.\n";
        return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
