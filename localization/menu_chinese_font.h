#pragma once
#include "menu_localization.h"
#include <imgui/imgui.h>
#include <Windows.h>
#include <string>

namespace MenuZh
{
inline bool LoadChineseFont(ImGuiIO& io, float size)
{
    if (io.Fonts->Fonts.empty())
    {
        ImFontConfig base;
        base.SizePixels = size;
        io.FontDefault = io.Fonts->AddFontDefault(&base);
    }
    if (!io.FontDefault)
        io.FontDefault = io.Fonts->Fonts[0];

    // Only load the glyphs used by the translation, keeping the atlas small.
    static ImVector<ImWchar> ranges;
    ranges.clear();
    ImFontGlyphRangesBuilder builder;
    for (const auto& entry : Dictionary())
        builder.AddText(entry.second);
    builder.BuildRanges(&ranges);

    wchar_t windows[MAX_PATH] = {};
    if (!GetWindowsDirectoryW(windows, MAX_PATH))
        return false;
    const wchar_t* candidates[] = { L"\\Fonts\\msyh.ttc", L"\\Fonts\\simhei.ttf", L"\\Fonts\\arialuni.ttf" };
    for (const auto* candidate : candidates)
    {
        const std::wstring path = std::wstring(windows) + candidate;
        HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                                  FILE_ATTRIBUTE_NORMAL, nullptr);
        if (file == INVALID_HANDLE_VALUE)
            continue;
        const DWORD bytes = GetFileSize(file, nullptr);
        if (!bytes || bytes == INVALID_FILE_SIZE || bytes > 64 * 1024 * 1024)
        {
            CloseHandle(file);
            continue;
        }
        void* data = ImGui::MemAlloc(bytes);
        DWORD read = 0;
        const bool loaded = data && ReadFile(file, data, bytes, &read, nullptr) && read == bytes;
        CloseHandle(file);
        if (!loaded)
        {
            ImGui::MemFree(data);
            continue;
        }
        ImFontConfig config;
        config.MergeMode = true;
        config.FontDataOwnedByAtlas = true;
        config.DstFont = io.FontDefault;
        io.Fonts->AddFontFromMemoryTTF(data, static_cast<int>(bytes), size, &config, ranges.Data);
        return true;
    }
    return false;
}
}
