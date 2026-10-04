# SPDX-License-Identifier: GPL-3.0-or-later
# Game-owned frame-generation runtime sync. Backup/restore design inspired by OptiScaler Aurora.
param(
    [ValidateSet('Check','Sync','Restore')][string]$Mode='Check',
    [string]$InstallDir=$PSScriptRoot,
    [string]$LogPath=''
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$allowed=@('nvngx_dlssg.dll','sl.interposer.dll','sl.common.dll','sl.dlss.dll','sl.dlss_g.dll','sl.nis.dll','sl.reflex.dll','sl.pcl.dll')
function HashFile([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function FullPath([string]$Path){return [IO.Path]::GetFullPath($Path).TrimEnd('\')}
function Within([string]$Path,[string]$Root){return (FullPath $Path).StartsWith((FullPath $Root)+'\',[StringComparison]::OrdinalIgnoreCase)}
function Say([string]$Text){Write-Host $Text}
function SaveJson($Value,[string]$Path){
    $temporary=$Path+'.tmp'
    [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 9),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}
function SlMajor([string]$Path){
    $version=(Get-Item -LiteralPath $Path).VersionInfo
    if($version.FileMajorPart -in @(1,2)){return $version.FileMajorPart}
    return 0
}
function FindTargets([string]$Root){
    $queue=[Collections.Generic.Queue[object]]::new()
    $queue.Enqueue(@{Path=$Root;Depth=0})
    $found=[Collections.Generic.List[string]]::new()
    $deadline=[DateTime]::UtcNow.AddSeconds(12);$visited=0
    $skip=@('OptiScaler','Content','Paks','Saved','Movies','Audio','Sounds','Textures','ShaderCache','DerivedDataCache','_CommonRedist')
    while($queue.Count){
        if(++$visited -gt 7000 -or [DateTime]::UtcNow -gt $deadline){throw '扫描范围过大，未修改文件。请将工具放在游戏渲染 EXE 目录。'}
        $item=$queue.Dequeue()
        foreach($child in @(Get-ChildItem -LiteralPath $item.Path -Force -ErrorAction SilentlyContinue)){
            if($child.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
            if($child.PSIsContainer){
                if($item.Depth -lt 9 -and $child.Name -notin $skip -and !$child.Name.StartsWith('.')){
                    $queue.Enqueue(@{Path=$child.FullName;Depth=$item.Depth+1})
                }
            }elseif($child.Name -in $allowed){$found.Add($child.FullName)}
        }
    }
    return @($found | Sort-Object -Unique)
}
function GameRunning([string]$Root){
    foreach($process in @(Get-Process)){
        try{$path=$process.Path}catch{continue}
        if($path -and (Within $path $Root)){return $true}
    }
    return $false
}
function ValidateEntry($Entry){
    if(!$Entry.Target -or [IO.Path]::GetFileName($Entry.Target) -notin $allowed -or
       !(Within $Entry.Target $scanRoot) -or (Within $Entry.Target $optiDir)){
        throw '恢复记录含有无效目标，未修改文件。'
    }
    if($Entry.OriginalExists -and (!(Within $Entry.Backup $stateDir) -or !(Test-Path -LiteralPath $Entry.Backup -PathType Leaf))){
        throw '恢复备份丢失或路径无效，未修改文件。'
    }
}
function Main {
    $script:installRoot=FullPath $InstallDir
    $script:optiDir=Join-Path $installRoot 'OptiScaler'
    if(!(Test-Path -LiteralPath $optiDir -PathType Container)){throw '请将工具放在含有 OptiScaler 文件夹的游戏目录。'}
    if([IO.Path]::GetPathRoot($installRoot).TrimEnd('\') -eq $installRoot -or
       (Split-Path $installRoot -Leaf) -in @('common','steamapps','SteamLibrary')){throw '请选择单个游戏目录。'}
    $script:scanRoot=$installRoot
    $cursor=[IO.DirectoryInfo]::new($installRoot)
    for($i=0;$i -lt 6 -and $cursor;$i++){
        if(Test-Path -LiteralPath (Join-Path $cursor.FullName 'Engine') -PathType Container){$script:scanRoot=$cursor.FullName;break}
        if(!$cursor.Parent -or $cursor.Parent.Name -in @('common','steamapps','SteamLibrary')){break}
        $cursor=$cursor.Parent
    }
    $script:stateDir=Join-Path $optiDir 'RuntimeSync\state'
    $statePath=Join-Path $stateDir 'manifest.json'
    if($LogPath){
        $safeLog=FullPath $LogPath
        if(!(Within $safeLog (Join-Path $optiDir 'RuntimeSync'))){throw '日志路径无效。'}
        New-Item -ItemType Directory -Path (Split-Path $safeLog -Parent) -Force | Out-Null
        Start-Transcript -LiteralPath $safeLog -Force | Out-Null
        $script:transcript=$true
    }
    Say 'DLSS Unlocked 帧生成运行库工具'
    Say "游戏目录：$installRoot"
    $running=GameRunning $scanRoot
    if($running -and $Mode -ne 'Check'){throw '请先完全退出游戏，再同步或恢复运行库。'}
    $entries=@()
    if(Test-Path -LiteralPath $statePath){
        $state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if($state.Schema -ne 1 -or $state.InstallDir -ne $installRoot -or $state.ScanRoot -ne $scanRoot){throw '恢复记录与当前游戏目录不符。'}
        $entries=@($state.Entries)
        foreach($entry in $entries){ValidateEntry $entry}
    }
    if($Mode -eq 'Restore'){
        if(!$entries.Count){Say '没有需要恢复的运行库。';return 0}
        $restored=0;$kept=0
        # Validate every usable backup before the first target is changed.
        foreach($entry in $entries){
            if($entry.OriginalExists -and (HashFile $entry.Backup) -ne $entry.OriginalHash){throw '备份校验失败，未修改文件。'}
        }
        foreach($entry in $entries){
            if(!(Test-Path -LiteralPath $entry.Target -PathType Leaf)){$kept++;continue}
            if((HashFile $entry.Target) -ne $entry.DeployedHash){Say "保留已由游戏或其他工具修改的文件：$($entry.Target)";$kept++;continue}
            if($entry.OriginalExists){
                Copy-Item -LiteralPath $entry.Backup -Destination $entry.Target -Force
                if((HashFile $entry.Target) -ne $entry.OriginalHash){throw '恢复后校验失败。'}
            }else{Remove-Item -LiteralPath $entry.Target -Force}
            $restored++
        }
        Say "恢复完成：恢复 $restored 个文件，保留 $kept 个文件。"
        return 0
    }
    $policyPath=Join-Path $optiDir 'RuntimeSync\runtimes.json'
    $policy=Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($policy.Schema -ne 1 -or @($policy.Files).Count -ne $allowed.Count){throw '运行库清单无效。'}
    $sources=@{}
    foreach($file in $policy.Files){
        if($file.Name -notin $allowed -or $sources.ContainsKey($file.Name) -or $file.Source -ne "OptiScaler/streamline/$($file.Name)"){throw '运行库来源无效。'}
        $source=Join-Path $installRoot $file.Source
        if(!(Test-Path -LiteralPath $source -PathType Leaf) -or (HashFile $source) -ne $file.Sha256){throw "配套运行库缺失或校验失败：$($file.Name)。请完整安装 Streamline 组件。"}
        if($Mode -eq 'Sync'){
            $signature=Get-AuthenticodeSignature -LiteralPath $source
            if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'NVIDIA Corporation'){throw "NVIDIA 签名校验失败：$($file.Name)"}
        }
        $sources[$file.Name]=@{Path=$source;Hash=$file.Sha256;Version=$file.Version}
    }
    $targets=@(FindTargets $scanRoot)
    if(!$targets.Count){Say '未发现游戏原生帧生成运行库，无需同步。';return 0}
    # Preserve the complete native chain if any discovered Streamline generation is incompatible.
    $protected=@($targets | Where-Object {[IO.Path]::GetFileName($_) -like 'sl.*.dll' -and (SlMajor $_) -ne 2})
    if($protected.Count){
        foreach($target in $protected){Say "保留 Streamline 1.x 或版本不明的运行库：$target"}
        Say '该游戏运行库代际不兼容，整套原生帧生成运行库保持原样。'
        return 0
    }
    # PCL is a new dependency of the bundled Reflex. Add it only beside an existing native Reflex.
    foreach($target in @($targets)){
        if([IO.Path]::GetFileName($target) -eq 'sl.reflex.dll'){
            $dependency=Join-Path (Split-Path $target -Parent) 'sl.pcl.dll'
            if($dependency -notin $targets){$targets+= $dependency}
        }
    }
    $changes=[Collections.Generic.List[object]]::new();$correct=0
    foreach($target in $targets){
        if(!(Within $target $scanRoot) -or (Within $target $optiDir)){throw '同步目标超出游戏范围。'}
        $name=[IO.Path]::GetFileName($target)
        $exists=Test-Path -LiteralPath $target -PathType Leaf
        $hash=if($exists){HashFile $target}else{''}
        if($hash -eq $sources[$name].Hash){$correct++;continue}
        $version=if($exists){(Get-Item -LiteralPath $target).VersionInfo.FileVersion}else{'缺失'}
        Say "$name：$version -> $($sources[$name].Version)  [$target]"
        $changes.Add(@{Target=$target;Name=$name;Exists=$exists;Hash=$hash})
    }
    Say "已匹配 $correct 个，需要同步 $($changes.Count) 个。"
    if($Mode -eq 'Check'){
        if($running){Say '游戏正在运行；这里只检查文件。已加载的旧 DLL 需要退出游戏后更新并重启。'}
        if($changes.Count){Say '退出游戏后运行“同步运行库.cmd”即可备份并修复。';return 10}
        Say '运行库文件一致。请在游戏内确认 Transfusion 显示的实际倍率。'
        return 0
    }
    if(!$changes.Count){Say '运行库已同步，无需修改。';return 0}
    if(GameRunning $scanRoot){throw '游戏已启动，未替换文件。'}
    $transaction=Join-Path $stateDir ('backup\'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $transaction -Force | Out-Null
    $nextEntries=@($entries)
    foreach($change in $changes){
        $id=$changes.IndexOf($change)
        $snapshot=Join-Path $transaction ("$id-"+$change.Name)
        if($change.Exists){
            Copy-Item -LiteralPath $change.Target -Destination $snapshot
            if((HashFile $snapshot) -ne $change.Hash){throw '备份校验失败，未替换文件。'}
        }
        $change.Before=$snapshot
        $existing=@($nextEntries | Where-Object {$_.Target -eq $change.Target}) | Select-Object -First 1
        if($existing -and $change.Hash -eq $existing.DeployedHash){
            $originalExists=$existing.OriginalExists;$originalHash=$existing.OriginalHash;$backup=$existing.Backup
        }else{
            $originalExists=$change.Exists;$originalHash=$change.Hash;$backup=if($change.Exists){$snapshot}else{''}
        }
        $updated=[pscustomobject]@{Target=$change.Target;OriginalExists=$originalExists;OriginalHash=$originalHash;Backup=$backup;DeployedHash=$sources[$change.Name].Hash}
        $nextEntries=@($nextEntries | Where-Object {$_.Target -ne $change.Target})+@($updated)
    }
    $previous=if(Test-Path -LiteralPath $statePath){[IO.File]::ReadAllText($statePath)}else{$null}
    $nextState=[ordered]@{Schema=1;InstallDir=$installRoot;ScanRoot=$scanRoot;Profile=$policy.Profile;Entries=$nextEntries;Status='Prepared'}
    SaveJson $nextState $statePath
    $attempted=[Collections.Generic.List[object]]::new()
    try{
        if(GameRunning $scanRoot){throw '游戏已启动，停止同步。'}
        foreach($change in $changes){
            $attempted.Add($change)
            Copy-Item -LiteralPath $sources[$change.Name].Path -Destination $change.Target -Force
            if((HashFile $change.Target) -ne $sources[$change.Name].Hash){throw '同步后文件校验失败。'}
        }
        $nextState.Status='Synchronized'
        SaveJson $nextState $statePath
    }catch{
        foreach($change in $attempted){
            if($change.Exists){
                if((Test-Path -LiteralPath $change.Target) -and (HashFile $change.Target) -eq $change.Hash){continue}
                Copy-Item -LiteralPath $change.Before -Destination $change.Target -Force
            }
            elseif((Test-Path -LiteralPath $change.Target) -and (HashFile $change.Target) -eq $sources[$change.Name].Hash){Remove-Item -LiteralPath $change.Target -Force}
        }
        if($null -ne $previous){[IO.File]::WriteAllText($statePath,$previous,[Text.UTF8Encoding]::new($false))}
        else{$nextState.Status='Rolled back';SaveJson $nextState $statePath}
        throw
    }
    Say "同步完成：更新 $($changes.Count) 个文件。原文件已备份。"
    Say '启动游戏，开启 DLSS 帧生成，并在 Transfusion 页确认实际倍率。'
    return 0
}
$transcript=$false
try{$result=Main;exit [int]$result}
catch{Write-Host "未完成：$($_.Exception.Message)" -ForegroundColor Yellow;exit 4}
finally{if($transcript){Stop-Transcript | Out-Null}}
