param([switch]$WriteRace,[switch]$RequireRaceSafe,[switch]$PlaybackWriteRace,[switch]$DownloadWriteRace,
    [ValidateSet('Full','Range','Head','Conditional')][string]$DownloadVariant='Full')
if($DownloadVariant -ne 'Full'){$DownloadWriteRace=$true}
. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
$profileRoot=Join-Path $root 'data/data/youtube-personal'
if(Test-Path $profileRoot){throw 'Service-gate test requires absent isolated profiles'}
function Observe($label,$path,$headers,$expected,$method='Get',$body=$null){
    $r=Request $path $headers $method $body
    $rows.Add(@{Label=$label;Status=$r.Status;Expected=$expected;PrivateNamePresent=($expected -eq 404 -and $r.Text.Contains('PrivateNativeVideo_a_client'))})
    if($r.Status -ne $expected -or $rows[$rows.Count-1].PrivateNamePresent){
        $contract=Call 'PersonalChannelsFixture/ProductionServiceGate'
        $rows.Add(@{Label='Production response contract at failed positive control';Contract=$contract.LastResponseContract})
        throw "Unexpected production service response: $label"
    }
    return $r
}
function BPositive($phase){
    Observe "$phase B own metadata" "Users/$($subjects.b.UserId)/Items/$($subjects.b.VideoId)" $subjects.b.Headers 200|Out-Null
    $r=Observe "$phase B own file" "Items/$($subjects.b.VideoId)/Download" $subjects.b.Headers 200
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=[BitConverter]::ToString($sha.ComputeHash([byte[]]$r.Bytes)).Replace('-','')}finally{$sha.Dispose()}
    if($hash -ne $subjects.b.SourceHash){throw 'B native file changed'}
    $rows[$rows.Count-1].HashMatches=$true
    if($DownloadVariant -in @('Range','Conditional')){
        $variantHeaders=$subjects.b.Headers.Clone()
        if($DownloadVariant -eq 'Range'){$variantHeaders.Range='bytes=0-127'}
        else{if(-not $r.ETag){throw 'B lacks conditional validator'};$variantHeaders['If-None-Match']=$r.ETag}
        $ownVariant=Request "Items/$($subjects.b.VideoId)/Download" $variantHeaders
        $valid=if($DownloadVariant -eq 'Range'){
            $prefix=[byte[]]([IO.File]::ReadAllBytes($subjects.b.SourcePath)[0..127])
            $ownVariant.Status -eq 206 -and $ownVariant.Bytes.Length -eq 128 -and $ownVariant.ContentRange -eq "bytes 0-127/$($r.Bytes.Length)" -and [Convert]::ToBase64String($ownVariant.Bytes) -eq [Convert]::ToBase64String($prefix)
        }else{$ownVariant.Status -eq 304 -and $ownVariant.Bytes.Length -eq 0 -and $ownVariant.ETag -eq $r.ETag -and -not $ownVariant.PrivateAHeader}
        $rows.Add(@{Label="$phase B own download variant";Variant=$DownloadVariant;Status=$ownVariant.Status;Bytes=$ownVariant.Bytes.Length;Valid=$valid})
        if(-not $valid){throw 'B own download variant changed'}
    }
    foreach($method in @('Get','Post')){
        $path=if($method -eq 'Get'){"Items/$($subjects.b.VideoId)/PlaybackInfo?UserId=$($subjects.b.UserId)"}else{"Items/$($subjects.b.VideoId)/PlaybackInfo"}
        $body=if($method -eq 'Post'){@{}}else{$null}
        $playback=Observe "$phase B $method PlaybackInfo" $path $subjects.b.Headers 200 $method $body
        $info=$playback.Text|ConvertFrom-Json
        $own=$playback.Text.Contains('PrivateNativeVideo_b_client');$foreign=$playback.Text.Contains('PrivateNativeVideo_a_client')
        $rows.Add(@{Label="$phase B $method actual PlaybackInfo source";MediaSources=@($info.MediaSources).Count;OwnNamePresent=$own;ForeignNamePresent=$foreign;ErrorCode=$info.ErrorCode})
        if(@($info.MediaSources).Count -lt 1 -or -not $own -or $foreign -or $info.ErrorCode){throw 'B PlaybackInfo does not contain its own usable native source'}
    }
    if($DownloadVariant -eq 'Head'){HeadChecks $phase}
}
function HeadChecks($phase){
    $before=Call 'PersonalChannelsFixture/ProductionServiceGate'
    foreach($actor in @('a','b')){
        foreach($target in @('a','b')){
            $r=Request "Items/$($subjects[$target].VideoId)/Download" $subjects[$actor].Headers Head
            $entity=@($r.HeaderNames|Where-Object {$_ -in @('Content-Disposition','Content-Range','ETag','Last-Modified','Accept-Ranges')})
            $privateHeader=$r.PrivateAHeader -or $r.PrivateBHeader
            $rows.Add(@{Label="$phase $actor HEAD target $target";Status=$r.Status;Bytes=$r.Bytes.Length;PrivateHeader=$privateHeader;EntityHeaderCount=$entity.Count})
            if($r.Status -ne 404 -or $r.Bytes.Length -ne 0 -or $privateHeader -or $entity.Count){throw 'Unsupported HEAD disclosed private entity data'}
        }
    }
    $after=Call 'PersonalChannelsFixture/ProductionServiceGate'
    $rows.Add(@{Label="$phase HEAD requests do not enter native service";CheckedDelta=($after.Checked-$before.Checked)})
    if($after.Checked -ne $before.Checked){throw 'HEAD unexpectedly reached audited service'}
}
function ForeignRoutes($phase){
    $id=$subjects.a.VideoId;$uid=$subjects.a.UserId
    $targets=@(
        @{Path="Users/$uid/Items/$id";Method='Get'},
        @{Path="Items/$id/Download";Method='Get'},
        @{Path="Items/$id/PlaybackInfo?UserId=$uid";Method='Get'},
        @{Path="Items/$id/PlaybackInfo";Method='Post'},
        @{Path="Users/$uid/PlayedItems/$id";Method='Post'},
        @{Path="Users/$uid/PlayedItems/$id/Delete";Method='Post'},
        @{Path="Users/$uid/FavoriteItems/$id";Method='Post'},
        @{Path="Users/$uid/FavoriteItems/$id/Delete";Method='Post'},
        @{Path="Users/$uid/Items/$id/Rating";Method='Post'},
        @{Path="Users/$uid/Items/$id/Rating/Delete";Method='Post'}
    )
    $before=Call 'PersonalChannelsFixture/ProductionServiceGate'
    foreach($target in $targets){
        $body=if($target.Method -eq 'Post'){@{}}else{$null}
        Observe "$phase B foreign $($target.Path)" $target.Path $subjects.b.Headers 404 $target.Method $body|Out-Null
    }
    $after=Call 'PersonalChannelsFixture/ProductionServiceGate'
    $rows.Add(@{Label="$phase ten denials come from production prefix";CheckedDelta=($after.Checked-$before.Checked);DeniedDelta=($after.Denied-$before.Denied)})
    if($after.Checked-$before.Checked -ne 10 -or $after.Denied-$before.Denied -ne 10){throw 'Production service prefix did not account for all denials'}
}
try{
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1')|Out-Null
    $fixture=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
    foreach($actor in @('a','b')){
        $u=@($fixture.Users|Where-Object Owner -eq $actor)[0];$lib=@($fixture.Libraries|Where-Object Owner -eq $actor)[0]
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Production service test`", Device=`"Isolated`", DeviceId=`"service-$actor`", Version=`"1`""} Post @{Username=$u.Name;Pw=''}
        if($login.User.Policy.IsAdministrator -or $login.User.Id -ne $u.UserId){throw 'Wrong ordinary token'}
        $sourcePath=Join-Path $lib.Folder "PrivateNativeVideo_${actor}_client.mp4"
        $subjects[$actor]=@{UserId=$u.UserId;VideoId=$lib.VideoId;Headers=@{'X-Emby-Token'=$login.AccessToken};SourcePath=$sourcePath;SourceHash=(Get-FileHash $sourcePath).Hash}
        $subjects[$actor].Profile=Call 'YouTubePlugin/MyProfile' $subjects[$actor].Headers Post @{ExpectedRevision=0;Channels=@('UC'+('a'*22))}
        $bound=Call 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{RootKey=[long]$lib.LibraryId;OwnerUserId=$u.UserId}
        if(-not $bound.Registered){throw 'Missing production binding'}
    }
    $state=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
    if($state.ExperimentalEnabled -or -not $state.Production.Installed -or $state.Production.AuditedDtoCount -ne 18){throw 'Production-only service test not ready'}
    $rows.Add(@{Label='Actual production prefix installed; experimental guard disabled';ProductionInstalled=$true;ExperimentalEnabled=$false;AuditedDtoCount=$state.Production.AuditedDtoCount})
    $baseline=Observe 'A own active metadata' "Users/$($subjects.a.UserId)/Items/$($subjects.a.VideoId)" $subjects.a.Headers 200
    $beforeData=($baseline.Text|ConvertFrom-Json).UserData|ConvertTo-Json -Compress
    ForeignRoutes 'Active'
    $afterData=(Observe 'A native state after foreign mutations' "Users/$($subjects.a.UserId)/Items/$($subjects.a.VideoId)" $subjects.a.Headers 200).Text|ConvertFrom-Json
    if(($afterData.UserData|ConvertTo-Json -Compress) -ne $beforeData){throw 'Foreign mutations changed A native history'}
    $rows.Add(@{Label='A native UserData unchanged by ten foreign requests';Unchanged=$true})
    BPositive 'Active'
    foreach($mutation in @('FavoriteItems','PlayedItems')){
        Observe "A own $mutation mutation" "Users/$($subjects.a.UserId)/$mutation/$($subjects.a.VideoId)" $subjects.a.Headers 200 Post @{}|Out-Null
        $data=(Call "Users/$($subjects.a.UserId)/Items/$($subjects.a.VideoId)" $subjects.a.Headers).UserData
        $value=if($mutation -eq 'FavoriteItems'){$data.IsFavorite}else{$data.Played}
        $rows.Add(@{Label="A native $mutation change exists";Changed=[bool]$value})
        if(-not $value){throw 'Own native mutation failed'}
    }
    Observe 'Allowed owner cannot target another user history' "Users/$($subjects.b.UserId)/FavoriteItems/$($subjects.a.VideoId)" $subjects.a.Headers 404 Post @{}|Out-Null
    if($DownloadVariant -eq 'Head'){
        $nativeHead=Get-Content (Join-Path $PSScriptRoot 'bin/native-download-variant-baseline-results.json') -Raw|ConvertFrom-Json
        if(-not $nativeHead.Completed){throw 'Native unsupported HEAD baseline not completed'}
        $rows.Add(@{Label='HEAD unsupported in independently verified native baseline';Verified=$true})
    }
    if(($WriteRace -or $PlaybackWriteRace -or $DownloadWriteRace) -and $DownloadVariant -ne 'Head'){
        $timingPath='PersonalChannelsFixture/NativeReferenceWriteGate'
        $writeBefore=Call 'PersonalChannelsFixture/ProductionItemList'
        $family=if($DownloadWriteRace){'GetDownload'}elseif($PlaybackWriteRace){'GetPlaybackInfo'}else{'GetItem'}
        $privatePath=if($DownloadWriteRace){"Items/$($subjects.a.VideoId)/Download"}elseif($PlaybackWriteRace){"Items/$($subjects.a.VideoId)/PlaybackInfo?UserId=$($subjects.a.UserId)"}else{"Users/$($subjects.a.UserId)/Items/$($subjects.a.VideoId)"}
        if($DownloadWriteRace){
            $positive=Observe 'A private download before timing probe' $privatePath $subjects.a.Headers 200
            $sha=[Security.Cryptography.SHA256]::Create()
            try{$hash=[BitConverter]::ToString($sha.ComputeHash([byte[]]$positive.Bytes)).Replace('-','')}finally{$sha.Dispose()}
            if($hash -ne $subjects.a.SourceHash){throw 'A download source not positively established'}
            $rows.Add(@{Label='A positive download matches actual source SHA';HashMatches=$true;Bytes=$positive.Bytes.Length})
            $downloadMethod=if($DownloadVariant -eq 'Head'){'Head'}else{'Get'}
            $downloadHeaders=$subjects.a.Headers.Clone()
            if($DownloadVariant -eq 'Range'){$downloadHeaders.Range='bytes=0-127'}
            if($DownloadVariant -eq 'Conditional'){
                if($positive.ETag){$downloadHeaders['If-None-Match']=$positive.ETag}
                elseif($positive.LastModified){$downloadHeaders['If-Modified-Since']=$positive.LastModified}
                else{throw 'Download has no validator; conditional response cannot be positively established'}
            }
            if($DownloadVariant -ne 'Full'){
                $variant=Request $privatePath $downloadHeaders $downloadMethod
                $rows.Add(@{Label='Actual authorized download variant';Variant=$DownloadVariant;Status=$variant.Status;Bytes=$variant.Bytes.Length;ContentLength=$variant.ContentLength;ContentRange=$variant.ContentRange;HasETag=[bool]$positive.ETag;HasLastModified=[bool]$positive.LastModified})
                $variantContract=Call 'PersonalChannelsFixture/ProductionServiceGate'
                $rows.Add(@{Label='Response contract after authorized download variant';Contract=$variantContract.LastResponseContract})
                if($DownloadVariant -eq 'Range'){
                    $prefix=[byte[]]([IO.File]::ReadAllBytes($subjects.a.SourcePath)[0..127])
                    if($variant.Status -ne 206 -or $variant.Bytes.Length -ne 128 -or $variant.ContentRange -ne "bytes 0-127/$($positive.Bytes.Length)" -or [Convert]::ToBase64String($variant.Bytes) -ne [Convert]::ToBase64String($prefix)){throw 'Authorized range does not return requested source bytes'}
                }elseif($DownloadVariant -eq 'Head'){
                    if($variant.Status -ne 200 -or $variant.Bytes.Length -ne 0 -or $variant.ContentLength -ne $positive.Bytes.Length){throw 'Authorized HEAD does not describe source without body'}
                }elseif($variant.Status -ne 304 -or $variant.Bytes.Length -ne 0){throw 'Authorized conditional download did not produce 304'}
                $foreignHeaders=$downloadHeaders.Clone();$foreignHeaders['X-Emby-Token']=$subjects.b.Headers['X-Emby-Token']
                $beforeVariant=Call 'PersonalChannelsFixture/ProductionServiceGate'
                $foreignVariant=Request $privatePath $foreignHeaders $downloadMethod
                $afterVariant=Call 'PersonalChannelsFixture/ProductionServiceGate'
                $entity=@($foreignVariant.HeaderNames|Where-Object {$_ -in @('Content-Disposition','Content-Range','ETag','Last-Modified','Accept-Ranges')})
                $rows.Add(@{Label='Foreign account download variant';Variant=$DownloadVariant;Status=$foreignVariant.Status;PrivateHeader=$foreignVariant.PrivateAHeader;EntityHeaderCount=$entity.Count;CheckedDelta=($afterVariant.Checked-$beforeVariant.Checked);DeniedDelta=($afterVariant.Denied-$beforeVariant.Denied)})
                if($foreignVariant.Status -ne 404 -or $foreignVariant.PrivateAHeader -or $foreignVariant.Text.Contains('PrivateNativeVideo_a_client') -or $entity.Count -or $afterVariant.Checked-$beforeVariant.Checked -ne 1 -or $afterVariant.Denied-$beforeVariant.Denied -ne 1){throw 'Foreign variant not privately denied by production prefix'}
            }
        }
        if($PlaybackWriteRace){
            $positive=Observe 'A private PlaybackInfo before timing probe' $privatePath $subjects.a.Headers 200
            if(-not $positive.Text.Contains('PrivateNativeVideo_a_client')){throw 'Private PlaybackInfo source not positively established'}
            $rows.Add(@{Label='A positive PlaybackInfo contains private video name';Present=$true})
        }
        Call $timingPath $admin Post @{OwnerUserId=$subjects.a.UserId;Playback=[bool]$PlaybackWriteRace;Download=[bool]$DownloadWriteRace}|Out-Null
        $requestMethod=if($DownloadWriteRace){$downloadMethod}else{'Get'}
        $requestHeaders=if($DownloadWriteRace){$downloadHeaders}else{$subjects.a.Headers}
        $message=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($requestMethod.ToUpperInvariant()),"$base/$privatePath")
        foreach($key in $requestHeaders.Keys){$message.Headers.TryAddWithoutValidation($key,[string]$requestHeaders[$key])|Out-Null}
        $message.Headers.TryAddWithoutValidation('X-Isolated-Reference-Gate','before-write')|Out-Null
        $pending=$client.SendAsync($message)
        try{
            $deadline=[DateTime]::UtcNow.AddSeconds(10)
            do{$pause=Call $timingPath;if($pause.Active){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
            if(-not $pause.Active -or $pending.IsCompleted){
                $rows.Add(@{Label='Native reference timing pause not reached';ResultContract=$pause.ResultContract;PendingCompleted=$pending.IsCompleted})
                throw 'Actual private reference write did not pause'
            }
            $rows.Add(@{Label='Actual reference result contract';ResultContract=$pause.ResultContract})
            $rows.Add(@{Label='Actual A reference writer paused before native write';Active=$true;HttpPending=$true;Family=$family})
            BPositive 'While A metadata paused'
            $deleted=Call 'YouTubePlugin/MyProfile/Delete' $subjects.a.Headers Post @{ExpectedRevision=$subjects.a.Profile.Revision}
            $pause=Call $timingPath
            if($deleted.State -ne 'Deleted' -or (Call 'YouTubePlugin/MyProfile' $subjects.a.Headers).State -ne 'Deleted' -or -not $pause.Active -or $pause.TimedOut -or $pending.IsCompleted){throw 'Deletion did not complete before metadata write release'}
            $rows.Add(@{Label='A profile deletion persisted before private metadata release';Deleted=$true;PauseStillActive=$true})
        }finally{Call $timingPath $admin Post @{Release=$true}|Out-Null}
        $response=$pending.GetAwaiter().GetResult()
        try{
            $bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            $text=if(-not $DownloadWriteRace -or [int]$response.StatusCode -ge 400){[Text.Encoding]::UTF8.GetString($bytes)}else{''}
            $safe=[int]$response.StatusCode -eq 404 -and -not $text.Contains('PrivateNativeVideo_a_client')
            $contentType=[string]$response.Content.Headers.ContentType
            $headerText=(@($response.Headers|ForEach-Object {$_.Key+':'+($_.Value -join ',')})+@($response.Content.Headers|ForEach-Object {$_.Key+':'+($_.Value -join ',')})) -join "`n"
            $headerPrivate=[Uri]::UnescapeDataString($headerText).Contains('PrivateNativeVideo_a_client')
            $safe=$safe -and -not $headerPrivate
            $sha=[Security.Cryptography.SHA256]::Create()
            try{$matchesA=[BitConverter]::ToString($sha.ComputeHash([byte[]]$bytes)).Replace('-','') -eq $subjects.a.SourceHash}finally{$sha.Dispose()}
            $entityHeaders=@('Content-Disposition','Content-Range','ETag','Last-Modified','Accept-Ranges')
            $responseHeaderNames=@($response.Headers|ForEach-Object {$_.Key})+@($response.Content.Headers|ForEach-Object {$_.Key})
            $retainedEntityHeaders=@($entityHeaders|Where-Object {$responseHeaderNames -contains $_})
            if($DownloadWriteRace){
                $expectedErrorLength=if($DownloadVariant -eq 'Head'){16}else{$bytes.Length}
                $safe=$safe -and -not $matchesA -and $contentType -match 'json|text' -and $retainedEntityHeaders.Count -eq 0 -and $response.Content.Headers.ContentLength -eq $expectedErrorLength
                if($DownloadVariant -eq 'Head'){$safe=$safe -and $bytes.Length -eq 0}
            }
            $rows.Add(@{Label='Private reference response after completed deletion';Status=[int]$response.StatusCode;PrivateNamePresent=$text.Contains('PrivateNativeVideo_a_client');HeaderPrivateNamePresent=$headerPrivate;IsolationPass=$safe;Family=$family;Bytes=$bytes.Length;MatchesASource=$matchesA;ContentType=$contentType;ContentLength=$response.Content.Headers.ContentLength;HasContentDisposition=($null -ne $response.Content.Headers.ContentDisposition);RetainedEntityHeaders=$retainedEntityHeaders})
            if($RequireRaceSafe -and -not $safe){throw 'Private metadata leaked after completed deletion'}
        }finally{$response.Dispose();$message.Dispose()}
        $writeAfter=Call 'PersonalChannelsFixture/ProductionItemList'
        $rows.Add(@{Label='Production write boundary handles private reference response';Installed=$writeAfter.Installed;WritesDelta=($writeAfter.Writes-$writeBefore.Writes);DeniedDelta=($writeAfter.WritesDenied-$writeBefore.WritesDenied)})
        if($RequireRaceSafe -and (-not $writeAfter.Installed -or $writeAfter.WritesDenied-$writeBefore.WritesDenied -ne 1)){throw 'Private response denial not accounted for by production write hook'}
        if($DownloadWriteRace -and $RequireRaceSafe){
            $exclusive=$false;$deadline=[DateTime]::UtcNow.AddSeconds(3)
            do{
                try{$handle=[IO.File]::Open($subjects.a.SourcePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None);try{$exclusive=$true}finally{$handle.Dispose()}}catch{Start-Sleep -Milliseconds 50}
            }while(-not $exclusive -and [DateTime]::UtcNow -lt $deadline)
            $rows.Add(@{Label='Rejected download leaves no source handle preventing exclusive read';ExclusiveReadOpened=$exclusive})
            if(-not $exclusive){throw 'Rejected writer retained native source handle'}
        }
    }else{$deleted=Call 'YouTubePlugin/MyProfile/Delete' $subjects.a.Headers Post @{ExpectedRevision=$subjects.a.Profile.Revision}}
    ForeignRoutes 'Deleted profile'
    Observe 'Deleted A cannot read retained native item' "Users/$($subjects.a.UserId)/Items/$($subjects.a.VideoId)" $subjects.a.Headers 404|Out-Null
    BPositive 'Deleted profile'
    $before=(Call 'PersonalChannelsFixture/Guard').BootId
    & $control -Stop|Out-Null;& $control|Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(40)
    do{try{$guard=Call 'PersonalChannelsFixture/Guard';if($guard.Ready -and $guard.BootId -ne $before){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    if(-not $guard.Ready -or $guard.BootId -eq $before){throw 'Production gate restart failed'}
    $state=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
    if($state.ExperimentalEnabled -or -not $state.Production.Installed){throw 'Restart did not restore production-only service enforcement'}
    $rows.Add(@{Label='Actual restart with production prefix and experimental guard disabled';RestartVerified=$true})
    ForeignRoutes 'After restart'
    BPositive 'After restart'
    $completed=$true
}finally{
    $report=if($DownloadWriteRace -and $DownloadVariant -ne 'Full'){'production-download-'+$DownloadVariant.ToLowerInvariant()+'-results.json'}elseif($DownloadWriteRace -and $RequireRaceSafe){'production-download-write-protected-results.json'}elseif($DownloadWriteRace){'production-download-write-race-results.json'}elseif($PlaybackWriteRace){'production-playback-info-write-results.json'}elseif($WriteRace -and $RequireRaceSafe){'production-service-write-protected-results.json'}elseif($WriteRace){'production-service-write-race-results.json'}else{'production-service-gate-results.json'}
    $scope=if($DownloadVariant -eq 'Head'){'Original ten service DTO cases with thirteen-DTO production gate installed; unsupported GetDownload HEAD across accounts/deletion/restart; no HEAD writer race claim'}else{'Original ten service DTO cases with thirteen-DTO production gate installed; optional actual private reference writer pause and profile deletion; download variant '+$DownloadVariant+'; no universal boundary claim'}
    @{Completed=$completed;Observations=$rows.ToArray();Scope=$scope}|ConvertTo-Json -Depth 9|Set-Content (Join-Path $PSScriptRoot ('bin/'+$report)) -Encoding UTF8
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
Write-Output ('Production-only service observations='+$rows.Count)
