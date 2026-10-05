param([Parameter(Mandatory=$true)][string]$TagName)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$work = Join-Path $root ('temp_optiscaler/installer-check-' + [guid]::NewGuid().ToString('N'))
$archive = Join-Path $work 'archive'
$install = Join-Path $work 'installed'
Expand-Archive -LiteralPath (Join-Path $root "Output/dlss-unlocked-standalone-$TagName.zip") -DestinationPath $archive
New-Item -ItemType Directory -Path $install | Out-Null
function Assert($Condition, [string]$Message) { if (!$Condition) { throw $Message } }
$process = Start-Process -FilePath (Join-Path $root "Output/dlss-unlocked-setup-$TagName.exe") -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/DIR=`"$install`"",'/COMPONENTS=mainfiles/dlldxgi,core,streamline,optional/regentries,optional/fgdebug',"/LOG=`"$work/install.log`"") -WindowStyle Hidden -Wait -PassThru
Assert ($process.ExitCode -eq 0) "Installer exited $($process.ExitCode)"
$checked = 0
foreach ($file in Get-ChildItem $archive -Recurse -File) {
    $relative = $file.FullName.Substring($archive.Length + 1)
    if ($relative -eq 'OptiScaler.ini') { continue } # Existing wizard rewrites settings.
    $target = Join-Path $install $relative
    Assert (Test-Path -LiteralPath $target) "Installer file missing: $relative"
    Assert ((Get-FileHash $target).Hash -eq (Get-FileHash $file.FullName).Hash) "Installer hash mismatch: $relative"
    $checked++
}
$ini = Get-Content (Join-Path $install 'OptiScaler.ini') -Raw
foreach ($setting in @('AmpereMfgUnlock=false','AdaMfgUnlock=false','External=true','LoadAsiPlugins=true')) {
    Assert ($ini.Contains($setting)) "Installer setting missing: $setting"
}
$policy = Get-Content (Join-Path $install 'OptiScaler/RuntimeSync/runtimes.json') -Raw | ConvertFrom-Json
foreach ($file in $policy.Files) {
    Assert ((Get-FileHash (Join-Path $install $file.Name)).Hash -eq $file.Sha256) "Automatic runtime sync failed: $($file.Name)"
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $install 'runtime_sync.ps1') -InstallDir $install -Mode Check
Assert ($LASTEXITCODE -eq 0) 'Installed runtime check failed'
$process = Start-Process -FilePath (Join-Path $install 'unins000.exe') -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -WindowStyle Hidden -Wait -PassThru
Assert ($process.ExitCode -eq 0) 'Uninstaller failed'
foreach ($file in $policy.Files) { Assert (!(Test-Path (Join-Path $install $file.Name))) "Uninstall did not restore original absence: $($file.Name)" }
@{Tag=$TagName;InstallerFilesMatched=$checked;AutomaticSync=$true;UninstallRestore=$true;GameRenderingTested=$false} |
    ConvertTo-Json | Set-Content (Join-Path $root "Output/$TagName-installer-validation.json") -Encoding UTF8
Write-Output "Verified $checked installer files, automatic runtime sync, and uninstall restoration."
