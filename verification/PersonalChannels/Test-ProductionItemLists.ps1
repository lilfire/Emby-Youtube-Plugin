param([switch]$InventoryRace,[switch]$RequireRaceSafe,[switch]$ResultRace,[switch]$WriteRace,[switch]$AfterWriteCheckRace)
. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
$profileRoot=Join-Path $root 'data/data/youtube-personal'
$nativeEmptyPageTotal=$null
if(Test-Path $profileRoot){throw 'List test requires absent isolated profiles'}
function ListCheck($label,$path,$actor,$total,$size){
    $r=Request $path $subjects[$actor].Headers
    if($r.Status -ne 200){throw "List HTTP $($r.Status): $label"}
    $list=$r.Text|ConvertFrom-Json
    $foreign=if($actor -eq 'a'){'PrivateNativeVideo_b_client'}else{'PrivateNativeVideo_a_client'}
    $rows.Add(@{Label=$label;Status=$r.Status;Total=$list.TotalRecordCount;Size=@($list.Items).Count;ExpectedTotal=$total;ExpectedSize=$size;ForeignNamePresent=$r.Text.Contains($foreign)})
    if($list.TotalRecordCount -ne $total -or @($list.Items).Count -ne $size -or $r.Text.Contains($foreign)){throw "Wrong filtered count/page: $label"}
}
function Lists($phase,$aCount){
    foreach($actor in @('a','b')){
        $count=if($actor -eq 'a'){$aCount}else{1}
        $other=if($actor -eq 'a'){'b'}else{'a'}
        $baseQuery='Recursive=true&IncludeItemTypes=Video&EnableTotalRecordCount=true'
        ListCheck "$phase $actor own complete list" "Items?UserId=$($subjects[$actor].UserId)&$baseQuery" $actor $count $count
        ListCheck "$phase $actor first page" "Items?UserId=$($subjects[$actor].UserId)&$baseQuery&StartIndex=0&Limit=1" $actor $count $count
        $emptyTotal=if($count -eq 1){$nativeEmptyPageTotal}else{0}
        ListCheck "$phase $actor page past end" "Items?UserId=$($subjects[$actor].UserId)&$baseQuery&StartIndex=1&Limit=1" $actor $emptyTotal 0
        ListCheck "$phase $actor forged query subject" "Items?UserId=$($subjects[$other].UserId)&$baseQuery" $actor $count $count
        ListCheck "$phase $actor forged path subject" "Users/$($subjects[$other].UserId)/Items?$baseQuery" $actor $count $count
    }
}
try{
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1')|Out-Null
    $fixture=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
    $baselineUser=@($fixture.Users|Where-Object Owner -eq 'a')[0]
    $baselineLogin=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="Native list baseline", Device="Isolated", DeviceId="list-baseline", Version="1"'} Post @{Username=$baselineUser.Name;Pw=''}
    $baselineHeaders=@{'X-Emby-Token'=$baselineLogin.AccessToken}
    Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}|Out-Null
    $disabled=Call 'PersonalChannelsFixture/ProductionItemList' $admin Post @{RemoveForNativeBaseline=$true}
    if($disabled.Installed -or $disabled.Error -ne 'PatchLost'){throw 'Native baseline did not remove actual production list hooks'}
    $native=Call "Items?UserId=$($baselineUser.UserId)&Recursive=true&IncludeItemTypes=Video&EnableTotalRecordCount=true&StartIndex=1&Limit=1" $baselineHeaders
    if(@($native.Items).Count -ne 0){throw 'Native baseline page is not empty'}
    $nativeEmptyPageTotal=[int]$native.TotalRecordCount
    $rows.Add(@{Label='Actual native empty-page count without production/experimental list hooks';Total=$nativeEmptyPageTotal;Size=0;ProductionListInstalled=$false;ExperimentalEnabled=$false})
    $normal=Call "Items?UserId=$($baselineUser.UserId)&Recursive=true&IncludeItemTypes=Video&EnableTotalRecordCount=true" $baselineHeaders
    if($normal.TotalRecordCount -ne 1 -or @($normal.Items).Count -ne 1 -or $normal.Items[0].Name -ne 'PrivateNativeVideo_a_client'){throw 'Native baseline source not positively established'}
    $rows.Add(@{Label='Actual native baseline own full list';Total=1;Size=1})
    & $control -Stop|Out-Null;& $control|Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(40)
    do{try{$ready=Call 'PersonalChannelsFixture/Guard';if($ready.Ready){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    if(-not $ready.Ready -or -not (Call 'PersonalChannelsFixture/ProductionItemList').Installed){throw 'List hooks not restored after native baseline restart'}
    foreach($actor in @('a','b')){
        $u=@($fixture.Users|Where-Object Owner -eq $actor)[0];$lib=@($fixture.Libraries|Where-Object Owner -eq $actor)[0]
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Production lists`", Device=`"Isolated`", DeviceId=`"lists-$actor`", Version=`"1`""} Post @{Username=$u.Name;Pw=''}
        if($login.User.Policy.IsAdministrator){throw 'Wrong test token'}
        $subjects[$actor]=@{UserId=$u.UserId;Headers=@{'X-Emby-Token'=$login.AccessToken}}
        $subjects[$actor].Profile=Call 'YouTubePlugin/MyProfile' $subjects[$actor].Headers Post @{ExpectedRevision=0;Channels=@('UC'+('a'*22))}
        $bound=Call 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{RootKey=[long]$lib.LibraryId;OwnerUserId=$u.UserId}
        if(-not $bound.Registered){throw 'Native binding absent'}
        $policy=(Call "Users/$($u.UserId)").Policy;$policy.EnableAllFolders=$true
        Call "Users/$($u.UserId)/Policy" $admin Post $policy|Out-Null
        if(-not (Call "Users/$($u.UserId)").Policy.EnableAllFolders){throw 'Native all-library access not enabled'}
        $rows.Add(@{Label="$actor native policy allows all libraries";EnableAllFolders=$true})
    }
    $state=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
    $installed=Call 'PersonalChannelsFixture/ProductionItemList'
    if($state.ExperimentalEnabled -or -not $installed.Installed){throw 'Production-only list test not ready'}
    $rows.Add(@{Label='Production query gate installed with experimental guard off';Installed=$true;ExperimentalEnabled=$false})
    Lists 'Active' 1
    if($InventoryRace -or $ResultRace -or $WriteRace -or $AfterWriteCheckRace){
        $timingPath=if($WriteRace -or $AfterWriteCheckRace){'PersonalChannelsFixture/NativeListWriteGate'}elseif($ResultRace){'PersonalChannelsFixture/NativeListResultGate'}else{'PersonalChannelsFixture/NativeListInventoryGate'}
        Call $timingPath $admin Post @{OwnerUserId=$subjects.a.UserId;AfterCheck=[bool]$AfterWriteCheckRace}|Out-Null
        $message=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,"$base/Items?UserId=$($subjects.a.UserId)&Recursive=true&IncludeItemTypes=Video&EnableTotalRecordCount=true")
        foreach($key in $subjects.a.Headers.Keys){$message.Headers.TryAddWithoutValidation($key,[string]$subjects.a.Headers[$key])|Out-Null}
        $message.Headers.TryAddWithoutValidation('X-Isolated-List-Gate','after-inventory')|Out-Null
        $pending=$client.SendAsync($message)
        $deletionPending=$null;$deleteMessage=$null
        try{
            $deadline=[DateTime]::UtcNow.AddSeconds(10)
            do{$pause=Call $timingPath;if($pause.Active){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
            if(-not $pause.Active -or $pending.IsCompleted){throw 'Native list did not reach the requested timing pause'}
            $pauseLabel=if($AfterWriteCheckRace){'Actual A list paused after production write permission check'}elseif($WriteRace){'Actual A list paused at native WriteToAsync after result checks'}elseif($ResultRace){'Actual A list paused after native task completed before result wrapper'}else{'Actual A list paused after inventory before native service'}
            $rows.Add(@{Label=$pauseLabel;Active=$true;HttpPending=$true})
            if($ResultRace){
                if(-not $pause.NativeTaskCompleted){throw 'Native result task was not completed at pause'}
                $rows.Add(@{Label='Actual native result completed before deletion and production wrapper';NativeTaskCompleted=$true;ResultType=$pause.ResultType})
            }
            ListCheck 'B own list while A paused' "Items?UserId=$($subjects.b.UserId)&Recursive=true&IncludeItemTypes=Video&EnableTotalRecordCount=true" 'b' 1 1
            if($AfterWriteCheckRace -and $RequireRaceSafe){
                if(-not $pause.AfterCheck){throw 'Timing hook is not after production write check'}
                $deleteMessage=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,"$base/YouTubePlugin/MyProfile/Delete")
                foreach($key in $subjects.a.Headers.Keys){$deleteMessage.Headers.TryAddWithoutValidation($key,[string]$subjects.a.Headers[$key])|Out-Null}
                $deleteMessage.Content=[Net.Http.StringContent]::new((@{ExpectedRevision=$subjects.a.Profile.Revision}|ConvertTo-Json),[Text.Encoding]::UTF8,'application/json')
                $deletionPending=$client.SendAsync($deleteMessage)
                $deadline=[DateTime]::UtcNow.AddSeconds(5)
                do{$lease=Call "PersonalChannelsFixture/TransferLease?OwnerUserId=$($subjects.a.UserId)";if($lease.Waiting -ge 1){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
                $readback=Call 'YouTubePlugin/MyProfile' $subjects.a.Headers
                if(-not $lease.Held -or $lease.Waiting -lt 1 -or $deletionPending.IsCompleted -or $readback.State -ne 'Draft'){throw 'Deletion did not wait at actual owner lease'}
                $rows.Add(@{Label='Deletion reached owner gate while native writer held lease';Held=$lease.Held;Waiting=$lease.Waiting;DeleteHttpPending=$true;PersistedState=$readback.State})
                $savedB=Call 'YouTubePlugin/MyProfile' $subjects.b.Headers Post @{ExpectedRevision=$subjects.b.Profile.Revision;Channels=@('UC'+('b'*22))}
                if($savedB.Revision -ne $subjects.b.Profile.Revision+1){throw 'Other owner save blocked or failed'}
                $rows.Add(@{Label='B profile mutation succeeds while A deletion waits';RevisionAdvanced=$true})
            }else{
                $deleted=Call 'YouTubePlugin/MyProfile/Delete' $subjects.a.Headers Post @{ExpectedRevision=$subjects.a.Profile.Revision}
                if($deleted.State -ne 'Deleted' -or (Call 'YouTubePlugin/MyProfile' $subjects.a.Headers).State -ne 'Deleted'){throw 'A profile deletion not persisted before list release'}
            }
            $pause=Call $timingPath
            if(-not $pause.Active -or $pause.TimedOut -or $pending.IsCompleted){throw 'List pause did not remain active through profile deletion'}
            $rows.Add(@{Label='A mutation state while list request held';Deleted=($null -eq $deletionPending);PauseStillActive=$true;DeletionWaiting=($null -ne $deletionPending)})
        }finally{Call $timingPath $admin Post @{Release=$true}|Out-Null}
        $response=$pending.GetAwaiter().GetResult()
        try{
            $text=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $result=if([int]$response.StatusCode -eq 200){$text|ConvertFrom-Json}else{$null}
            $safe=if($null -ne $deletionPending){[int]$response.StatusCode -eq 200 -and $result.TotalRecordCount -eq 1 -and @($result.Items).Count -eq 1 -and $text.Contains('PrivateNativeVideo_a_client') -and -not $text.Contains('PrivateNativeVideo_b_client')}else{([int]$response.StatusCode -eq 404 -or ([int]$response.StatusCode -eq 200 -and $result.TotalRecordCount -eq 0 -and @($result.Items).Count -eq 0)) -and -not $text.Contains('PrivateNativeVideo_a_client')}
            $resultSize=if($null -eq $result){0}else{@($result.Items).Count}
            $responseLabel=if($null -ne $deletionPending){'Authorized list whose native write held the lease before mutation'}else{'Previously authorized list after completed deletion'}
            $rows.Add(@{Label=$responseLabel;Status=[int]$response.StatusCode;Total=$result.TotalRecordCount;Size=$resultSize;PrivateNamePresent=$text.Contains('PrivateNativeVideo_a_client');IsolationPass=$safe})
            if($RequireRaceSafe -and -not $safe){throw 'Held list response leaked revoked A content'}
        }finally{$response.Dispose();$message.Dispose()}
        if($null -ne $deletionPending){
            $deleteResponse=$deletionPending.GetAwaiter().GetResult()
            try{
                $deleted=$deleteResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json
                $lease=Call "PersonalChannelsFixture/TransferLease?OwnerUserId=$($subjects.a.UserId)"
                if([int]$deleteResponse.StatusCode -ne 200 -or $deleted.State -ne 'Deleted' -or (Call 'YouTubePlugin/MyProfile' $subjects.a.Headers).State -ne 'Deleted' -or $lease.Held -or $lease.Waiting){throw 'Queued deletion did not finish after native write release'}
                $rows.Add(@{Label='Queued deletion persisted after native write lease released';Status=[int]$deleteResponse.StatusCode;State=$deleted.State;Held=$lease.Held;Waiting=$lease.Waiting})
            }finally{$deleteResponse.Dispose();$deleteMessage.Dispose()}
        }
        if($WriteRace){
            $writeState=Call 'PersonalChannelsFixture/ProductionItemList'
            $rows.Add(@{Label='Production native write prefix executed';Installed=$writeState.Installed;Writes=$writeState.Writes;WritesDenied=$writeState.WritesDenied})
            if($RequireRaceSafe -and (-not $writeState.Installed -or $writeState.WritesDenied -lt 1)){throw 'Production native write denial was not observed'}
        }
    }else{$deleted=Call 'YouTubePlugin/MyProfile/Delete' $subjects.a.Headers Post @{ExpectedRevision=$subjects.a.Profile.Revision}}
    Lists 'Deleted A profile' 0
    $before=(Call 'PersonalChannelsFixture/Guard').BootId
    & $control -Stop|Out-Null;& $control|Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(40)
    do{try{$guard=Call 'PersonalChannelsFixture/Guard';if($guard.Ready -and $guard.BootId -ne $before){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    if(-not $guard.Ready -or $guard.BootId -eq $before){throw 'List restart failed'}
    $state=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
    $installed=Call 'PersonalChannelsFixture/ProductionItemList'
    if($state.ExperimentalEnabled -or -not $installed.Installed){throw 'Production-only list gate not restored'}
    $rows.Add(@{Label='Actual restart and experimental guard off';RestartVerified=$true})
    Lists 'After restart' 0
    $state=Call 'PersonalChannelsFixture/ProductionItemList'
    $rows.Add(@{Label='Production scope and native query prefixes executed';Requests=$state.Requests;Queries=$state.Queries;Writes=$state.Writes;WritesDenied=$state.WritesDenied})
    if($state.Requests -lt 10 -or $state.Queries -lt 10){throw 'Native query hooks not observed'}
    $completed=$true
}finally{
    $report=if($AfterWriteCheckRace -and $RequireRaceSafe){'production-item-list-write-lease-results.json'}elseif($AfterWriteCheckRace){'production-item-list-after-write-check-race-results.json'}elseif($WriteRace -and $RequireRaceSafe){'production-item-list-write-protected-results.json'}elseif($WriteRace){'production-item-list-write-race-results.json'}elseif($ResultRace -and $RequireRaceSafe){'production-item-list-result-protected-results.json'}elseif($ResultRace){'production-item-list-result-race-results.json'}elseif($RequireRaceSafe){'production-item-list-revocation-protected-results.json'}elseif($InventoryRace){'production-item-list-revocation-race-results.json'}else{'production-item-list-results.json'}
    @{Completed=$completed;Observations=$rows.ToArray();Scope='GetItems counts/paging; optional inventory/result/native-write pause with profile deletion; no universal revocation claim'}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot ('bin/'+$report)) -Encoding UTF8
    try{
        & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null
        if(Test-Path $profileRoot){
            $dir=[IO.Path]::GetFullPath($profileRoot);$expected=[IO.Path]::GetFullPath((Join-Path $root 'data/data/youtube-personal'))
            if($dir -ne $expected -or -not $dir.StartsWith([IO.Path]::GetFullPath($root)+[IO.Path]::DirectorySeparatorChar)){throw 'Unsafe profile cleanup'}
            $names=@('encryption.key','native-reference-bindings.json','native-reference-bindings.required','private-source-scopes.json','private-source-scopes.required')+@($subjects.Values|ForEach-Object{$_.UserId+'.json'})
            $files=@(Get-ChildItem -LiteralPath $dir -Force)
            if(@($files|Where-Object {$_.PSIsContainer -or $_.Name -notin $names -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)}).Count){throw 'Unexpected private files'}
            foreach($file in $files){Remove-Item -LiteralPath $file.FullName};Remove-Item -LiteralPath $dir
        }
    }finally{$client.Dispose()}
}
Write-Output ('Production-only item list observations='+$rows.Count)
