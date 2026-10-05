param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [string]$DeveloperCommand = ''
)
$ErrorActionPreference = 'Stop'
$SourcePath = [IO.Path]::GetFullPath($SourcePath)
$root = Split-Path $PSScriptRoot -Parent
if (!$DeveloperCommand) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (!$installation) { throw 'Visual Studio C++ tools not found' }
    $DeveloperCommand = Join-Path $installation 'VC/Auxiliary/Build/vcvars64.bat'
}
if (!(Test-Path -LiteralPath $DeveloperCommand)) { throw 'Developer command not found' }
$work = Join-Path $root ('temp_optiscaler/menu-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$components = Join-Path $work 'components'
Expand-Archive -LiteralPath (Join-Path $root 'Output/RTX20-30-FP16-Transfusion-components.zip') -DestinationPath $components
$imgui = Join-Path $SourcePath 'OptiScaler/include/imgui'
$common = @(
    '/nologo','/std:c++latest','/EHsc','/MT','/O2','/utf-8','/DNOMINMAX','/UNDEBUG',
    ('/I"' + $SourcePath + '/OptiScaler"'),
    ('/I"' + $SourcePath + '/OptiScaler/include"'),
    ('/I"' + $SourcePath + '/external/freetype"')
)
$imguiSources = @('imgui.cpp','imgui_draw.cpp','imgui_widgets.cpp','imgui_tables.cpp','misc/freetype/imgui_freetype.cpp') | ForEach-Object { '"' + (Join-Path $imgui $_) + '"' }
$link = @('/link', ('"' + $SourcePath + '/external/freetype/freetype.lib"'), 'user32.lib','gdi32.lib','imm32.lib','shell32.lib','psapi.lib')
$results = @()
foreach ($test in @(
    @{Name='low-latency'; Source=(Join-Path $SourcePath 'tests/low_latency_selection_unit.cpp'); ImGui=$false},
    @{Name='viewport'; Source=(Join-Path $SourcePath 'tests/menu_viewport_unit.cpp'); ImGui=$true},
    @{Name='chinese-menu'; Source=(Join-Path $PSScriptRoot 'menu_ui_check.cpp'); ImGui=$true},
    @{Name='transfusion-menu'; Source=(Join-Path $PSScriptRoot 'transfusion_ui_check.cpp'); ImGui=$true}
)) {
    $testDir = Join-Path $work $test.Name
    New-Item -ItemType Directory -Path $testDir | Out-Null
    $exe = Join-Path $testDir ($test.Name + '.exe')
    $arguments = $common + @(('"' + $test.Source + '"'), ('/Fe:"' + $exe + '"'))
    if ($test.ImGui) { $arguments += $imguiSources + $link }
    $command = '@echo off' + "`r`ncall `"$DeveloperCommand`" >nul`r`nif errorlevel 1 exit /b 1`r`ncl " + ($arguments -join ' ') + "`r`nexit /b %errorlevel%`r`n"
    $cmdPath = Join-Path $testDir 'build.cmd'
    [IO.File]::WriteAllText($cmdPath, $command, [Text.Encoding]::ASCII)
    Push-Location $testDir
    try {
        & cmd.exe /d /c $cmdPath
        if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $($test.Name)" }
        if ($test.Name -eq 'chinese-menu') { & $exe (Join-Path $testDir 'preview.bmp') }
        elseif ($test.Name -eq 'transfusion-menu') {
            $config = Join-Path $testDir 'DLSSG-Transfusion.json'
            Copy-Item (Join-Path $components 'OptiScaler/plugins/DLSSG-Transfusion.json') $config
            & $exe $config
        } else { & $exe }
        if ($LASTEXITCODE -ne 0) { throw "Test failed: $($test.Name)" }
        $results += $test.Name
    } finally { Pop-Location }
}
@{SourceCommit=(& git -C $SourcePath rev-parse HEAD).Trim(); Passed=$results; GameRenderingTested=$false} |
    ConvertTo-Json | Set-Content (Join-Path $root 'Output/menu-validation.json') -Encoding UTF8
Write-Output "Passed: $($results -join ', ')"
