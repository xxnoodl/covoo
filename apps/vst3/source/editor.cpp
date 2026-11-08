#define NOMINMAX
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include "editor.h"
#include "plugin.h"
#include "receiver_process.h"
#include <cstring>
#include <fstream>
#include <vector>

namespace covoo {
namespace {
const Steinberg::ViewRect viewRect(0, 0, 680, 620);
const char editorAnchor = 0;
unsigned openViews = 0; // Editor lifetime is confined to the host UI thread.
std::wstring widen(const std::string& text) { return {text.begin(), text.end()}; }
std::string read(const std::filesystem::path& path) {
    std::ifstream stream(path, std::ios::binary);
    std::string result(8192, '\0');
    stream.read(result.data(), static_cast<std::streamsize>(result.size()));
    result.resize(static_cast<std::size_t>(stream.gcount()));
    return result;
}
HWND control(HWND parent, const wchar_t* type, const wchar_t* label, DWORD style, int x, int y, int width, int height, int id = 0) {
    auto window = CreateWindowExW(0, type, label, WS_CHILD | WS_VISIBLE | style,
        x, y, width, height, parent, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr), nullptr);
    SendMessageW(window, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
    return window;
}
void enumerate(HWND combo, const std::string& preferred) {
    SendMessageW(combo, CB_RESETCONTENT, 0, 0);
    ULONG bytes = 16384;
    std::vector<unsigned char> memory(bytes);
    auto* adapters = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(memory.data());
    ULONG result = GetAdaptersAddresses(AF_INET, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER, nullptr, adapters, &bytes);
    if (result == ERROR_BUFFER_OVERFLOW) {
        memory.resize(bytes); adapters = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(memory.data());
        result = GetAdaptersAddresses(AF_INET, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER, nullptr, adapters, &bytes);
    }
    if (result != NO_ERROR) return;
    for (auto* adapter = adapters; adapter; adapter = adapter->Next) {
        if (adapter->OperStatus != IfOperStatusUp || adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
        for (auto* item = adapter->FirstUnicastAddress; item; item = item->Next) {
            if (item->Address.lpSockaddr->sa_family != AF_INET) continue;
            wchar_t address[INET_ADDRSTRLEN]{};
            const auto* ipv4 = reinterpret_cast<sockaddr_in*>(item->Address.lpSockaddr);
            if (!InetNtopW(AF_INET, const_cast<IN_ADDR*>(&ipv4->sin_addr), address, INET_ADDRSTRLEN)) continue;
            const auto label = std::wstring(address) + L" | " + adapter->FriendlyName;
            const auto index = SendMessageW(combo, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(label.c_str()));
            if (std::wstring(address) == widen(preferred)) SendMessageW(combo, CB_SETCURSEL, index, 0);
        }
    }
}
}
Editor::Editor(Controller& controller) : CPluginView(&viewRect), controller_(controller) { controller_.addRef(); }
Editor::~Editor() { removed(); controller_.release(); }
Steinberg::tresult PLUGIN_API Editor::isPlatformTypeSupported(Steinberg::FIDString type) {
    return type && !std::strcmp(type, Steinberg::kPlatformTypeHWND) ? Steinberg::kResultTrue : Steinberg::kResultFalse;
}
Steinberg::tresult PLUGIN_API Editor::attached(void* parent, Steinberg::FIDString type) {
    if (!parent || isPlatformTypeSupported(type) != Steinberg::kResultTrue || window_) return Steinberg::kResultFalse;
    WNDCLASSW description{};
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&editorAnchor), &module_);
    description.lpfnWndProc = windowProc; description.hInstance = module_;
    description.lpszClassName = L"CovooVstEditor";
    description.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    description.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
    RegisterClassW(&description);
    window_ = CreateWindowExW(0, description.lpszClassName, L"covoo", WS_CHILD | WS_VISIBLE,
        0, 0, 680, 620, static_cast<HWND>(parent), nullptr, description.hInstance, this);
    if (!window_) return Steinberg::kResultFalse;
    ++openViews;
    systemWindow = parent;
    control(window_, L"STATIC", L"covoo  /  Phone microphone", 0, 20, 16, 620, 28);
    control(window_, L"STATIC", L"First time: choose your PC connection, then Start. Scan here from the phone app.", 0, 20, 48, 640, 35);
    interfaces_ = control(window_, L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_VSCROLL, 20, 88, 470, 160, 101);
    control(window_, L"BUTTON", L"Refresh", BS_PUSHBUTTON, 505, 88, 130, 28, 102);
    control(window_, L"BUTTON", L"Start", BS_PUSHBUTTON, 20, 130, 100, 30, 103);
    control(window_, L"BUTTON", L"Stop", BS_PUSHBUTTON, 130, 130, 100, 30, 104);
    control(window_, L"BUTTON", L"Recordings", BS_PUSHBUTTON, 245, 130, 125, 30, 105);
    control(window_, L"BUTTON", L"Reset pairing", BS_PUSHBUTTON, 385, 130, 125, 30, 106);
    control(window_, L"STATIC", L"On your phone: Scan QR code, Remember receiver, Connect, then Stream to PC.\nNo MIDI notes needed. Put effects after covoo on this track.", 0, 20, 178, 640, 40);
    image_ = control(window_, L"STATIC", L"", SS_BITMAP | SS_CENTERIMAGE, 20, 230, 330, 330);
    status_ = control(window_, L"EDIT", L"Waiting for the source to activate…", ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL | WS_VSCROLL, 365, 230, 290, 330);
    control(window_, L"STATIC", L"Save this Live project to remember this receiver. Closing this window keeps audio running.", 0, 20, 577, 640, 30);
    enumerate(interfaces_, controller_.receiverAddress);
    SetTimer(window_, 1, 500, nullptr);
    update();
    return Steinberg::kResultOk;
}
Steinberg::tresult PLUGIN_API Editor::removed() {
    if (window_) {
        KillTimer(window_, 1); DestroyWindow(window_); window_ = nullptr;
        if (--openViews == 0) UnregisterClassW(L"CovooVstEditor", module_);
    }
    if (bitmap_) { DeleteObject(bitmap_); bitmap_ = nullptr; }
    systemWindow = nullptr;
    return Steinberg::kResultOk;
}
void Editor::command(unsigned id) {
    if (id == 102) { enumerate(interfaces_, controller_.receiverAddress); return; }
    if (id == 104) { controller_.receiverCommand("stop"); return; }
    if (id == 106) {
        if (MessageBoxW(window_, L"Stop the receiver and reject the old phone pairing? Start again to get a new QR code.", L"Reset covoo pairing", MB_YESNO | MB_ICONQUESTION) == IDYES)
            controller_.receiverCommand("forget");
        return;
    }
    if (id == 103) {
        const auto index = SendMessageW(interfaces_, CB_GETCURSEL, 0, 0);
        if (index == CB_ERR) { SetWindowTextW(status_, L"Choose the network interface your phone can reach."); return; }
        const auto length = SendMessageW(interfaces_, CB_GETLBTEXTLEN, index, 0);
        if (length <= 0 || length > 1024) return;
        std::wstring text(static_cast<std::size_t>(length) + 1, L'\0');
        SendMessageW(interfaces_, CB_GETLBTEXT, index, reinterpret_cast<LPARAM>(text.data()));
        text.resize(text.find(L' '));
        controller_.receiverCommand("start", {text.begin(), text.end()});
    }
    if (id == 105 && validId(controller_.instance)) {
        const auto directory = read(receiverRun(controller_.instance) / L"recordings.txt");
        // Open only a real child of this account's recordings root.
        const auto root = receiverRun(controller_.instance).parent_path().parent_path() / L"recordings";
        const auto path = std::filesystem::u8path(directory).lexically_normal();
        if (path.parent_path() == root && std::filesystem::is_directory(path))
            ShellExecuteW(window_, L"open", path.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
    }
}
void Editor::update() {
    controller_.receiverCommand("status");
    if (!controller_.receiverError.empty()) { SetWindowTextW(status_, widen(controller_.receiverError).c_str()); return; }
    if (!validId(controller_.instance)) { SetWindowTextW(status_, L"Enable the covoo source in Live first."); return; }
    const auto directory = receiverRun(controller_.instance);
    auto text = read(directory / L"view.txt");
    if (text.empty()) text = "Choose your connection above and press Start.\r\n\r\nPairing is saved for this project. No standalone covoo window is needed.";
    else {
        std::error_code error;
        const auto modified = std::filesystem::last_write_time(directory / L"view.txt", error);
        if (!error && std::filesystem::file_time_type::clock::now() - modified > std::chrono::seconds(5))
            text = "Status is stale or the receiver has stopped.\r\n" + text;
    }
    SetWindowTextW(status_, widen(text).c_str());
    const auto path = directory / L"pairing.bmp";
    if (std::filesystem::exists(path) && (!bitmap_ || imageInstance_ != controller_.instance)) {
        auto next = static_cast<HBITMAP>(LoadImageW(nullptr, path.c_str(), IMAGE_BITMAP, 330, 330, LR_LOADFROMFILE));
        if (next) {
            SendMessageW(image_, STM_SETIMAGE, IMAGE_BITMAP, reinterpret_cast<LPARAM>(next));
            if (bitmap_) DeleteObject(bitmap_);
            bitmap_ = next; imageInstance_ = controller_.instance;
        }
    } else if (!std::filesystem::exists(path) && bitmap_) {
        SendMessageW(image_, STM_SETIMAGE, IMAGE_BITMAP, 0); DeleteObject(bitmap_); bitmap_ = nullptr;
    }
}
LRESULT CALLBACK Editor::windowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    auto* self = reinterpret_cast<Editor*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
        self = static_cast<Editor*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (self) {
        // No exception may escape a Windows message dispatch into the DAW.
        try {
            if (message == WM_TIMER) { self->update(); return 0; }
            if (message == WM_COMMAND && HIWORD(wparam) == BN_CLICKED) { self->command(LOWORD(wparam)); return 0; }
        } catch (...) { if (self->status_) SetWindowTextW(self->status_, L"Connection control failed. Stop and reopen this view."); }
    }
    return DefWindowProcW(window, message, wparam, lparam);
}
}
