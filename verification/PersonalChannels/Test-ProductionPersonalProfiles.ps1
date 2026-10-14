# Actual production service running in isolated Emby, ordinary accounts only.
. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
$profileRoot=Join-Path $root 'data/data/youtube-personal'
$stage='setup';$restarted=$false
if(Test-Path -LiteralPath $profileRoot){throw 'Production profile test requires an absent isolated profile directory'}
function ProfileCheck($label,$headers,$method='Get',$body=$null,$expected=200,$path='YouTubePlugin/MyProfile'){
    $r=Request $path $headers $method $body
    $rows.Add(@{Label=$label;Status=$r.Status;Expected=$expected;ContainsMarkerKey=$r.Text.Contains('synthetic-a-http-key') -or $r.Text.Contains('synthetic-b-http-key')})
    if($r.Status -ne $expected -or $rows[$rows.Count-1].ContainsMarkerKey){throw "Unexpected profile response: $label"}
    if($r.Status -notin @(401,404)){
        $rows[$rows.Count-1].NoStore=$r.CacheControl.Contains('no-store')
        if(-not $rows[$rows.Count-1].NoStore){throw 'Profile response permits caching'}
    }
    if($r.Status -eq 200){return $r.Text|ConvertFrom-Json}
}
function RawMessage($json){
    $message=[System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post,"$base/YouTubePlugin/MyProfile")
    $message.Headers.TryAddWithoutValidation('X-Emby-Token',[string]$subjects.a.Headers['X-Emby-Token'])|Out-Null
    $message.Content=[System.Net.Http.StringContent]::new($json,[Text.Encoding]::UTF8,'application/json')
    return $message
}
function RawCheck($label,$json,$expected){
    $message=RawMessage $json;$response=$null
    try{
        $response=$client.SendAsync($message).GetAwaiter().GetResult()
        $status=[int]$response.StatusCode
        $text=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $containsKey=$text.Contains('synthetic-a-http-key') -or $text.Contains('synthetic-b-http-key')
        $rows.Add(@{Label=$label;Status=$status;Expected=$expected;ContainsMarkerKey=$containsKey})
        if($status -ne $expected -or $containsKey){throw 'Invalid raw JSON profile response'}
    }finally{if($response){$response.Dispose()};$message.Dispose()}
}
try{
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1')|Out-Null
    $journal=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
    foreach($owner in @('a','b')){
        $u=@($journal.Users|Where-Object Owner -eq $owner)[0]
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Production profile test`", Device=`"Isolated`", DeviceId=`"production-profile-$owner`", Version=`"1.0`""} Post @{Username=$u.Name;Pw=''}
        if($login.User.Id -ne $u.UserId -or $login.User.Policy.IsAdministrator){throw 'Wrong ordinary profile account'}
        $subjects[$owner]=@{UserId=$u.UserId;Headers=@{'X-Emby-Token'=$login.AccessToken}}
        $view=ProfileCheck "$owner absent" $subjects[$owner].Headers
        if($view.OwnerUserId.Replace('-','') -ne $u.UserId -or $view.State -ne 'Absent' -or $view.Revision -ne 0){throw 'Absent profile not scoped to actual owner'}
    }
    ProfileCheck 'Anonymous GET' @{} Get $null 401|Out-Null
    ProfileCheck 'Anonymous save' @{} Post @{ExpectedRevision=0;Channels=@()} 401|Out-Null
    $stage='own saves'
    $channel='UC'+('a'*22)
    $a=ProfileCheck 'A saves own key/channel' $subjects.a.Headers Post @{ExpectedRevision=0;Channels=@($channel);ApiKey='synthetic-a-http-key'}
    $b=ProfileCheck 'B saves same channel with own key' $subjects.b.Headers Post @{ExpectedRevision=0;Channels=@($channel);ApiKey='synthetic-b-http-key'}
    if(-not $a.HasApiKey -or -not $b.HasApiKey -or $a.CollectionId -eq $b.CollectionId -or $a.GenerationId -eq $b.GenerationId){throw 'Owners merged in production service'}
    $aFile=Join-Path $profileRoot ($subjects.a.UserId+'.json');$bFile=Join-Path $profileRoot ($subjects.b.UserId+'.json')
    $aHash=(Get-FileHash $aFile).Hash;$bHash=(Get-FileHash $bFile).Hash
    if((Get-Content $aFile -Raw).Contains('synthetic-a-http-key') -or (Get-Content $bFile -Raw).Contains('synthetic-b-http-key')){throw 'Production persisted plaintext key'}
    $stage='corrupt owner isolation'
    $aOriginal=Get-Content -LiteralPath $aFile -Raw
    try{
        [IO.File]::WriteAllText($aFile,'{')
        ProfileCheck 'Corrupt A profile returns sanitized unavailable response' $subjects.a.Headers Get $null 503|Out-Null
        $errorResponse=Request 'YouTubePlugin/MyProfile' $subjects.a.Headers
        $errorBody=$errorResponse.Text|ConvertFrom-Json
        if($errorBody.ErrorCode -ne 'ProfileUnavailable' -or $errorBody.Message -ne 'Personal profile storage unavailable.' -or $errorResponse.Text.Contains($profileRoot)){throw 'Corrupt-profile response exposed internal storage details'}
        $healthyB=ProfileCheck 'B profile remains available while A is corrupt' $subjects.b.Headers
        if($healthyB.CollectionId -ne $b.CollectionId -or $healthyB.Revision -ne $b.Revision -or $bHash -ne (Get-FileHash $bFile).Hash){throw 'A corruption changed B profile'}
    }finally{[IO.File]::WriteAllText($aFile,$aOriginal)}
    $stage='forged identity and invalid updates'
    $forged=ProfileCheck 'GET supplied B identity still reads authenticated A' $subjects.a.Headers Get $null 200 ("YouTubePlugin/MyProfile?UserId="+$subjects.b.UserId)
    if($forged.OwnerUserId -ne $a.OwnerUserId -or $forged.CollectionId -ne $a.CollectionId){throw 'Query identity replaced authenticated owner'}
    ProfileCheck 'A supplied foreign profile path' $subjects.a.Headers Get $null 404 ("YouTubePlugin/MyProfile/"+$subjects.b.UserId)|Out-Null
    ProfileCheck 'A forged body owner rejected' $subjects.a.Headers Post @{ExpectedRevision=$a.Revision;Channels=@();OwnerUserId=$subjects.b.UserId} 400|Out-Null
    ProfileCheck 'A stale save rejected' $subjects.a.Headers Post @{ExpectedRevision=0;Channels=@();ClearApiKey=$true} 409|Out-Null
    ProfileCheck 'A invalid channel rejected' $subjects.a.Headers Post @{ExpectedRevision=$a.Revision;Channels=@('../other')} 400|Out-Null
    ProfileCheck 'A missing revision rejected' $subjects.a.Headers Post @{Channels=@()} 400|Out-Null
    RawCheck 'Duplicate JSON identity-independent revision rejected' '{"ExpectedRevision":1,"expectedRevision":0,"Channels":[]}' 400
    RawCheck 'Malformed JSON rejected' '{' 400
    RawCheck 'Oversized body rejected' ('{"ExpectedRevision":1,"Channels":[],"padding":"'+('x'*33000)+'"}') 413
    if($aHash -ne (Get-FileHash $aFile).Hash -or $bHash -ne (Get-FileHash $bFile).Hash){throw 'Rejected mutation changed a production profile'}
    $stage='concurrent native HTTP saves'
    $pending=[Collections.Generic.List[object]]::new()
    $payload=@{ExpectedRevision=$a.Revision;Channels=@($channel)}|ConvertTo-Json -Depth 4
    try{
        foreach($index in 1..12){$message=RawMessage $payload;$pending.Add(@{Message=$message;Task=$client.SendAsync($message)})}
        $wins=0;$conflicts=0
        foreach($entry in $pending){
            $response=$entry.Task.GetAwaiter().GetResult()
            try{
                $status=[int]$response.StatusCode
                $body=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                if($status -eq 200){$wins++}elseif($status -eq 409){$conflicts++}else{throw 'Unexpected concurrent profile HTTP status'}
                $containsKey=$body.Contains('synthetic-a-http-key') -or $body.Contains('synthetic-b-http-key')
                $rows.Add(@{Label='Concurrent A same-revision save';Status=$status;ContainsMarkerKey=$containsKey})
                if($containsKey){throw 'Concurrent profile response exposed key'}
            }finally{$response.Dispose()}
        }
        if($wins -ne 1 -or $conflicts -ne 11 -or $bHash -ne (Get-FileHash $bFile).Hash){throw 'Concurrent HTTP update failed atomic revision/B isolation'}
    }finally{foreach($entry in $pending){$entry.Message.Dispose()}}
    $a=ProfileCheck 'A current after concurrent saves' $subjects.a.Headers
    if($a.Revision -ne 2){throw 'Concurrent profile revision incorrect'}
    $stage='restart'
    $boot=(Call 'PersonalChannelsFixture/Guard').BootId
    & $control -Stop|Out-Null
    & $control|Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(30);$ready=$null
    do{try{$ready=Call 'PersonalChannelsFixture/Guard';if($ready.Ready -and $ready.Enabled -and $ready.BootId -ne $boot){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    $restarted=$ready.Ready -and $ready.Enabled -and $ready.BootId -ne $boot
    if(-not $restarted){throw 'Production profile restart not confirmed'}
    foreach($owner in @('a','b')){
        $view=ProfileCheck "$owner profile after restart" $subjects[$owner].Headers
        $before=if($owner -eq 'a'){$a}else{$b}
        if($view.GenerationId -ne $before.GenerationId -or $view.Revision -ne $before.Revision -or -not $view.HasApiKey){throw 'Production profile failed restart recovery'}
    }
    $stage='delete and recreate'
    ProfileCheck 'Anonymous deletion rejected' @{} Post @{ExpectedRevision=$a.Revision} 401 'YouTubePlugin/MyProfile/Delete'|Out-Null
    ProfileCheck 'A forged deletion owner rejected' $subjects.a.Headers Post @{ExpectedRevision=$a.Revision;OwnerUserId=$subjects.b.UserId} 400 'YouTubePlugin/MyProfile/Delete'|Out-Null
    $deleted=ProfileCheck 'A deletes own generation' $subjects.a.Headers Post @{ExpectedRevision=$a.Revision} 200 'YouTubePlugin/MyProfile/Delete'
    if($deleted.State -ne 'Deleted' -or $deleted.HasApiKey -or $deleted.Channels.Count -ne 0){throw 'Deleted production profile remained active'}
    $newA=ProfileCheck 'A recreates own generation' $subjects.a.Headers Post @{ExpectedRevision=$deleted.Revision;Channels=@($channel)}
    if($newA.CollectionId -ne $a.CollectionId -or $newA.GenerationId -eq $a.GenerationId -or $newA.HasApiKey){throw 'Production generation revived old identity/key'}
    $bFinal=ProfileCheck 'B profile survives A lifecycle' $subjects.b.Headers
    if($bFinal.GenerationId -ne $b.GenerationId -or -not $bFinal.HasApiKey -or $bHash -ne (Get-FileHash $bFile).Hash){throw 'A lifecycle changed B'}
    $completed=$true
}finally{
    @{Completed=$completed;LastStage=$stage;RestartVerified=$restarted;ConcurrentWinners=$wins;ConcurrentConflicts=$conflicts;Observations=$rows.ToArray();Scope='Actual production profile routes, ordinary A/B/anonymous, identity forgery, malformed/oversized JSON, concurrent stale writes and generation lifecycle; no native media publication'}|ConvertTo-Json -Depth 9|Set-Content (Join-Path $PSScriptRoot 'bin/production-profile-service-results.json') -Encoding UTF8
    try{
        & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null
        foreach($owner in @('a','b')){
            if($subjects[$owner]){
                $path=[IO.Path]::GetFullPath((Join-Path $profileRoot ($subjects[$owner].UserId+'.json')))
                if(-not $path.StartsWith([IO.Path]::GetFullPath($profileRoot)+[IO.Path]::DirectorySeparatorChar)){throw 'Unsafe profile cleanup'}
                Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
            }
        }
        $remaining=@(Get-ChildItem -LiteralPath $profileRoot -File -ErrorAction SilentlyContinue|Where-Object Name -ne 'encryption.key')
        if($remaining.Count){throw 'Unexpected profile file remaining; cleanup retained'}
        $keyPath=[IO.Path]::GetFullPath((Join-Path $profileRoot 'encryption.key'))
        $allowed=[IO.Path]::GetFullPath($root)+[IO.Path]::DirectorySeparatorChar
        if(-not $keyPath.StartsWith($allowed)){throw 'Unsafe key cleanup'}
        Remove-Item -LiteralPath $keyPath -ErrorAction SilentlyContinue
        if(Test-Path -LiteralPath $profileRoot){Remove-Item -LiteralPath $profileRoot}
    }finally{$client.Dispose()}
}
Write-Output ('Production profile HTTP controls='+$rows.Count)
