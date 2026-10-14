param([switch]$RequireDurability,[switch]$DeleteWholeRoot,[switch]$WithLiveStreams)
# Synthetic isolated media and ordinary accounts only. No YouTube or main server.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../WatchState/bin/emby-isolated'))
$control=Join-Path $PSScriptRoot '../EmbyFixture/Start-IsolatedServer.ps1'
$statePath=Join-Path $PSScriptRoot 'bin/native-client-state.json'
$state=Get-Content $statePath -Raw|ConvertFrom-Json
$auth=Get-Content (Join-Path $root 'test-auth.json') -Raw|ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token};$subjects=@{};$rows=[Collections.Generic.List[object]]::new()
function Request($path,$headers=$admin,$method='Get',$body=$null){
    $args=@{Uri=('http://127.0.0.1:18096/emby/'+$path);Headers=$headers;Method=$method;TimeoutSec=15;UseBasicParsing=$true}
    if($null -ne $body){$args.ContentType='application/json';$args.Body=$body|ConvertTo-Json -Depth 12}
    try{$r=Invoke-WebRequest @args;return @{Status=[int]$r.StatusCode;Text=$r.Content}}
    catch{if(-not $_.Exception.Response){throw};return @{Status=[int]$_.Exception.Response.StatusCode;Text=[string]$_.ErrorDetails.Message}}
}
function Control($path,$headers=$admin,$method='Get',$body=$null){$r=Request $path $headers $method $body;if($r.Status -lt 200 -or $r.Status -ge 300){throw 'Growth control failed'};if($r.Text){return ($r.Text|ConvertFrom-Json)}}
function Observe($phase,$owner,$video,$expected,$name=$null){
    $s=$subjects[$owner];$r=Request "Users/$($s.User.Id)/Items/$video" $s.Headers
    $correct=$false
    if($r.Status -eq 200){$item=$r.Text|ConvertFrom-Json;$correct=[string]$item.Id -eq [string]$video -and $item.Name -eq $name;if(-not $correct){throw 'Growth returned wrong own item'}}
    $marker=$r.Text.Contains('PrivateNativeVideo_a_grown')
    $rows.Add(@{Phase=$phase;Actor=$owner;Operation='Metadata';Status=$r.Status;CorrectOwnItem=$correct;ContainsGrownMarker=$marker})
    if($r.Status -ne $expected -or ($expected -eq 404 -and $marker)){throw 'Growth access invariant failed'}
}
function MemberRecorded($id){
    $ledger=Get-Content (Join-Path $root 'data/data/personal-channels-fixture.json.native-reference-owners.json') -Raw|ConvertFrom-Json
    return @($ledger.Collections.PSObject.Properties|Where-Object {[string]$id -in $_.Value.References}).Count -ge 1
}
function Activity {return (Control 'PersonalChannelsFixture/NativeFixtureStreamActivity')}
function StreamCount($snapshot,$group,$name){$v=$snapshot.$group.PSObject.Properties[$name].Value;if($null -eq $v){return 0};return [int]$v}
function StreamRequest($phase,$actor,$operation,$path,$body,$expected=$null,$marker=$null){
    $r=Request $path $subjects[$actor].Headers Post $body
    $hasA=$r.Text.Contains('PrivateNativeVideo_a_grown') -or $r.Text.Contains('native-client\\a')
    $correct=$null -ne $marker -and $r.Text.Contains($marker)
    $rows.Add(@{Phase=$phase;Actor=$actor;Operation=$operation;Status=$r.Status;ContainsGrownMarker=$hasA;CorrectOwnSource=$correct})
    if($null -ne $expected -and $r.Status -ne $expected){throw 'Deleted-root stream status failed'}
    if($expected -eq 200 -and $marker -and -not $correct){throw 'Wrong owner stream source'}
    if($actor -eq 'b' -and $hasA){throw 'B received deleted A stream data'}
    return $r
}
function OpenOwnStream($phase,$owner,$video,$name,$prepare=$true){
    $s=$subjects[$owner]
    $play=Control "Items/$video/PlaybackInfo" $s.Headers Post @{UserId=$s.User.Id;DeviceId="growth-stream-$owner";IsPlayback=$true;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
    if(-not $play.PlaySessionId){throw 'No native play session'}
    if($prepare){$sources=@(Control "PersonalChannelsFixture/NativeFixtureDynamicSource?ItemKey=$video");if($sources.Count -ne 1 -or -not $sources[0].OpenToken){throw 'No native source token'};$s.OpenToken=$sources[0].OpenToken}
    $s.PlaySessionId=$play.PlaySessionId;$s.StreamName=$name
    $open=StreamRequest $phase $owner 'Own Open' 'LiveStreams/Open' @{ItemId=[long]$video;UserId=$s.User.Id;OpenToken=$s.OpenToken;PlaySessionId=$s.PlaySessionId;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true} 200
    $s.LiveStreamId=($open.Text|ConvertFrom-Json).MediaSource.LiveStreamId
    if(-not $s.LiveStreamId){throw 'No native live stream ID'}
    StreamRequest $phase $owner 'Own MediaInfo' 'LiveStreams/MediaInfo' @{LiveStreamId=$s.LiveStreamId} 200 $name|Out-Null
}
function ForeignStreamChecks($phase,$oldLive,$oldSession){
    $before=Activity
    if($phase -eq 'after restart'){
        $unknown='fixture-live-'+[guid]::NewGuid().ToString('N')
        $missing=StreamRequest $phase b 'Unknown stream MediaInfo control' 'LiveStreams/MediaInfo' @{LiveStreamId=$unknown}
        if($missing.Status -ne 204 -or $missing.Text){throw 'Unknown native MediaInfo control not empty'}
        $stale=StreamRequest $phase b 'Old A MediaInfo absent after restart' 'LiveStreams/MediaInfo' @{LiveStreamId=$oldLive} $missing.Status
        if($stale.Text){throw 'Stale stream returned a response body'}
        $missingClose=StreamRequest $phase b 'Unknown stream Close control' 'LiveStreams/Close' @{LiveStreamId=$unknown;PlaySessionId=$oldSession}
        if($missingClose.Status -ne 204 -or $missingClose.Text){throw 'Unknown native Close control not empty'}
        StreamRequest $phase b 'Old A Close absent after restart' 'LiveStreams/Close' @{LiveStreamId=$oldLive;PlaySessionId=$oldSession} $missingClose.Status|Out-Null
    }else{
        StreamRequest $phase b 'Foreign A MediaInfo' 'LiveStreams/MediaInfo' @{LiveStreamId=$oldLive} 404|Out-Null
        StreamRequest $phase b 'Foreign A Close' 'LiveStreams/Close' @{LiveStreamId=$oldLive;PlaySessionId=$oldSession} 404|Out-Null
    }
    $after=Activity
    $unchanged=(StreamCount $before NativeOpenStreams 'PrivateNativeVideo_a_grown') -eq (StreamCount $after NativeOpenStreams 'PrivateNativeVideo_a_grown') -and (StreamCount $before ProviderCloseCalls 'PrivateNativeVideo_a_grown') -eq (StreamCount $after ProviderCloseCalls 'PrivateNativeVideo_a_grown')
    if(-not $unchanged){throw 'Foreign deleted-root close changed native state'}
    $script:foreignStreamNoMutation=$script:foreignStreamNoMutation -and $unchanged
}
$completed=$false;$afterScanRecorded=$false;$deleted=$false;$beforeKnown=$false;$afterKnown=$false;$afterQuarantined=$false;$restart=$false;$removedRefsReadback=$false;$ownerConfigUnchanged=$false;$approvalNoSnapshot=$false
$foreignStreamNoMutation=$true;$aStreamRetainedAfterDelete=$false;$oldTokenNoMutation=$true;$finalStreamsEmpty=$false
try{
    $info=Control 'System/Info/Public';$guard=Control 'PersonalChannelsFixture/Guard'
    if($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0' -or -not $state.SetupReady -or -not $guard.Ready -or -not $guard.Enabled){throw 'Wrong isolated fixture'}
    foreach($owner in @('a','b')){
        $u=@($state.Users|Where-Object Owner -eq $owner)[0];$l=@($state.Libraries|Where-Object Owner -eq $owner)[0]
        $login=Control 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Member growth test`", Device=`"Isolated`", DeviceId=`"growth-$owner`", Version=`"1.0`""} Post @{Username=$u.Name;Pw=''}
        if($login.User.Id -ne $u.UserId -or $login.User.Policy.IsAdministrator){throw 'Wrong ordinary subject'}
        $subjects[$owner]=@{User=$login.User;Library=$l;Headers=@{'X-Emby-Token'=$login.AccessToken}}
    }
    $a=$subjects.a;$b=$subjects.b
    $guardPath=Join-Path $root 'data/data/personal-channels-fixture.json.guard.json'
    $guardDigest=(Get-FileHash $guardPath -Algorithm SHA256).Hash
    $file=Join-Path $a.Library.Folder 'PrivateNativeVideo_a_grown.mp4'
    if(Test-Path $file){throw 'Grown synthetic file already exists'}
    $state.Files+=@($file);$state|ConvertTo-Json -Depth 12|Set-Content $statePath -Encoding UTF8
    Copy-Item (Join-Path $a.Library.Folder 'PrivateNativeVideo_a_client.mp4') $file
    Control "Items/$($a.Library.LibraryId)/Refresh?Recursive=true&MetadataRefreshMode=FullRefresh&ImageRefreshMode=ValidationOnly" $a.Headers Post|Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(30);$grown=@()
    do{$items=Control "Users/$($a.User.Id)/Items?ParentId=$($a.Library.LibraryId)&Recursive=true&IncludeItemTypes=Video" $a.Headers;$grown=@($items.Items|Where-Object Name -eq 'PrivateNativeVideo_a_grown');if($grown.Count -eq 1){break};Start-Sleep -Milliseconds 150}while([DateTime]::UtcNow -lt $deadline)
    if($grown.Count -ne 1){throw 'Grown native item not scanned'}
    $grownId=[string]$grown[0].Id
    Observe 'after scan' a $grownId 200 'PrivateNativeVideo_a_grown'
    Observe 'after scan' b $grownId 404
    Observe 'after scan' b $b.Library.VideoId 200 'PrivateNativeVideo_b_client'
    $afterScanRecorded=MemberRecorded $grownId
    $reference=Control "PersonalChannelsFixture/NativeReferenceStatus?Candidate=$grownId"
    $beforeKnown=$reference.KnownPrivate
    if(-not $beforeKnown){throw 'Grown item was never classified private'}
    if($WithLiveStreams){
        if(-not $DeleteWholeRoot -or -not $RequireDurability){throw 'Stream variant requires durable whole-root mode'}
        OpenOwnStream 'before root delete' a $grownId 'PrivateNativeVideo_a_grown'
        OpenOwnStream 'before root delete' b $b.Library.VideoId 'PrivateNativeVideo_b_client'
        $oldALive=$a.LiveStreamId;$oldASession=$a.PlaySessionId;$oldAToken=$a.OpenToken
        $openTable=Activity
        if((StreamCount $openTable NativeOpenStreams 'PrivateNativeVideo_a_grown') -ne 1 -or (StreamCount $openTable NativeOpenStreams 'PrivateNativeVideo_b_client') -ne 1){throw 'Native positive stream table not verified'}
        ForeignStreamChecks 'before root delete' $oldALive $oldASession
        StreamRequest 'before root delete after foreign close' a 'Own MediaInfo' 'LiveStreams/MediaInfo' @{LiveStreamId=$oldALive} 200 'PrivateNativeVideo_a_grown'|Out-Null
    }
    if($DeleteWholeRoot){
        $badApproval=Request 'PersonalChannelsFixture/ApproveFixtureRootDeletion' $b.Headers Post @{RootKey=[long]$a.Library.LibraryId}
        $rows.Add(@{Phase='before root delete';Actor='b';Operation='Foreign root approval';Status=$badApproval.Status})
        if($badApproval.Status -notin @(401,403,404)){throw 'Ordinary B could approve trusted admin policy'}
        $nativeLedgerPath=Join-Path $root 'data/data/personal-channels-fixture.json.native-reference-owners.json'
        $ledgerDigest=(Get-FileHash $nativeLedgerPath -Algorithm SHA256).Hash
        $approval=Control 'PersonalChannelsFixture/ApproveFixtureRootDeletion' $admin Post @{RootKey=[long]$a.Library.LibraryId}
        $approvalNoSnapshot=$ledgerDigest -eq (Get-FileHash $nativeLedgerPath -Algorithm SHA256).Hash
        if(-not $approval.Approved -or -not $approval.GrownGuidReference -or -not $approvalNoSnapshot){throw 'Trusted synthetic deletion or no-snapshot control failed'}
        # Approval changes only the narrow trusted-admin delete policy, not the
        # collection owner, references or persisted configuration.
        $denied=Request 'Library/VirtualFolders/Delete' $b.Headers Post @{Id=$a.Library.LibraryId}
        $rows.Add(@{Phase='before root delete';Actor='b';Operation='Foreign root deletion';Status=$denied.Status})
        if($denied.Status -notin @(401,403,404)){throw 'Ordinary B could use trusted admin policy'}
        $nativeBefore=Control "PersonalChannelsFixture/NativeReferenceStatus?Candidate=$($a.Library.LibraryId)"
        if(-not $nativeBefore.NativeItemExists){throw 'B removed A root'}
        Observe 'before root delete' a $grownId 200 'PrivateNativeVideo_a_grown'
        $nativeDelete=Request 'Library/VirtualFolders/Delete' $admin Post @{Id=$a.Library.LibraryId}
        $rows.Add(@{Phase='trusted admin root delete';Actor='admin';Operation='Native DeleteVirtualFolder';Status=$nativeDelete.Status})
        if($nativeDelete.Status -notin @(200,204)){throw 'Native whole-root deletion failed'}
        $nativeAfter=Control "PersonalChannelsFixture/NativeReferenceStatus?Candidate=$($a.Library.LibraryId)"
        $grownAfter=Control "PersonalChannelsFixture/NativeReferenceStatus?Candidate=$grownId"
        $deleted=-not $nativeAfter.NativeItemExists -and -not $grownAfter.NativeItemExists
        $delete=@{GuidReference=$approval.RootGuidReference}
    }else{
        # Trusted admin calls actual SDK DeleteItem, without changing ownership or
        # forcing another guard Enable snapshot before deletion.
        $delete=Control 'PersonalChannelsFixture/DeleteGrownFixtureVideo' $admin Post @{ItemKey=[long]$grownId}
        $deleted=$delete.Deleted -and $delete.NativeItemGone -and $delete.MediaFileGone
    }
    if(-not $deleted){throw 'Native grown-item deletion readback failed'}
    $ownerConfigUnchanged=$guardDigest -eq (Get-FileHash $guardPath -Algorithm SHA256).Hash
    if($DeleteWholeRoot -and -not $ownerConfigUnchanged){throw 'Root deletion changed persisted ownership configuration'}
    Observe 'after delete' a $grownId 404
    Observe 'after delete' b $grownId 404
    Observe 'after delete' b $b.Library.VideoId 200 'PrivateNativeVideo_b_client'
    if($WithLiveStreams){
        $aStreamRetainedAfterDelete=(StreamCount (Activity) NativeOpenStreams 'PrivateNativeVideo_a_grown') -gt 0
        ForeignStreamChecks 'after root delete' $oldALive $oldASession
        # Observe owner's cached stream behavior without conflating revocation
        # with the accepted privacy guarantee between different accounts.
        StreamRequest 'after root delete' a 'Deleted owner cached MediaInfo' 'LiveStreams/MediaInfo' @{LiveStreamId=$oldALive}|Out-Null
        StreamRequest 'after root delete' b 'Own MediaInfo' 'LiveStreams/MediaInfo' @{LiveStreamId=$b.LiveStreamId} 200 'PrivateNativeVideo_b_client'|Out-Null
        StreamRequest 'after root delete' b 'Own Close' 'LiveStreams/Close' @{LiveStreamId=$b.LiveStreamId;PlaySessionId=$b.PlaySessionId} 204|Out-Null
    }
    & $control -Stop|Out-Null
    & $control|Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(30);$g=$null
    do{try{$g=Control 'PersonalChannelsFixture/Guard';if($g.Ready -and $g.Enabled -and $g.BootId -ne $guard.BootId){break}}catch{};Start-Sleep -Milliseconds 150}while([DateTime]::UtcNow -lt $deadline)
    $restart=$null -ne $g -and $g.Ready -and $g.Enabled -and $g.BootId -ne $guard.BootId
    if(-not $restart){throw 'Growth restart not ready'}
    if($WithLiveStreams){
        # Register the provider using B only. The saved A token is not reissued.
        $oldBToken=$b.OpenToken
        OpenOwnStream 'after restart' b $b.Library.VideoId 'PrivateNativeVideo_b_client'
        if($oldBToken -ne $b.OpenToken){throw 'B source token changed across restart'}
        ForeignStreamChecks 'after restart' $oldALive $oldASession
        foreach($actor in @('a','b')){
            $before=Activity
            $r=StreamRequest 'after restart' $actor 'Old deleted A token without ItemId' 'LiveStreams/Open' @{UserId=$subjects[$actor].User.Id;OpenToken=$oldAToken;PlaySessionId=$subjects[$actor].PlaySessionId;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
            $after=Activity
            $unchanged=(StreamCount $before NativeOpenStreams 'PrivateNativeVideo_a_grown') -eq (StreamCount $after NativeOpenStreams 'PrivateNativeVideo_a_grown') -and (StreamCount $before ProviderOpenCalls 'PrivateNativeVideo_a_grown') -eq (StreamCount $after ProviderOpenCalls 'PrivateNativeVideo_a_grown')
            if(-not $unchanged -or ($actor -eq 'b' -and $r.Status -ne 404) -or $r.Status -eq 200){throw 'Old deleted token caused access or mutation'}
            $oldTokenNoMutation=$oldTokenNoMutation -and $unchanged
        }
        StreamRequest 'after old token attempts' b 'Own MediaInfo' 'LiveStreams/MediaInfo' @{LiveStreamId=$b.LiveStreamId} 200 'PrivateNativeVideo_b_client'|Out-Null
        StreamRequest 'after restart' b 'Own Close' 'LiveStreams/Close' @{LiveStreamId=$b.LiveStreamId;PlaySessionId=$b.PlaySessionId} 204|Out-Null
        $end=Activity
        $finalStreamsEmpty=(StreamCount $end NativeOpenStreams 'PrivateNativeVideo_a_grown') -eq 0 -and (StreamCount $end NativeOpenStreams 'PrivateNativeVideo_b_client') -eq 0
        if(-not $finalStreamsEmpty){throw 'Native stream table not empty after restart positives'}
    }
    Observe 'after restart' a $grownId 404
    Observe 'after restart' b $grownId 404
    Observe 'after restart' b $b.Library.VideoId 200 'PrivateNativeVideo_b_client'
    $reference=Control "PersonalChannelsFixture/NativeReferenceStatus?Candidate=$grownId"
    $afterKnown=$reference.KnownPrivate;$afterQuarantined=$reference.Quarantined
    if($RequireDurability){
        $ledger=Get-Content (Join-Path $root 'data/data/personal-channels-fixture.json.native-reference-owners.json') -Raw|ConvertFrom-Json
        $collection=@($ledger.Collections.PSObject.Properties|ForEach-Object Value|Where-Object RootKey -eq $a.Library.LibraryId)
        $removedRefsReadback=$collection.Count -eq 1 -and $collection[0].OwnerGuid -eq $a.User.Id
        if($DeleteWholeRoot){$removedRefsReadback=$removedRefsReadback -and $collection[0].Deleted -and $grownId -in $collection[0].References -and $approval.GrownGuidReference -in $collection[0].References -and $delete.GuidReference -in $collection[0].References}
        else{$removedRefsReadback=$removedRefsReadback -and -not $collection[0].Deleted -and $grownId -in $collection[0].RemovedReferences -and $delete.GuidReference -in $collection[0].RemovedReferences -and $delete.GuidReference -in $collection[0].References}
        if(-not $removedRefsReadback){throw 'Removed numeric/GUID references or original owner did not persist'}
    }
    if($RequireDurability -and (-not $afterScanRecorded -or -not $afterKnown -or -not $afterQuarantined -or -not(MemberRecorded $grownId))){throw 'New member provenance did not survive deletion and restart'}
    $completed=$true
}finally{
    $report=if($WithLiveStreams){'native-growth-root-live-stream-results.json'}elseif($DeleteWholeRoot){'native-member-growth-whole-root-results.json'}elseif($RequireDurability){'native-member-growth-durable-results.json'}else{'native-member-growth-snapshot-results.json'}
    @{Completed=$completed;RequireDurability=$RequireDurability.IsPresent;WholeRootDeletion=$DeleteWholeRoot.IsPresent;OwnershipConfigDigestUnchanged=$ownerConfigUnchanged;ApprovalDidNotChangeLedgerDigest=$approvalNoSnapshot;RestartVerified=$restart;NativeDeletionReadback=$deleted;NewMemberPersistedAfterScan=$afterScanRecorded;PrivateKnownBeforeDeletion=$beforeKnown;PrivateKnownAfterDeletionAndRestart=$afterKnown;QuarantinedAfterRestart=$afterQuarantined;RemovedNumericGuidReferencesAndOwnerReadback=$removedRefsReadback;Scope='Newly scanned synthetic item, native deletion, metadata and durable private classification; no retained resource or byte leak proof';Observations=$rows}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot ('bin/'+$report)) -Encoding UTF8
    if($WithLiveStreams){@{Completed=$completed;AStreamRetainedImmediatelyAfterRootDelete=$aStreamRetainedAfterDelete;ForeignStreamChecksNoMutation=$foreignStreamNoMutation;OldDeletedTokenNoMutation=$oldTokenNoMutation;FinalNativeStreamsEmpty=$finalStreamsEmpty;Scope='Actual native stream registry with synthetic provider; source metadata/open/close, no video bytes';Observations=$rows}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'bin/native-growth-root-live-stream-state-results.json') -Encoding UTF8}
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null
}
Write-Output ("Native member growth observations="+$rows.Count+"; persisted after scan="+$afterScanRecorded+"; private known after restart="+$afterKnown+"; quarantined="+$afterQuarantined)
