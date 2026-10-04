param(
    [string]$SourcePath = '',
    [string]$MSBuildPath = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (!$SourcePath) { $SourcePath = Join-Path $projectRoot 'temp_optiscaler\localized-source' }
$SourcePath = [IO.Path]::GetFullPath($SourcePath)
if (!$MSBuildPath) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $installation = & $vswhere -products '*' -latest -requires Microsoft.Component.MSBuild -property installationPath
        if ($installation) { $MSBuildPath = Join-Path $installation 'MSBuild\Current\Bin\MSBuild.exe' }
    }
}
if (!$MSBuildPath -or !(Test-Path -LiteralPath $MSBuildPath)) { throw 'Provide -MSBuildPath for Visual Studio 2022 MSBuild.exe' }
& (Join-Path $PSScriptRoot 'apply-menu-zh.ps1') -SourcePath $SourcePath
Push-Location $projectRoot
try {
    & $MSBuildPath (Join-Path $SourcePath 'OptiScaler.sln') /t:Build /p:Configuration=Release /p:Platform=x64 /p:PostBuildEventUseInBuild=false /m:4 /v:minimal /fl '/flp:logfile=temp_optiscaler\menu-build.log;verbosity=minimal'
    if ($LASTEXITCODE -ne 0) { throw 'Menu DLL build failed; inspect temp_optiscaler/menu-build.log' }
    $packagePath = Join-Path $projectRoot 'Output\OptiScaler-0.9.33-zh-CN'
    New-Item -ItemType Directory -Path $packagePath -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $SourcePath 'x64\Release\OptiScaler.dll') -Destination $packagePath -Force
    Copy-Item -LiteralPath (Join-Path $SourcePath 'LICENSE') -Destination (Join-Path $packagePath 'LICENSE-OptiScaler.txt') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'INSTALL.zh-CN.txt') -Destination $packagePath -Force
    $patchPath = Join-Path $packagePath 'SourcePatch'
    New-Item -ItemType Directory -Path $patchPath -Force | Out-Null
    Get-ChildItem -LiteralPath $PSScriptRoot -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $patchPath -Force
    }
    $manifest = [ordered]@{
        Backend = 'ShyVortex/OptiScaler-DLSSNR-PreSR-Multipass'
        Version = '0.9.33'
        BaseCommit = (& git -C $SourcePath rev-parse HEAD).Trim()
        Language = 'zh-CN'
        Architecture = 'x64'
        Scope = 'In-game menu presentation and Chinese font loading'
        Font = 'System Microsoft YaHei / SimHei / Arial Unicode (not redistributed)'
        Sha256 = (Get-FileHash -LiteralPath (Join-Path $packagePath 'OptiScaler.dll') -Algorithm SHA256).Hash
        TranslationSha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'menu.zh-CN.txt') -Algorithm SHA256).Hash
    }
    $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $packagePath 'manifest.json') -Encoding UTF8
    Compress-Archive -Path (Join-Path $packagePath '*') -DestinationPath (Join-Path $projectRoot 'Output\OptiScaler-0.9.33-zh-CN.zip') -Force
    Write-Output "Chinese menu DLL packaged at $packagePath"
} finally { Pop-Location }
