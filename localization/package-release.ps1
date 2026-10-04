param(
    [Parameter(Mandatory = $true)][string]$UpstreamZip,
    [Parameter(Mandatory = $true)][string]$MenuPatchZip,
    [string]$Rtx2030BundleZip = '',
    [string]$ISCCPath = '',
    [string]$TagName = 'NR-v0.9.33-zh-CN'
)
$ErrorActionPreference = 'Stop'
if ($TagName -notmatch '^NR-v0\.9\.33-(?:RTX20-30-FP16-)?zh-CN(?:\.[0-9]+)?$') { throw 'Unsupported release tag' }
$isRtx2030 = $TagName -match '-RTX20-30-FP16-'
if ($isRtx2030 -ne [bool]$Rtx2030BundleZip) { throw 'The RTX 20/30 release requires its matching component bundle' }
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
$patchDictionary = Join-Path $patch 'SourcePatch\menu.zh-CN.txt'
if ((Get-FileHash -LiteralPath $patchDictionary).Hash -ne $manifest.TranslationSha256) { throw 'Packaged translation source SHA256 mismatch' }
$patchText = (Get-Content -LiteralPath $patchDictionary -Raw -Encoding UTF8).Replace("`r`n", "`n")
$repoText = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'menu.zh-CN.txt') -Raw -Encoding UTF8).Replace("`r`n", "`n")
if (![string]::Equals($patchText, $repoText, [StringComparison]::Ordinal)) { throw 'Repository translation differs from the validated menu build' }
if (!(Test-Path -LiteralPath (Join-Path $payload 'dxgi.dll'))) { throw 'Upstream proxy DLL is missing' }
$before = @{}
Get-ChildItem -LiteralPath $payload -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($payload.Length + 1)
    $before[$relative] = (Get-FileHash -LiteralPath $_.FullName).Hash
}
Copy-Item -LiteralPath $menuDll -Destination (Join-Path $payload 'dxgi.dll') -Force
$expectedFiles = @{} + $before
$expectedFiles['dxgi.dll'] = $manifest.Sha256
if ($isRtx2030) {
    if ($manifest.TransfusionCommit -ne 'b56bd2deed114507ad2c88f986d90ed50ffb4639') { throw 'Missing integrated Transfusion panel' }
    $translation = Join-Path $patch 'SourcePatch/transfusion/menu.zh-CN.txt'
    if ((Get-FileHash $translation).Hash -ne $manifest.TransfusionTranslationSha256) { throw 'Transfusion translation hash mismatch' }
    $extraText = (Get-Content $translation -Raw -Encoding UTF8).Replace("`r`n","`n")
    $repoExtra = (Get-Content (Join-Path $PSScriptRoot 'transfusion/menu.zh-CN.txt') -Raw -Encoding UTF8).Replace("`r`n","`n")
    if ($extraText -cne $repoExtra) { throw 'Transfusion translation differs from the validated menu build' }
    $components = Join-Path $work 'components'
    Expand-Archive -LiteralPath ([IO.Path]::GetFullPath($Rtx2030BundleZip)) -DestinationPath $components
    $componentManifest = Get-Content (Join-Path $components 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($componentManifest.Profile -ne 'RTX20-30-FP16-Transfusion' -or $componentManifest.TransfusionCommit -ne 'b56bd2deed114507ad2c88f986d90ed50ffb4639') { throw 'Unexpected component provenance' }
    foreach ($property in $componentManifest.Files.PSObject.Properties) {
        $relative = $property.Name.Replace('/', '\')
        $sourceFile = [IO.Path]::GetFullPath((Join-Path $components $relative))
        if (!$sourceFile.StartsWith($components + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid component path' }
        if ((Get-FileHash $sourceFile).Hash -ne $property.Value) { throw "Component hash mismatch: $relative" }
        $target = Join-Path $payload $relative
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        Copy-Item $sourceFile $target -Force
        $expectedFiles[$relative] = $property.Value
    }
    $fp16Hash = '6DAC1B40F0C87AF84A8177B18C741E84FB0C914F204C9D87D95916B665BA3AF8'
    if ($expectedFiles['nvngx_dlssnr.dll'] -ne $fp16Hash) { throw 'FP16 runtime mismatch' }
    if ($expectedFiles['OptiScaler\plugins\DLSSG-Transfusion.asi'] -ne '1EE608B923F94B9DFEB01D6CEDF7F7BB561E281F8BD92DB6549745493BA5771D') { throw 'Official optimized core mismatch' }
    Copy-Item (Join-Path $components 'nvngx_dlssnr.dll') (Join-Path $payload 'OptiScaler/streamline/nvngx_dlssnr.dll') -Force
    $expectedFiles['OptiScaler\streamline\nvngx_dlssnr.dll'] = $fp16Hash
    # Remove only known legacy runtimes from the fresh build staging directory.
    foreach ($relative in @($before.Keys)) {
        if ($relative -like 'OptiScaler\dlssg_sm86\*' -or $relative -eq 'OptiScaler\nvsmooth30.dll') {
            Remove-Item -LiteralPath (Join-Path $payload $relative) -Force
            $expectedFiles.Remove($relative)
        }
    }
    foreach ($pair in @(
        @('manifest.json','Licenses/RTX20-30-FP16-manifest.json'),
        @('SOURCE-PATCH','Licenses/OptiScaler-Transfusion-SourcePatch.zip')
    )) {
        $target = Join-Path $payload $pair[1]
        if ($pair[0] -eq 'SOURCE-PATCH') { Compress-Archive -Path (Join-Path $patch 'SourcePatch/*') -DestinationPath $target }
        else { Copy-Item (Join-Path $components $pair[0]) $target }
        $expectedFiles[$pair[1].Replace('/','\')] = (Get-FileHash $target).Hash
    }
    $installGuide = 'INSTALL-RTX20-30.zh-CN.txt'
    Copy-Item (Join-Path $PSScriptRoot $installGuide) (Join-Path $payload $installGuide)
    $expectedFiles[$installGuide] = (Get-FileHash (Join-Path $payload $installGuide)).Hash
    $iniPath = Join-Path $payload 'OptiScaler.ini'
    $ini = Get-Content $iniPath -Raw -Encoding UTF8
    foreach ($pair in @(@('AmpereMfgUnlock','false'), @('AdaMfgUnlock','false'), @('SmoothMotion','false'), @('External','true'), @('LoadAsiPlugins','true'))) {
        if ($ini -notmatch ('(?m)^'+$pair[0]+'=.*$')) { throw "INI key missing: $($pair[0])" }
        $ini = [regex]::Replace($ini,'(?m)^'+$pair[0]+'=[^\r\n]*',$pair[0]+'='+$pair[1])
    }
    $ini += "`r`n[SmoothMotion]`r`nEnableNVSmooth30=false`r`n"
    [IO.File]::WriteAllText($iniPath, $ini, [Text.UTF8Encoding]::new($false))
    $expectedFiles['OptiScaler.ini'] = (Get-FileHash $iniPath).Hash
}
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
        if (!$expectedFiles.ContainsKey($relative)) { throw "Unexpected archive entry: $relative" }
        $expected = $expectedFiles[$relative]
        $stream = $entry.Open()
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '') }
        finally { $sha.Dispose(); $stream.Dispose() }
        if ($actual -ne $expected) { throw "Packaged file SHA256 mismatch: $relative" }
        $checked++
    }
} finally { $archive.Dispose() }
if ($checked -ne $expectedFiles.Count) { throw 'The standalone archive is missing required files' }
if ($isRtx2030) { Write-Output "Verified $checked packaged files, supplied FP16 runtimes, official optimized Transfusion ASI and integrated panel and Chinese menu. Other upstream files are unchanged." }
else { Write-Output "Verified $checked packaged files; only dxgi.dll changed." }

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
    if ($isRtx2030) { $template = $template.Replace('AmpereMfgUnlock=true','AmpereMfgUnlock=false') }
    $installerScript = Join-Path $work 'DLSS unlocked zh-CN.iss'
    [IO.File]::WriteAllText($installerScript, $template, [Text.UTF8Encoding]::new($true))
    & $ISCCPath "/O$output" "/Fdlss-unlocked-setup-$TagName" $installerScript
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed' }
    $installer = Join-Path $output "dlss-unlocked-setup-$TagName.exe"
    if (!(Test-Path -LiteralPath $installer)) { throw 'Installer output is missing' }
    Get-FileHash -LiteralPath $installer
}
Get-FileHash -LiteralPath $zipPath
