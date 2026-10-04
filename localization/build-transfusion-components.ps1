param([string]$Archive='temp_optiscaler/transfusion-input/DLSSG-Transfusion-v1.4.5.3-rtx20-30-40.zip', [string]$Fp16='temp_optiscaler/rtx20-30-input/fp16/nvngx_dlssnr.dll', [ValidateSet('RTX20-30-FP16','RTX40')][string]$Profile='RTX20-30-FP16', [string]$SfV2Archive='temp_optiscaler/rhi-nr-compare/nvngx_dlssnr_310.8.SF-v2.zip')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if((Get-FileHash $Archive).Hash -ne 'A4337D56E7D9545A8C7636845481D4199047D599C35E74A167AEEBF2D7A1F3D1'){throw 'Author release hash mismatch'}
if($Profile -eq 'RTX20-30-FP16' -and (Get-FileHash $Fp16).Hash -ne '6DAC1B40F0C87AF84A8177B18C741E84FB0C914F204C9D87D95916B665BA3AF8'){throw 'FP16 hash mismatch'}
$sfV2ArchiveHash='1DA35941894994EB087E017577829E492454E9BAE3A6A9397027069CEB74955C'
$sfV2DllHash='6EB209E764F39872625DEBD6ABAF45E2BB6322F6F270F781F70C059AE30B3927'
if($Profile -eq 'RTX40' -and (Get-FileHash $SfV2Archive).Hash -ne $sfV2ArchiveHash){throw 'SF-v2 archive hash mismatch'}
$work=Join-Path $root ('temp_optiscaler/transfusion-components-'+[guid]::NewGuid().ToString('N'))
$author=Join-Path $work 'author';$bundle=Join-Path $work 'bundle'
Expand-Archive $Archive $author
$plugin=Join-Path $bundle 'OptiScaler/plugins';$license=Join-Path $bundle 'Licenses/Transfusion'
New-Item -ItemType Directory -Path $plugin,$license -Force | Out-Null
Copy-Item (Join-Path $author 'alternative-proxies/DLSSG-Transfusion.asi') $plugin
Copy-Item (Join-Path $author 'DLSSG-Transfusion.json') $plugin
foreach($name in @('LICENSE','README.md','INJECTION.md','CHANGELOG.md')){Copy-Item (Join-Path $author $name) $license}
if($Profile -eq 'RTX20-30-FP16'){Copy-Item $Fp16 (Join-Path $bundle 'nvngx_dlssnr.dll')}
if($Profile -eq 'RTX40'){
    $nrSource=Join-Path $work 'nr-sfv2'
    Expand-Archive -LiteralPath $SfV2Archive -DestinationPath $nrSource
    $nrDll=Join-Path $nrSource 'nvngx_dlssnr.dll'
    $nrVersion=(Get-Item $nrDll).VersionInfo
    if((Get-FileHash $nrDll).Hash -ne $sfV2DllHash -or $nrVersion.FileBuildPart -ne 2){throw 'SF-v2 runtime mismatch'}
    Copy-Item -LiteralPath $nrDll -Destination (Join-Path $bundle 'nvngx_dlssnr.dll')
}
$files=[ordered]@{}
Get-ChildItem $bundle -Recurse -File | Sort-Object FullName | ForEach-Object { $files[$_.FullName.Substring($bundle.Length+1).Replace('\','/')]=(Get-FileHash $_.FullName).Hash }
$manifest=[ordered]@{Profile="$Profile-Transfusion";TransfusionVersion='v1.4.5.3-rtx20-30-40';TransfusionCommit='b56bd2deed114507ad2c88f986d90ed50ffb4639';AuthorArchiveSha256=(Get-FileHash $Archive).Hash;Core='Official optimized ASI, unchanged';Files=$files}
if($Profile -eq 'RTX40'){
    $manifest['NrRuntime']=[ordered]@{Variant='ShortFuse SF-v2';Version='310.8.2.0';SourceUrl='https://github.com/RankFTW/rhi-repo/releases/download/dlssnr-310.8.SF-v2/nvngx_dlssnr_310.8.SF-v2.zip';ArchiveSha256=$sfV2ArchiveHash;DllSha256=$sfV2DllHash}
}
$manifest|ConvertTo-Json -Depth 4|Set-Content (Join-Path $bundle 'manifest.json') -Encoding UTF8
Compress-Archive (Join-Path $bundle '*') (Join-Path $root "Output/$Profile-Transfusion-components.zip") -Force
Get-FileHash (Join-Path $root "Output/$Profile-Transfusion-components.zip")
