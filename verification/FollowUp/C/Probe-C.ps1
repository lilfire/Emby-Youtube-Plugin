# Runs inside the production-only asset lifecycle after paired A/B controls.
# Mutations are local administrator fault injection, not a client exploit.
function Digest([byte[]]$bytes){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','')}finally{$sha.Dispose()}
}
$cacheRoot=[IO.Path]::GetFullPath((Join-Path $root 'data/cache'))
$cacheRecords=[Collections.Generic.List[object]]::new()
foreach($kind in @('image','subtitle')){
    $aResponse=Request (AssetPath $subjects.a $kind) $subjects.a.Headers
    $bResponse=Request (AssetPath $subjects.b $kind) $subjects.b.Headers
    if($aResponse.Status -ne 200 -or $bResponse.Status -ne 200 -or -not(PayloadMatches $aResponse.Bytes $kind 'a') -or -not(PayloadMatches $bResponse.Bytes $kind 'b')){throw 'Content provenance baseline missing'}
    $aHash=Digest $aResponse.Bytes;$bHash=Digest $bResponse.Bytes
    if($aHash -eq $bHash){throw 'Different owner bytes required'}
    $familyRoot=Join-Path $cacheRoot $(if($kind -eq 'image'){'images'}else{'subtitles'})
    if(-not(Test-Path $familyRoot)){throw 'Native cache family root absent'}
    $candidates=@(Get-ChildItem -LiteralPath $familyRoot -File -Recurse | Where-Object {$_.LastWriteTimeUtc -ge $cStarted -and $_.Length -eq $aResponse.Bytes.Length -and (Get-FileHash -LiteralPath $_.FullName).Hash -eq $aHash})
    if($candidates.Count -ne 1){throw "Unique actual $kind cache output not found: $($candidates.Count)"}
    $target=$candidates[0].FullName
    if(-not $target.StartsWith($cacheRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or ($candidates[0].Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unsafe cache mutation'}
    $original=[IO.File]::ReadAllBytes($target)
    $timestamp=[IO.File]::GetLastWriteTimeUtc($target)
    try{
        [IO.File]::WriteAllBytes($target,[byte[]]$bResponse.Bytes)
        [IO.File]::SetLastWriteTimeUtc($target,$timestamp)
        $before=Call 'PersonalChannelsFixture/ProductionServiceGate'
        $r=Request (AssetPath $subjects.a $kind) $subjects.a.Headers
        $after=Call 'PersonalChannelsFixture/ProductionServiceGate'
        $foreign=PayloadMatches $r.Bytes $kind 'b'
        $rows.Add(@{Label='C approved cache path contains foreign bytes';Kind=$kind;Status=$r.Status;Bytes=$r.Bytes.Length;ContainsForeignBContent=$foreign;MatchesForeignHash=(Digest $r.Bytes) -eq $bHash;AssetGateInstalled=$after.AssetSources.Installed;ImageRecipeVersion=$after.AssetSources.ImageRecipeVersion;IoCallsDelta=$after.StaticSources.IoCalls-$before.StaticSources.IoCalls;IsolationPass=($r.Status -eq 404 -and -not $foreign)})
        Asset 'C cache replaced negative account control' 'b' 'a' $kind $false
        Asset 'C cache replaced independent B' 'b' 'b' $kind $true
        # Restore before constructing the response, then change the file after
        # the actual production writer authorization check.
        [IO.File]::WriteAllBytes($target,$original)
        [IO.File]::SetLastWriteTimeUtc($target,$timestamp)
        $raceKind=if($kind -eq 'image'){'Image'}else{'Subtitle'}
        Call 'PersonalChannelsFixture/NativeReferenceWriteGate' $admin Post @{OwnerUserId=$subjects.a.UserId;Asset=$raceKind;AfterCheck=$true}|Out-Null
        $message=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,"$base/$(AssetPath $subjects.a $kind)")
        foreach($key in $subjects.a.Headers.Keys){$message.Headers.TryAddWithoutValidation($key,[string]$subjects.a.Headers[$key])|Out-Null}
        $message.Headers.TryAddWithoutValidation('X-Isolated-Reference-Gate','before-write')|Out-Null
        $pending=$client.SendAsync($message)
        $replacementBlocked=$false
        try{
            $deadline=[DateTime]::UtcNow.AddSeconds(10)
            do{$pause=Call 'PersonalChannelsFixture/NativeReferenceWriteGate';if($pause.Active){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
            if(-not $pause.Active -or -not $pause.AfterCheck -or $pause.TimedOut -or $pending.IsCompleted){throw 'Actual post-check writer seam missing'}
            try{
                [IO.File]::WriteAllBytes($target,[byte[]]$bResponse.Bytes)
                [IO.File]::SetLastWriteTimeUtc($target,$timestamp)
            }catch [IO.IOException]{$replacementBlocked=$true}
        }finally{Call 'PersonalChannelsFixture/NativeReferenceWriteGate' $admin Post @{Release=$true}|Out-Null}
        $response=$pending.GetAwaiter().GetResult()
        try{
            $bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            $foreign=PayloadMatches $bytes $kind 'b'
            $own=PayloadMatches $bytes $kind 'a'
            $rows.Add(@{Label='C cache replacement after production writer check';Kind=$kind;WriterPausedAfterCheck=$true;ReplacementBlockedByWindowsFileHandle=$replacementBlocked;Status=[int]$response.StatusCode;Bytes=$bytes.Length;ContainsForeignBContent=$foreign;ContainsOwnAContent=$own;MatchesForeignHash=(Digest $bytes) -eq $bHash;IsolationPass=((-not $foreign) -and (([int]$response.StatusCode -eq 404) -or ($replacementBlocked -and [int]$response.StatusCode -eq 200 -and $own)))})
        }finally{$response.Dispose();$message.Dispose()}
        $cacheRecords.Add(@{Kind=$kind;RelativePath=$target.Substring($cacheRoot.Length+1);OriginalHash=$aHash;InjectedHash=$bHash})
    }finally{
        [IO.File]::WriteAllBytes($target,$original)
        [IO.File]::SetLastWriteTimeUtc($target,$timestamp)
        if((Get-FileHash -LiteralPath $target).Hash -ne $aHash){throw 'Cache restore readback failed'}
    }
    Asset 'C cache restored owner control' 'a' 'a' $kind $true
}
$cacheRecords.ToArray()|ConvertTo-Json -Depth 4|Set-Content (Join-Path $cOutput 'cache-records.json') -Encoding UTF8
