#define IMGUI_DEFINE_MATH_OPERATORS
#include <imgui/imgui.h>
#include <imgui/imgui_internal.h>
#include <menu/menu_chinese_font.h>
#include <dlssnr/DlssNr_PipelineUi.h>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <set>
#include <vector>

static void WritePreview(const char* path)
{
    constexpr int width = 1024, height = 1100;
    std::vector<unsigned char> output(width * height * 4, 255);
    for (int i = 0; i < width * height; ++i)
        output[i * 4] = 27, output[i * 4 + 1] = 23, output[i * 4 + 2] = 21;
    const auto edge = [](ImVec2 a, ImVec2 b, ImVec2 p) { return (p.x-a.x)*(b.y-a.y)-(p.y-a.y)*(b.x-a.x); };
    for (const auto* list : ImGui::GetDrawData()->CmdLists)
        for (const auto& command : list->CmdBuffer)
        {
            if (command.UserCallback) continue;
            const auto* texture = command.TexRef._TexData;
            for (unsigned idx = 0; idx + 2 < command.ElemCount; idx += 3)
            {
                const auto& a = list->VtxBuffer[list->IdxBuffer[command.IdxOffset+idx] + command.VtxOffset];
                const auto& b = list->VtxBuffer[list->IdxBuffer[command.IdxOffset+idx+1] + command.VtxOffset];
                const auto& c = list->VtxBuffer[list->IdxBuffer[command.IdxOffset+idx+2] + command.VtxOffset];
                const float area = edge(a.pos, b.pos, c.pos);
                if (std::abs(area) < 0.00001f) continue;
                const int minX = std::max(0, int(std::max(command.ClipRect.x, std::floor(std::min({a.pos.x,b.pos.x,c.pos.x})))));
                const int maxX = std::min(width, int(std::min(command.ClipRect.z, std::ceil(std::max({a.pos.x,b.pos.x,c.pos.x})))));
                const int minY = std::max(0, int(std::max(command.ClipRect.y, std::floor(std::min({a.pos.y,b.pos.y,c.pos.y})))));
                const int maxY = std::min(height, int(std::min(command.ClipRect.w, std::ceil(std::max({a.pos.y,b.pos.y,c.pos.y})))));
                for (int y = minY; y < maxY; ++y)
                    for (int x = minX; x < maxX; ++x)
                    {
                        const ImVec2 p(x+0.5f, y+0.5f);
                        const float wa = edge(b.pos,c.pos,p)/area, wb = edge(c.pos,a.pos,p)/area, wc = 1-wa-wb;
                        if (wa < 0 || wb < 0 || wc < 0) continue;
                        float colour[4] = {};
                        for (int channel = 0; channel < 4; ++channel)
                            colour[channel] = (((a.col >> (channel*8)) & 255)*wa + ((b.col >> (channel*8)) & 255)*wb + ((c.col >> (channel*8)) & 255)*wc)/255.0f;
                        if (texture && texture->Pixels)
                        {
                            const float u = a.uv.x*wa+b.uv.x*wb+c.uv.x*wc, v = a.uv.y*wa+b.uv.y*wb+c.uv.y*wc;
                            const int tx = std::clamp(int(u*texture->Width),0,texture->Width-1);
                            const int ty = std::clamp(int(v*texture->Height),0,texture->Height-1);
                            const auto* sample = texture->Pixels+(ty*texture->Width+tx)*texture->BytesPerPixel;
                            if (texture->BytesPerPixel == 1) colour[3] *= sample[0]/255.0f;
                            else for (int channel = 0; channel < 4; ++channel) colour[channel] *= sample[channel]/255.0f;
                        }
                        auto* pixel = &output[(y*width+x)*4];
                        for (int channel = 0; channel < 3; ++channel)
                            pixel[2-channel] = static_cast<unsigned char>(std::clamp(colour[channel]*colour[3]*255+pixel[2-channel]*(1-colour[3]),0.0f,255.0f));
                    }
            }
        }
    BITMAPFILEHEADER file = {};
    BITMAPINFOHEADER info = {};
    file.bfType = 0x4d42;
    file.bfOffBits = sizeof(file)+sizeof(info);
    file.bfSize = file.bfOffBits+static_cast<DWORD>(output.size());
    info.biSize = sizeof(info); info.biWidth = width; info.biHeight = -height;
    info.biPlanes = 1; info.biBitCount = 32; info.biCompression = BI_RGB;
    std::ofstream stream(path, std::ios::binary);
    stream.write(reinterpret_cast<const char*>(&file), sizeof(file));
    stream.write(reinterpret_cast<const char*>(&info), sizeof(info));
    stream.write(reinterpret_cast<const char*>(output.data()), output.size());
}

