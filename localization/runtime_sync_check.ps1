param(
    [Parameter(Mandatory=$true)][string]$RuntimeSource,
    [Parameter(Mandatory=$true)][string]$LegacySource
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$work=Join-Path $root ('temp_optiscaler/runtime-sync-test-'+[guid]::NewGuid().ToString('N'))
$script=Join-Path $PSScriptRoot 'runtime-sync/runtime_sync.ps1'
$names=@('nvngx_dlssg.dll','sl.interposer.dll','sl.common.dll','sl.dlss.dll','sl.dlss_g.dll','sl.nis.dll','sl.reflex.dll','sl.pcl.dll')
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path).Hash}
function Assert($Condition,[string]$Message){if(!$Condition){throw $Message}}
function Fixture([string]$Name){
    $game=Join-Path $work $Name
    $bundle=Join-Path $game 'OptiScaler/streamline'
    $state=Join-Path $game 'OptiScaler/RuntimeSync'
    New-Item -ItemType Directory -Path $bundle,$state -Force | Out-Null
    $policy=[ordered]@{Schema=1;Profile='Test';Files=@($names|ForEach-Object {
        $source=Join-Path $RuntimeSource $_
        Copy-Item -LiteralPath $source -Destination $bundle
        if($_ -ne 'sl.pcl.dll'){Copy-Item -LiteralPath (Join-Path $LegacySource $_) -Destination $game}
        [ordered]@{Name=$_;Source="OptiScaler/streamline/$_";Sha256=(Hash $source);Version=(Get-Item $source).VersionInfo.FileVersion}
    })}
    $policy|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $state 'runtimes.json') -Encoding UTF8
    foreach($sentinel in @('nvngx_dlss.dll','nvngx_dlssd.dll','nvngx_dlssnr.dll')){
        Set-Content -LiteralPath (Join-Path $game $sentinel) -Value 'Preserve the game runtime' -Encoding ASCII
    }
    return $game
}
function InvokeMode([string]$Game,[string]$Mode,[int]$Expected=0){
    $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -InstallDir $Game -Mode $Mode 2>&1
    $code=$LASTEXITCODE
    $output|Out-File -LiteralPath (Join-Path $work 'test.log') -Append -Encoding UTF8
    Assert ($code -eq $Expected) "$Mode returned $code instead of $Expected : $output"
}
function Original([string]$Game){
    foreach($name in $names|Where-Object {$_ -ne 'sl.pcl.dll'}){
        Assert ((Hash (Join-Path $Game $name)) -eq (Hash (Join-Path $LegacySource $name))) "Original not preserved: $name"
    }
    Assert (!(Test-Path (Join-Path $Game 'sl.pcl.dll'))) 'Added PCL not removed'
    foreach($name in @('nvngx_dlss.dll','nvngx_dlssd.dll','nvngx_dlssnr.dll')){
        Assert ((Get-Content (Join-Path $Game $name)).Trim() -eq 'Preserve the game runtime') "SR/RR/NR changed: $name"
    }
}
function Synced([string]$Game){
    foreach($name in $names){Assert ((Hash (Join-Path $Game $name)) -eq (Hash (Join-Path $RuntimeSource $name))) "Not synced: $name"}
}
$game=Fixture 'basic'
InvokeMode $game 'Check' 10
Original $game
Assert (!(Test-Path (Join-Path $game 'OptiScaler/RuntimeSync/state'))) 'Check wrote state'
InvokeMode $game 'Sync'
Synced $game
$manifest=Join-Path $game 'OptiScaler/RuntimeSync/state/manifest.json'
$firstHash=Hash $manifest
$state=Get-Content $manifest -Raw|ConvertFrom-Json
Assert (@($state.Entries).Count -eq 8) 'Incorrect backup entry count'
foreach($entry in $state.Entries){
    if($entry.OriginalExists){Assert ((Hash $entry.Backup) -eq $entry.OriginalHash) 'Original backup mismatch'}
    else{Assert ([IO.Path]::GetFileName($entry.Target) -eq 'sl.pcl.dll') 'Unexpected newly added runtime'}
}
InvokeMode $game 'Sync'
Assert ((Hash $manifest) -eq $firstHash) 'Idempotent sync rewrote backup state'
InvokeMode $game 'Check'
InvokeMode $game 'Restore'
Original $game
InvokeMode $game 'Sync'
$custom=Join-Path $game 'nvngx_dlssg.dll'
Copy-Item (Join-Path $LegacySource 'nvngx_dlssg.dll') $custom -Force
$bytes=[IO.File]::ReadAllBytes($custom)
[IO.File]::WriteAllBytes($custom,($bytes+[byte]42))
$customHash=Hash $custom
InvokeMode $game 'Restore'
Assert ((Hash $custom) -eq $customHash) 'Restore overwrote a game update'
InvokeMode $game 'Sync'
Synced $game
InvokeMode $game 'Restore'
Assert ((Hash $custom) -eq $customHash) 'Repair failed to refresh original backup after a game update'
Write-Host 'PASS: check, signed sync, missing PCL, idempotence, restore and game-update preservation'

