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
    $components = Join-Path $work 'components'
    Expand-Archive -LiteralPath ([IO.Path]::GetFullPath($Rtx2030BundleZip)) -DestinationPath $components
    $componentManifest = Get-Content -LiteralPath (Join-Path $components 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($componentManifest.Profile -ne 'RTX20-30-FP16' -or $componentManifest.DlssgCommit -ne '329b4c85927c64a8dba2e25125e6d02a42ab63fe') { throw 'Unexpected RTX 20/30 component provenance' }
    $fp16Hash = '6DAC1B40F0C87AF84A8177B18C741E84FB0C914F204C9D87D95916B665BA3AF8'
    $dlssgHash = '7489A89BF593CDA243D95C62E6D8B75905D9774E27B7B2D53B91625A79C05CA4'
    if ((Get-FileHash -LiteralPath (Join-Path $components 'nvngx_dlssnr.dll')).Hash -ne $fp16Hash) { throw 'Supplied FP16 runtime SHA256 mismatch' }
    if ((Get-FileHash -LiteralPath (Join-Path $components 'dlssg_sm86\dlssg_sm86.dll')).Hash -ne $dlssgHash) { throw 'Supplied DLSSG runtime SHA256 mismatch' }
    foreach ($property in $componentManifest.Files.PSObject.Properties) {
        $relative = $property.Name.Replace('/', '\')
        $sourceFile = [IO.Path]::GetFullPath((Join-Path $components $relative))
        if (!$sourceFile.StartsWith($components + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid component path' }
        if ((Get-FileHash -LiteralPath $sourceFile).Hash -ne $property.Value) { throw "Component SHA256 mismatch: $relative" }
    }
    foreach ($relative in @('nvngx_dlssnr.dll', 'OptiScaler\streamline\nvngx_dlssnr.dll')) {
        Copy-Item -LiteralPath (Join-Path $components 'nvngx_dlssnr.dll') -Destination (Join-Path $payload $relative) -Force
        $expectedFiles[$relative] = $fp16Hash
    }
    $moduleSource = Join-Path $components 'dlssg_sm86'
    Get-ChildItem -LiteralPath $moduleSource -File -Force | ForEach-Object {
        $relative = 'OptiScaler\dlssg_sm86\' + $_.Name
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $payload $relative) -Force
        $expectedFiles[$relative] = (Get-FileHash -LiteralPath $_.FullName).Hash
    }
    $checksums = Join-Path $payload 'OptiScaler\dlssg_sm86\checksums.sha256'
    $hashLines = Get-ChildItem -LiteralPath $moduleSource -File -Force | Sort-Object Name | ForEach-Object { ((Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()) + '  ' + $_.Name }
    [IO.File]::WriteAllText($checksums, ($hashLines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
    $expectedFiles['OptiScaler\dlssg_sm86\checksums.sha256'] = (Get-FileHash -LiteralPath $checksums).Hash
    $notices = 'Licenses\dlssg_sm86_THIRD_PARTY_NOTICES.txt'
    Copy-Item -LiteralPath (Join-Path $moduleSource 'THIRD_PARTY_NOTICES.txt') -Destination (Join-Path $payload $notices) -Force
    $expectedFiles[$notices] = (Get-FileHash -LiteralPath (Join-Path $payload $notices)).Hash
    $profileManifest = 'Licenses\RTX20-30-FP16-manifest.json'
    Copy-Item -LiteralPath (Join-Path $components 'manifest.json') -Destination (Join-Path $payload $profileManifest) -Force
    $expectedFiles[$profileManifest] = (Get-FileHash -LiteralPath (Join-Path $payload $profileManifest)).Hash
    $installGuide = 'INSTALL-RTX20-30.zh-CN.txt'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $installGuide) -Destination (Join-Path $payload $installGuide) -Force
    $expectedFiles[$installGuide] = (Get-FileHash -LiteralPath (Join-Path $payload $installGuide)).Hash

    # Both specialized packages start with the same single NVIDIA FG provider.
    $ini = Get-Content -LiteralPath (Join-Path $payload 'OptiScaler.ini') -Raw -Encoding UTF8
    foreach ($key in @('External=true', 'AmpereMfgUnlock=true', 'AdaMfgUnlock=false')) {
        if ($ini -notmatch ('(?m)^' + [regex]::Escape($key) + '\r?$')) { throw "Required RTX 20/30 default is missing: $key" }
    }
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
if ($isRtx2030) { Write-Output "Verified $checked packaged files, supplied FP16 runtimes, supplied DLSSG module and Chinese menu. Other upstream files are unchanged." }
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
    $installerScript = Join-Path $work 'DLSS unlocked zh-CN.iss'
    [IO.File]::WriteAllText($installerScript, $template, [Text.UTF8Encoding]::new($true))
    & $ISCCPath "/O$output" "/Fdlss-unlocked-setup-$TagName" $installerScript
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed' }
    $installer = Join-Path $output "dlss-unlocked-setup-$TagName.exe"
    if (!(Test-Path -LiteralPath $installer)) { throw 'Installer output is missing' }
    Get-FileHash -LiteralPath $installer
}
Get-FileHash -LiteralPath $zipPath
