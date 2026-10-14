param([switch]$WithGuard)
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root=Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$base='http://127.0.0.1:18096/emby'
$control=Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1'
$auth=Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$fixture=Join-Path $root 'data/plugins/PersonalChannelsFixture.dll'
$profileBase=Join-Path $root 'data/data/personal-channels-fixture.json'
$profileFiles=@(($profileBase+'.profiles.json'),($profileBase+'.profiles.key'),($profileBase+'.profiles.json.tmp'))
$createdUsers=[Collections.Generic.List[string]]::new()
$rows=[Collections.Generic.List[object]]::new()
$started=$false;$installed=$false;$ownsProfileFiles=$false
$keys=@{a='synthetic-a-'+[guid]::NewGuid().ToString('N');b='synthetic-b-'+[guid]::NewGuid().ToString('N')}
$channels=@{a='UC'+('a'*22);b='UC'+('b'*22);shared='UC'+('s'*22)}
$state=@{}
function Digest($value) {
    $h=[Security.Cryptography.SHA256]::Create()
    try {[BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($value))).Replace('-','')} finally {$h.Dispose()}
}
function Request($path,$headers=$admin,$method='Get',$body=$null) {
    $status=200;$data=$null
    try {
        $args=@{Uri="$base/$path";Headers=$headers;Method=$method;TimeoutSec=15}
        if ($null -ne $body) {$args.ContentType='application/json';$args.Body=ConvertTo-Json -InputObject $body -Depth 12}
        $data=Invoke-RestMethod @args
    } catch {
        if (-not $_.Exception.Response) {throw 'Profile request failed without HTTP response'}
        $status=[int]$_.Exception.Response.StatusCode
        $data=@{Error=$_.ErrorDetails.Message}
    }
    $json=ConvertTo-Json -InputObject $data -Depth 12 -Compress
    foreach ($marker in $keys.Values) {if ($json.Contains($marker)) {throw 'Stored synthetic key appeared in response'}}
    return @{Status=$status;Data=$data}
}
function Call($path,$headers=$admin,$method='Get',$body=$null) {
    $r=Request $path $headers $method $body
    if ($r.Status -lt 200 -or $r.Status -ge 300) {throw "Profile control HTTP $($r.Status): $path"}
    return $r.Data
}
function Record($label,$passed) {
    $rows.Add(@{Label=$label;Passed=[bool]$passed})
    if (-not $passed) {throw "Profile assertion failed: $label"}
}
function Profile($owner) {Call 'PersonalChannelsFixture/MyYouTube' $state[$owner].Headers}
function Prepared($owner) {Call 'PersonalChannelsFixture/MyYouTube/PreparedRequest' $state[$owner].Headers}
function Same($left,$right) {(ConvertTo-Json -InputObject $left -Depth 12 -Compress) -eq (ConvertTo-Json -InputObject $right -Depth 12 -Compress)}
function CreateSubject($owner) {
    $name="native-privacy-fixture-$owner"
    $user=Call 'Users/New' $admin Post @{Name=$name};$createdUsers.Add([string]$user.Id)
    $policy=$user.Policy
    $policy.IsAdministrator=$false;$policy.EnableAllFolders=$false;$policy.EnabledFolders=@();$policy.EnableAllChannels=$false;$policy.EnabledChannels=@()
    Call "Users/$($user.Id)/Policy" $admin Post $policy | Out-Null
    $read=(Call "Users/$($user.Id)").Policy
    Record "$owner restricted policy readback" (-not $read.IsAdministrator -and -not $read.EnableAllFolders -and $read.EnabledFolders.Count -eq 0)
    $session=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Personal profiles test`", Device=`"Isolated test`", DeviceId=`"native-profile-$owner`", Version=`"1.0`""} Post @{Username=$name;Pw=''}
    Record "$owner actual login subject" ($session.User.Id -eq $user.Id -and -not $session.User.Policy.IsAdministrator)
    $headers=@{'X-Emby-Token'=$session.AccessToken}
    $subject=Call 'PersonalChannelsFixture/Subject' $headers
    return @{UserId=[string]$user.Id;OwnerGuid=$subject.UserId;Headers=$headers}
}
try {
    if (Test-Path -LiteralPath $fixture) {throw 'Fixture already installed'}
    if (Test-Path -LiteralPath ($profileBase+'.guard.json')) {throw 'Existing guard state'}
    foreach ($file in $profileFiles) {if (Test-Path -LiteralPath $file) {throw 'Existing profile data; refusing overwrite'}}
    $existingProcess=Get-Process EmbyServer -ErrorAction SilentlyContinue
    if ($existingProcess) {throw 'Test server already running'}
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin/Release/net6.0/PersonalChannelsFixture.dll') -Destination $fixture
    $installed=$true;$ownsProfileFiles=$true
    & $control;$started=$true
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong test server'}
    if ($WithGuard) {
        $guard=Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId}
        Record 'Central guard enabled and ready' ($guard.Enabled -and $guard.Ready)
    }
    $existing=Call 'Users'
    if (@($existing | Where-Object {$_.Name -in @('native-privacy-fixture-a','native-privacy-fixture-b')}).Count) {throw 'Synthetic users already exist'}
    foreach ($owner in @('a','b')) {
        $state[$owner]=CreateSubject $owner
        $empty=Profile $owner
        Record "$owner empty own profile" ($empty.OwnerUserId -eq $state[$owner].OwnerGuid -and $empty.Channels.Count -eq 0 -and -not $empty.HasApiKey)
        $saved=Call 'PersonalChannelsFixture/MyYouTube' $state[$owner].Headers Post @{Channels=@($channels[$owner]);ApiKey=$keys[$owner]}
        $state[$owner].CollectionId=$saved.CollectionId
        Record "$owner own save/read" ($saved.OwnerUserId -eq $state[$owner].OwnerGuid -and $saved.HasApiKey -and $saved.Channels.Count -eq 1 -and $saved.Channels[0] -eq $channels[$owner] -and $saved.CollectionId.Length -eq 32)
        $prepared=Prepared $owner
        Record "$owner server key retrieval" ($prepared.KeyFingerprint -eq (Digest $keys[$owner]) -and $prepared.OwnerUserId -eq $state[$owner].OwnerGuid)
    }
    Record 'Distinct immutable collection identities' ($state.a.CollectionId -ne $state.b.CollectionId)
    $disk=Get-Content -LiteralPath $profileFiles[0] -Raw
    Record 'No plaintext keys in profile store' (-not $disk.Contains($keys.a) -and -not $disk.Contains($keys.b))
    foreach ($owner in @('a','b')) {
        $other=if ($owner -eq 'a') {'b'} else {'a'}
        $before=Profile $other
        $forged=Call "PersonalChannelsFixture/MyYouTube?UserId=$($state[$other].UserId)&OwnerUserId=$($state[$other].OwnerGuid)&CollectionId=$($state[$other].CollectionId)" $state[$owner].Headers
        Record "$owner spoofed query stays own" ($forged.OwnerUserId -eq $state[$owner].OwnerGuid -and $forged.CollectionId -eq $state[$owner].CollectionId)
        $saved=Call 'PersonalChannelsFixture/MyYouTube' $state[$owner].Headers Post @{UserId=$state[$other].UserId;OwnerUserId=$state[$other].OwnerGuid;CollectionId=$state[$other].CollectionId;Channels=@($channels[$owner],$channels.shared);ApiKey=$keys[$owner]}
        Record "$owner forged body stays own" ($saved.OwnerUserId -eq $state[$owner].OwnerGuid -and $saved.CollectionId -eq $state[$owner].CollectionId)
        Record "$owner cannot mutate foreign profile" (Same $before (Profile $other))
        $pathAttack=Request "PersonalChannelsFixture/MyYouTube/$($state[$other].OwnerGuid)" $state[$owner].Headers
        Record "$owner foreign path unavailable" ($pathAttack.Status -eq 404)
        $before=Profile $owner
        foreach ($invalid in @(@{Channels=@('invalid');ApiKey=$keys[$other]},@{Channels=@($channels[$owner]);ApiKey=' '},@{Channels=@($channels[$owner]);ApiKey=$keys[$other];ClearApiKey=$true})) {
            $bad=Request 'PersonalChannelsFixture/MyYouTube' $state[$owner].Headers Post $invalid
            Record "$owner invalid write rejected without mutation" ($bad.Status -eq 400 -and (Same $before (Profile $owner)))
        }
    }
    foreach ($path in @('PersonalChannelsFixture/MyYouTube','PersonalChannelsFixture/MyYouTube/PreparedRequest')) {
        Record "Anonymous denied $path" ((Request $path @{}).Status -eq 401)
        Record "Non-test administrator excluded $path" ((Request $path).Status -eq 404)
    }
    Record 'Anonymous write denied' ((Request 'PersonalChannelsFixture/MyYouTube' @{} Post @{Channels=@($channels.shared);ApiKey=$keys.a}).Status -eq 401)
    $sameKey='synthetic-shared-'+[guid]::NewGuid().ToString('N')
    foreach ($owner in @('a','b')) {
        $saved=Call 'PersonalChannelsFixture/MyYouTube' $state[$owner].Headers Post @{Channels=@($channels.shared);ApiKey=$sameKey}
        Record "$owner same key/channel retains own collection" ($saved.OwnerUserId -eq $state[$owner].OwnerGuid -and $saved.CollectionId -eq $state[$owner].CollectionId)
    }
    Record 'Same key/channel has separate owners' ((Prepared 'a').KeyFingerprint -eq (Prepared 'b').KeyFingerprint -and (Profile 'a').CollectionId -ne (Profile 'b').CollectionId)
    # Actual HTTP requests run concurrently; replies are checked against the authenticated subject.
    $pool=[RunspaceFactory]::CreateRunspacePool(1,6);$pool.Open();$pending=@();$keySets=@{};$fingerprints=@{}
    foreach ($owner in @('a','b')) {
        $keySets[$owner]=@(1..12 | ForEach-Object {"synthetic-$owner-$_-"+[guid]::NewGuid().ToString('N')})
        $fingerprints[$owner]=@($keySets[$owner] | ForEach-Object {Digest $_})
    }
    $worker={
        param($base,$token,$ownerGuid,$collection,$channel,$key,$allowedHashes,$forgedUser)
        $h=@{'X-Emby-Token'=$token}
        $body=@{Channels=@($channel);ApiKey=$key;UserId=$forgedUser} | ConvertTo-Json -Compress
        $save=Invoke-RestMethod "$base/PersonalChannelsFixture/MyYouTube" -Method Post -Headers $h -ContentType 'application/json' -Body $body -TimeoutSec 15
        $read=Invoke-RestMethod "$base/PersonalChannelsFixture/MyYouTube?UserId=$forgedUser" -Headers $h -TimeoutSec 15
        $prepared=Invoke-RestMethod "$base/PersonalChannelsFixture/MyYouTube/PreparedRequest?UserId=$forgedUser" -Headers $h -TimeoutSec 15
        return @{OwnerCorrect=($save.OwnerUserId -eq $ownerGuid -and $read.OwnerUserId -eq $ownerGuid -and $prepared.OwnerUserId -eq $ownerGuid);CollectionStable=($save.CollectionId -eq $collection -and $read.CollectionId -eq $collection);ChannelsOwn=($read.Channels.Count -eq 1 -and $read.Channels[0] -eq $channel);KeyFromOwnSet=($prepared.KeyFingerprint -in $allowedHashes);PlaintextAbsent=(-not ($save | ConvertTo-Json -Compress).Contains($key))}
    }
    try {
        foreach ($i in 0..11) {foreach ($owner in @('a','b')) {
            $other=if ($owner -eq 'a') {'b'} else {'a'}
            $p=[PowerShell]::Create();$p.RunspacePool=$pool
            $p.AddScript($worker.ToString()).AddArgument($base).AddArgument($state[$owner].Headers['X-Emby-Token']).AddArgument($state[$owner].OwnerGuid).AddArgument($state[$owner].CollectionId).AddArgument($channels[$owner]).AddArgument($keySets[$owner][$i]).AddArgument($fingerprints[$owner]).AddArgument($state[$other].UserId) | Out-Null
            $pending+=@{PowerShell=$p;Handle=$p.BeginInvoke();Owner=$owner;Index=$i}
        }}
        foreach ($job in $pending) {
            $out=@($job.PowerShell.EndInvoke($job.Handle))
            Record "Concurrent $($job.Owner) request $($job.Index)" (-not $job.PowerShell.HadErrors -and $out.Count -eq 1 -and $out[0].OwnerCorrect -and $out[0].CollectionStable -and $out[0].ChannelsOwn -and $out[0].KeyFromOwnSet -and $out[0].PlaintextAbsent)
        }
    } finally {foreach ($job in $pending) {$job.PowerShell.Dispose()};$pool.Dispose()}
    foreach ($owner in @('a','b')) {
        Call 'PersonalChannelsFixture/MyYouTube' $state[$owner].Headers Post @{Channels=@($channels[$owner]);ApiKey=$keys[$owner]} | Out-Null
    }
    $beforeB=Prepared 'b'
    Call 'PersonalChannelsFixture/MyYouTube' $state.a.Headers Post @{Channels=@($channels.a);ClearApiKey=$true} | Out-Null
    Record 'Key clear affects only A' (-not (Profile 'a').HasApiKey -and (Prepared 'a').KeyFingerprint -eq $null -and (Same $beforeB (Prepared 'b')))
    Call 'PersonalChannelsFixture/MyYouTube' $state.a.Headers Post @{Channels=@($channels.a);ApiKey=$keys.a} | Out-Null
    $before=@{a=(Profile 'a');b=(Profile 'b')};$boot=(Call 'PersonalChannelsFixture/Guard').BootId
    & $control -Stop;& $control
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
    Record 'Verified fresh server process' ($info.ServerName -eq 'Isolated Watch State Test' -and (Call 'PersonalChannelsFixture/Guard').BootId -ne $boot)
    if ($WithGuard) {
        $guard=Call 'PersonalChannelsFixture/Guard'
        Record 'Central guard restored after restart' ($guard.Enabled -and $guard.Ready)
    }
    foreach ($owner in @('a','b')) {
        Record "$owner profile survives restart" (Same $before[$owner] (Profile $owner))
        Record "$owner encrypted key usable after restart" ((Prepared $owner).KeyFingerprint -eq (Digest $keys[$owner]))
    }
    # Copying B's ciphertext into A's record must fail authenticated decryption.
    $original=[IO.File]::ReadAllBytes($profileFiles[0])
    try {
        $store=Get-Content -LiteralPath $profileFiles[0] -Raw | ConvertFrom-Json
        $store.($state.a.OwnerGuid).EncryptedApiKey=$store.($state.b.OwnerGuid).EncryptedApiKey
        [IO.File]::WriteAllText($profileFiles[0],(ConvertTo-Json -InputObject $store -Depth 12))
        $bad=Request 'PersonalChannelsFixture/MyYouTube/PreparedRequest' $state.a.Headers
        Record 'Cross-owner ciphertext rejected' ($bad.Status -eq 500)
        Record 'B key unaffected by A ciphertext corruption' ((Prepared 'b').KeyFingerprint -eq (Digest $keys.b))
    } finally {[IO.File]::WriteAllBytes($profileFiles[0],$original)}
    $old= $state.a
    Call "Users/$($old.UserId)" $admin Delete | Out-Null
    $state.a=CreateSubject 'a'
    $fresh=Profile 'a'
    Record 'Recreated username cannot inherit deleted user profile' ($state.a.OwnerGuid -ne $old.OwnerGuid -and $fresh.CollectionId -eq '' -and -not $fresh.HasApiKey -and $fresh.Channels.Count -eq 0)
    Write-Output "Personal profile assertions: $($rows.Count); failures: $(@($rows | Where-Object {-not $_.Passed}).Count)"
} finally {
    if ($started) {
        try {
            $existingIds=@((Call 'Users') | ForEach-Object Id)
            foreach ($id in $createdUsers) {if ($id -in $existingIds) {Call "Users/$id" $admin Delete | Out-Null}}
            $remaining=@((Call 'Users') | ForEach-Object Id)
            Record 'User cleanup readback' (@($remaining | Where-Object {$_ -in $createdUsers}).Count -eq 0)
        } finally {& $control -Stop}
    }
    if ($installed) {Remove-Item -LiteralPath $fixture -ErrorAction SilentlyContinue}
    if ($installed -and $WithGuard) {Remove-Item -LiteralPath ($profileBase+'.guard.json') -ErrorAction SilentlyContinue}
    if ($ownsProfileFiles) {
        foreach ($file in $profileFiles) {
            $target=[IO.Path]::GetFullPath($file)
            if (-not $target.StartsWith($root+[IO.Path]::DirectorySeparatorChar)) {throw 'Unsafe profile cleanup path'}
            Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
        }
        Record 'Profile file cleanup readback' (@($profileFiles | Where-Object {Test-Path -LiteralPath $_}).Count -eq 0)
    }
    $report=if ($WithGuard) {'personal-profile-guard-results.json'} else {'personal-profile-results.json'}
    $rows | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot "bin/$report") -Encoding UTF8
}