$game=Fixture 'unknown-streamline'
Set-Content (Join-Path $game 'sl.interposer.dll') 'unknown generation' -Encoding ASCII
$unknownHash=Hash (Join-Path $game 'sl.interposer.dll')
InvokeMode $game 'Sync'
Assert ((Hash (Join-Path $game 'sl.interposer.dll')) -eq $unknownHash) 'Unknown Streamline overwritten'
Assert ((Hash (Join-Path $game 'nvngx_dlssg.dll')) -eq (Hash (Join-Path $LegacySource 'nvngx_dlssg.dll'))) 'Unknown chain partially updated'
Assert (!(Test-Path (Join-Path $game 'sl.pcl.dll'))) 'Unknown chain received PCL'
Write-Host 'PASS: unknown Streamline chain preserved'

$game=Fixture 'streamline-1'
$old=Join-Path $game 'sl.interposer.dll'
$bytes=[IO.File]::ReadAllBytes($old)
$found=$false
for($i=0;$i -lt $bytes.Length-16;$i++){
    if([BitConverter]::ToUInt32($bytes,$i) -eq [uint32]4277077181){
        [Array]::Copy([BitConverter]::GetBytes([uint32]65536),0,$bytes,$i+8,4)
        $found=$true;break
    }
}
Assert $found 'Version resource signature missing'
[IO.File]::WriteAllBytes($old,$bytes)
Assert ((Get-Item $old).VersionInfo.FileMajorPart -eq 1) 'Synthetic Streamline 1 fixture invalid'
InvokeMode $game 'Sync'
Assert ((Get-Item $old).VersionInfo.FileMajorPart -eq 1) 'Streamline 1 replaced'
Assert (!(Test-Path (Join-Path $game 'sl.pcl.dll'))) 'Streamline 1 chain received PCL'
Write-Host 'PASS: Streamline 1 chain preserved'

$game=Fixture 'tampered-source'
Set-Content (Join-Path $game 'OptiScaler/streamline/sl.pcl.dll') 'tampered' -Encoding ASCII
InvokeMode $game 'Sync' 4
Original $game
Write-Host 'PASS: tampered source rejected before modifications'

$game=Fixture 'locked-target'
$locked=[IO.File]::Open((Join-Path $game 'sl.dlss_g.dll'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try{InvokeMode $game 'Sync' 4}finally{$locked.Dispose()}
Original $game
Write-Host 'PASS: failed write rolls back earlier replacements'

$game=Fixture 'ue-layout'
$render=Join-Path $game 'Project/Binaries/Win64'
$engine=Join-Path $game 'Engine/Plugins/Runtime/Nvidia/Streamline/Binaries/ThirdParty/Win64'
New-Item -ItemType Directory -Path $render,$engine -Force|Out-Null
Move-Item -LiteralPath (Join-Path $game 'OptiScaler') -Destination $render
foreach($name in $names|Where-Object {$_ -ne 'sl.pcl.dll'}){Move-Item -LiteralPath (Join-Path $game $name) -Destination $engine}
InvokeMode $render 'Sync'
foreach($name in $names){Assert ((Hash (Join-Path $engine $name)) -eq (Hash (Join-Path $RuntimeSource $name))) "UE runtime missed: $name"}
InvokeMode $render 'Restore'
foreach($name in $names|Where-Object {$_ -ne 'sl.pcl.dll'}){Assert ((Hash (Join-Path $engine $name)) -eq (Hash (Join-Path $LegacySource $name))) "UE restore failed: $name"}
Write-Host 'PASS: Unreal Engine sibling plugin directory discovery and restore'

$game=Fixture 'running-process'
$exe=Join-Path $game 'RuntimeSyncTest.exe'
Copy-Item "$env:SystemRoot/System32/cmd.exe" $exe
$process=Start-Process -FilePath $exe -ArgumentList '/c ping -n 30 127.0.0.1 > nul' -WindowStyle Hidden -PassThru
try{
    Start-Sleep -Milliseconds 500
    Assert (!$process.HasExited) 'Test process exited early'
    InvokeMode $game 'Sync' 4
    Original $game
    InvokeMode $game 'Restore' 4
    InvokeMode $game 'Check' 10
    Original $game
}finally{if(!$process.HasExited){Stop-Process -Id $process.Id -Force}}
Write-Host 'PASS: running game blocks writes, check remains read-only'
Write-Host "All runtime sync checks passed. Evidence: $work"
