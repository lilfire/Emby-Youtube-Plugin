param([ValidateSet('Start','StartAdmin','StopAdmin','SeedQuota','RecordAdmin','Record','Reload','Stop')][string]$Action='Record')
. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
$profileRoot=[IO.Path]::GetFullPath((Join-Path $root 'data/data/youtube-personal'))
$browserStatePath=Join-Path $PSScriptRoot 'bin/alpha-browser-state.json'
$nativeStatePath=Join-Path $PSScriptRoot 'bin/native-client-state.json'
function RecordAlphaLibrary($state){
    $profile=Call 'YouTubePlugin/MyProfile' @{'X-Emby-Token'=$state.Token}
    if(-not $profile.Revision){return}
    $native=Get-Content -LiteralPath $nativeStatePath -Raw|ConvertFrom-Json
    $media=Join-Path $profileRoot ('media/'+$state.UserId+'/'+$profile.CollectionId.Replace('-','')+'/'+$profile.GenerationId.Replace('-',''))
    if(-not @($native.Libraries|Where-Object Folder -eq $media).Count){
        $name='YouTube '+$profile.GenerationId.Replace('-','')
        $job=Call 'YouTubePlugin/MyJob' @{'X-Emby-Token'=$state.Token}
        $native.Libraries+=@(@{Owner='alpha-browser';Name=$name;PlannedRenameName=$name;Folder=$media;LibraryId=if($job.LibraryId){[string]$job.LibraryId}else{''}})
        $native|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $nativeStatePath -Encoding UTF8
    }
    Write-Output ('Alpha UI profile state='+$profile.State+'; revision='+$profile.Revision)
}
try{
    if($Action -eq 'Start'){
        if((Test-Path -LiteralPath $browserStatePath) -or (Test-Path -LiteralPath $profileRoot)){throw 'Inspect existing browser fixture before starting another'}
        & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1')|Out-Null
        $native=Get-Content -LiteralPath $nativeStatePath -Raw|ConvertFrom-Json
        $user=@($native.Users|Where-Object Owner -eq 'a')[0]
        $session=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="Alpha browser setup", Device="Isolated", DeviceId="alpha-browser-setup", Version="1"'} Post @{Username=$user.Name;Pw=''}
        if($session.User.Id -ne $user.UserId -or $session.User.Policy.IsAdministrator){throw 'Wrong browser fixture account'}
        $state=@{UserId=$user.UserId;Name=$user.Name;Token=$session.AccessToken;WorkerStarted=$false}
        $state|ConvertTo-Json|Set-Content -LiteralPath $browserStatePath -Encoding UTF8
        $mode=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
        if($mode.ExperimentalEnabled -or -not $mode.Production.Installed){throw 'Production controls unavailable'}
        # Seed a dummy key through HTTP before runtime start. The browser never
        # enters a genuine credential; saving blank retains only this test key.
        Call 'YouTubePlugin/MyProfile' @{'X-Emby-Token'=$state.Token} Post @{ExpectedRevision=0;Channels=@();ApiKey='synthetic-alpha-personal-key'}|Out-Null
        $started=Call 'PersonalChannelsFixture/PersonalJobs' $admin Post @{}
        if(-not $started.Started){throw 'Browser worker failed to start'}
        $state.WorkerStarted=$true;$state|ConvertTo-Json|Set-Content -LiteralPath $browserStatePath -Encoding UTF8
        RecordAlphaLibrary $state
        Write-Output ('Browser fixture ready: http://127.0.0.1:18096; ordinary account '+$state.Name)
    }elseif($Action -eq 'StopAdmin'){
        $state=Get-Content -LiteralPath $browserStatePath -Raw|ConvertFrom-Json
        if($state.AdminUserId){
            $user=Call ('Users/'+$state.AdminUserId)
            if($user.Name -ne 'closed-alpha-ui-admin' -or -not $user.Policy.IsAdministrator){throw 'Unexpected UI administrator cleanup identity'}
            Call ('Users/'+$state.AdminUserId) $admin Delete|Out-Null
            if(@((Call 'Users')|Where-Object Id -eq $state.AdminUserId).Count){throw 'UI administrator cleanup failed readback'}
            $state.PSObject.Properties.Remove('AdminUserId')
            $state|ConvertTo-Json|Set-Content -LiteralPath $browserStatePath -Encoding UTF8
        }
        Write-Output 'Disposable UI administrator removed; ordinary playback fixture retained.'
    }elseif($Action -eq 'SeedQuota'){
        $state=Get-Content -LiteralPath $browserStatePath -Raw|ConvertFrom-Json
        $native=Get-Content -LiteralPath $nativeStatePath -Raw|ConvertFrom-Json
        $user=@($native.Users|Where-Object Owner -eq 'b')[0]
        $session=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="Alpha quota UI", Device="Isolated", DeviceId="alpha-quota-ui", Version="1"'} Post @{Username=$user.Name;Pw=''}
        if($session.User.Id -ne $user.UserId -or $session.User.Policy.IsAdministrator){throw 'Wrong quota test identity'}
        $headers=@{'X-Emby-Token'=$session.AccessToken}
        $profile=Call 'YouTubePlugin/MyProfile' $headers
        if($profile.Revision -ne 0 -and ($state.QuotaUserId -ne $user.UserId -or -not $profile.HasApiKey -or $profile.Channels.Count -ne 1 -or $profile.Channels[0] -ne ('UC'+('b'*22)))){throw 'Inspect existing B profile before quota setup'}
        if(-not $state.QuotaUserId){$state|Add-Member -NotePropertyName QuotaUserId -NotePropertyValue ([string]$user.UserId)}
        $state|ConvertTo-Json|Set-Content -LiteralPath $browserStatePath -Encoding UTF8
        Call 'YouTubePlugin/MyProfile' $headers Post @{ExpectedRevision=$profile.Revision;Channels=@('UC'+('b'*22));ApiKey='synthetic-alpha-quota-key'}|Out-Null
        Write-Output 'Controlled quota-error profile seeded for ordinary B; no Google request.'
    }elseif($Action -eq 'RecordAdmin'){
        $configuration=Call 'Plugins/B2C3D4E5-F6A7-4B5C-9D0E-1F2A3B4C5D6E/Configuration'
        $safe=@{}
        foreach($property in $configuration.PSObject.Properties){if($property.Name.StartsWith('PersonalYouTube')){$safe[$property.Name]=$property.Value}}
        $safe|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/alpha-browser-admin-readback.json') -Encoding UTF8
        $safe|ConvertTo-Json
    }elseif($Action -eq 'StartAdmin'){
        $state=Get-Content -LiteralPath $browserStatePath -Raw|ConvertFrom-Json
        $name='closed-alpha-ui-admin'
        if($state.AdminUserId){
            $user=Call ('Users/'+$state.AdminUserId)
            if($user.Name -ne $name -or -not $user.Policy.IsAdministrator){throw 'Unexpected UI administrator identity'}
        }else{
            if(@((Call 'Users')|Where-Object Name -eq $name).Count){throw 'Inspect existing UI administrator before setup'}
            $user=Call 'Users/New' $admin Post @{Name=$name}
            $state|Add-Member -NotePropertyName AdminUserId -NotePropertyValue ([string]$user.Id)
            $state|ConvertTo-Json|Set-Content -LiteralPath $browserStatePath -Encoding UTF8
            $policy=$user.Policy;$policy.IsAdministrator=$true
            Call ('Users/'+$user.Id+'/Policy') $admin Post $policy|Out-Null
            $check=Call ('Users/'+$user.Id)
            if($check.Name -ne $name -or -not $check.Policy.IsAdministrator){throw 'UI administrator policy readback failed'}
        }
        Write-Output 'Disposable isolated UI administrator ready: closed-alpha-ui-admin (no password).'
    }elseif($Action -eq 'Reload'){
        $state=Get-Content -LiteralPath $browserStatePath -Raw|ConvertFrom-Json
        RecordAlphaLibrary $state
        Call 'PersonalChannelsFixture/PersonalJobs' $admin Delete|Out-Null
        & $control -Stop|Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin/Release/net6.0/PersonalChannelsFixture.dll') -Destination (Join-Path $root 'data/plugins/PersonalChannelsFixture.dll')
        & $control|Out-Null
        $deadline=[DateTime]::UtcNow.AddSeconds(40)
        do{try{$guard=Call 'PersonalChannelsFixture/Guard';if($guard.Ready){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
        if(-not $guard.Ready){throw 'Browser fixture restart failed'}
        $mode=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
        if($mode.ExperimentalEnabled -or -not $mode.Production.Installed){throw 'Production controls unavailable after reload'}
        $started=Call 'PersonalChannelsFixture/PersonalJobs' $admin Post @{}
        if(-not $started.Started){throw 'Browser worker failed to restart'}
        Write-Output 'Browser fixture reloaded; user identities retained.'
    }elseif($Action -eq 'Record'){
        $state=Get-Content -LiteralPath $browserStatePath -Raw|ConvertFrom-Json
        RecordAlphaLibrary $state
    }else{
        $state=Get-Content -LiteralPath $browserStatePath -Raw|ConvertFrom-Json
        # Native cleanup removes the fixture before deleting accounts. Resume
        # from its journal if a later step failed, without a deleted user's token.
        if(Test-Path -LiteralPath (Join-Path $root 'data/plugins/PersonalChannelsFixture.dll')){
            RecordAlphaLibrary $state
            if($state.WorkerStarted){Call 'PersonalChannelsFixture/PersonalJobs' $admin Delete|Out-Null}
            $state.WorkerStarted=$false
            $state|ConvertTo-Json|Set-Content -LiteralPath $browserStatePath -Encoding UTF8
        }
        if($state.AdminUserId){
            $user=Call ('Users/'+$state.AdminUserId)
            if($user.Name -ne 'closed-alpha-ui-admin' -or -not $user.Policy.IsAdministrator){throw 'Unexpected UI administrator cleanup identity'}
            Call ('Users/'+$state.AdminUserId) $admin Delete|Out-Null
            if(@((Call 'Users')|Where-Object Id -eq $state.AdminUserId).Count){throw 'UI administrator cleanup failed readback'}
        }
        if(Test-Path -LiteralPath $nativeStatePath){
            & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null
        }else{
            $cleanup=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/native-client-cleanup.json') -Raw|ConvertFrom-Json
            if(-not $cleanup.UsersGone -or -not $cleanup.LibrariesGone -or -not $cleanup.FixtureGone -or -not $cleanup.GuardGone -or (Get-Process EmbyServer -ErrorAction SilentlyContinue)){throw 'Native cleanup completion unverified'}
        }
        if(Test-Path -LiteralPath $profileRoot){
            $expected=[IO.Path]::GetFullPath((Join-Path $root 'data/data/youtube-personal'))
            if($profileRoot -ne $expected -or -not $profileRoot.StartsWith([IO.Path]::GetFullPath($root)+[IO.Path]::DirectorySeparatorChar)){throw 'Unsafe browser profile cleanup'}
            $allowed=@('encryption.key','native-reference-bindings.json','native-reference-bindings.required','publication-journal.json','publication-journal.required','DTi8wZ1a1TA.mp4',($state.UserId+'.json'))
            if($state.QuotaUserId){$allowed+=@($state.QuotaUserId+'.json')}
            if(@(Get-ChildItem -LiteralPath $profileRoot -Recurse -Force|Where-Object{($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or (-not $_.PSIsContainer -and $_.Name -notin $allowed)}).Count){throw 'Unexpected browser cleanup file'}
            [IO.Directory]::Delete($profileRoot,$true)
        }
        Remove-Item -LiteralPath $browserStatePath
        Write-Output 'Browser fixture cleanup verified.'
    }
}finally{$client.Dispose()}
