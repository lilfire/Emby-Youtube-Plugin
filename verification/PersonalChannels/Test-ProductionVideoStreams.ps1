param([switch]$RequireIsolation,[ValidateSet('None','Full','Head','Range','Conditional')][string]$StreamWriteRace='None',[switch]$TraceStaticFactory,[switch]$InjectFactoryMismatch,
    [ValidateSet('Full','Head','Range','Conditional')][string]$MismatchVariant='Full',[switch]$BufferedYouTube)
if($StreamWriteRace -ne 'None'){$RequireIsolation=$true}
. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
$profileRoot=Join-Path $root 'data/data/youtube-personal'
if(Test-Path $profileRoot){throw 'Video stream test requires absent isolated profiles'}
function Hash([byte[]]$bytes){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','')}finally{$sha.Dispose()}
}
function StreamPath($owner,$sourceOwner=$owner){
    "Videos/$($subjects[$owner].VideoId)/stream.mp4?Static=true&MediaSourceId=$($subjects[$sourceOwner].SourceId)"
}
function OwnStreams($phase,$actor){
    $subject=$subjects[$actor];$path=StreamPath $actor
    $ownHeaders=$subject.Headers.Clone()
    if($TraceStaticFactory -and $actor -eq 'a'){$ownHeaders['X-Isolated-Static-Factory']='trace'}
    $full=Request $path $ownHeaders
    $matches=(Hash $full.Bytes) -eq $subject.SourceHash
    $rows.Add(@{Label="$phase $actor own static video";Status=$full.Status;Bytes=$full.Bytes.Length;SourceHashMatches=$matches})
    if($full.Status -ne 200 -or -not $matches){throw 'Own static stream is not the actual source'}
    $default=Request "Videos/$($subject.VideoId)/stream.mp4?Static=true" $ownHeaders
    $matches=(Hash $default.Bytes) -eq $subject.SourceHash
    $rows.Add(@{Label="$phase $actor own default static video source";Status=$default.Status;SourceHashMatches=$matches})
    if($default.Status -ne 200 -or -not $matches){throw 'Own default static source failed'}
    $head=Request $path $ownHeaders Head
    $rows.Add(@{Label="$phase $actor own stream HEAD";Status=$head.Status;Bytes=$head.Bytes.Length;ContentLength=$head.ContentLength})
    if($head.Status -ne 200 -or $head.Bytes.Length -ne 0 -or $head.ContentLength -ne $full.Bytes.Length){throw 'Own stream HEAD failed'}
    $rangeHeaders=$ownHeaders.Clone();$rangeHeaders.Range='bytes=0-127'
    $range=Request $path $rangeHeaders
    $prefix=[byte[]]([IO.File]::ReadAllBytes($subject.SourcePath)[0..127])
    $matches=[Convert]::ToBase64String($range.Bytes) -eq [Convert]::ToBase64String($prefix)
    $rows.Add(@{Label="$phase $actor own stream range";Status=$range.Status;Bytes=$range.Bytes.Length;SourcePrefixMatches=$matches;ContentRange=$range.ContentRange})
    if($range.Status -ne 206 -or -not $matches -or $range.ContentRange -ne "bytes 0-127/$($full.Bytes.Length)"){throw 'Own stream range failed'}
    if(-not $full.ETag){throw 'Static stream has no established validator'}
    $conditional=$ownHeaders.Clone();$conditional['If-None-Match']=$full.ETag
    $cached=Request $path $conditional
    $rows.Add(@{Label="$phase $actor own stream conditional";Status=$cached.Status;Bytes=$cached.Bytes.Length;SameETag=($cached.ETag -eq $full.ETag)})
    if($cached.Status -ne 304 -or $cached.Bytes.Length -ne 0 -or $cached.ETag -ne $full.ETag){throw 'Own conditional stream failed'}
    $subject.ETag=$full.ETag
}
function ForeignStreams($phase){
    foreach($actor in @('a','b')){
        $target=if($actor -eq 'a'){'b'}else{'a'}
        foreach($variant in @('Full','Head','Range','Conditional','MixedSource','MixedMissingSource')){
            $headers=$subjects[$actor].Headers.Clone()
            if($variant -eq 'Range'){$headers.Range='bytes=0-127'}
            if($variant -eq 'Conditional'){$headers['If-None-Match']=$subjects[$target].ETag}
            $method=if($variant -eq 'Head'){'Head'}else{'Get'}
            $path=if($variant -eq 'MixedSource'){StreamPath $actor $target}elseif($variant -eq 'MixedMissingSource'){"Videos/$($subjects[$actor].VideoId)/stream.mp4?Static=true&MediaSourceId=isolated_missing_source"}else{StreamPath $target}
            $before=Call 'PersonalChannelsFixture/ProductionServiceGate'
            $r=Request $path $headers $method
            $after=Call 'PersonalChannelsFixture/ProductionServiceGate'
            $private=if($target -eq 'a'){$r.PrivateAHeader -or $r.Text.Contains('PrivateNativeVideo_a_client')}else{$r.PrivateBHeader -or $r.Text.Contains('PrivateNativeVideo_b_client')}
            $entity=@($r.HeaderNames|Where-Object {$_ -in @('Content-Disposition','Content-Range','ETag','Last-Modified','Accept-Ranges')})
            $generic=if($method -eq 'Head'){$r.Bytes.Length -eq 0}else{$r.Text -eq 'Item not found.'}
            $safe=$r.Status -eq 404 -and -not $private -and $entity.Count -eq 0 -and $generic -and $r.ContentLength -eq 15
            $enforced=$after.Checked-$before.Checked -eq 1 -and $after.Denied-$before.Denied -eq 1
            $rows.Add(@{Label="$phase $actor foreign $target stream $variant";Status=$r.Status;Bytes=$r.Bytes.Length;MatchesForeignSource=((Hash $r.Bytes) -eq $subjects[$target].SourceHash);PrivateNamePresent=$private;EntityHeaderCount=$entity.Count;IsolationPass=$safe;CheckedDelta=($after.Checked-$before.Checked);DeniedDelta=($after.Denied-$before.Denied)})
            if($RequireIsolation -and (-not $safe -or -not $enforced)){throw 'Private stream not isolated by production prefix'}
        }
    }
}
function DeletedOwner($phase){
    foreach($variant in @('Full','Head','Range','Conditional')){
        $headers=$subjects.a.Headers.Clone()
        if($variant -eq 'Range'){$headers.Range='bytes=0-127'}
        if($variant -eq 'Conditional'){$headers['If-None-Match']=$subjects.a.ETag}
        $method=if($variant -eq 'Head'){'Head'}else{'Get'}
        $before=Call 'PersonalChannelsFixture/ProductionServiceGate'
        $r=Request (StreamPath 'a') $headers $method
        $after=Call 'PersonalChannelsFixture/ProductionServiceGate'
        $entity=@($r.HeaderNames|Where-Object {$_ -in @('Content-Disposition','Content-Range','ETag','Last-Modified','Accept-Ranges')})
        $rows.Add(@{Label="$phase deleted A own stream $variant";Status=$r.Status;Bytes=$r.Bytes.Length;PrivateHeader=$r.PrivateAHeader;EntityHeaderCount=$entity.Count;DeniedDelta=($after.Denied-$before.Denied)})
        if($r.Status -ne 404 -or $r.PrivateAHeader -or $r.Text.Contains('PrivateNativeVideo_a_client') -or $entity.Count -or $after.Denied-$before.Denied -ne 1){throw 'Deleted owner stream remains accessible'}
    }
}
try{
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -BufferedYouTube:$BufferedYouTube|Out-Null
    $fixture=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
    foreach($actor in @('a','b')){
        $u=@($fixture.Users|Where-Object Owner -eq $actor)[0];$lib=@($fixture.Libraries|Where-Object Owner -eq $actor)[0]
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Video stream test`", Device=`"Isolated`", DeviceId=`"stream-$actor`", Version=`"1`""} Post @{Username=$u.Name;Pw=''}
        if($login.User.Policy.IsAdministrator -or $login.User.Id -ne $u.UserId){throw 'Wrong ordinary token'}
        $sourcePath=Join-Path $lib.Folder "PrivateNativeVideo_${actor}_client.mp4"
        $subjects[$actor]=@{UserId=$u.UserId;VideoId=$lib.VideoId;Headers=@{'X-Emby-Token'=$login.AccessToken};SourcePath=$sourcePath;SourceHash=(Get-FileHash $sourcePath).Hash}
        $subjects[$actor].Profile=Call 'YouTubePlugin/MyProfile' $subjects[$actor].Headers Post @{ExpectedRevision=0;Channels=@('UC'+('a'*22))}
        $bound=Call 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{RootKey=[long]$lib.LibraryId;OwnerUserId=$u.UserId}
        if(-not $bound.Registered){throw 'Missing production binding'}
    }
    $state=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
    if($state.ExperimentalEnabled -or -not $state.Production.Installed){throw 'Production-only stream test not ready'}
    $rows.Add(@{Label='Production reference gate active and experimental guard disabled';Installed=$true;ExperimentalEnabled=$false;AuditedDtoCount=$state.Production.AuditedDtoCount})
    if($InjectFactoryMismatch){
        $playback=Call "Items/$($subjects.a.VideoId)/PlaybackInfo" $subjects.a.Headers Post @{}
        $source=@($playback.MediaSources)[0]
        if(-not $source.Id -or -not $source.Path.EndsWith('PrivateNativeVideo_a_client.mp4')){throw 'Synthetic A source not established'}
        $subjects.a.SourceId=$source.Id
        $positive=Request (StreamPath 'a') $subjects.a.Headers
        if($positive.Status -ne 200 -or (Hash $positive.Bytes) -ne $subjects.a.SourceHash -or -not $positive.ETag){throw 'A source/validator not established before mismatch'}
        $rows.Add(@{Label='A authorized source before mismatch';Status=$positive.Status;SourceHashMatches=$true;HasETag=$true})
        $sourceBefore=Call 'PersonalChannelsFixture/ProductionServiceGate'
        Call 'PersonalChannelsFixture/NativeStaticFactoryTrace' $admin Post @{OwnerUserId=$subjects.a.UserId;ItemId=[long]$subjects.a.VideoId;ForeignItemId=[long]$subjects.b.VideoId}|Out-Null
        $headers=$subjects.a.Headers.Clone();$headers['X-Isolated-Static-Factory']='inject'
        if($MismatchVariant -eq 'Range'){$headers.Range='bytes=0-127'}
        if($MismatchVariant -eq 'Conditional'){$headers['If-None-Match']=$positive.ETag}
        $method=if($MismatchVariant -eq 'Head'){'Head'}else{'Get'}
        $r=Request (StreamPath 'a') $headers $method
        $own=(Hash $r.Bytes) -eq $subjects.a.SourceHash;$foreign=(Hash $r.Bytes) -eq $subjects.b.SourceHash
        $entity=@($r.HeaderNames|Where-Object {$_ -in @('Content-Disposition','Content-Range','ETag','Last-Modified','Accept-Ranges')})
        $generic=if($MismatchVariant -eq 'Head'){$r.Bytes.Length -eq 0}else{$r.Text -eq 'Item not found.'}
        $safe=$r.Status -eq 404 -and -not $foreign -and $entity.Count -eq 0 -and $generic -and $r.ContentLength -eq 15
        $trace=Call 'PersonalChannelsFixture/NativeStaticFactoryTrace'
        $sourceGate=Call 'PersonalChannelsFixture/ProductionServiceGate'
        $ioDelta=$sourceGate.StaticSources.IoCalls-$sourceBefore.StaticSources.IoCalls
        $deniedDelta=$sourceGate.StaticSources.Denied-$sourceBefore.StaticSources.Denied
        $rows.Add(@{Label='Production static source state at mismatch';SourceState=$sourceGate.StaticSources;IoCallsDelta=$ioDelta;DeniedDelta=$deniedDelta})
        $rows.Add(@{Label='Injected nested static factory source mismatch';Variant=$MismatchVariant;Status=$r.Status;Bytes=$r.Bytes.Length;OwnSourceHashMatches=$own;ForeignSourceHashMatches=$foreign;EntityHeaderCount=$entity.Count;IsolationPass=$safe;Injected=$trace.Injected})
        $rows.Add(@{Label='Actual native mismatch trace';Installed=$trace.Installed;Injected=$trace.Injected;Events=$trace.Events})
        if($trace.Injected -ne 1){throw 'Controlled native source mismatch was not reached'}
        if($RequireIsolation -and -not $safe){throw 'Injected source mismatch not isolated'}
        if($RequireIsolation -and (-not $sourceGate.StaticSources.Installed -or $ioDelta -ne 0 -or $deniedDelta -lt 1)){throw 'Injected mismatch not denied before bound reader I/O'}
        if(-not $RequireIsolation -and (-not $foreign -or $r.Status -ne 200)){throw 'Mismatch diagnostic did not reproduce foreign source delivery'}
        $bPlayback=Call "Items/$($subjects.b.VideoId)/PlaybackInfo" $subjects.b.Headers Post @{}
        $subjects.b.SourceId=@($bPlayback.MediaSources)[0].Id
        OwnStreams 'Mismatch independent B control' 'b'
        $completed=$true
        return
    }
    if($TraceStaticFactory){Call 'PersonalChannelsFixture/NativeStaticFactoryTrace' $admin Post @{OwnerUserId=$subjects.a.UserId;ItemId=[long]$subjects.a.VideoId}|Out-Null}
    foreach($actor in @('a','b')){
        $playback=Call "Items/$($subjects[$actor].VideoId)/PlaybackInfo" $subjects[$actor].Headers Post @{}
        $source=@($playback.MediaSources)[0]
        if(-not $source.Id -or -not $source.Path.EndsWith("PrivateNativeVideo_${actor}_client.mp4")){throw 'Own PlaybackInfo source not established'}
        $subjects[$actor].SourceId=$source.Id
        OwnStreams 'Active' $actor
    }
    ForeignStreams 'Active'
    if($TraceStaticFactory){
        $trace=Call 'PersonalChannelsFixture/NativeStaticFactoryTrace'
        if(-not $trace.Installed -or $trace.Events.Count -eq 0){throw 'Actual static factory trace missing'}
        $fileCalls=@($trace.Events|Where-Object {$_.Phase -eq 'Before' -and $_.Method.Contains(' GetStaticFileResult(')})
        $nested=@($trace.Events|Where-Object {$_.Phase -eq 'Before' -and $_.Method.Contains(' GetStaticResult(')})
        $fileWriters=@($trace.Events|Where-Object {$_.Phase -eq 'After' -and $_.ResultType -eq 'Emby.Server.Implementations.HttpServer.FileWriter'})
        $emptyWriters=@($trace.Events|Where-Object {$_.Phase -eq 'After' -and $_.ResultType -eq 'Emby.Server.Implementations.Services.EmptyHttpResult'})
        if($fileCalls.Count -ne 5 -or $nested.Count -ne 5 -or $fileWriters.Count -ne 8 -or $emptyWriters.Count -ne 2 -or $trace.Injected -ne 0){throw 'Unexpected actual factory coverage'}
        foreach($entry in $fileCalls){if(-not $entry.MatchesExpectedPath -or $entry.ContentFactoryPresent){throw 'Unexpected pre-construction file factory options'}}
        foreach($entry in $nested){
            $bound=$entry.BoundReaderContract
            if(-not $entry.ContentFactoryPresent -or -not $bound.ReaderMatchesExpectedPath -or -not $bound.SeparateReaderOptions -or -not $bound.SameMetadataOptions -or $bound.NativeReaderMethod.BodyHash -ne '6EF1D70DA9C84A39140CC50C0166C4A8A9670A07ED10ECB324632061E649FC1B'){throw 'Actual reader closure not bound to separate approved options'}
        }
        foreach($entry in $fileWriters){
            $bound=$entry.BoundReaderContract
            if($entry.WriterPathPresent -or -not $entry.WriterFactoryPresent -or -not $bound.ReaderMatchesExpectedPath -or -not $bound.SeparateReaderOptions -or $bound.NativeReaderMethod.BodyHash -ne '6EF1D70DA9C84A39140CC50C0166C4A8A9670A07ED10ECB324632061E649FC1B'){throw 'Actual file writer does not carry observed bound reader'}
        }
        $sourceGate=Call 'PersonalChannelsFixture/ProductionServiceGate'
        if(-not $sourceGate.StaticSources.Installed){throw 'Production source gate not installed during trace'}
        $rows.Add(@{Label='Actual native static factory trace';Installed=$trace.Installed;Events=$trace.Events;FileFactoryCalls=$fileCalls.Count;NestedFactoryCalls=$nested.Count;FileWriterResults=$fileWriters.Count;EmptyWriterResults=$emptyWriters.Count;SeparateBoundReaderVerified=$true;SourceState=$sourceGate.StaticSources})
    }
    if($RequireIsolation){
        if($StreamWriteRace -ne 'None'){
            $timingPath='PersonalChannelsFixture/NativeReferenceWriteGate'
            $writeBefore=Call 'PersonalChannelsFixture/ProductionItemList'
            Call $timingPath $admin Post @{OwnerUserId=$subjects.a.UserId;Video=$true}|Out-Null
            $method=if($StreamWriteRace -eq 'Head'){'Head'}else{'Get'}
            $message=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($method.ToUpperInvariant()),"$base/$(StreamPath 'a')")
            foreach($key in $subjects.a.Headers.Keys){$message.Headers.TryAddWithoutValidation($key,[string]$subjects.a.Headers[$key])|Out-Null}
            if($StreamWriteRace -eq 'Range'){$message.Headers.TryAddWithoutValidation('Range','bytes=0-127')|Out-Null}
            if($StreamWriteRace -eq 'Conditional'){$message.Headers.TryAddWithoutValidation('If-None-Match',$subjects.a.ETag)|Out-Null}
            $message.Headers.TryAddWithoutValidation('X-Isolated-Reference-Gate','before-write')|Out-Null
            $pending=$client.SendAsync($message)
            try{
                $deadline=[DateTime]::UtcNow.AddSeconds(10)
                do{$pause=Call $timingPath;if($pause.Active){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
                if(-not $pause.Active -or $pending.IsCompleted -or $pause.TimedOut){throw 'Actual private video writer did not pause'}
                $rows.Add(@{Label='Actual native video writer paused';Variant=$StreamWriteRace;ResultContract=$pause.ResultContract;HttpPending=$true})
                OwnStreams 'While A writer paused' 'b'
                $deleted=Call 'YouTubePlugin/MyProfile/Delete' $subjects.a.Headers Post @{ExpectedRevision=$subjects.a.Profile.Revision}
                $pause=Call $timingPath
                if($deleted.State -ne 'Deleted' -or (Call 'YouTubePlugin/MyProfile' $subjects.a.Headers).State -ne 'Deleted' -or -not $pause.Active -or $pause.TimedOut -or $pending.IsCompleted){throw 'Actual profile deletion did not finish before stream release'}
                $rows.Add(@{Label='Actual A deletion persisted while native video writer held';Deleted=$true;HttpPending=$true})
            }finally{Call $timingPath $admin Post @{Release=$true}|Out-Null}
            $response=$pending.GetAwaiter().GetResult()
            try{
                $bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
                $text=[Text.Encoding]::UTF8.GetString($bytes)
                $headerText=(@($response.Headers|ForEach-Object {$_.Key+':'+($_.Value -join ',')})+@($response.Content.Headers|ForEach-Object {$_.Key+':'+($_.Value -join ',')})) -join "`n"
                $private=[Uri]::UnescapeDataString($headerText).Contains('PrivateNativeVideo_a_client')
                $names=@($response.Headers|ForEach-Object {$_.Key})+@($response.Content.Headers|ForEach-Object {$_.Key})
                $entity=@($names|Where-Object {$_ -in @('Content-Disposition','Content-Range','ETag','Last-Modified','Accept-Ranges')})
                $generic=if($StreamWriteRace -eq 'Head'){$bytes.Length -eq 0}else{$text -eq 'Items not found.'}
                $safe=[int]$response.StatusCode -eq 404 -and $generic -and -not $private -and $entity.Count -eq 0 -and $response.Content.Headers.ContentLength -eq 16
                $rows.Add(@{Label='Private stream response after completed deletion';Variant=$StreamWriteRace;Status=[int]$response.StatusCode;Bytes=$bytes.Length;ContentLength=$response.Content.Headers.ContentLength;GenericBody=$generic;PrivateHeader=$private;EntityHeaderCount=$entity.Count;IsolationPass=$safe})
                if(-not $safe){throw 'Stale private stream not safely denied'}
            }finally{$response.Dispose();$message.Dispose()}
            $writeAfter=Call 'PersonalChannelsFixture/ProductionItemList'
            $rows.Add(@{Label='Production write hook denied stale private stream';Installed=$writeAfter.Installed;DeniedDelta=($writeAfter.WritesDenied-$writeBefore.WritesDenied)})
            if(-not $writeAfter.Installed -or $writeAfter.WritesDenied-$writeBefore.WritesDenied -ne 1){throw 'Stale stream denial not from production write hook'}
            $handle=[IO.File]::Open($subjects.a.SourcePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
            $handle.Dispose()
            $rows.Add(@{Label='Rejected static stream source allows exclusive read';Opened=$true})
        }else{
            $deleted=Call 'YouTubePlugin/MyProfile/Delete' $subjects.a.Headers Post @{ExpectedRevision=$subjects.a.Profile.Revision}
            if($deleted.State -ne 'Deleted' -or (Call 'YouTubePlugin/MyProfile' $subjects.a.Headers).State -ne 'Deleted'){throw 'A deletion not persisted'}
        }
        OwnStreams 'Deleted profile' 'b'
        ForeignStreams 'Deleted profile'
        DeletedOwner 'Deleted profile'
        $beforeBoot=(Call 'PersonalChannelsFixture/Guard').BootId
        & $control -Stop|Out-Null
        & $control|Out-Null
        $deadline=[DateTime]::UtcNow.AddSeconds(40)
        do{try{$guard=Call 'PersonalChannelsFixture/Guard';if($guard.Ready -and $guard.BootId -ne $beforeBoot){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
        if(-not $guard.Ready -or $guard.BootId -eq $beforeBoot){throw 'Video test restart not verified'}
        $state=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
        if($state.ExperimentalEnabled -or -not $state.Production.Installed){throw 'Video restart not production-only'}
        $rows.Add(@{Label='Actual video test restart';RestartVerified=$true;ExperimentalEnabled=$false})
        OwnStreams 'After restart' 'b'
        ForeignStreams 'After restart'
        DeletedOwner 'After restart'
    }
    $completed=$true
}finally{
    $name=if($InjectFactoryMismatch){if($RequireIsolation){if($MismatchVariant -eq 'Full'){'production-static-factory-mismatch-protected-results.json'}else{'production-static-factory-mismatch-'+$MismatchVariant.ToLowerInvariant()+'-results.json'}}else{'production-static-factory-mismatch-diagnostic-results.json'}}elseif($TraceStaticFactory){'production-static-factory-trace-results.json'}elseif($StreamWriteRace -ne 'None'){'production-video-stream-'+$StreamWriteRace.ToLowerInvariant()+'-write-results.json'}elseif($RequireIsolation){'production-video-stream-protected-results.json'}else{'production-video-stream-diagnostic-results.json'}
    if($BufferedYouTube){$name='production-buffered-youtube-stream-results.json'}
    $scope=if($InjectFactoryMismatch){'Controlled synthetic A/B fault injection in mutable nested factory options; no ordinary-client exploit claim'}elseif($BufferedYouTube){'Actual publicly downloaded YouTube test video DTi8wZ1a1TA served as native local MP4; full/head/range/ETag/mixed source/deletion/restart; synthetic B control; not actual app playback or automatic personal publication'}else{'Actual static GetVideoStream; full/head/range/ETag/mixed source; native profiles and bindings; experimental guard disabled; not all media routes'}
    @{Completed=$completed;Observations=$rows.ToArray();Scope=$scope}|ConvertTo-Json -Depth 12|Set-Content (Join-Path $PSScriptRoot ('bin/'+$name)) -Encoding UTF8
    try{
        & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null
        if(Test-Path $profileRoot){
            $dir=[IO.Path]::GetFullPath($profileRoot);$expected=[IO.Path]::GetFullPath((Join-Path $root 'data/data/youtube-personal'))
            if($dir -ne $expected -or -not $dir.StartsWith([IO.Path]::GetFullPath($root)+[IO.Path]::DirectorySeparatorChar)){throw 'Unsafe profile cleanup'}
            $names=@('encryption.key','native-reference-bindings.json','native-reference-bindings.required')+@($subjects.Values|ForEach-Object{$_.UserId+'.json'})
            $files=@(Get-ChildItem -LiteralPath $dir -Force)
            if(@($files|Where-Object {$_.PSIsContainer -or $_.Name -notin $names -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)}).Count){throw 'Unexpected file retained'}
            foreach($file in $files){Remove-Item -LiteralPath $file.FullName}
            Remove-Item -LiteralPath $dir
        }
    }finally{$client.Dispose()}
}
Write-Output ('Production video stream observations='+$rows.Count)