int main(int argc, char** argv)
{
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.IniFilename = nullptr;
    io.DisplaySize = ImVec2(1024,1100);
    io.DeltaTime = 1.0f/60.0f;
    io.BackendFlags |= ImGuiBackendFlags_RendererHasTextures;
    assert(MenuZh::LoadChineseFont(io, 16.0f));
    MenuZh::Enabled = true;
    assert(std::strcmp(MenuZh::Text("Save Settings"), "\xE4\xBF\x9D\xE5\xAD\x98\xE8\xAE\xBE\xE7\xBD\xAE") == 0);
    assert(std::strcmp(MenuZh::Text("nvngx_dlss.dll"), "nvngx_dlss.dll") == 0);
    bool checkbox = true;
    ImVec2 checkboxCentre;
    const auto frame = [&](int clickState)
    {
        if (clickState >= 0) { io.AddMousePosEvent(checkboxCentre.x,checkboxCentre.y); io.AddMouseButtonEvent(0,clickState != 0); }
        ImGui::NewFrame();
        ImGui::SetNextWindowPos(ImVec2(12,12), ImGuiCond_Always);
        ImGui::SetNextWindowSize(ImVec2(590,1075), ImGuiCond_Always);
        ImGui::Begin("OptiScaler 0.9.33 - Menu Preview",nullptr,ImGuiWindowFlags_NoResize|ImGuiWindowFlags_NoMove);
        const auto originalId = ImGui::GetID("Save Settings");
        MenuZh::Enabled = false;
        assert(ImGui::GetID("Save Settings") == originalId);
        MenuZh::Enabled = true;
        ImGui::Button("Save Settings");
        assert(GImGui->LastItemData.ID == originalId);
        const auto chinese = ImGui::CalcTextSize(MenuZh::Text("Change Upscaler"));
        const auto translated = ImGui::CalcTextSize("Change Upscaler");
        assert(std::abs(chinese.x-translated.x) < 0.01f);
        const auto hidden = ImGui::CalcTextSize("Change Upscaler##2",nullptr,true);
        assert(std::abs(hidden.x-chinese.x) < 0.01f);
        ImGui::SameLine(); ImGui::Button("Close");
        ImGui::SeparatorText("Upscalers");
        ImGui::Button("Change Upscaler##2");
        static int quality = 1;
        const char* qualities[] = {"Quality","Balanced","Performance","Ultra Performance"};
        ImGui::Combo("Upscaler Quality",&quality,qualities,4);
        ImGui::SeparatorText("Frame Generation");
        ImGui::Checkbox("Enable Frame Generation",&checkbox);
        const auto lo = ImGui::GetItemRectMin(), hi = ImGui::GetItemRectMax();
        checkboxCentre = ImVec2((lo.x+hi.x)*0.5f,(lo.y+hi.y)*0.5f);
        bool off = false;
        ImGui::Checkbox("External frame generation / MFG unlocker",&off);
        ImGui::Checkbox("Enable SM86/SM75 MFG (experimental; restart)##ampere",&off);
        ImGui::Checkbox("Dynamic Multi-Frame Generation##sm86",&off);
        int frames = 3; ImGui::SliderInt("Max Generated Frames",&frames,0,5);
        ImGui::TextWrapped("Save Settings and restart to apply this change.");
        ImGui::SeparatorText("DLSS Neural Rendering");
        DlssNr::PipelineUi::View view;
        static auto selected = DlssNr::PipelineUi::Section::Model;
        DlssNr::PipelineUi::Draw(view,selected);
        ImGui::End();
        ImGui::SetNextWindowPos(ImVec2(615,12), ImGuiCond_Always);
        ImGui::SetNextWindowSize(ImVec2(395,800), ImGuiCond_Always);
        ImGui::Begin("Advanced Settings",nullptr,ImGuiWindowFlags_NoResize|ImGuiWindowFlags_NoMove);
        ImGui::SeparatorText("Input");
        ImGui::SliderInt("Model resolution",&frames,25,200,"%d%%");
        ImGui::Checkbox("Peripheral compression",&off);
        ImGui::SeparatorText("Model passes");
        ImGui::Checkbox("Auto skin mask",&off);
        float intensity = 1.0f;
        ImGui::SliderFloat("Intensity",&intensity,0,2);
        ImGui::SliderFloat("Local structure",&intensity,0,2);
        ImGui::SeparatorText("Inspect NR");
        ImGui::Checkbox("Hold frame",&off);
        ImGui::Checkbox("Label the sides",&off);
        ImGui::TextWrapped("Compare the original and NR output.");
        ImGui::SeparatorText("Keybinds");
        ImGui::Button("Menu");
        ImGui::TextUnformatted("Escape to cancel, Backspace to unbind");
        ImGui::SeparatorText("Information");
        ImGui::Text("Running%s - %.2f ms elapsed%s","",1.23,"");
        ImGui::TextWrapped("NR needs the D3D12 bridge on D3D11. Choose an upscaler marked w/Dx12 and restart.");
        ImGui::Button("Open Wiki");
        ImGui::End();
        ImGui::Render();
        for (auto* texture : io.Fonts->TexList)
        {
            if (texture->Status == ImTextureStatus_WantDestroy) continue;
            texture->SetTexID(static_cast<ImTextureID>(texture->UniqueID+1));
            texture->SetStatus(ImTextureStatus_OK);
        }
    };
    frame(-1); frame(-1);
    frame(1); frame(0);
    assert(!checkbox);
    auto* baked = io.FontDefault->GetFontBaked(16.0f);
    std::set<unsigned int> glyphs;
    for (const auto& entry : MenuZh::Dictionary())
        for (const char* text = entry.second; *text;)
        {
            unsigned int codepoint = 0;
            const int bytes = ImTextCharFromUtf8(&codepoint,text,nullptr);
            assert(bytes > 0); text += bytes;
            if (codepoint < 0x80) continue;
            glyphs.insert(codepoint);
            assert(baked->FindGlyphNoFallback(static_cast<ImWchar>(codepoint)));
        }
    frame(-1);
    assert(ImGui::GetDrawData()->TotalVtxCount > 1000);
    if (argc > 1) WritePreview(argv[1]);
    std::printf("PASS: %zu translations, %zu Unicode glyphs, stable widget IDs, matching layout, real checkbox click.\n",MenuZh::Dictionary().size(),glyphs.size());
    ImGui::DestroyContext();
}
