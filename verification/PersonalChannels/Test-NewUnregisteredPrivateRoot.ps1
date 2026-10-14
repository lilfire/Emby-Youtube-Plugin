param([switch]$InFlight,[switch]$ReserveIdentity,[switch]$CreationContext,[switch]$BufferedPublication,[switch]$ProductionDiscovery,[switch]$UserDataProbe)
if($ProductionDiscovery -and -not $BufferedPublication){throw 'Production discovery requires buffered publication'}
if($BufferedPublication -and -not $CreationContext){throw 'Buffered publication requires production creation context'}
. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
$profileRoot=[IO.Path]::GetFullPath((Join-Path $root 'data/data/youtube-personal'))
$stage='setup';$restart=$false;$created=$null
if($BufferedPublication){$client.Timeout=[TimeSpan]::FromSeconds(90)}
if(Test-Path -LiteralPath $profileRoot){throw 'New root test requires absent isolated profiles'}
function Observe($label,$path,$headers,$expected){
    $r=Request $path $headers
    $rows.Add(@{Label=$label;Status=$r.Status;Expected=$expected;PrivateNameInDenied=($expected -eq 404 -and $r.Text.Contains($created.Name))})
    if($r.Status -ne $expected -or $rows[$rows.Count-1].PrivateNameInDenied){throw "Unexpected new-root response: $label"}
    return $r
}
function Controls($phase){
    foreach($actor in @('a','b')){foreach($alias in @($created.LibraryId,$created.LibraryGuid)){
        Observe "$phase $actor unregistered root alias" "Users/$($subjects[$actor].UserId)/Items/$alias" $subjects[$actor].Headers 404|Out-Null
    }}
    foreach($actor in @('a','b')){
        $list=Observe "$phase $actor native library list" 'Library/VirtualFolders/Query' $subjects[$actor].Headers 200
        if($list.Text.Contains($created.Name) -or $list.Text.Contains($created.Folder)){throw 'Private new root appears in list'}
    }
    Observe "$phase B own video metadata" "Users/$($subjects.b.UserId)/Items/$($subjects.b.VideoId)" $subjects.b.Headers 200|Out-Null
    $download=Observe "$phase B own video file" "Items/$($subjects.b.VideoId)/Download" $subjects.b.Headers 200
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=[BitConverter]::ToString($sha.ComputeHash([byte[]]$download.Bytes)).Replace('-','')}finally{$sha.Dispose()}
    $rows[$rows.Count-1].HashMatchesSource=$hash -eq $subjects.b.SourceHash
    if($hash -ne $subjects.b.SourceHash){throw 'B own source changed'}
}
try{
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1')|Out-Null
    $statePath=Join-Path $PSScriptRoot 'bin/native-client-state.json'
    $journal=Get-Content $statePath -Raw|ConvertFrom-Json
    foreach($actor in @('a','b')){
        $u=@($journal.Users|Where-Object Owner -eq $actor)[0];$lib=@($journal.Libraries|Where-Object Owner -eq $actor)[0]
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"New private root test`", Device=`"Isolated`", DeviceId=`"new-root-$actor`", Version=`"1`""} Post @{Username=$u.Name;Pw=''}
        if($login.User.Id -ne $u.UserId -or $login.User.Policy.IsAdministrator){throw 'Wrong ordinary account'}
        $subjects[$actor]=@{UserId=$u.UserId;Headers=@{'X-Emby-Token'=$login.AccessToken};VideoId=$lib.VideoId;SourceHash=(Get-FileHash (Join-Path $lib.Folder "PrivateNativeVideo_${actor}_client.mp4")).Hash}
        $profileBody=@{ExpectedRevision=0;Channels=@('UC'+('a'*22))}
        if($BufferedPublication){$profileBody.ApiKey='synthetic-personal-publish-'+$actor}
        Call 'YouTubePlugin/MyProfile' $subjects[$actor].Headers Post $profileBody|Out-Null
        if($actor -eq 'b'){Call 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{RootKey=[long]$lib.LibraryId;OwnerUserId=$u.UserId}|Out-Null}
    }
    $reserved=Call 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{OwnerUserId=$subjects.a.UserId;JournalAction='ReserveNew'}
    if($reserved.State -ne 'Preparing'){throw 'Missing preparing reservation'}
    $source=[IO.Path]::GetFullPath($reserved.MediaPath)
    $mediaBase=[IO.Path]::GetFullPath((Join-Path $profileRoot 'media'))+[IO.Path]::DirectorySeparatorChar
    if(-not $source.StartsWith($mediaBase,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path $source)){throw 'Unsafe or existing private source'}
    $mode=Call 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{Enable=$true}
    if(-not $mode.Enabled){throw 'Native bridge unavailable'}
    if($ProductionDiscovery){
        $productionMode=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
        if($productionMode.ExperimentalEnabled){throw 'Experimental guard remains enabled'}
    }
    if($CreationContext){
        $guardState=Call 'PersonalChannelsFixture/ProductionCreationGuard'
        if(-not $guardState.ContractMatched -or -not $guardState.Installed -or $guardState.Error){throw 'Production native creation guard was not installed by plugin startup'}
        $rows.Add(@{Label='Production creation hook verified at plugin startup';ContractMatched=$true;Installed=$true;RuntimeType=$guardState.RuntimeType})
    }
    $stage='new native root before any ID registration'
    [IO.Directory]::CreateDirectory($source)|Out-Null
    $name='JournalPending_'+$reserved.GenerationId.Replace('-','')
    # The planned cleanup identity is journaled before the native create call.
    $created=@{Name=$name;Folder=$source;LibraryId='';LibraryGuid='';PlannedRenameName=$name}
    $journal.Libraries+=@($created);$journal|ConvertTo-Json -Depth 12|Set-Content $statePath -Encoding UTF8
    $createBody=@{Name=$name;CollectionType='homevideos';Paths=@($source);RefreshLibrary=$false;LibraryOptions=@{EnableRealtimeMonitor=$false;SaveLocalMetadata=$false;TypeOptions=@(@{Type='Video';MetadataFetchers=@();ImageFetchers=@()})}}
    if($InFlight){
        $stage='paused actual CreateItem before source options'
        Call 'PersonalChannelsFixture/NativeCreationGate' $admin Post @{Name=$name;ReserveIdentity=($ReserveIdentity.IsPresent -and -not $CreationContext)}|Out-Null
        $createPath=if($CreationContext){'PersonalChannelsFixture/NativeContextCreate'}else{'Library/VirtualFolders'}
        if($CreationContext){$createBody=@{Name=$name;OwnerUserId=$subjects.a.UserId}}
        $createMessage=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,"$base/$createPath")
        foreach($key in $admin.Keys){$createMessage.Headers.TryAddWithoutValidation($key,[string]$admin[$key])|Out-Null}
        $createMessage.Content=[Net.Http.StringContent]::new(($createBody|ConvertTo-Json -Depth 10),[Text.Encoding]::UTF8,'application/json')
        $pendingCreate=$client.SendAsync($createMessage)
        try{
            $deadline=[DateTime]::UtcNow.AddSeconds(10)
            do{$gate=Call 'PersonalChannelsFixture/NativeCreationGate';if($gate.Active){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
            if(-not $gate.Active -or -not $gate.NativeExists -or $pendingCreate.IsCompleted -or $gate.Locations.Count -ne 0){throw 'Missing native pre-source creation window'}
            $created.LibraryId=[string]$gate.InternalId;$created.LibraryGuid=[string]$gate.Guid
            $journal|ConvertTo-Json -Depth 12|Set-Content $statePath -Encoding UTF8
            $rows.Add(@{Label='Actual native creation paused before source options';NativeExists=$true;CreateHttpPending=$true;LocationsCount=$gate.Locations.Count})
            if($ReserveIdentity -or $CreationContext){
                $publication=Get-Content (Join-Path $profileRoot 'publication-journal.json') -Raw|ConvertFrom-Json
                $entry=@($publication.Entries|Where-Object{$_.GenerationId.Replace('-','') -eq $reserved.GenerationId.Replace('-','')})
                if($entry.Count -ne 1 -or $entry[0].State -ne 'Preparing' -or $entry[0].ReservedRootId.Replace('-','') -ne $created.LibraryGuid){throw 'Actual native root GUID was not durably reserved'}
                $rows.Add(@{Label='Actual root GUID durably reserved while native create is paused';ReservedIdentityMatches=$true;State='Preparing'})
            }
            foreach($actor in @('a','b')){
                $policy=(Call "Users/$($subjects[$actor].UserId)").Policy
                $policy.EnabledFolders=@($policy.EnabledFolders)+@($created.LibraryGuid)
                Call "Users/$($subjects[$actor].UserId)/Policy" $admin Post $policy|Out-Null
                if($created.LibraryGuid -notin (Call "Users/$($subjects[$actor].UserId)").Policy.EnabledFolders){throw 'Native test policy missing'}
                foreach($alias in @($created.LibraryId,$created.LibraryGuid)){
                    $r=Request "Users/$($subjects[$actor].UserId)/Items/$alias" $subjects[$actor].Headers
                    $rows.Add(@{Label="In-flight $actor root metadata";Alias=$alias;Status=$r.Status;PrivateNamePresent=$r.Text.Contains($name);IsolationPass=($r.Status -eq 404 -and -not $r.Text.Contains($name))})
                    if(($ReserveIdentity -or $CreationContext) -and -not $rows[$rows.Count-1].IsolationPass){throw 'Protected in-flight metadata exposed root'}
                }
                if($ProductionDiscovery -and $CreationContext -and $actor -eq 'a'){
                    # Publishing holds A's transfer lease; a synchronous
                    # wait here would consume the entire creation pause.
                    $ownerListMessage=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,"$base/Library/VirtualFolders/Query")
                    foreach($key in $subjects.a.Headers.Keys){$ownerListMessage.Headers.TryAddWithoutValidation($key,[string]$subjects.a.Headers[$key])|Out-Null}
                    $pendingOwnerList=$client.SendAsync($ownerListMessage)
                    continue
                }
                $list=Request 'Library/VirtualFolders/Query' $subjects[$actor].Headers
                $rows.Add(@{Label="In-flight $actor library list";Status=$list.Status;PrivateNamePresent=$list.Text.Contains($name);IsolationPass=($list.Status -eq 200 -and -not $list.Text.Contains($name))})
                if(($ReserveIdentity -or $CreationContext) -and -not $rows[$rows.Count-1].IsolationPass){throw 'Protected in-flight list exposed root'}
            }
            $gate=Call 'PersonalChannelsFixture/NativeCreationGate'
            if(-not $gate.Active -or $gate.TimedOut -or $pendingCreate.IsCompleted){throw 'Creation gate no longer held during observations'}
            if($pendingOwnerList){
                $rows.Add(@{Label='Owner list issued while native creation remains paused';CreationActive=$gate.Active;BodyRequestPending=(-not $pendingOwnerList.IsCompleted)})
            }
        }finally{
            Call 'PersonalChannelsFixture/NativeCreationGate' $admin Post @{Release=$true}|Out-Null
            $createResponse=$pendingCreate.GetAwaiter().GetResult()
            try{if(-not $createResponse.IsSuccessStatusCode){throw 'Native create failed after release'}}finally{$createResponse.Dispose();$createMessage.Dispose()}
            if($pendingOwnerList){
                $ownerListResponse=$null
                try{
                    $ownerListResponse=$pendingOwnerList.GetAwaiter().GetResult()
                    $ownerListText=$ownerListResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                    $rows.Add(@{Label='Owner list issued during pause omits Preparing root after lease release';Status=[int]$ownerListResponse.StatusCode;PrivateNamePresent=$ownerListText.Contains($name);PrivatePathPresent=$ownerListText.Contains($source)})
                    if([int]$ownerListResponse.StatusCode -ne 200 -or $ownerListText.Contains($name) -or $ownerListText.Contains($source)){throw 'Preparing root leaked through queued owner list'}
                }finally{if($ownerListResponse){$ownerListResponse.Dispose()};$ownerListMessage.Dispose()}
            }
        }
    }else{
        if($CreationContext){Call 'PersonalChannelsFixture/NativeContextCreate' $admin Post @{Name=$name;OwnerUserId=$subjects.a.UserId}|Out-Null}
        else{Call 'Library/VirtualFolders' $admin Post $createBody|Out-Null}
    }
    # Fixture mode filters normal library lists, even for admin. Resolve the new
    # root via a narrowly controlled native probe, not a guessed numeric ID.
    $native=Call ('PersonalChannelsFixture/NewRootIdentity?Name='+[Uri]::EscapeDataString($name))
    if(-not $native.Exists -or $native.Locations.Count -ne 1 -or [IO.Path]::GetFullPath($native.Locations[0]) -ne $source){throw 'Wrong new native source'}
    $created.LibraryId=[string]$native.InternalId;$created.LibraryGuid=[string]$native.Guid
    $journal|ConvertTo-Json -Depth 12|Set-Content $statePath -Encoding UTF8
    $user=Call "Users/$($subjects.a.UserId)";$policy=$user.Policy;$policy.EnabledFolders=@($policy.EnabledFolders)+@($created.LibraryGuid)
    Call "Users/$($subjects.a.UserId)/Policy" $admin Post $policy|Out-Null
    $check=(Call "Users/$($subjects.a.UserId)").Policy
    if($created.LibraryGuid -notin $check.EnabledFolders){throw 'A native policy was not enabled for positive potential access'}
    $ledger=Get-Content (Join-Path $profileRoot 'native-reference-bindings.json') -Raw|ConvertFrom-Json
    $aBindings=@($ledger.Items|Where-Object{$_.OwnerUserId.Replace('-','') -eq $subjects.a.UserId -or $_.InternalId -eq [long]$created.LibraryId})
    if($CreationContext){
        if($aBindings.Count -ne 1 -or $aBindings[0].InternalId -ne [long]$created.LibraryId -or $aBindings[0].OwnerUserId.Replace('-','') -ne $subjects.a.UserId -or $aBindings[0].ItemId.Replace('-','') -ne $created.LibraryGuid){throw 'Production publisher root binding mismatch'}
    }elseif($aBindings.Count){throw 'New A identity unexpectedly bound'}
    $rows.Add(@{Label='Actual new root has controlled source; production publisher binds its root before returning';NativeExists=$true;SourceMatches=$true;ANativePolicyEnabled=$true;ProductionBound=$CreationContext.IsPresent;UsesFixtureNamePrefix=$false})
    Controls 'Before registration'
    $stage='actual restart with new unregistered root'
    $before=(Call 'PersonalChannelsFixture/Guard').BootId
    & $control -Stop|Out-Null;& $control|Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(40)
    do{try{$guard=Call 'PersonalChannelsFixture/Guard';if($guard.Ready -and $guard.BootId -ne $before){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    if(-not $guard.Ready -or $guard.BootId -eq $before){throw 'New-root restart failed'}
    $restart=$true
    if($ProductionDiscovery){
        $productionMode=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
        if($productionMode.ExperimentalEnabled){throw 'Experimental guard enabled after restart'}
    }
    if($CreationContext){
        $guardState=Call 'PersonalChannelsFixture/ProductionCreationGuard'
        if(-not $guardState.ContractMatched -or -not $guardState.Installed -or $guardState.Error){throw 'Production creation hook missing after actual restart'}
        $rows.Add(@{Label='Production creation hook verified after actual restart';ContractMatched=$true;Installed=$true})
    }
    Controls 'After actual restart'
    $stage='register and activate same new native root'
    $registered=Call 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{RootKey=[long]$created.LibraryId;OwnerUserId=$subjects.a.UserId;JournalAction='RegisterNew'}
    if(-not $registered.Registered){throw 'New root registration failed'}
    $rows.Add(@{Label='Same new root receives production binding';Registered=$true;NativeCount=$registered.NativeCount})
    foreach($alias in @($created.LibraryId,$created.LibraryGuid)){Observe 'Registered but Preparing A root' "Users/$($subjects.a.UserId)/Items/$alias" $subjects.a.Headers 404|Out-Null}
    if($BufferedPublication){
        # The admin staging operation is not an ordinary client request. The
        # experimental guard must not inject its user context into indexing.
        $adminMode=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
        if($adminMode.ExperimentalEnabled){throw 'Experimental guard still enabled for staging'}
        $published=Call 'PersonalChannelsFixture/BufferedPublication' $admin Post @{RootKey=[long]$created.LibraryId;OwnerUserId=$subjects.a.UserId}
        if(-not $published.Published -or -not $published.VideoId -or $published.Bytes -le 1000){throw 'Real buffered publication failed'}
        if($published.PersonalCatalogCalls -ne 2 -or -not $published.StagingReleased){throw 'Personal refresh did not use saved key/channel or release successful staging'}
        $rows.Add(@{Label='Production buffer and publisher index and bind actual YouTube video';Published=$true;SHA256=$published.SHA256;Bytes=$published.Bytes})
        $rootOwners=@{}
        foreach($record in $journal.Libraries|Where-Object{$_.Owner -in @('a','b')}){$rootOwners[$record.LibraryId]=$subjects[$record.Owner].UserId}
        if(-not $ProductionDiscovery){Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId;RootOwnerUserIds=$rootOwners}|Out-Null}
    }else{
        $activated=Call 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{RootKey=[long]$created.LibraryId;OwnerUserId=$subjects.a.UserId;JournalAction='ActivateNew'}
        if(-not $activated.Activated){throw 'New root activation failed'}
    }
    $rows.Add(@{Label='Same new root activates';Activated=$true})
    foreach($alias in @($created.LibraryId,$created.LibraryGuid)){
        $own=Observe 'Active A same new root positive control' "Users/$($subjects.a.UserId)/Items/$alias" $subjects.a.Headers 200
        if(-not $own.Text.Contains($created.Name)){throw 'Active same root positive control missing'}
        Observe 'Active B foreign new root' "Users/$($subjects.b.UserId)/Items/$alias" $subjects.b.Headers 404|Out-Null
    }
    $ownList=Observe 'Active A library list' 'Library/VirtualFolders/Query' $subjects.a.Headers 200
    if(-not $ownList.Text.Contains($created.Name)){throw 'Active own library list missing new root'}
    $foreignList=Observe 'Active B library list' 'Library/VirtualFolders/Query' $subjects.b.Headers 200
    if($foreignList.Text.Contains($created.Name)){throw 'Active private root exposed to B list'}
    if($ProductionDiscovery){
        foreach($actor in @('a','b')){
            $plain=Observe "Active $actor unpaged library list" 'Library/VirtualFolders' $subjects[$actor].Headers 200
            if(($actor -eq 'a') -ne $plain.Text.Contains($created.Name)){throw 'Unpaged library ownership mismatch'}
        }
        $claimed=Observe 'B claims A in library query' "Library/VirtualFolders/Query?UserId=$($subjects.a.UserId)" $subjects.b.Headers 200
        if($claimed.Text.Contains($created.Name) -or $claimed.Text.Contains($created.Folder)){throw 'Claimed library user leaked private source'}
        $byId=Observe 'B queries private library ID' "Library/VirtualFolders/Query?Ids=$($created.LibraryId)&StartIndex=0&Limit=1" $subjects.b.Headers 200
        $empty=$byId.Text|ConvertFrom-Json
        if(@($empty.Items).Count -ne 0 -or $empty.TotalRecordCount -ne 0){throw 'Private library ID affected items or count'}
        $page=Observe 'B paged library count' 'Library/VirtualFolders/Query?StartIndex=0&Limit=1' $subjects.b.Headers 200
        $baseline=$foreignList.Text|ConvertFrom-Json;$paged=$page.Text|ConvertFrom-Json
        if($paged.TotalRecordCount -ne $baseline.TotalRecordCount -or @($paged.Items).Count -gt 1 -or $page.Text.Contains($created.Name)){throw 'Library paging/count includes private source'}
    }
    if($BufferedPublication){
        $mode=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
        if($mode.ExperimentalEnabled -or -not $mode.Production.Installed){throw 'Production-only media gate unavailable'}
        foreach($actor in @('a','b')){
            $expected=if($actor -eq 'a'){200}else{404}
            Observe "Published YouTube $actor metadata using production access" "Users/$($subjects[$actor].UserId)/Items/$($published.VideoId)" $subjects[$actor].Headers $expected|Out-Null
            $stream=Observe "Published YouTube $actor actual static video" "Videos/$($published.VideoId)/stream.mp4?Static=true" $subjects[$actor].Headers $expected
            if($actor -eq 'a'){
                $sha=[Security.Cryptography.SHA256]::Create()
                try{$hash=[BitConverter]::ToString($sha.ComputeHash([byte[]]$stream.Bytes)).Replace('-','')}finally{$sha.Dispose()}
                if($hash -ne $published.SHA256 -or $stream.Bytes.Length -ne $published.Bytes){throw 'Published YouTube stream differs from production buffer'}
                $rows.Add(@{Label='Native stream exactly matches buffer output';SHA256=$hash;Bytes=$stream.Bytes.Length})
            }elseif($stream.Text.Contains('DTi8wZ1a1TA') -or $stream.Bytes.Length -gt 100){throw 'Foreign buffered video leaked'}
        }
        $profile=Call 'YouTubePlugin/MyProfile' $subjects.a.Headers
        if($UserDataProbe){
            function VideoUserData($actor){Call "PersonalChannelsFixture/NativeUserData?OwnerUserId=$($subjects[$actor].UserId)&ItemId=$($published.VideoId)" $admin}
            $bBefore=VideoUserData 'b'|ConvertTo-Json -Compress
            $ownData=Request "Users/$($subjects.a.UserId)/Items/$($published.VideoId)/UserData" $subjects.a.Headers Post @{PlaybackPositionTicks=10000000;Played=$true;PlayCount=3;IsFavorite=$true}
            $aState=VideoUserData 'a'
            $rows.Add(@{Label='A own UserData update persists native state';Status=$ownData.Status;Played=$aState.Played;PlayCount=$aState.PlayCount;PlaybackPositionTicks=$aState.PlaybackPositionTicks})
            if($ownData.Status -ne 204 -or -not $aState.Played -or $aState.PlayCount -ne 3 -or $aState.PlaybackPositionTicks -ne 10000000){throw 'Owner native UserData positive control failed'}
            $aBefore=$aState|ConvertTo-Json -Compress
            $stage='foreign native UserData update'
            $foreignData=Request "Users/$($subjects.b.UserId)/Items/$($published.VideoId)/UserData" $subjects.b.Headers Post @{PlaybackPositionTicks=10000000;Played=$true;PlayCount=7;IsFavorite=$true}
            $rows.Add(@{Label='B updates A private video UserData';Status=$foreignData.Status;ReplyBytes=$foreignData.Bytes.Length;PrivateVideoPresent=$foreignData.Text.Contains('DTi8wZ1a1TA')})
            if($foreignData.Status -ne 404){throw 'Native UserData route accepts foreign private video'}
            $cross=Request "Users/$($subjects.b.UserId)/Items/$($published.VideoId)/UserData" $subjects.a.Headers Post @{PlaybackPositionTicks=20000000;Played=$false;PlayCount=9}
            $bClaimsA=Request "Users/$($subjects.a.UserId)/Items/$($published.VideoId)/UserData" $subjects.b.Headers Post @{PlaybackPositionTicks=30000000;Played=$false;PlayCount=11}
            $unchanged=(VideoUserData 'b'|ConvertTo-Json -Compress) -eq $bBefore -and (VideoUserData 'a'|ConvertTo-Json -Compress) -eq $aBefore
            $rows.Add(@{Label='Foreign and forged UserData updates preserve both native states';OwnerClaimsOther=$cross.Status;ForeignClaimsOwner=$bClaimsA.Status;NativeStateUnchanged=$unchanged})
            if($cross.Status -ne 404 -or $bClaimsA.Status -ne 404 -or -not $unchanged){throw 'UserData mutation crossed account boundary'}
            $stage='UserData persistence across actual restart'
            $beforeUserDataBoot=(Call 'PersonalChannelsFixture/Guard').BootId
            & $control -Stop|Out-Null;& $control|Out-Null
            $deadline=[DateTime]::UtcNow.AddSeconds(40)
            do{try{$userDataGuard=Call 'PersonalChannelsFixture/Guard';if($userDataGuard.Ready -and $userDataGuard.BootId -ne $beforeUserDataBoot){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
            if(-not $userDataGuard.Ready -or $userDataGuard.BootId -eq $beforeUserDataBoot){throw 'UserData actual restart failed'}
            $productionMode=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
            if($productionMode.ExperimentalEnabled -or -not $productionMode.Production.Installed){throw 'UserData production gate missing after restart'}
            $persisted=(VideoUserData 'a'|ConvertTo-Json -Compress) -eq $aBefore -and (VideoUserData 'b'|ConvertTo-Json -Compress) -eq $bBefore
            $rows.Add(@{Label='UserData reload after actual server restart preserves both accounts';BootChanged=$true;NativeStateUnchanged=$persisted})
            if(-not $persisted){throw 'UserData state differs after actual restart'}
        }
        Call 'YouTubePlugin/MyProfile/Delete' $subjects.a.Headers Post @{ExpectedRevision=$profile.Revision}|Out-Null
        Observe 'Deleted profile cannot stream published YouTube video' "Videos/$($published.VideoId)/stream.mp4?Static=true" $subjects.a.Headers 404|Out-Null
        if($UserDataProbe){
            $deletedData=Request "Users/$($subjects.a.UserId)/Items/$($published.VideoId)/UserData" $subjects.a.Headers Post @{PlaybackPositionTicks=40000000;Played=$false;PlayCount=13}
            $unchanged=(VideoUserData 'a'|ConvertTo-Json -Compress) -eq $aBefore
            $rows.Add(@{Label='Deleted profile cannot update persisted native UserData';Status=$deletedData.Status;NativeStateUnchanged=$unchanged})
            if($deletedData.Status -ne 404 -or -not $unchanged){throw 'Deleted profile mutated video state'}
        }
        if($ProductionDiscovery){
            foreach($actor in @('a','b')){
                $deletedList=Observe "Deleted collection absent from $actor library list" 'Library/VirtualFolders/Query' $subjects[$actor].Headers 200
                if($deletedList.Text.Contains($created.Name) -or $deletedList.Text.Contains($created.Folder)){throw 'Deleted collection still discoverable'}
            }
        }
        $stage='buffered YouTube published and revoked'
    }
    $completed=$true
}catch{
    $failure=$_.Exception.Message
    throw
}finally{
    try{
    $reportName=if($BufferedPublication){'production-buffered-publication-results.json'}elseif($CreationContext){'native-production-creation-hook-results.json'}elseif($ReserveIdentity){'new-root-in-flight-protected-results.json'}elseif($InFlight){'new-root-in-flight-results.json'}else{'new-unregistered-private-root-results.json'}
    if($ProductionDiscovery){$reportName='production-buffered-discovery-results.json'}
    if($UserDataProbe){$reportName='production-user-data-probe-results.json'}
    $scope=if($ProductionDiscovery){'Experimental access guard disabled before creation and explicitly after restart. Production discovery and media checks, controlled Google catalog input, real YouTube buffer. Fixture administers synthetic accounts and optional creation pause. Not automatic jobs, all routes or app playback.'}elseif($BufferedPublication){'Production real YouTube buffer and native publication with controlled catalog input. Earlier empty-root discovery uses the experimental guard; published video endpoints disable that guard. Not automatic profile jobs, Google Data API verification, all routes, or app playback.'}else{'Actual new empty native root; optional pause after CreateItem before source options. Finite diagnostics, not universal isolation proof.'}
    @{Completed=$completed;Failure=$failure;LastStage=$stage;RestartVerified=$restart;InFlight=$InFlight.IsPresent;Observations=$rows.ToArray();Scope=$scope}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot ('bin/'+$reportName)) -Encoding UTF8
    }finally{
    try{
        & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null
        if(Test-Path -LiteralPath $profileRoot){
            $allowedRoot=[IO.Path]::GetFullPath((Join-Path $root 'data/data/youtube-personal'))
            if($profileRoot -ne $allowedRoot -or -not $profileRoot.StartsWith([IO.Path]::GetFullPath($root)+[IO.Path]::DirectorySeparatorChar)){throw 'Unsafe profile-tree cleanup'}
            $allowedNames=@('encryption.key','native-reference-bindings.json','native-reference-bindings.required','publication-journal.json','publication-journal.required')+@($subjects.Values|ForEach-Object{$_.UserId+'.json'})
            if($BufferedPublication){$allowedNames+=@('DTi8wZ1a1TA.mp4')}
            $entries=@(Get-ChildItem -LiteralPath $profileRoot -Recurse -Force)
            if(@($entries|Where-Object{($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or (-not $_.PSIsContainer -and $_.Name -notin $allowedNames)}).Count){throw 'Unexpected file or link retained during bounded cleanup'}
            [IO.Directory]::Delete($profileRoot,$true)
        }
    }finally{$client.Dispose()}
    }
}
Write-Output ('New unregistered native root observations='+$rows.Count)
