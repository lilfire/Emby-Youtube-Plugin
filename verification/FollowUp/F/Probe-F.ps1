# Runs inside the existing alpha fixture after A has real native playback.
function FRecord($label,$pass,$details=@{}){
    $details.Label=$label;$details.Passed=[bool]$pass;$rows.Add($details)
    if(-not $pass){throw ('F assertion failed: '+$label)}
}
function FWait($actor,$expected){
    $deadline=[DateTime]::UtcNow.AddMinutes(3)
    do{
        $value=Call 'YouTubePlugin/MyJob' $subjects[$actor].Headers
        if($value.State -eq $expected){return $value}
        if($value.State -eq 'Failed'){throw ('F job failed: '+$value.ErrorCode)}
        Start-Sleep -Milliseconds 200
    }while([DateTime]::UtcNow -lt $deadline)
    throw 'F job timeout'
}
function FTrack($actor,$profile){
    $subjectActor=$actor.Split('-')[0]
    $entry=@{Owner=('f-'+$actor);Name=('YouTube '+$profile.GenerationId.Replace('-',''));LibraryId='';
      Folder=(Join-Path $profileRoot ('media/'+$subjects[$subjectActor].UserId+'/'+$profile.CollectionId.Replace('-','')+'/'+$profile.GenerationId.Replace('-','')));
      PlannedRenameName=('YouTube '+$profile.GenerationId.Replace('-',''))}
    $journal.Libraries+=@($entry)
    $journal|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $statePath -Encoding UTF8
    return $entry
}
function FVideo($actor,$ready){
    $items=Call "Users/$($subjects[$actor].UserId)/Items?ParentId=$($ready.LibraryId)&Recursive=true&IncludeItemTypes=Video" $subjects[$actor].Headers
    if($items.Items.Count -ne 1){throw 'F positive native video missing'}
    return $items.Items[0].Id
}
function FPair($label,$id,$owner,$foreign,$deniedStatus=404){
    $positive=Request "Videos/$id/stream.mp4?Static=true" $subjects[$owner].Headers
    $negative=Request "Videos/$id/stream.mp4?Static=true" $subjects[$foreign].Headers
    FRecord $label ($positive.Status -eq 200 -and $positive.Bytes.Length -gt 1000 -and $negative.Status -eq $deniedStatus) @{OwnerStatus=$positive.Status;OwnerBytes=$positive.Bytes.Length;ForeignStatus=$negative.Status}
}
$stage='F shared key/channel complete publication'
$bProfile=Call 'YouTubePlugin/MyProfile' $subjects.b.Headers Post @{ExpectedRevision=0;Channels=@('UC'+('a'*22));ApiKey='synthetic-alpha-personal-key'}
$bLibrary=FTrack 'b' $bProfile
$bJob=FWait 'b' 'Ready';$bLibrary.LibraryId=[string]$bJob.LibraryId
$journal|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $statePath -Encoding UTF8
$bVideo=FVideo 'b' $bJob
FRecord 'F identical key/channel produces separate collections, generations and native roots' ($bProfile.CollectionId -ne $saved.CollectionId -and $bProfile.GenerationId -ne $saved.GenerationId -and $bJob.LibraryId -ne $job.LibraryId)
FPair 'F A shared source owner/foreign playback' $video 'a' 'b'
FPair 'F B shared source owner/foreign playback' $bVideo 'b' 'a'
$bFile=Join-Path $profileRoot ($subjects.b.UserId+'.json');$bProfileHash=(Get-FileHash $bFile).Hash
$stage='F diagnostic and profile routes identity/body matrix'
$routes=@(@{Path='YouTubePlugin/MyProfile';Method='Get';Body=$null},@{Path='YouTubePlugin/MyJob';Method='Get';Body=$null},
 @{Path='YouTubePlugin/PersonalServerStatus';Method='Get';Body=$null},
 @{Path='YouTubePlugin/MyProfile';Method='Post';Body=@{ExpectedRevision=$saved.Revision;Channels=@();OwnerUserId=$subjects.b.UserId}},
 @{Path='YouTubePlugin/MyProfile/Delete';Method='Post';Body=@{ExpectedRevision=$saved.Revision;OwnerUserId=$subjects.b.UserId}})
