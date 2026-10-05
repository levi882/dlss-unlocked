param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [string]$Version = '0.9.34',
    [string]$BaseCommit = '73fab132f9f48d194926b27124d9320b0b4cc870'
)
$ErrorActionPreference = 'Stop'
$SourcePath = [IO.Path]::GetFullPath($SourcePath)
$baseCommit = $BaseCommit
$actualCommit = (& git -C $SourcePath rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $baseCommit) {
    throw "This menu patch targets OptiScaler $Version at $baseCommit; got $actualCommit"
}
if ($Version -notmatch '^\d+\.\d+\.\d+$' -or $BaseCommit -notmatch '^[a-f0-9]{40}$') { throw 'Invalid source version or commit' }
$tagCommit = (& git -C $SourcePath rev-parse "v${Version}^{commit}").Trim()
if ($LASTEXITCODE -ne 0 -or $tagCommit -ne $BaseCommit) { throw 'Source commit does not match the upstream version tag' }
$utf8 = New-Object Text.UTF8Encoding($false)
$entries = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
foreach ($line in [IO.File]::ReadAllLines((Join-Path $PSScriptRoot 'menu.zh-CN.txt'), $utf8)) {
    if (!$line.Trim() -or $line.StartsWith('#')) { continue }
    $parts = $line -split ' => ', 2
    if ($parts.Count -ne 2) { throw "Invalid translation: $line" }
    $key = [regex]::Unescape($parts[0])
    $value = [regex]::Unescape($parts[1])
    if ($entries.Contains($key)) { throw "Duplicate translation: $key" }
    $entries.Add($key, $value)
    $formatPattern = '%[-+#0]*[0-9]*(?:\.[0-9]+)?(?:hh|ll|[hljztL])?[diuoxXfFeEgGaAcspn%]'
    $originalFormats = @([regex]::Matches($key, $formatPattern) | ForEach-Object { $_.Value })
    $translatedFormats = @([regex]::Matches($value, $formatPattern) | ForEach-Object { $_.Value })
    if (($originalFormats -join '|') -cne ($translatedFormats -join '|')) {
        throw "Printf placeholders differ: $key"
    }
}
$menuPath = Join-Path $SourcePath 'OptiScaler\menu'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'menu_localization.h') -Destination $menuPath -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'menu_chinese_font.h') -Destination $menuPath -Force
$header = @(
    '#pragma once', '#include <string_view>', '#include <unordered_map>',
    'namespace MenuZh {',
    'inline const std::unordered_map<std::string_view, const char*>& Dictionary() {',
    '    static const std::unordered_map<std::string_view, const char*> values = {'
)
foreach ($key in $entries.Keys) {
    $value = $entries[$key]
    if ($key.Contains(')zh"') -or $value.Contains(')zh"')) { throw 'Raw literal delimiter collision' }
    # Narrow literals must be UTF-8 even on a compiler using code page 936.
    $escapedValue = ($utf8.GetBytes($value) | ForEach-Object { '\x' + $_.ToString('X2') }) -join ''
    $header += '        { R"zh(' + $key + ')zh", "' + $escapedValue + '" },'
}
$header += @('    };', '    return values;', '}', '}')
$dictionaryPath = Join-Path $menuPath 'menu_zh_dictionary.h'
$dictionaryText = ($header -join "`n") + "`n"
if (!(Test-Path -LiteralPath $dictionaryPath) -or [IO.File]::ReadAllText($dictionaryPath) -cne $dictionaryText) {
    [IO.File]::WriteAllText($dictionaryPath, $dictionaryText, $utf8)
}

function Add-AtFunctionStart([string]$text, [string]$name, [string]$code) {
    $pattern = '(?m)^' + [regex]::Escape($name) + '[^\r\n]*\r?\n\{\r?\n'
    $match = [regex]::Match($text, $pattern)
    if (!$match.Success) { throw "Function not found: $name" }
    return $text.Insert($match.Index + $match.Length, $code + "`n")
}

$imguiPath = Join-Path $SourcePath 'OptiScaler\include\imgui\imgui.cpp'
$imgui = [IO.File]::ReadAllText($imguiPath)
if (!$imgui.Contains('MenuZh::Range')) {
    $imgui = [regex]::Replace($imgui, '(?m)^#include "imgui.h"\r?$', '#include "imgui.h"' + "`n" + '#include "../../menu/menu_localization.h"')
    $imgui = Add-AtFunctionStart $imgui 'void ImGui::RenderTextWrapped(' '    MenuZh::Range(text, text_end);'
    $imgui = Add-AtFunctionStart $imgui 'void ImGui::RenderTextClippedEx(' '    MenuZh::Range(text, text_display_end);'
    # Insert after hiding ##, preserving original ID and pointer boundaries.
    $start = $imgui.IndexOf('void ImGui::RenderText(')
    $at = $imgui.IndexOf('    if (text != text_display_end)', $start)
    $imgui = $imgui.Insert($at, "    MenuZh::Range(text, text_display_end);`n`n")
    $start = $imgui.IndexOf('void ImGui::RenderTextEllipsis(')
    $at = $imgui.IndexOf('    const ImVec2 text_size', $start)
    $imgui = $imgui.Insert($at, "    MenuZh::Range(text, text_end_full);`n")
    $start = $imgui.IndexOf('ImVec2 ImGui::CalcTextSize(')
    $at = $imgui.IndexOf('    ImFont* font = g.Font;', $start)
    $imgui = $imgui.Insert($at, "    MenuZh::Range(text, text_display_end);`n`n")
    [IO.File]::WriteAllText($imguiPath, $imgui, $utf8)
}

