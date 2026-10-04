#define IMGUI_DEFINE_MATH_OPERATORS
#include <imgui/imgui.h>
#include <imgui/imgui_internal.h>
#include <menu/menu_chinese_font.h>
#include <menu/transfusion/panel.h>
#include <cassert>
#include <fstream>
#include <set>

namespace OptiInput {
bool IsKeyDown(int) { return false; }
bool IsKeyPressed(int) { return false; }
}
static int WINAPI Status(DLSSGTStatus* status) {
    assert(status->version == DLSSGT_ADDON_API_VERSION);
    status->bridgeReady = 1; status->setOptionsSeen = 1;
    status->frameGenerationOn = 1; status->appliedMultiplier = 4;
    return 1;
}
static bool captured = false;
static void WINAPI Capture(int value) { captured = value != 0; }
static int WINAPI Overlay(DLSSGTOverlay* value) {
    value->visible=1; value->nativeDrawing=0; value->lineCount=1;
    strcpy_s(value->lines[0], "4x | 120 FPS"); return 1;
}
int main(int argc, char** argv) {
    assert(argc == 2);
    ImGui::CreateContext();
    auto& io = ImGui::GetIO();
    io.IniFilename = nullptr; io.DisplaySize = ImVec2(1024,800);
    io.DeltaTime = 1.0f/60; io.BackendFlags |= ImGuiBackendFlags_RendererHasTextures;
    assert(MenuZh::LoadChineseFont(io,16)); MenuZh::Enabled = true;
    using namespace TransfusionMenu;
    gConfigPath.assign(argv[1],argv[1]+strlen(argv[1]));
    gGetConfigPath = reinterpret_cast<DLSSGTGetConfigPathFn>(1); // path is supplied above
    gGetStatus = Status; gSetHotkeyCapture = Capture;
    gGetOverlay = Overlay;
    ReloadIfChanged(); assert(gLoaded);
    const std::string original = gText;
    // Exercise every mode and each expandable group using the real adapter.
    for (const char* mode : {"fixed","dynamic","game"}) {
        assert(SaveString("mode",mode));
        for (int frame=0;frame<3;++frame) {
            ImGui::NewFrame();
            ImGui::SetNextWindowSize(ImVec2(750,650));
            ImGui::Begin("Transfusion test");
            Render();
            ImGui::SetNextItemOpen(true,ImGuiCond_Always); DrawDisplay();
            ImGui::SetNextItemOpen(true,ImGuiCond_Always); Keyboard keyboard; DrawHotkeys(&keyboard);
            ImGui::End(); ImGui::Render();
            assert(ImGui::GetDrawData()->TotalVtxCount > 0);
        }
        std::string value; assert(config_text::GetString(gText,"mode",value) && value==mode);
    }
    // A real mouse click must edit the original JSON key, with atomic persistence.
    ImVec2 click;
    auto draw = [&](int state) {
        if(state>=0) { io.AddMousePosEvent(click.x,click.y); io.AddMouseButtonEvent(0,state!=0); }
        ImGui::NewFrame();
        ImGui::SetNextWindowPos(ImVec2(20,20)); ImGui::SetNextWindowSize(ImVec2(750,200));
        ImGui::Begin("Persistence test");
        BoolSetting("showOverlay",MenuZh::Text("Show multiplier / FPS overlay"),false,false,"");
        const auto lo=ImGui::GetItemRectMin(),hi=ImGui::GetItemRectMax();
        click=ImVec2((lo.x+hi.x)/2,(lo.y+hi.y)/2);
        ImGui::End(); ImGui::Render();
    };
    draw(-1);draw(-1);draw(0);draw(1);draw(0);
    bool show=false; assert(config_text::GetBool(gText,"showOverlay",show) && show);
    std::string disk; FILETIME time{};
    assert(ReadWholeFile(gConfigPath,disk,time) && disk==gText);
    assert(disk.find("\"showOverlay\": true")!=std::string::npos);
    assert(disk.find("// Show the in-game")!=std::string::npos); // comments survive
    SetCapture(true); assert(captured); ResetCapture(); assert(!captured && gListening==-1);
    assert(NeedsOverlay());
    for(int i=0;i<3;++i){ImGui::NewFrame(); DrawGameOverlay(); ImGui::Render();}
    assert(ImGui::GetDrawData()->TotalVtxCount>0);
    // Every translated Unicode code point has a real system-font glyph.
    std::set<unsigned> glyphs;
    for(const auto& entry:MenuZh::Dictionary()) {
        const char* p=entry.second;
        while(*p) { unsigned c=0; p+=ImTextCharFromUtf8(&c,p,nullptr); if(c>127) glyphs.insert(c); }
    }
    auto* baked=io.FontDefault->GetFontBaked(16);
    for(auto c:glyphs) assert(baked->FindGlyphNoFallback(c));
    printf("Transfusion panel: all modes rendered, mouse toggle persisted, comments preserved, capture released, %zu glyphs verified.\n",glyphs.size());
    ImGui::DestroyContext();
}
