param(
    [Parameter(Mandatory = $true)][string]$UpstreamZip,
    [Parameter(Mandatory = $true)][string]$MenuPatchZip,
    [string]$ISCCPath = '',
    [string]$TagName = 'NR-v0.9.33-zh-CN'
)
$ErrorActionPreference = 'Stop'
if ($TagName -notmatch '^NR-v0\.9\.33-zh-CN(?:\.[0-9]+)?$') { throw 'Unsupported release tag' }
$projectRoot = Split-Path $PSScriptRoot -Parent
$UpstreamZip = [IO.Path]::GetFullPath($UpstreamZip)
$MenuPatchZip = [IO.Path]::GetFullPath($MenuPatchZip)
$baselineHash = 'E2DAD29EBFCA2DCF9094FAFB25692EC2CEE1E822DCAAD6949051971FE58CFC7E'
if ((Get-FileHash -LiteralPath $UpstreamZip).Hash -ne $baselineHash) { throw 'Upstream archive SHA256 mismatch' }
$work = Join-Path $projectRoot ('temp_optiscaler\release-' + [guid]::NewGuid().ToString('N'))
$payload = Join-Path $work 'payload'
$patch = Join-Path $work 'patch'
New-Item -ItemType Directory -Path $payload, $patch -Force | Out-Null
Expand-Archive -LiteralPath $UpstreamZip -DestinationPath $payload
Expand-Archive -LiteralPath $MenuPatchZip -DestinationPath $patch
$manifest = Get-Content -LiteralPath (Join-Path $patch 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$menuDll = Join-Path $patch 'OptiScaler.dll'
if ($manifest.Version -ne '0.9.33' -or $manifest.BaseCommit -ne '8bfff2724e0287891d3c636cfede12cb4eca876b') { throw 'Unexpected menu build provenance' }
if ((Get-FileHash -LiteralPath $menuDll).Hash -ne $manifest.Sha256) { throw 'Chinese menu DLL SHA256 mismatch' }
if ((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'menu.zh-CN.txt')).Hash -ne $manifest.TranslationSha256) { throw 'Translation source SHA256 mismatch' }
if (!(Test-Path -LiteralPath (Join-Path $payload 'dxgi.dll'))) { throw 'Upstream proxy DLL is missing' }
$before = @{}
Get-ChildItem -LiteralPath $payload -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($payload.Length + 1)
    $before[$relative] = (Get-FileHash -LiteralPath $_.FullName).Hash
}
Copy-Item -LiteralPath $menuDll -Destination (Join-Path $payload 'dxgi.dll') -Force
$output = Join-Path $projectRoot 'Output'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$zipPath = Join-Path $output "dlss-unlocked-standalone-$TagName.zip"
Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $zipPath -Force

# Read every packaged entry back, preserving upstream companions and configuration.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
$checked = 0
try {
    foreach ($entry in $archive.Entries) {
        if (!$entry.Name) { continue }
        $relative = $entry.FullName.Replace('/', '\')
        if (!$before.ContainsKey($relative)) { throw "Unexpected archive entry: $relative" }
        $expected = if ($relative -eq 'dxgi.dll') { $manifest.Sha256 } else { $before[$relative] }
        $stream = $entry.Open()
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '') }
        finally { $sha.Dispose(); $stream.Dispose() }
        if ($actual -ne $expected) { throw "Packaged file SHA256 mismatch: $relative" }
        $checked++
    }
} finally { $archive.Dispose() }
if ($checked -ne $before.Count) { throw 'The standalone archive is missing upstream files' }
Write-Output "Verified $checked packaged files; only dxgi.dll changed."

if ($ISCCPath) {
    # Retain the upstream wizard, proxy choices and configuration code. Package
    # every standalone companion, including plugins, with its existing layout.
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($choice in @(
        @{ Dest = '{app}'; Name = 'dxgi.dll'; Component = 'mainfiles/dlldxgi' },
        @{ Dest = '{app}'; Name = 'version.dll'; Component = 'mainfiles/dllversion' },
        @{ Dest = '{app}'; Name = 'winmm.dll'; Component = 'mainfiles/dllwinmm' },
        @{ Dest = '{app}\plugins'; Name = 'dlss-unlocked.asi'; Component = 'mainfiles/asiversion' }
    )) {
        $lines.Add(('Source: "{0}"; DestDir: "{1}"; DestName: "{2}"; Flags: ignoreversion overwritereadonly; Components: {3}' -f (Join-Path $payload 'dxgi.dll'), $choice.Dest, $choice.Name, $choice.Component))
    }
    Get-ChildItem -LiteralPath $payload -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($payload.Length + 1)
        if ($relative -eq 'dxgi.dll') { return }
        $parent = Split-Path $relative -Parent
        $dest = if ($parent) { '{app}\' + $parent } else { '{app}' }
        $component = if ($relative -like 'OptiScaler\streamline\*') { 'streamline' }
                     elseif ($relative -eq 'OptiScaler\dlssg_to_fsr3.ini') { 'optional/fgdebug' }
                     else { 'core' }
        $lines.Add(('Source: "{0}"; DestDir: "{1}"; Flags: ignoreversion overwritereadonly; Components: {2}' -f $_.FullName, $dest, $component))
    }
    $template = Get-Content -LiteralPath (Join-Path $projectRoot 'DLSS unlocked.iss') -Raw -Encoding UTF8
    $fileBlock = "[Files]`r`n" + ($lines -join "`r`n") + "`r`n`r`n"
    $template = [regex]::Replace($template, '(?ms)^\[Files\].*?(?=^\[InstallDelete\])', [Text.RegularExpressions.MatchEvaluator]{ param($m) $fileBlock })
    $template = $template.Replace('#define MyAppVersion "1.0.0.0"', '#define MyAppVersion "0.9.33"')
    $template = $template.Replace('LicenseFile=DLSS for NVIDIA - License.rtf', 'LicenseFile=' + (Join-Path $projectRoot 'DLSS for NVIDIA - License.rtf'))
    $template = $template.Replace('InfoBeforeFile=DLSS Unlocked Intro.rtf', 'InfoBeforeFile=' + (Join-Path $projectRoot 'DLSS Unlocked Intro.rtf'))
    $installerScript = Join-Path $work 'DLSS unlocked zh-CN.iss'
    [IO.File]::WriteAllText($installerScript, $template, [Text.UTF8Encoding]::new($true))
    & $ISCCPath "/O$output" "/Fdlss-unlocked-setup-$TagName" $installerScript
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed' }
    $installer = Join-Path $output "dlss-unlocked-setup-$TagName.exe"
    if (!(Test-Path -LiteralPath $installer)) { throw 'Installer output is missing' }
    Get-FileHash -LiteralPath $installer
}
Get-FileHash -LiteralPath $zipPath