$widgetsPath = Join-Path $SourcePath 'OptiScaler\include\imgui\imgui_widgets.cpp'
$widgets = [IO.File]::ReadAllText($widgetsPath)
if (!$widgets.Contains('MenuZh::Range')) {
    $widgets = [regex]::Replace($widgets, '(?m)^#include "imgui.h"\r?$', '#include "imgui.h"' + "`n" + '#include "../../menu/menu_localization.h"')
    $widgets = Add-AtFunctionStart $widgets 'void ImGui::TextEx(' '    MenuZh::Range(text, text_end);'
    $widgets = Add-AtFunctionStart $widgets 'void ImGui::TextV(' '    fmt = MenuZh::Text(fmt);'
    [IO.File]::WriteAllText($widgetsPath, $widgets, $utf8)
}

$commonPath = Join-Path $menuPath 'menu_common.cpp'
$commonEncoding = New-Object Text.UTF8Encoding($true)
$common = [IO.File]::ReadAllText($commonPath)
if (!$common.Contains('MenuZh::LoadChineseFont')) {
    $common = $common.Replace('#include "menu_common.h"', '#include "menu_common.h"' + "`n" + '#include "menu_chinese_font.h"')
    $anchor = '    if (!Config::Instance()->OverlayMenu.value_or_default())'
    $initStart = $common.IndexOf('    // Setup Dear ImGui context')
    $at = $common.IndexOf($anchor, $initStart)
    if ($at -lt 0) { throw 'Font initialization anchor not found' }
    $common = $common.Insert($at, "    MenuZh::Enabled = MenuZh::LoadChineseFont(io, fontSize);`n    if (!MenuZh::Enabled)`n        LOG_WARN(`"Chinese menu font unavailable; retaining English labels`" );`n`n")
    # Status words appear only as displayed values. Backend/config strings stay intact.
    foreach ($word in @('Exists', "Doesn't Exist", 'Exist', "Don't Exist")) {
        $common = $common.Replace('"' + $word + '"', 'MenuZh::Text("' + $word + '")')
    }
    [IO.File]::WriteAllText($commonPath, $common, $commonEncoding)
}
if (!$common.Contains('fmt = MenuZh::Text(fmt);')) {
    $common = Add-AtFunctionStart $common 'inline std::string StrFmt(' '    fmt = MenuZh::Text(fmt);'
    [IO.File]::WriteAllText($commonPath, $common, $commonEncoding)
}
# Upstream menu_common.cpp uses a UTF-8 BOM; preserve its source encoding.
if ([IO.File]::ReadAllBytes($commonPath)[0] -ne 0xEF) {
    [IO.File]::WriteAllText($commonPath, $common, $commonEncoding)
}

$nrMenuPath = Join-Path $SourcePath 'OptiScaler\dlssnr\DlssNr_Menu.cpp'
$nrMenu = [IO.File]::ReadAllText($nrMenuPath)
if (!$nrMenu.Contains('menu_localization.h')) {
    $nrMenu = $nrMenu.Replace('#include "pch.h"', '#include "pch.h"' + "`n" + '#include <menu/menu_localization.h>')
    foreach ($part in @('  (model running, edit hidden)', ' natively on Vulkan')) {
        $nrMenu = $nrMenu.Replace('"' + $part + '"', 'MenuZh::Text("' + $part + '")')
    }
    [IO.File]::WriteAllText($nrMenuPath, $nrMenu, $utf8)
}

$overlayPath = Join-Path $SourcePath 'OptiScaler\dlssnr\DlssNr_MenuOverlay.cpp'
$overlay = [IO.File]::ReadAllText($overlayPath)
if (!$overlay.Contains('menu_localization.h')) {
    $overlay = $overlay.Replace('#include "pch.h"', '#include "pch.h"' + "`n" + '#include <menu/menu_localization.h>')
    foreach ($tag in @('DLSS NR : ON', 'DLSS NR : OFF')) {
        $overlay = $overlay.Replace('"' + $tag + '"', 'MenuZh::Text("' + $tag + '")')
    }
    [IO.File]::WriteAllText($overlayPath, $overlay, $utf8)
}

$pipelinePath = Join-Path $SourcePath 'OptiScaler\dlssnr\DlssNr_PipelineUi.h'
$pipeline = [IO.File]::ReadAllText($pipelinePath)
if (!$pipeline.Contains('menu_localization.h')) {
    $pipeline = $pipeline.Replace('#include <imgui/imgui.h>', '#include <imgui/imgui.h>' + "`n" + '#include <menu/menu_localization.h>')
    $pipeline = $pipeline.Replace('label.title, nullptr, wrapWidth', 'MenuZh::Text(label.title), nullptr, wrapWidth')
    $pipeline = $pipeline.Replace('label.detail.c_str(),' + "`r`n" + '                      nullptr, wrapWidth', 'MenuZh::Text(label.detail.c_str()),' + "`r`n" + '                      nullptr, wrapWidth')
    foreach ($part in @(' pass', ' passes', ' pass (no RR)', 'Separate ', 'HDR / paper white / ')) {
        $pipeline = $pipeline.Replace('"' + $part + '"', 'MenuZh::Text("' + $part + '")')
    }
    [IO.File]::WriteAllText($pipelinePath, $pipeline, $utf8)
}
Write-Output "Applied $($entries.Count) menu translations to $SourcePath"
