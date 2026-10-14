. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
$profileRoot=Join-Path $root 'data/data/youtube-personal'
if(Test-Path $profileRoot){throw 'Hook-loss test requires absent isolated profiles'}
function AssertState($label,$ok){$rows.Add(@{Label=$label;Pass=[bool]$ok});if(-not $ok){throw $label}}
function PositiveB($phase){
    Check "$phase B own metadata" "Users/$($subjects.b.UserId)/Items/$($subjects.b.VideoId)" $subjects.b.Headers 200|Out-Null
    Check "$phase B own download" "Items/$($subjects.b.VideoId)/Download" $subjects.b.Headers 200 'b'|Out-Null
}
try{
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1')|Out-Null
    $fixture=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
    $a=@($fixture.Users|Where-Object Owner -eq 'a')[0]
    $b=@($fixture.Users|Where-Object Owner -eq 'b')[0];$lib=@($fixture.Libraries|Where-Object Owner -eq 'b')[0]
    $login=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="Hook loss test", Device="Isolated", DeviceId="hook-loss-b", Version="1"'} Post @{Username=$b.Name;Pw=''}
    $subjects.b=@{UserId=$b.UserId;VideoId=$lib.VideoId;Headers=@{'X-Emby-Token'=$login.AccessToken};SourceHash=(Get-FileHash (Join-Path $lib.Folder 'PrivateNativeVideo_b_client.mp4')).Hash}
    $state=Call 'PersonalChannelsFixture/ProductionCreationGuard'
    AssertState 'Production prefix is verified before removal' ($state.Installed -and $state.ContractMatched)
    AssertState 'Native creation availability requires actual prefix' (Call 'PersonalChannelsFixture/ProductionCreationGuard' $admin Post @{}).Available
    PositiveB 'Before prefix loss'
    $removed=Call 'PersonalChannelsFixture/ProductionCreationGuard' $admin Post @{RemovePrefix=$true;OwnerUserId=$a.UserId}
    AssertState 'Removing only production prefix makes requirement fail' (-not $removed.Available)
    $state=Call 'PersonalChannelsFixture/ProductionCreationGuard'
    AssertState 'Status detects actual lost prefix' (-not $state.Installed -and $state.Error -eq 'PatchLost')
    $name='JournalPending_'+[Guid]::NewGuid().ToString('N')
    $failed=Request 'PersonalChannelsFixture/NativeContextCreate' $admin Post @{OwnerUserId=$a.UserId;Name=$name}
    AssertState 'Native creation request fails with guard missing' ($failed.Status -ge 400)
    AssertState 'Failed guarded call created no native root' (-not (Call ('PersonalChannelsFixture/NewRootIdentity?Name='+$name)).Exists)
    AssertState 'Failed guarded call created no private profile or journal directory' (-not (Test-Path $profileRoot))
    PositiveB 'After prefix loss'
    $before=(Call 'PersonalChannelsFixture/Guard').BootId
    & $control -Stop|Out-Null;& $control|Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(40)
    do{try{$ready=Call 'PersonalChannelsFixture/Guard';if($ready.Ready -and $ready.BootId -ne $before){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    AssertState 'Actual server restart completed' ($ready.Ready -and $ready.BootId -ne $before)
    $state=Call 'PersonalChannelsFixture/ProductionCreationGuard'
    AssertState 'Production prefix reinstalls at actual restart' ($state.Installed -and $state.ContractMatched)
    AssertState 'Actual prefix requirement succeeds after restart' (Call 'PersonalChannelsFixture/ProductionCreationGuard' $admin Post @{}).Available
    PositiveB 'After restart'
    $completed=$true
}finally{
    @{Completed=$completed;Observations=$rows.ToArray();Scope='Actual production prefix loss, creation refusal before profile/native mutation, unaffected B native file, actual restart'}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'bin/native-creation-hook-loss-results.json') -Encoding UTF8
    try{& (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null}finally{$client.Dispose()}
}
Write-Output ('Native creation hook loss observations='+$rows.Count)