foreach($r in $routes){
    $anon=Request $r.Path @{} $r.Method $r.Body
    FRecord ('F anonymous '+$r.Method+' '+$r.Path) ($anon.Status -eq 401) @{Status=$anon.Status}
    $own=Request ($r.Path+'?UserId='+$subjects.b.UserId+'&OwnerUserId='+$subjects.b.UserId) $subjects.a.Headers $r.Method $r.Body
    $expected=if($r.Path -like '*PersonalServerStatus'){403}elseif($r.Method -eq 'Post'){400}else{200}
    $pass=$own.Status -eq $expected
    if($expected -eq 200){$view=$own.Text|ConvertFrom-Json;$pass=$pass -and $view.OwnerUserId.Replace('-','') -eq $subjects.a.UserId}
    FRecord ('F manipulated identity '+$r.Method+' '+$r.Path) $pass @{Status=$own.Status}
}
$status=Request 'YouTubePlugin/PersonalServerStatus' $admin
FRecord 'F administrator positive diagnostic control' ($status.Status -eq 200)
FRecord 'F forged route bodies preserve B profile' ((Get-FileHash $bFile).Hash -eq $bProfileHash)
$stage='F concurrent key/channel update during actual native creation'
$saved=Call 'YouTubePlugin/MyProfile' $subjects.a.Headers Post @{ExpectedRevision=$saved.Revision;Channels=@('UC'+('a'*22))}
$pendingLibrary=FTrack 'a-pending' $saved
Call 'PersonalChannelsFixture/NativeCreationGate' $admin Post @{Name=$pendingLibrary.Name;ReserveIdentity=$false}|Out-Null
$deadline=[DateTime]::UtcNow.AddMinutes(3)
do{$gate=Call 'PersonalChannelsFixture/NativeCreationGate';if($gate.Active){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
FRecord 'F actual publication paused after native root insertion' ($gate.Active -and $gate.NativeExists -and -not $gate.TimedOut)
$pendingLibrary.LibraryId=[string]$gate.InternalId
$journal|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $statePath -Encoding UTF8
$message=[System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post,"$base/YouTubePlugin/MyProfile")
$message.Headers.TryAddWithoutValidation('X-Emby-Token',[string]$subjects.a.Headers['X-Emby-Token'])|Out-Null
$message.Content=[System.Net.Http.StringContent]::new((@{ExpectedRevision=$saved.Revision;Channels=@('UC'+('b'*22));ApiKey='synthetic-alpha-personal-key'}|ConvertTo-Json),[Text.Encoding]::UTF8,'application/json')
$response=$null
try{
    $task=$client.SendAsync($message)
    Start-Sleep -Milliseconds 300
    FRecord 'F profile update waits during production creation lease' (-not $task.IsCompleted)
    $bStream=Request "Videos/$bVideo/stream.mp4?Static=true" $subjects.b.Headers
    FRecord 'F B playback works while A publication and update are pending' ($bStream.Status -eq 200 -and $bStream.Bytes.Length -gt 1000)
    Call 'PersonalChannelsFixture/NativeCreationGate' $admin Post @{Release=$true}|Out-Null
    $response=$task.GetAwaiter().GetResult()
    FRecord 'F queued profile update completes after publication lease release' ([int]$response.StatusCode -eq 200)
    $saved=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json
}finally{
    Call 'PersonalChannelsFixture/NativeCreationGate' $admin Post @{Release=$true}|Out-Null
    if($response){$response.Dispose()};$message.Dispose()
}
$newLibrary=FTrack 'a-latest' $saved
$job=FWait 'a' 'Ready';$newLibrary.LibraryId=[string]$job.LibraryId
$journal|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $statePath -Encoding UTF8
$video=FVideo 'a' $job
$media=$newLibrary.Folder
FRecord 'F latest revision publishes and interrupted generation is retired' ($job.ProfileRevision -eq $saved.Revision -and $job.LibraryId -ne $pendingLibrary.LibraryId -and -not(Test-Path $pendingLibrary.Folder))
FPair 'F latest A publication owner/foreign playback' $video 'a' 'b'
$routes+=@(@{Path='YouTubePlugin/MyProfile';Method='Post';Body=@{ExpectedRevision=$saved.Revision;Channels=@('UC'+('b'*22))}},
 @{Path='YouTubePlugin/MyProfile/Delete';Method='Post';Body=@{ExpectedRevision=$saved.Revision}})
$stage='F disabled account and revoked session'
$aUser=@($journal.Users|Where-Object Owner -eq 'a')[0]
$policy=(Call "Users/$($subjects.a.UserId)").Policy
$policy.IsDisabled=$true;Call "Users/$($subjects.a.UserId)/Policy" $admin Post $policy|Out-Null
FRecord 'F disabled account policy readback' ((Call "Users/$($subjects.a.UserId)").Policy.IsDisabled)
foreach($r in $routes){
    $denied=Request $r.Path $subjects.a.Headers $r.Method $r.Body
    FRecord ('F disabled session '+$r.Method+' '+$r.Path) ($denied.Status -in @(401,403)) @{Status=$denied.Status}
}
FPair 'F disabled A leaves B playback functional' $bVideo 'b' 'a' 401
$policy.IsDisabled=$false;Call "Users/$($subjects.a.UserId)/Policy" $admin Post $policy|Out-Null
$login=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="F identities", Device="Isolated", DeviceId="f-relogin", Version="1"'} Post @{Username=$aUser.Name;Pw=''}
$subjects.a.Headers=@{'X-Emby-Token'=$login.AccessToken}
FPair 'F reenabled A playback positive control' $video 'a' 'b'
$revoke=Request ('Auth/Keys/'+$subjects.a.Headers['X-Emby-Token']) $admin Delete
FRecord 'F native token revocation accepted' ($revoke.Status -in @(200,204))
foreach($r in $routes){
    $denied=Request $r.Path $subjects.a.Headers $r.Method $r.Body
    FRecord ('F revoked session '+$r.Method+' '+$r.Path) ($denied.Status -eq 401) @{Status=$denied.Status}
}
$login=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="F identities", Device="Isolated", DeviceId="f-new-token", Version="1"'} Post @{Username=$aUser.Name;Pw=''}
$subjects.a.Headers=@{'X-Emby-Token'=$login.AccessToken}
FPair 'F new A token playback positive control' $video 'a' 'b'
$stage='F account deletion and identical name new GUID'
$oldId=$subjects.a.UserId;$oldHeaders=$subjects.a.Headers
Call "Users/$oldId" $admin Delete|Out-Null
FRecord 'F account deletion native readback' (@((Call 'Users')|Where-Object Id -eq $oldId).Count -eq 0)
foreach($r in $routes){
    $denied=Request $r.Path $oldHeaders $r.Method $r.Body
    FRecord ('F deleted account session '+$r.Method+' '+$r.Path) ($denied.Status -eq 401) @{Status=$denied.Status}
}
$replacement=Call 'Users/New' $admin Post @{Name=$aUser.Name}
$journal.Users+=@(@{Owner='f-replacement';Name=$aUser.Name;UserId=[string]$replacement.Id})
$journal|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $statePath -Encoding UTF8
$login=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="F identities", Device="Isolated", DeviceId="f-replacement", Version="1"'} Post @{Username=$aUser.Name;Pw=''}
$replacementHeaders=@{'X-Emby-Token'=$login.AccessToken}
$newProfile=Call 'YouTubePlugin/MyProfile' $replacementHeaders
FRecord 'F identical name new GUID inherits no profile or key' ($replacement.Id -ne $oldId -and $newProfile.State -eq 'Absent' -and $newProfile.Revision -eq 0 -and -not $newProfile.HasApiKey)
$oldStream=Request "Videos/$video/stream.mp4?Static=true" $replacementHeaders
FRecord 'F identical name new GUID cannot read old native video' ($oldStream.Status -eq 404) @{Status=$oldStream.Status}
$bStream=Request "Videos/$bVideo/stream.mp4?Static=true" $subjects.b.Headers
FRecord 'F A account lifecycle preserves B profile and playback' ($bStream.Status -eq 200 -and $bStream.Bytes.Length -gt 1000 -and (Get-FileHash $bFile).Hash -eq $bProfileHash)
$oldProfilePath=Join-Path $profileRoot ($oldId+'.json')
FRecord 'F deleted account profile retention measured' (Test-Path $oldProfilePath) @{OldProfileRetained=(Test-Path $oldProfilePath);OldMediaRetained=(Test-Path $media);Classification='Retention finding; access denied'}
