# Real native elements and ordinary HTTP callers; experimental fixture hooks
# consume the loaded production binding ledger. No real YouTube call.
param([switch]$UnboundDescendant,[switch]$PublicationJournal,[switch]$ActualAccess)
. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
$profileRoot=Join-Path $root 'data/data/youtube-personal'
$stage='setup';$restarted=$false;$preparingRestart=$false
$reportName=if($ActualAccess){'production-native-actual-access-results.json'}elseif($PublicationJournal){'production-native-publication-journal-results.json'}elseif($UnboundDescendant){'production-native-binding-unbound-descendant-results.json'}else{'production-native-binding-results.json'}
if(Test-Path -LiteralPath $profileRoot){throw 'Production binding test requires absent isolated profiles'}
function BindingCheck($label,$path,$headers,$expected,$sourceOwner=$null){
    $r=Request $path $headers
    $entry=@{Label=$label;Status=$r.Status;Expected=$expected;PrivateNameInDenied=($expected -eq 404 -and ($r.Text.Contains('PrivateNativeVideo_a_client') -or $r.Text.Contains('PrivateNativeVideo_b_client') -or $r.Text.Contains('PrivateNativeVideo_a_grown')))}
    if($entry.PrivateNameInDenied -or $r.Status -ne $expected){throw "Unexpected native binding result: $label"}
    if($path.EndsWith('/Download')){
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$hash=[BitConverter]::ToString($sha.ComputeHash([byte[]]$r.Bytes)).Replace('-','')}finally{$sha.Dispose()}
        $entry.Bytes=$r.Bytes.Length
        if($sourceOwner){$entry.HashMatchesSource=($hash -eq $subjects[$sourceOwner].SourceHash);if(-not $entry.HashMatchesSource){throw 'Own native download differs'}}
        elseif($expected -eq 404 -and $r.Bytes.Length -ne 0){throw 'Denied native download returned bytes'}
    }
    $rows.Add($entry)
    return $r
}
function BPositive($phase){
    BindingCheck "$phase B own metadata" "Users/$($subjects.b.UserId)/Items/$($subjects.b.VideoId)" $subjects.b.Headers 200|Out-Null
    BindingCheck "$phase B own download" "Items/$($subjects.b.VideoId)/Download" $subjects.b.Headers 200 'b'|Out-Null
    $list=BindingCheck "$phase B video list" "Items?UserId=$($subjects.b.UserId)&Recursive=true&IncludeItemTypes=Video" $subjects.b.Headers 200
    if(-not $list.Text.Contains('PrivateNativeVideo_b_client') -or $list.Text.Contains('PrivateNativeVideo_a_client') -or $list.Text.Contains('PrivateNativeVideo_a_grown')){throw 'Incorrect B native list'}
}
function ActualDecision($label,$reference,$headers,$expected,$extra=''){
    $r=Request ('PersonalChannelsFixture/NativeAccessDecision?Reference='+[Uri]::EscapeDataString($reference)+$extra) $headers
    $decision=if($r.Status -eq 200){($r.Text|ConvertFrom-Json).Decision}else{''}
    if($headers.Count -eq 0 -and $r.Status -eq 401 -and $expected -eq 'Denied'){
        $rows.Add(@{Label=$label;Status=401;NativeAuthenticationRejected=$true;ProductionPolicyInvoked=$false})
        return
    }
    $rows.Add(@{Label=$label;Status=$r.Status;Decision=$decision;ExpectedDecision=$expected})
    if($r.Status -ne 200 -or $decision -ne $expected){throw "Incorrect actual-subject native policy: $label"}
}
function ActualPolicies($phase,$aExpected){
    if(-not $ActualAccess){return}
    $hyphenated=([Guid]::Parse($subjects.a.VideoGuid)).ToString('D')
    foreach($alias in @($subjects.a.VideoId,$subjects.a.VideoGuid,$hyphenated)){
        ActualDecision "$phase actual A policy" $alias $subjects.a.Headers $aExpected
        ActualDecision "$phase actual B foreign policy" $alias $subjects.b.Headers 'Denied'
        ActualDecision "$phase anonymous private policy" $alias @{} 'Denied'
        $none=Call ('PersonalChannelsFixture/NativeAbsentSubjectDecision?Reference='+[Uri]::EscapeDataString($alias))
        $rows.Add(@{Label="$phase production native policy without user";Decision=$none.Decision;ExplicitNullUser=$true})
        if($none.Decision -ne 'Denied'){throw 'Private actual native item allowed without user'}
    }
    ActualDecision "$phase actual B own policy" $subjects.b.VideoId $subjects.b.Headers 'Allowed'
    ActualDecision "$phase B cannot claim A query subject" $subjects.a.VideoId $subjects.b.Headers 'Denied' ('&UserId='+$subjects.a.UserId)
    ActualDecision "$phase B own reference survives forged A query subject" $subjects.b.VideoId $subjects.b.Headers 'Allowed' ('&UserId='+$subjects.a.UserId)
    ActualDecision "$phase A cannot claim B query subject" $subjects.b.VideoId $subjects.a.Headers 'Denied' ('&UserId='+$subjects.b.UserId)
}
function UnboundChecks($phase){
    if(-not $subjects.a.GrownId){return}
    foreach($alias in @($subjects.a.GrownId,$subjects.a.GrownGuid)){
        foreach($actor in @('a','b')){BindingCheck "$phase $actor unbound descendant metadata" "Users/$($subjects[$actor].UserId)/Items/$alias" $subjects[$actor].Headers 404|Out-Null}
    }
    foreach($actor in @('a','b','anonymous')){
        $headers=if($actor -eq 'anonymous'){@{}}else{$subjects[$actor].Headers}
        BindingCheck "$phase $actor unbound descendant download" "Items/$($subjects.a.GrownId)/Download" $headers 404|Out-Null
    }
}
function DeniedA($phase){
    ActualPolicies $phase 'Denied'
    foreach($alias in @($subjects.a.VideoId,$subjects.a.VideoGuid)){
        foreach($actor in @('a','b')){BindingCheck "$phase $actor old A metadata" "Users/$($subjects[$actor].UserId)/Items/$alias" $subjects[$actor].Headers 404|Out-Null}
    }
    foreach($actor in @('a','b','anonymous')){
        $headers=if($actor -eq 'anonymous'){@{}}else{$subjects[$actor].Headers}
        BindingCheck "$phase $actor old A download" "Items/$($subjects.a.VideoId)/Download" $headers 404|Out-Null
    }
    $list=BindingCheck "$phase A video list" "Items?UserId=$($subjects.a.UserId)&Recursive=true&IncludeItemTypes=Video" $subjects.a.Headers 200
    if($list.Text.Contains('PrivateNativeVideo_a_client') -or $list.Text.Contains('PrivateNativeVideo_b_client') -or $list.Text.Contains('PrivateNativeVideo_a_grown')){throw 'A list retained denied native name'}
    UnboundChecks $phase
    BPositive $phase
}
try{
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1')|Out-Null
    $journal=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
    foreach($owner in @('a','b')){
        $u=@($journal.Users|Where-Object Owner -eq $owner)[0];$lib=@($journal.Libraries|Where-Object Owner -eq $owner)[0]
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Production binding test`", Device=`"Isolated`", DeviceId=`"production-native-$owner`", Version=`"1`""} Post @{Username=$u.Name;Pw=''}
        if($login.User.Id -ne $u.UserId -or $login.User.Policy.IsAdministrator){throw 'Wrong ordinary binding account'}
        $subjects[$owner]=@{UserId=$u.UserId;Headers=@{'X-Emby-Token'=$login.AccessToken};VideoId=$lib.VideoId;RootId=$lib.LibraryId;SourceHash=(Get-FileHash (Join-Path $lib.Folder "PrivateNativeVideo_${owner}_client.mp4")).Hash}
        $profile=Call 'YouTubePlugin/MyProfile' $subjects[$owner].Headers Post @{ExpectedRevision=0;Channels=@('UC'+('a'*22));ApiKey="synthetic-native-$owner-key"}
        $subjects[$owner].Profile=$profile
        if($PublicationJournal){
            $pending=Call 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{RootKey=[long]$lib.LibraryId;OwnerUserId=$u.UserId;JournalAction='Begin'}
            if($pending.State -ne 'Preparing'){throw 'Native publication was not prepared'}
            $rows.Add(@{Label="$owner real preparing journal entry";State=$pending.State})
        }
        $bound=Call 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{RootKey=[long]$lib.LibraryId;OwnerUserId=$u.UserId}
        if(-not $bound.Registered -or $bound.NativeCount -lt 2){throw 'Native production registration failed'}
        $subjects[$owner].VideoGuid=@($bound.References|Where-Object InternalId -eq ([long]$lib.VideoId))[0].Guid
        $rows.Add(@{Label="$owner actual native registration";Registered=$true;NativeCount=$bound.NativeCount})
    }
    $mode=Call 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{Enable=$true}
    if(-not $mode.Enabled){throw 'Binding bridge not enabled'}
    if($PublicationJournal){
        $stage='registered native references remain preparing'
        $bActivated=Call 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{RootKey=[long]$subjects.b.RootId;OwnerUserId=$subjects.b.UserId;JournalAction='Activate'}
        if(-not $bActivated.Activated){throw 'B publication did not activate'}
        $rows.Add(@{Label='B publication activates independently';Activated=$true})
        DeniedA 'Preparing A'
        foreach($actor in @('a','b')){foreach($alias in @($subjects.a.RootId,@($journal.Libraries|Where-Object Owner -eq 'a')[0].LibraryGuid)){
            BindingCheck "Preparing $actor A root alias" "Users/$($subjects[$actor].UserId)/Items/$alias" $subjects[$actor].Headers 404|Out-Null
        }}
        $native=Call 'PersonalChannelsFixture/NativeRecreatedRootProbe'
        if(-not $native.Exists -or $native.RootKey -ne $subjects.a.RootId -or @($native.Videos|Where-Object Key -eq $subjects.a.VideoId).Count -ne 1){throw 'Preparing native content was not retained'}
        $rows.Add(@{Label='Preparing A retains actual native root and video';NativeExists=$true})
        $stage='restart with preparing native publication'
        $before=(Call 'PersonalChannelsFixture/Guard').BootId
        & $control -Stop|Out-Null;& $control|Out-Null
        $deadline=[DateTime]::UtcNow.AddSeconds(40)
        do{try{$guard=Call 'PersonalChannelsFixture/Guard';if($guard.Ready -and $guard.BootId -ne $before){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
        if(-not $guard.Ready -or $guard.BootId -eq $before){throw 'Preparing publication restart failed'}
        $preparingRestart=$true
        DeniedA 'Preparing A after actual restart'
        foreach($actor in @('a','b')){foreach($alias in @($subjects.a.RootId,@($journal.Libraries|Where-Object Owner -eq 'a')[0].LibraryGuid)){
            BindingCheck "Preparing restart $actor A root alias" "Users/$($subjects[$actor].UserId)/Items/$alias" $subjects[$actor].Headers 404|Out-Null
        }}
        $stage='activate A native publication'
        $aActivated=Call 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{RootKey=[long]$subjects.a.RootId;OwnerUserId=$subjects.a.UserId;JournalAction='Activate'}
        if(-not $aActivated.Activated){throw 'A publication did not activate'}
        $rows.Add(@{Label='A publication activates after restart';Activated=$true})
    }
    $stage='active native controls'
    foreach($owner in @('a','b')){
        $foreign=if($owner -eq 'a'){'b'}else{'a'}
        foreach($alias in @($subjects[$owner].VideoId,$subjects[$owner].VideoGuid)){
            BindingCheck "$owner own native alias" "Users/$($subjects[$owner].UserId)/Items/$alias" $subjects[$owner].Headers 200|Out-Null
            BindingCheck "$foreign foreign native alias" "Users/$($subjects[$foreign].UserId)/Items/$alias" $subjects[$foreign].Headers 404|Out-Null
        }
        BindingCheck "$owner own native file" "Items/$($subjects[$owner].VideoId)/Download" $subjects[$owner].Headers 200 $owner|Out-Null
        BindingCheck "$foreign foreign native file" "Items/$($subjects[$owner].VideoId)/Download" $subjects[$foreign].Headers 404|Out-Null
        BindingCheck 'Anonymous native file' "Items/$($subjects[$owner].VideoId)/Download" @{} 404|Out-Null
    }
    if($UnboundDescendant){
        $stage='native descendant without production binding'
        $lib=@($journal.Libraries|Where-Object Owner -eq 'a')[0]
        $grownFile=Join-Path $lib.Folder 'PrivateNativeVideo_a_grown.mp4'
        if(Test-Path -LiteralPath $grownFile){throw 'Unexpected existing grown fixture file'}
        $journal.Files+=@($grownFile);$journal|ConvertTo-Json -Depth 12|Set-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Encoding UTF8
        Copy-Item -LiteralPath (Join-Path $lib.Folder 'PrivateNativeVideo_a_client.mp4') -Destination $grownFile
        Call "Items/$($subjects.a.RootId)/Refresh?Recursive=true&MetadataRefreshMode=FullRefresh&ImageRefreshMode=ValidationOnly" $subjects.a.Headers Post|Out-Null
        $deadline=[DateTime]::UtcNow.AddSeconds(30)
        do{$native=Call 'PersonalChannelsFixture/NativeRecreatedRootProbe';$grown=@($native.Videos|Where-Object Name -eq 'PrivateNativeVideo_a_grown');if($grown.Count -eq 1){break};Start-Sleep -Milliseconds 150}while([DateTime]::UtcNow -lt $deadline)
        if($grown.Count -ne 1){throw 'New native descendant was not scanned'}
        $subjects.a.GrownId=[string]$grown[0].Key;$subjects.a.GrownGuid=[string]$grown[0].Guid
        $ledger=Get-Content (Join-Path $profileRoot 'native-reference-bindings.json') -Raw|ConvertFrom-Json
        if(@($ledger.Items|Where-Object{$_.InternalId -eq [long]$subjects.a.GrownId -or $_.ItemId.Replace('-','') -eq $subjects.a.GrownGuid}).Count){throw 'Descendant unexpectedly production-registered'}
        $rows.Add(@{Label='Actual native descendant exists without production binding';NativeExists=$true;ProductionBound=$false})
        UnboundChecks 'Active profile'
        $list=BindingCheck 'Active A list hides unbound descendant' "Items?UserId=$($subjects.a.UserId)&Recursive=true&IncludeItemTypes=Video" $subjects.a.Headers 200
        if(-not $list.Text.Contains('PrivateNativeVideo_a_client') -or $list.Text.Contains('PrivateNativeVideo_a_grown')){throw 'Wrong active A descendant list'}
    }
    ActualPolicies 'Active' 'Allowed'
    $stage='delete profile with retained native source'
    $deleted=Call 'YouTubePlugin/MyProfile/Delete' $subjects.a.Headers Post @{ExpectedRevision=$subjects.a.Profile.Revision}
    if($deleted.State -ne 'Deleted'){throw 'Profile deletion failed'}
    DeniedA 'Deleted profile'
    $probe=Call 'PersonalChannelsFixture/NativeRecreatedRootProbe'
    $rows.Add(@{Label='Deleted profile retains actual native source';NativeProbe=$probe})
    # Read the fixture's actual root probe shape, not merely denial responses.
    if(-not $probe.Exists -or $probe.RootKey -ne $subjects.a.RootId -or @($probe.Videos|Where-Object Key -eq $subjects.a.VideoId).Count -ne 1){throw 'Native source was unexpectedly removed'}
    $stage='actual restart'
    $before=(Call 'PersonalChannelsFixture/Guard').BootId
    & $control -Stop|Out-Null;& $control|Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(40)
    do{try{$guard=Call 'PersonalChannelsFixture/Guard';if($guard.Ready -and $guard.BootId -ne $before){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    if(-not $guard.Ready -or $guard.BootId -eq $before){throw 'Actual binding test restart failed'}
    $restarted=$true
    DeniedA 'After actual restart'
    $stage='recreate profile without transferring native identity'
    $newA=Call 'YouTubePlugin/MyProfile' $subjects.a.Headers Post @{ExpectedRevision=$deleted.Revision;Channels=@('UC'+('a'*22))}
    if($newA.GenerationId -eq $subjects.a.Profile.GenerationId -or $newA.CollectionId -ne $subjects.a.Profile.CollectionId){throw 'Wrong recreated generation'}
    $ledgerPath=Join-Path $profileRoot 'native-reference-bindings.json';$ledgerHash=(Get-FileHash $ledgerPath).Hash
    $collision=Call 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{RootKey=[long]$subjects.a.RootId;OwnerUserId=$subjects.a.UserId}
    if($collision.Registered -or -not $collision.IdentityConflict -or $ledgerHash -ne (Get-FileHash $ledgerPath).Hash){throw 'Old native identity transferred'}
    $rows.Add(@{Label='Actual existing native pair cannot transfer to new generation';IdentityConflict=$true;LedgerUnchanged=$true})
    DeniedA 'Recreated profile'
    if($ActualAccess){
        $stage='remove actual native A root while retaining production identities'
        Call 'PersonalChannelsFixture/ApproveFixtureRootDeletion' $admin Post @{RootKey=[long]$subjects.a.RootId}|Out-Null
        Call 'Library/VirtualFolders/Delete' $admin Post @{Id=$subjects.a.RootId}|Out-Null
        $journal.Libraries=@($journal.Libraries|Where-Object Owner -ne 'a')
        $journal|ConvertTo-Json -Depth 12|Set-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Encoding UTF8
        foreach($phase in @('Native root removed','Absent native aliases after restart')){
            if($phase -like '*restart*'){
                $before=(Call 'PersonalChannelsFixture/Guard').BootId
                & $control -Stop|Out-Null;& $control|Out-Null
                $deadline=[DateTime]::UtcNow.AddSeconds(40)
                do{try{$guard=Call 'PersonalChannelsFixture/Guard';if($guard.Ready -and $guard.BootId -ne $before){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
                if(-not $guard.Ready -or $guard.BootId -eq $before){throw 'Absent native alias restart failed'}
                $rows.Add(@{Label='Actual restart with native A elements absent';RestartVerified=$true})
            }
            $rootState=Call ('PersonalChannelsFixture/NativeReferenceStatus?Candidate='+$subjects.a.RootId)
            $videoState=Call ('PersonalChannelsFixture/NativeReferenceStatus?Candidate='+$subjects.a.VideoId)
            if($rootState.NativeItemExists -or $videoState.NativeItemExists){throw 'Native A root/video not actually absent'}
            $rows.Add(@{Label="$phase actual native root and video absence";RootNativeExists=$false;VideoNativeExists=$false})
            ActualPolicies $phase 'Denied'
            $rootBinding=(Get-Content (Join-Path $profileRoot 'native-reference-bindings.json') -Raw|ConvertFrom-Json).Items|Where-Object InternalId -eq ([long]$subjects.a.RootId)
            foreach($alias in @($subjects.a.RootId,$rootBinding.ItemId.Replace('-',''),$rootBinding.ItemId)){
                ActualDecision "$phase absent root owner policy" $alias $subjects.a.Headers 'Denied'
                ActualDecision "$phase absent root foreign policy" $alias $subjects.b.Headers 'Denied'
            }
            BPositive $phase
        }
    }
    $completed=$true
}finally{
    @{Completed=$completed;LastStage=$stage;RestartVerified=$restarted;PreparingRestartVerified=$preparingRestart;PublicationJournal=[bool]$PublicationJournal;UnboundDescendant=[bool]$UnboundDescendant;Observations=$rows.ToArray();Scope='Loaded production journal/bindings with real native roots/videos, ordinary HTTP metadata/downloads/lists; experimental fixture Harmony hooks, no production native creation pipeline or YouTube playback'}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $PSScriptRoot ('bin/'+$reportName)) -Encoding UTF8
    try{
        & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null
        if(Test-Path -LiteralPath $profileRoot){
            $dir=[IO.Path]::GetFullPath($profileRoot);$allowed=[IO.Path]::GetFullPath($root)+[IO.Path]::DirectorySeparatorChar
            if(-not $dir.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe production binding cleanup'}
            $names=@('encryption.key','native-reference-bindings.json','native-reference-bindings.required','publication-journal.json','publication-journal.required')+@($subjects.Values|ForEach-Object{$_.UserId+'.json'})
            $files=@(Get-ChildItem -LiteralPath $dir -Force)
            if(@($files|Where-Object{$_.PSIsContainer -or $_.Name -notin $names}).Count){throw 'Unexpected production binding file retained'}
            foreach($file in $files){Remove-Item -LiteralPath $file.FullName}
            Remove-Item -LiteralPath $dir
        }
    }finally{$client.Dispose()}
}
Write-Output ('Actual production/native binding observations='+$rows.Count)
