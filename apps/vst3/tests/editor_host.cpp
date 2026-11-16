#define NOMINMAX
#include "plugin.h"
#include "receiver_process.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "public.sdk/source/common/memorystream.h"
#include <windows.h>
#include <array>
#include <cstring>
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
int main(int argc, char** argv) {
    try {
        const bool hold=argc==4 && std::strcmp(argv[1],"--fault-holder")==0;
        require(argc==1 || hold,"Usage: editor-host [--fault-holder READY PUBLIC_STATE]");
        const bool restored=hold && std::filesystem::exists(argv[3]);
        require(!covoo::validAddress("1.2.3.999") && !covoo::validAddress("0.0.0.0") && !covoo::validId("../secret"), "untrusted selectors accepted");
        auto* host = new HostApplication;
        auto* processor = new covoo::Processor;
        auto* controller = new covoo::Controller;
        require(processor->initialize(host) == kResultOk && controller->initialize(host) == kResultOk, "host init failed");
        processor->connect(controller); controller->connect(processor);
        ProcessSetup setup{kRealtime, kSample32, 256, 48000};
        if (hold && std::filesystem::exists(argv[3])) {
            const auto bytes=read(argv[3]);
            require(bytes.size()<=64,"public state fixture too large");
            MemoryStream saved;
            int32 written=0;
            require(saved.write(const_cast<char*>(bytes.data()),static_cast<int32>(bytes.size()),&written)==kResultOk && written==static_cast<int32>(bytes.size()),"state fixture write failed");
            saved.seek(0,IBStream::kIBSeekSet,nullptr);
            require(processor->setState(&saved)==kResultOk,"state fixture restore failed");
        }
        require(processor->setupProcessing(setup) == kResultOk && processor->setActive(true) == kResultOk, "source activation failed");
        controller->receiverCommand("status");
        require(controller->hostState == "Live has not enabled source processing.",
                "disabled processing diagnostic missing");
        processor->setProcessing(true);
        controller->receiverCommand("status");
        require(controller->hostState == "Waiting for Live's first audio callback.",
                "first callback diagnostic missing");
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
        if (!restored) SendMessageW(child, WM_COMMAND, MAKEWPARAM(103, BN_CLICKED), 0);
        const auto directory = covoo::receiverRun(instance);
        const auto status = directory / L"view.txt";
        require(waitFor(status, "Waiting for phone connection"), ("managed receiver failed: " + read(status) + controller->receiverError).c_str());
        require(waitFor(directory / L"pairing.bmp", "BM", 5), "QR not published");
        MemoryStream state;
        require(processor->getState(&state) == kResultOk && state.getSize() == 44, "public receiver configuration not saved");
        const auto recordings = read(directory / L"recordings.txt");
        auto profile=instance;
        if (hold && std::filesystem::exists(argv[3])) {
            const auto saved=read(argv[3]);
            require(saved.size()>=32,"profile fixture missing");
            profile=saved.substr(saved.size()-32);
            require(covoo::validId(profile),"profile fixture invalid");
        }
        const auto config = read(directory.parent_path().parent_path() / L"vst3-receivers" / profile / L"connection.json");
        require(!recordings.empty() && config.find("port") != std::string::npos, "recordings location/remembered port missing");
        if (hold) {
            std::ofstream publicState(argv[3],std::ios::binary);
            publicState.write(static_cast<const char*>(state.getData()),state.getSize());
            publicState.close();
            require(publicState.good(),"public state save failed");
            std::ofstream ready(argv[2]);ready<<instance;ready.close();
            require(ready.good(),"ready fixture write failed");
            const auto stop=std::filesystem::path(argv[2]).replace_extension(".stop");
            std::array<float,256> left{},right{};
            float* channels[]{left.data(),right.data()};
            AudioBusBuffers bus{};bus.numChannels=2;bus.channelBuffers32=channels;
            ProcessData data{};data.processMode=kRealtime;data.symbolicSampleSize=kSample32;
            data.numOutputs=1;data.outputs=&bus;data.numSamples=256;
            const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(30);
            while (!std::filesystem::exists(stop) && std::chrono::steady_clock::now()<deadline) {
                require(processor->process(data)==kResultOk,"fault host process failed");
                MSG message{};
                while(PeekMessageW(&message,nullptr,0,0,PM_REMOVE)) {TranslateMessage(&message);DispatchMessageW(&message);}
                std::this_thread::sleep_for(std::chrono::milliseconds(5));
            }
            require(std::filesystem::exists(stop),"fault holder deadline exceeded");
            view->removed();view->release();
            processor->setProcessing(false);processor->setActive(false);
            processor->disconnect(controller);controller->disconnect(processor);
            processor->terminate();controller->terminate();processor->release();controller->release();host->release();
            DestroyWindow(parent);
            return 0;
        }
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
