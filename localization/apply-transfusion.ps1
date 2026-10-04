param([Parameter(Mandatory=$true)][string]$SourcePath)
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
$source = Join-Path $PSScriptRoot 'transfusion'
$dest = Join-Path $SourcePath 'OptiScaler/menu/transfusion'
New-Item -ItemType Directory -Path $dest -Force | Out-Null
foreach ($name in @('addon_api.h','hotkey_binding.h','config_text.hpp')) { Copy-Item -LiteralPath (Join-Path $source $name) -Destination $dest -Force }
$panel = [IO.File]::ReadAllText((Join-Path $source 'upstream-addon.cpp'))
$overlayStart = $panel.IndexOf('void DrawGameOverlay(')
$overlay = $panel.Substring($overlayStart,$panel.IndexOf('bool gRegistered',$overlayStart)-$overlayStart).Replace('reshade::api::effect_runtime*','')
$panel = $panel.Substring(0, $panel.IndexOf('bool OnOverlay(')) + "`n" + $overlay + "`n} // namespace TransfusionMenu`n"
$panel = $panel.Replace('#define ImTextureID ImU64', '').Replace('#include <deps/imgui/imgui.h>', '#include <imgui/imgui.h>')
$panel = $panel.Replace('#include <include/reshade.hpp>', '#include "../input/input_system.h"')
$panel = $panel.Replace('#include "config_text.hpp"', '#include "config_text.hpp"' + "`n" + '#include "../menu_localization.h"')
$panel = $panel.Replace('../native/addon_api.h', 'addon_api.h').Replace('../native/hotkey_binding.h', 'hotkey_binding.h')
$panel = [regex]::Replace($panel, '(?m)^namespace\r?\n\{', "namespace TransfusionMenu`n{")
$panel = $panel.Replace('reshade::api::effect_runtime* runtime', 'Keyboard* runtime')
$keyboard = @'
struct Keyboard {
    bool is_key_pressed(uint32_t key) const { return OptiInput::IsKeyPressed(static_cast<int>(key)); }
    bool is_key_down(uint32_t key) const { return OptiInput::IsKeyDown(static_cast<int>(key)); }
};
'@
$at = $panel.IndexOf('constexpr const char* kPanelName')
$panel = $panel.Insert($at, $keyboard + "`n")
# Keep ASCII symbols supported by the existing OptiScaler font (no ReShade icon font).
$icons = @{ '\xef\x80\xa1'='!'; '\xef\x83\xa2'='R'; '\xef\x80\x8c'='+'; '\xef\x81\xb1'='!'; '\xef\x80\x8d'='x'; '\xef\x81\x9a'='i'; '\xef\x84\x8c'='o' }
foreach ($key in $icons.Keys) { $panel = $panel.Replace($key, $icons[$key]) }
$panel = $panel.Replace('ImVec2(0, 0), ImGuiChildFlags_AlwaysUseWindowPadding', 'ImVec2(680, 560), ImGuiChildFlags_AlwaysUseWindowPadding')
$entries = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
foreach ($line in [IO.File]::ReadAllLines((Join-Path $source 'menu.zh-CN.txt'), $utf8)) {
    if (!$line.Trim() -or $line.StartsWith('#')) { continue }
    $parts = $line -split ' => ', 2
    if ($parts.Count -ne 2) { throw 'Malformed Transfusion translation' }
    $key = [regex]::Unescape($parts[0]); $value = [regex]::Unescape($parts[1])
    if ($entries.Contains($key)) { throw "Duplicate Transfusion translation: $key" }
    $formats = '%[-+#0]*[0-9]*(?:\.[0-9]+)?(?:hh|ll|[hljztL])?[diuoxXfFeEgGaAcspn%]'
    if ((@([regex]::Matches($key,$formats)|ForEach-Object Value) -join '|') -cne (@([regex]::Matches($value,$formats)|ForEach-Object Value) -join '|')) { throw "Printf mismatch: $key" }
    $entries.Add($key,$value)
}
# Rewrite complete C++ literal groups only. Neither JSON keys nor serialized
# option values appear in the translation map. Original sources stay intact.
$literalPattern = '"(?:[^"\\]|\\.)*"(?:\s*"(?:[^"\\]|\\.)*")*'
$panel = [regex]::Replace($panel,$literalPattern,[Text.RegularExpressions.MatchEvaluator]{param($m)
    $value = ([regex]::Matches($m.Value,'"((?:[^"\\]|\\.)*)"') | ForEach-Object { [regex]::Unescape($_.Groups[1].Value) }) -join ''
    if ($entries.Contains($value)) { return 'MenuZh::Text(' + $m.Value + ')' }
    return $m.Value
})
# Hotkey labels come from an untouched shared engine header; translate at display.
$panel = [regex]::Replace($panel,'Info\(([^)]+)\)\.label','MenuZh::Text(Info($1).label)')
# Font measurement and direct draw-list text must use the same translated value.
$panel = $panel.Replace('std::string full = text;', 'std::string full = MenuZh::Text(text);')
$panel = $panel.Replace('return text;', 'return MenuZh::Text(text);')
$panel = $panel.Replace('format, values...', 'MenuZh::Text(format), values...')
$panel = $panel.Replace('format, args', 'MenuZh::Text(format), args')
$panel += @'
namespace TransfusionMenu {
inline void ResetCapture() { gListening = -1; SetCapture(false); }
inline bool Available() { return ConnectEngine(); }
inline void Render() { Keyboard keyboard; DrawPanel(&keyboard); }
inline bool NeedsOverlay() {
    static DLSSGTOverlay value{};
    static ULONGLONG last = 0;
    const auto now = GetTickCount64();
    if (now-last >= 250) {
        last=now; value={}; value.size=sizeof(value);
        if (!ConnectEngine() || !gGetOverlay || !gGetOverlay(&value)) value={};
    }
    return value.visible && !value.nativeDrawing && value.lineCount;
}
}
'@
[IO.File]::WriteAllText((Join-Path $dest 'panel.h'), $panel, $utf8)
# Extend the dictionary/font atlas for this profile, leaving the normal map intact.
$dictionary = Join-Path $SourcePath 'OptiScaler/menu/menu_zh_dictionary.h'
$text = [IO.File]::ReadAllText($dictionary)
$extra = foreach ($key in $entries.Keys) {
    $escaped = ($utf8.GetBytes($entries[$key]) | ForEach-Object { '\x'+$_.ToString('X2') }) -join ''
    '        { R"zh('+ $key +')zh", "'+$escaped+'" },'
}
# insert before base entries so shared label translations use the new panel's map
$text = $text.Replace('static const std::unordered_map<std::string_view, const char*> values = {', 'static const std::unordered_map<std::string_view, const char*> values = {' + "`n" + ($extra -join "`n"))
[IO.File]::WriteAllText($dictionary,$text,$utf8)
$commonPath = Join-Path $SourcePath 'OptiScaler/menu/menu_common.cpp'
$common = [IO.File]::ReadAllText($commonPath)
if (!$common.Contains('transfusion/panel.h')) {
    $common = $common.Replace('#include "pch.h"', '#include "pch.h"' + "`n" + '#include "transfusion/panel.h"')
    $old = @'
        // Main two-column settings content.
        RenderMainMenuTable(ctx);

        // Diagnostics and footer actions below the settings table.
        RenderMainMenuGraphs(ctx);
        RenderMainMenuBottomBar(ctx);
'@
    $new = @'
        if (ImGui::BeginTabBar("##OptiScalerTransfusionTabs")) {
            if (ImGui::BeginTabItem("OptiScaler")) {
                TransfusionMenu::ResetCapture();
                RenderMainMenuTable(ctx);
                RenderMainMenuGraphs(ctx);
                RenderMainMenuBottomBar(ctx);
                ImGui::EndTabItem();
            }
            if (ImGui::BeginTabItem("Transfusion frame generation")) {
                TransfusionMenu::Render();
                ImGui::EndTabItem();
            }
            ImGui::EndTabBar();
        }
'@
    $normalized = $common.Replace("`r`n","`n")
    if (!$normalized.Contains($old.Replace("`r`n","`n"))) { throw 'Main menu integration point missing' }
    $common = $normalized.Replace($old.Replace("`r`n","`n"),$new.Replace("`r`n","`n"))
    # Once the new engine is loaded, hide the obsolete FG/SM controls entirely.
    foreach ($fn in @('RenderFrameGenerationSelection','RenderFrameGenerationRuntimeSettings')) {
        $pattern = '(void MenuCommon::'+$fn+'\(RenderMenuContext& ctx\)\s*\{)'
        $common = [regex]::Replace($common,$pattern,'$1' + "`n    if (TransfusionMenu::Available()) return;`n")
    }
    $common = $common.Replace('    RenderMainMenuWindow(ctx);', '    if (!_isVisible) TransfusionMenu::ResetCapture();' + "`n    RenderMainMenuWindow(ctx);")
    [IO.File]::WriteAllText($commonPath,$common,[Text.UTF8Encoding]::new($true))
}
$common = [IO.File]::ReadAllText($commonPath)
if (!$common.Contains('TransfusionMenu::NeedsOverlay()')) {
    $common=$common.Replace('config->ShowFps.value_or_default() || _isVisible ||', 'config->ShowFps.value_or_default() || TransfusionMenu::NeedsOverlay() || _isVisible ||')
    $common=$common.Replace('    RenderPerformanceOverlay(ctx);', '    RenderPerformanceOverlay(ctx);' + "`n    if (ctx.newFrame) TransfusionMenu::DrawGameOverlay();")
    [IO.File]::WriteAllText($commonPath,$common,[Text.UTF8Encoding]::new($true))
}
Write-Output "Integrated $($entries.Count) Transfusion translations in the existing OptiScaler menu"
