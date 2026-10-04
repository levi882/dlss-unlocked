param([string]$Archive='temp_optiscaler/transfusion-input/DLSSG-Transfusion-v1.4.5.3-rtx20-30-40.zip', [string]$Fp16='temp_optiscaler/rtx20-30-input/fp16/nvngx_dlssnr.dll')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if((Get-FileHash $Archive).Hash -ne 'A4337D56E7D9545A8C7636845481D4199047D599C35E74A167AEEBF2D7A1F3D1'){throw 'Author release hash mismatch'}
if((Get-FileHash $Fp16).Hash -ne '6DAC1B40F0C87AF84A8177B18C741E84FB0C914F204C9D87D95916B665BA3AF8'){throw 'FP16 hash mismatch'}
$work=Join-Path $root ('temp_optiscaler/transfusion-components-'+[guid]::NewGuid().ToString('N'))
$author=Join-Path $work 'author';$bundle=Join-Path $work 'bundle'
Expand-Archive $Archive $author
$plugin=Join-Path $bundle 'OptiScaler/plugins';$license=Join-Path $bundle 'Licenses/Transfusion'
New-Item -ItemType Directory -Path $plugin,$license -Force | Out-Null
Copy-Item (Join-Path $author 'alternative-proxies/DLSSG-Transfusion.asi') $plugin
Copy-Item (Join-Path $author 'DLSSG-Transfusion.json') $plugin
foreach($name in @('LICENSE','README.md','INJECTION.md','CHANGELOG.md')){Copy-Item (Join-Path $author $name) $license}
Copy-Item $Fp16 (Join-Path $bundle 'nvngx_dlssnr.dll')
$files=[ordered]@{}
Get-ChildItem $bundle -Recurse -File | Sort-Object FullName | ForEach-Object { $files[$_.FullName.Substring($bundle.Length+1).Replace('\','/')]=(Get-FileHash $_.FullName).Hash }
$manifest=[ordered]@{Profile='RTX20-30-FP16-Transfusion';TransfusionVersion='v1.4.5.3-rtx20-30-40';TransfusionCommit='b56bd2deed114507ad2c88f986d90ed50ffb4639';AuthorArchiveSha256=(Get-FileHash $Archive).Hash;Core='Official optimized ASI, unchanged';Files=$files}
$manifest|ConvertTo-Json -Depth 4|Set-Content (Join-Path $bundle 'manifest.json') -Encoding UTF8
Compress-Archive (Join-Path $bundle '*') (Join-Path $root 'Output/RTX20-30-FP16-Transfusion-components.zip') -Force
Get-FileHash (Join-Path $root 'Output/RTX20-30-FP16-Transfusion-components.zip')
