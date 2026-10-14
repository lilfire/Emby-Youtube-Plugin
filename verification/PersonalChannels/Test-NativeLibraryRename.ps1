$ErrorActionPreference='Stop'
$base='http://127.0.0.1:18096/emby/'
$auth=Get-Content (Join-Path $PSScriptRoot '../WatchState/bin/emby-isolated/test-auth.json') -Raw|ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$statePath=Join-Path $PSScriptRoot 'bin/native-client-state.json';$state=Get-Content $statePath -Raw|ConvertFrom-Json
$control=Join-Path $PSScriptRoot '../EmbyFixture/Start-IsolatedServer.ps1'
$subjects=@{};$rows=[Collections.Generic.List[object]]::new()
function Request($path,$headers=$admin,$method='Get',$body=$null){
    $args=@{Uri=$base+$path;Headers=$headers;Method=$method;TimeoutSec=20;UseBasicParsing=$true}
    if($null -ne $body){$args.ContentType='application/json';$args.Body=$body|ConvertTo-Json -Depth 12}
    try{$r=Invoke-WebRequest @args;return @{Status=[int]$r.StatusCode;Text=$r.Content}}
    catch{if(-not $_.Exception.Response){throw};return @{Status=[int]$_.Exception.Response.StatusCode;Text=[string]$_.ErrorDetails.Message}}
}
function Control($path,$headers=$admin,$method='Get',$body=$null){$r=Request $path $headers $method $body;if($r.Status -lt 200 -or $r.Status -ge 300){throw 'Rename control failed'};if($r.Text){return ($r.Text|ConvertFrom-Json)}}
function Ownership($adminA=$false){
    $map=@{};foreach($l in $state.Libraries){$map[$l.LibraryId]=if($adminA -and $l.Owner -eq 'a'){$auth.UserId}else{($state.Users|Where-Object Owner -eq $l.Owner).UserId}}
    Control 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId;RootOwnerUserIds=$map}|Out-Null
}
function Phase($phase){
    foreach($owner in @('a','b')){
        $s=$subjects[$owner];$other=if($owner -eq 'a'){'b'}else{'a'}
        foreach($case in @(@{Label='own video';Path="Users/$($s.UserId)/Items/$($s.VideoId)";Expected=200},@{Label='foreign video';Path="Users/$($s.UserId)/Items/$($subjects[$other].VideoId)";Expected=404},@{Label='own PlaybackInfo';Path="Items/$($s.VideoId)/PlaybackInfo?UserId=$($s.UserId)";Expected=200})){
            $r=Request $case.Path $s.Headers
            $correctItem=$false;$correctSource=$false
            if($r.Status -eq 200 -and $case.Label -eq 'own video') {
                $item=$r.Text|ConvertFrom-Json
                $correctItem=[string]$item.Id -eq [string]$s.VideoId -and $item.Name -eq "PrivateNativeVideo_${owner}_client"
                if(-not $correctItem){throw 'Rename returned wrong native video'}
            }
            if($r.Status -eq 200 -and $case.Label -eq 'own PlaybackInfo') {
                $play=$r.Text|ConvertFrom-Json
                $correctSource=@($play.MediaSources|Where-Object {$_.Path -eq $s.FilePath}).Count -ge 1
                if(-not $correctSource){throw 'Rename playback metadata lost own source'}
            }
            $rows.Add(@{Phase=$phase;Actor=$owner;Operation=$case.Label;Status=$r.Status;CorrectVideoMetadata=$correctItem;HasOwnNativeFileSource=$correctSource})
            if($r.Status -ne $case.Expected){throw 'Rename owner access failed'}
        }
    }
}
try{
    $info=Control 'System/Info/Public';$initialGuard=Control 'PersonalChannelsFixture/Guard'
    if($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0' -or -not $initialGuard.Enabled -or -not $initialGuard.Ready -or -not $state.SetupReady){throw 'Wrong isolated fixture'}
    foreach($owner in @('a','b')){
        $u=@($state.Users|Where-Object Owner -eq $owner)[0];$l=@($state.Libraries|Where-Object Owner -eq $owner)[0]
        $login=Control 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Library rename test`", Device=`"Isolated`", DeviceId=`"rename-$owner`", Version=`"1.0`""} Post @{Username=$u.Name;Pw=''}
        if($login.User.Id -ne $u.UserId -or $login.User.Policy.IsAdministrator){throw 'Wrong ordinary subject'}
        $subjects[$owner]=@{UserId=$u.UserId;VideoId=$l.VideoId;FilePath=(Join-Path $l.Folder "PrivateNativeVideo_${owner}_client.mp4");Headers=@{'X-Emby-Token'=$login.AccessToken}}
    }
    Phase before
    $record=@($state.Libraries|Where-Object Owner -eq 'a')[0]
    $oldId=$record.LibraryId;$oldGuid=$record.LibraryGuid;$newName='Private Native Fixture a renamed'
    $record|Add-Member NoteProperty PlannedRenameName $newName
    $state|ConvertTo-Json -Depth 14|Set-Content -LiteralPath $statePath -Encoding UTF8
    # Trusted admin-only mutation; private root is temporarily assigned to admin
    # for the actual native API call, then restored to its ordinary owner.
    Ownership $true
    $rename=Request 'Library/VirtualFolders/Name' $admin Post @{Id=$oldId;NewName=$newName}
    $rows.Add(@{Phase='trusted admin rename';Actor='admin';Operation='Native RenameVirtualFolder';Status=$rename.Status})
    if($rename.Status -notin @(200,204)){throw 'Native rename failed'}
    $renamed=@((Control 'Library/VirtualFolders/Query').Items|Where-Object {$_.Name -eq $newName -and $_.Locations.Count -eq 1 -and [IO.Path]::GetFullPath($_.Locations[0]) -eq [IO.Path]::GetFullPath($record.Folder)})
    if($renamed.Count -ne 1){throw 'Renamed root not observable under trusted admin ownership'}
    $sameId=[string]$renamed[0].ItemId -eq $oldId;$sameGuid=$renamed[0].Guid -eq $oldGuid
    $record.LibraryId=[string]$renamed[0].ItemId;$record.LibraryGuid=$renamed[0].Guid;$record.Name=$newName
    $state|ConvertTo-Json -Depth 14|Set-Content -LiteralPath $statePath -Encoding UTF8
    Ownership
    Phase 'after rename'
    & $control -Stop
    & $control
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do{try{$g=Control 'PersonalChannelsFixture/Guard';if($g.Ready -and $g.Enabled){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    if(-not $g.Ready -or -not $g.Enabled -or $g.BootId -eq $initialGuard.BootId){throw 'Restart not verified'}
    Phase 'after restart'
    $root=(Control "Users/$($subjects.a.UserId)/Items/$($record.LibraryId)" $subjects.a.Headers)
    if($root.Name -ne $newName){throw 'Renamed display name did not survive restart'}
    @{Completed=$true;Scope='Actual native virtual folder rename, synthetic ordinary libraries and local media';RootIdUnchanged=$sameId;RootGuidUnchanged=$sameGuid;DisplayNameSurvivedRestart=$true;OldVideoReferencesWorked=$true;RestartVerified=$true;TrustedTemporaryAdminOwnership=$true;Observations=$rows}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'bin/native-library-rename-results.json') -Encoding UTF8
    Write-Output ("Native library rename completed; observations="+$rows.Count+"; same root ID="+$sameId+"; same root GUID="+$sameGuid)
}catch{
    @{Completed=$false;ErrorCategory=$_.Exception.GetType().Name;Observations=$rows}|ConvertTo-Json -Depth 7|Set-Content (Join-Path $PSScriptRoot 'bin/native-library-rename-incomplete.json') -Encoding UTF8
    throw
}
