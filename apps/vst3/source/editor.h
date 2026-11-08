#pragma once
#define NOMINMAX
#include <windows.h>
#include <string>
#include "public.sdk/source/common/pluginview.h"
namespace covoo {
class Controller;
class Editor final : public Steinberg::CPluginView {
public:
    explicit Editor(Controller& controller);
    ~Editor() override;
    Steinberg::tresult PLUGIN_API isPlatformTypeSupported(Steinberg::FIDString type) override;
    Steinberg::tresult PLUGIN_API attached(void* parent, Steinberg::FIDString type) override;
    Steinberg::tresult PLUGIN_API removed() override;
private:
    static LRESULT CALLBACK windowProc(HWND, UINT, WPARAM, LPARAM);
    void update();
    void command(unsigned id);
    Controller& controller_;
    HWND window_ = nullptr, interfaces_ = nullptr, status_ = nullptr, image_ = nullptr;
    HBITMAP bitmap_ = nullptr;
    std::string imageInstance_;
    HINSTANCE module_ = nullptr;
};
}
