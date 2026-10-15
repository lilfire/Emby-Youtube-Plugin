param([switch]$InspectSourceInventory,[switch]$RequireIsolation,[switch]$InspectNative,[switch]$DynamicViews,[ValidateSet('None','Views','Latest','Suggestions','Counts','Genres','Studios','Tags','GenresImage','StudiosImage','TagsImage','Search')][string]$WriterRace='None',[switch]$AfterWriteCheckRace,[ValidateSet('Standard','Suggestions','Counts','Metadata','Search','SearchHistory')][string]$DiscoveryFamily='Standard',[switch]$InspectCounts,[switch]$FixtureMovies,[switch]$InspectMetadataReferences,[switch]$PublicMetadataA,[switch]$InspectMetadataImages,[switch]$DerivedMetadataImages,[ValidateSet('Name','NameIndex','Id')][string]$MetadataImageStyle='Name',[switch]$HistoryMutationRace)
$isImageWriter=$WriterRace -in @('GenresImage','StudiosImage','TagsImage')
if($HistoryMutationRace -and ($DiscoveryFamily -ne 'SearchHistory' -or $WriterRace -ne 'None' -or $PublicMetadataA)){throw 'History mutation timing requires its own private SearchHistory matrix'}
if($isImageWriter -and -not $InspectMetadataImages){throw 'Metadata image writer requires its image matrix'}
if($WriterRace -eq 'TagsImage' -and $MetadataImageStyle -ne 'Id'){throw 'Tags image writer has no declared name route; select Id'}
if($PublicMetadataA -and $isImageWriter){throw 'Private metadata image writer requires private A'}
if($InspectMetadataImages -and ($DiscoveryFamily -ne 'Metadata' -or ($WriterRace -ne 'None' -and -not $isImageWriter))){throw 'Metadata image matrix requires its own Metadata family'}
if($DerivedMetadataImages -and -not $InspectMetadataImages){throw 'Derived metadata images require the image matrix'}
if($PublicMetadataA -and $DiscoveryFamily -ne 'SearchHistory' -and ((-not $InspectMetadataReferences -and -not $InspectMetadataImages) -or $DiscoveryFamily -ne 'Metadata')){throw 'Public source control requires direct Metadata references/images or SearchHistory'}
if($InspectMetadataReferences -and ($DiscoveryFamily -ne 'Metadata' -or $WriterRace -ne 'None')){throw 'Direct metadata references require their separate plain matrix'}
if($DiscoveryFamily -in @('Counts','Metadata')){$FixtureMovies=$true}
if($FixtureMovies -and $DiscoveryFamily -notin @('Counts','Metadata') -and (-not $InspectCounts -or $WriterRace -ne 'None' -or $DiscoveryFamily -ne 'Standard')){throw 'Movie count diagnostic requires its own plain standard inspection'}
if($InspectCounts -and $RequireIsolation){throw 'Counts inspection is diagnostic; use a separate verified counts contract for isolation claims'}
if($DiscoveryFamily -ne 'Standard' -and $DiscoveryFamily -ne 'Metadata' -and ($WriterRace -notin @('None',$DiscoveryFamily) -or $DynamicViews)){throw 'Discovery family requires its own request matrix'}
if($DiscoveryFamily -eq 'Metadata' -and ($WriterRace -notin @('None','Genres','Studios','Tags','GenresImage','StudiosImage','TagsImage') -or $DynamicViews)){throw 'Metadata writer requires its own request matrix'}
if($WriterRace -in @('Genres','Studios','Tags') -and $DiscoveryFamily -ne 'Metadata'){throw 'Metadata writer requires Metadata discovery family'}
if($WriterRace -eq 'Suggestions' -and $DiscoveryFamily -ne 'Suggestions'){throw 'Suggestions writer requires Suggestions discovery family'}
if($WriterRace -eq 'Counts' -and $DiscoveryFamily -ne 'Counts'){throw 'Counts writer requires Counts discovery family'}
if($WriterRace -eq 'Search' -and $DiscoveryFamily -ne 'Search'){throw 'Search writer requires Search discovery family'}
if($AfterWriteCheckRace -and $WriterRace -eq 'None' -and -not $HistoryMutationRace){throw 'After-check discovery test requires a writer target'}
. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
$profileRoot=Join-Path $root 'data/data/youtube-personal'
if(Test-Path -LiteralPath $profileRoot){throw 'Discovery test requires absent isolated profiles'}
function DiscoveryPath($uid,$kind){
    if($kind -eq 'Search'){return "Items?UserId=$uid&Recursive=true&IncludeItemTypes=Video&EnableTotalRecordCount=true&SearchTerm=PrivateNativeVideo"}
    if($kind -in @('Genres','Studios','Tags')){return "$kind`?UserId=$uid&SortBy=SortName&Limit=100"}
    if($kind -eq 'Counts'){return "Items/Counts?UserId=$uid"}
    if($kind -eq 'Suggestions'){return "Users/$uid/Suggestions?IncludeItemTypes=Video&Limit=100"}
    $dynamic=if($DynamicViews){'true'}else{'false'}
    if($kind -eq 'Views'){return "Users/$uid/Views?AllowDynamicChildren=$dynamic&IncludeHidden=true&IncludeExternalContent=false"}
    return "Users/$uid/Items/Latest?IncludeItemTypes=Video&GroupItems=false&Limit=100"
}
function ReferencesPrivate($value,$references){
    if($null -eq $value){return $false}
    if($value -is [string]){return $value -in $references}
    if($value -is [int] -or $value -is [long]){return [string]$value -in $references}
    if($value -is [Array]){foreach($entry in $value){if(ReferencesPrivate $entry $references){return $true}};return $false}
    if($value -is [pscustomobject]){foreach($property in $value.PSObject.Properties){if(ReferencesPrivate $property.Value $references){return $true}}}
    return $false
}
function DerivedMetadataImageMatches($bytes,$owner){
    if($bytes.Length -lt 8 -or [BitConverter]::ToString([byte[]]$bytes[0..7]) -ne '89-50-4E-47-0D-0A-1A-0A'){return $false}
    Add-Type -AssemblyName System.Drawing
    $memory=[IO.MemoryStream]::new([byte[]]$bytes,$false);$image=$null
    try{
        $image=[Drawing.Image]::FromStream($memory)
        if($image.Width -ne 80 -or $image.Height -ne 45){return $false}
        foreach($point in @(@(0,0),@(40,22),@(79,44))){
            $pixel=$image.GetPixel($point[0],$point[1])
            $valid=if($owner -eq 'a'){$pixel.B -gt 200 -and $pixel.R -lt 30 -and $pixel.G -lt 30}else{$pixel.R -gt 200 -and $pixel.B -lt 30 -and $pixel.G -lt 30}
            if(-not $valid){return $false}
        }
        return $true
    }catch{return $false}finally{if($image){$image.Dispose()};$memory.Dispose()}
}
function ExactCounts($body,$movies){
    $fields=@('MovieCount','SeriesCount','EpisodeCount','GameCount','ArtistCount','ProgramCount','GameSystemCount','TrailerCount','SongCount','AlbumCount','MusicVideoCount','BoxSetCount','BookCount','ItemCount')
    if($null -eq $body -or @($body.PSObject.Properties).Count -ne $fields.Count){return $false}
    foreach($field in $fields){$expected=if($field -eq 'MovieCount'){$movies}else{0};if(-not $body.PSObject.Properties[$field] -or $body.$field -ne $expected){return $false}}
    return $true
}
function CountsMatrix($phase,$aActive){
    foreach($actor in @('a','b','anonymous')){
        $headers=if($actor -eq 'anonymous'){@{}}else{$subjects[$actor].Headers}
        $claims=if($actor -eq 'anonymous'){@('none')}else{@($actor,$(if($actor -eq 'a'){'b'}else{'a'}),'none')}
        foreach($claim in $claims){
            foreach($parent in @('all','a-id','a-guid','b-id','b-guid')){
                $parts=@()
                if($claim -ne 'none'){$parts+=('UserId='+$subjects[$claim].UserId)}
                $parentOwner=if($parent -eq 'all'){''}else{$parent.Substring(0,1)}
                if($parentOwner){$reference=if($parent.EndsWith('-guid')){$subjects[$parentOwner].LibraryGuid}else{$subjects[$parentOwner].LibraryId};$parts+=('ParentId='+$reference)}
                $path='Items/Counts'+$(if($parts.Count){'?'+($parts -join '&')}else{''})
                $before=Call 'PersonalChannelsFixture/ProductionItemList'
                $r=Request $path $headers
                $after=Call 'PersonalChannelsFixture/ProductionItemList'
                $body=if($r.Status -eq 200){$r.Text|ConvertFrom-Json}else{$null}
                $expectedMovies=if($actor -eq 'b' -or ($actor -eq 'a' -and $aActive)){1}else{0}
                $privateParentDenied=$parentOwner -and ($parentOwner -ne $actor -or ($parentOwner -eq 'a' -and -not $aActive))
                $denied=$actor -eq 'anonymous' -or $privateParentDenied
                $safe=if($denied){$r.Status -in @(401,403,404) -and -not $r.Text.Contains('MovieCount') -and -not $r.Text.Contains('PrivateNative') -and -not $r.Text.Contains('Private Native')}else{$r.Status -eq 200 -and (ExactCounts $body $expectedMovies)}
                $requests=$after.Requests-$before.Requests;$queries=$after.Queries-$before.Queries;$parentDenials=$after.CountParentsDenied-$before.CountParentsDenied
                $reached=$after.Installed -and $after.AuditedDtoCount -ge 5 -and $(if($actor -eq 'anonymous'){$true}elseif($privateParentDenied){$requests -eq 1 -and $queries -eq 0 -and $parentDenials -eq 1}else{$requests -eq 1 -and $queries -eq 7 -and $parentDenials -eq 0})
                if($RequireIsolation){$safe=$safe -and $reached}
                $rows.Add(@{Label="$phase $actor Counts claimed subject $claim parent $parent";Kind='Counts';Status=$r.Status;ExpectedMovies=$expectedMovies;MovieCount=$body.MovieCount;ExpectedDenied=$denied;Counts=$body;RequestsDelta=$requests;QueriesDelta=$queries;ParentDenialsDelta=$parentDenials;ProductionBoundaryReached=$reached;IsolationPass=$safe})
                if(-not $denied -and $expectedMovies -eq 1 -and ($r.Status -ne 200 -or $body.MovieCount -ne 1)){throw 'Counts own positive control missing'}
            }
        }
    }
}
function HistorySnapshot{
    $result=@{}
    foreach($owner in @('a','b')){
        $history=Call ("PersonalChannelsFixture/NativeSearchHistory?OwnerUserId="+$subjects[$owner].UserId)
        if($history.UserId -ne $subjects[$owner].UserId.Replace('-','')){throw 'Wrong native history subject'}
        $result[$owner]=@($history.Ids|Sort-Object)
        $result[$owner+'Dates']=@($history.Entries|Sort-Object Id|ForEach-Object {$_.Id+'='+$_.Date})
    }
    return $result
}
function HistoryAction($label,$actor,$claim,$ids,$searched,$clear,$expectedAllowed){
    $headers=if($actor -eq 'anonymous'){@{}}else{$subjects[$actor].Headers}
    $before=HistorySnapshot
    # Native dates are persisted at whole-second precision. A denied report
    # must be separated from its seed to expose a timestamp-only mutation.
    if(-not $expectedAllowed -and $actor -ne 'anonymous' -and -not $clear){Start-Sleep -Milliseconds 2100}
    $path=if($clear -eq 'Delete'){"Users/$($subjects[$claim].UserId)/RecentlySearched"}elseif($clear -eq 'Post'){"Users/$($subjects[$claim].UserId)/RecentlySearched/Delete"}else{"Users/$($subjects[$claim].UserId)/SearchedItems/"}
    $method=if($clear -eq 'Delete'){'Delete'}else{'Post'}
    $body=if($clear){$null}else{@{Ids=@($ids);WasSearched=[bool]$searched}}
    $gateBefore=Call 'PersonalChannelsFixture/ProductionServiceGate'
    $r=Request $path $headers $method $body
    $gateAfter=Call 'PersonalChannelsFixture/ProductionServiceGate'
    $after=HistorySnapshot
    $unchanged=(@($before.aDates) -join ',') -eq (@($after.aDates) -join ',') -and (@($before.bDates) -join ',') -eq (@($after.bDates) -join ',')
    $ownId=[string]$subjects[$claim].References[1]
    $nativeOwn=$ownId -in @($after[$claim])
    $targetsPresent=@($ids|Where-Object {$_ -notin @($after[$claim])}).Count -eq 0
    $pass=if($expectedAllowed){$r.Status -in @(200,204) -and $(if($clear){@($after[$claim]).Count -eq 0}else{$targetsPresent})}else{$r.Status -in @(401,403,404) -and $unchanged}
    if($expectedAllowed -and -not $clear -and @($ids).Count -eq 0){$pass=$r.Status -in @(200,204) -and $unchanged}
    $checked=$gateAfter.Checked-$gateBefore.Checked;$denied=$gateAfter.Denied-$gateBefore.Denied
    $reached=$gateAfter.Installed -and $gateAfter.AuditedDtoCount -eq 18 -and $(if($clear){$checked -eq 0 -and $denied -eq 0}elseif($actor -eq 'anonymous'){($checked -eq 0 -and $denied -eq 0) -or ($checked -eq 1 -and $denied -eq 1)}elseif($expectedAllowed){$checked -eq 1 -and $denied -eq 0}else{$checked -eq 1 -and $denied -eq 1})
    if($RequireIsolation){$pass=$pass -and $reached}
    $rows.Add(@{Label=$label;Kind='SearchHistory';Status=$r.Status;Actor=$actor;Claim=$claim;TargetIds=@($ids);Clear=$clear;Searched=[bool]$searched;ExpectedAllowed=$expectedAllowed;Before=$before;After=$after;Unchanged=$unchanged;NativeOwnPresent=$nativeOwn;TargetsPresent=$targetsPresent;PublicSourceA=[bool]$PublicMetadataA;CheckedDelta=$checked;DeniedDelta=$denied;ProductionBoundaryReached=$reached;IsolationPass=$pass})
    if($expectedAllowed -and -not $pass){throw 'Own native search history positive control failed'}
}
function Discovery($phase,$aActive){
    if($env:PERSONAL_YOUTUBE_A_PROBE){
        . $env:PERSONAL_YOUTUBE_A_PROBE
        Invoke-AProbe $phase $aActive
        return
    }
    if($DiscoveryFamily -eq 'SearchHistory'){
        $aId=[string]$subjects.a.References[1];$bId=[string]$subjects.b.References[1]
        if($aActive){
            HistoryAction "$phase A own history positive" a a @($aId) $true '' $true
            HistoryAction "$phase A own duplicate frame positive" a a @($aId,$aId) $true '' $true
            HistoryAction "$phase A own empty frame positive" a a @() $true '' $true
            HistoryAction "$phase A foreign item in own history" a a @($bId) $true '' $false
            HistoryAction "$phase B own history seed" b b @($bId) $true '' $true
            HistoryAction "$phase A forged B subject report" a b @($bId) $false '' $false
            HistoryAction "$phase B own history reseed for post clear" b b @($bId) $true '' $true
            HistoryAction "$phase A forged B subject post clear" a b @() $false Post $false
            HistoryAction "$phase B own history reseed for delete clear" b b @($bId) $true '' $true
            HistoryAction "$phase A forged B subject delete clear" a b @() $false Delete $false
            HistoryAction "$phase A own history clear before mixed report" a a @() $false Post $true
            HistoryAction "$phase A mixed own and foreign report" a a @($aId,$bId) $true '' $false
            HistoryAction "$phase A mixed own and missing report" a a @($aId,'ffffffff-ffff-ffff-ffff-fffffffffff1') $true '' $false
            HistoryAction "$phase A mixed own and malformed report" a a @($aId,'not-a-native-id') $true '' $false
            HistoryAction "$phase A mixed own and null report" a a @($aId,$null) $true '' $false
            HistoryAction "$phase A own history seed before deletion" a a @($aId) $true '' $true
        }else{
            HistoryAction "$phase A own history clear after profile deletion" a a @() $false Post $true
            HistoryAction "$phase A old own item history report" a a @($aId) $true '' ([bool]$PublicMetadataA)
        }
        HistoryAction "$phase B own history seed for lifecycle clear" b b @($bId) $true '' $true
        HistoryAction "$phase A forged B subject lifecycle clear" a b @() $false Post $false
        HistoryAction "$phase B own history clear positive" b b @() $false Post $true
        if($PublicMetadataA){HistoryAction "$phase B public A source report positive" b b @($aId) $true '' $true}
        HistoryAction "$phase anonymous history report" anonymous b @($bId) $true '' $false
        HistoryAction "$phase anonymous history clear" anonymous b @() $false Delete $false
        return
    }
    if($DiscoveryFamily -eq 'Search'){
        foreach($actor in @('a','b','anonymous')){
            $headers=if($actor -eq 'anonymous'){@{}}else{$subjects[$actor].Headers}
            $other=if($actor -eq 'a'){'b'}else{'a'}
            foreach($claim in @('a','b','omitted')){
                foreach($route in @('Items','Users')){
                    if($route -eq 'Users' -and $claim -eq 'omitted'){continue}
                    foreach($termOwner in @('common','a','b')){
                        $term=if($termOwner -eq 'common'){'PrivateNativeVideo'}else{"PrivateNativeVideo_${termOwner}_client"}
                        foreach($page in @('All','First','PastEnd')){
                            $path=if($route -eq 'Items'){'Items?'}else{"Users/$($subjects[$claim].UserId)/Items?"}
                            if($route -eq 'Items' -and $claim -ne 'omitted'){$path+="UserId=$($subjects[$claim].UserId)&"}
                            $path+='Recursive=true&IncludeItemTypes=Video&EnableTotalRecordCount=true&Fields=Path,ProviderIds&SearchTerm='+[Uri]::EscapeDataString($term)
                            if($page -eq 'First'){$path+='&StartIndex=0&Limit=1'}elseif($page -eq 'PastEnd'){$path+='&StartIndex=1&Limit=1'}
                            $before=Call 'PersonalChannelsFixture/ProductionItemList'
                            $r=Request $path $headers
                            $after=Call 'PersonalChannelsFixture/ProductionItemList'
                            $body=if($r.Status -eq 200){$r.Text|ConvertFrom-Json}else{$null}
                            $items=@(if($body){$body.Items})
                            $matchingOwn=$actor -ne 'anonymous' -and ($actor -eq 'b' -or $aActive) -and $termOwner -in @('common',$actor)
                            $expectedSize=if($matchingOwn -and $page -ne 'PastEnd'){1}else{0}
                            $foreign=$actor -ne 'anonymous' -and ($r.Text.Contains("PrivateNativeVideo_${other}_client") -or (ReferencesPrivate $body $subjects[$other].References))
                            $anonymousPrivate=$actor -eq 'anonymous' -and ($r.Text.Contains('PrivateNativeVideo') -or (ReferencesPrivate $body ($subjects.a.References+$subjects.b.References)))
                            $deleted= -not $aActive -and ($r.Text.Contains('PrivateNativeVideo_a_client') -or (ReferencesPrivate $body $subjects.a.References))
                            $own=$actor -ne 'anonymous' -and @($items|Where-Object Name -eq "PrivateNativeVideo_${actor}_client").Count -eq 1
                            $countMatches=$null -ne $body -and $(if($page -eq 'PastEnd' -and $matchingOwn){$body.TotalRecordCount -in @(0,1)}else{$body.TotalRecordCount -eq $expectedSize})
                            $safe=if($actor -eq 'anonymous'){$r.Status -in @(401,403,404) -and -not $anonymousPrivate}else{$r.Status -eq 200 -and $items.Count -eq $expectedSize -and $own -eq ($expectedSize -eq 1) -and $countMatches -and -not $foreign -and -not $deleted}
                            $requests=$after.Requests-$before.Requests;$queries=$after.Queries-$before.Queries;$writes=$after.Writes-$before.Writes
                            $reached=$after.Installed -and $after.AuditedDtoCount -eq 10 -and $(if($actor -eq 'anonymous'){$requests -eq 0 -and $writes -eq 0}else{$requests -eq 1 -and $queries -gt 0 -and $writes -eq 1})
                            if($RequireIsolation){$safe=$safe -and $reached}
                            $rows.Add(@{Label="$phase $actor search $route claimed $claim term $termOwner page $page";Kind='Search';Status=$r.Status;ExpectedSize=$expectedSize;Size=$items.Count;TotalRecordCount=$body.TotalRecordCount;OwnPresent=$own;ForeignPresent=$foreign;DeletedPresent=$deleted;AnonymousPrivate=$anonymousPrivate;RequestsDelta=$requests;QueriesDelta=$queries;WritesDelta=$writes;ProductionBoundaryReached=$reached;IsolationPass=$safe})
                            if($expectedSize -eq 1 -and ($r.Status -ne 200 -or -not $own)){throw 'Own search positive control missing'}
                        }
                    }
                }
            }
            $r=Request ('Search/Hints?SearchTerm=PrivateNativeVideo&UserId='+$subjects.a.UserId) $headers
            $rows.Add(@{Label="$phase $actor obsolete search hints diagnostic";Kind='ObsoleteSearchHints';Status=$r.Status;Bytes=$r.Bytes.Length;Body=$r.Text;PrivateNamePresent=$r.Text.Contains('PrivateNativeVideo');Scope='Diagnostic only; no own positive control or audited obsolete service contract'})
        }
        return
    }
    if($DiscoveryFamily -eq 'Counts'){CountsMatrix $phase $aActive;return}
    if($DiscoveryFamily -eq 'Metadata'){
        foreach($actor in @('a','b','anonymous')){
            $claims=if($actor -eq 'anonymous'){@('none')}else{@('a','b','none')}
            foreach($claim in $claims){
                foreach($kind in @('Genres','Studios','Tags')){
                    $singular=if($kind -eq 'Genres'){'Genre'}elseif($kind -eq 'Studios'){'Studio'}else{'Tag'}
                    $path="$kind`?Fields=ItemCounts,ChildCount&SortBy=SortName&Limit=100"
                    if($claim -ne 'none'){$path+='&UserId='+$subjects[$claim].UserId}
                    $before=Call 'PersonalChannelsFixture/ProductionItemList'
                    $headers=if($actor -eq 'anonymous'){@{}}else{$subjects[$actor].Headers}
                    $r=Request $path $headers
                    $after=Call 'PersonalChannelsFixture/ProductionItemList'
                    $body=if($r.Status -eq 200){$r.Text|ConvertFrom-Json}else{$null}
                    $own="PrivateNative${singular}_$actor";$other=if($actor -eq 'a'){'b'}else{'a'}
                    $ownExpected=$actor -eq 'b' -or ($actor -eq 'a' -and ($aActive -or $PublicMetadataA))
                    $ownPresent=$own -in $body.Items.Name
                    $foreign=$r.Text.Contains("PrivateNative${singular}_$other")
                    $foreignReference=if($actor -eq 'anonymous'){$false}else{ReferencesPrivate $body $subjects[$other].MetadataReferences}
                    if($PublicMetadataA -and $other -eq 'a'){$foreign=$false;$foreignReference=$false}
                    $deleted= -not $aActive -and $r.Text.Contains("PrivateNative${singular}_a")
                    if($PublicMetadataA){$deleted=$false}
                    $expected=if($ownExpected){2}else{0}
                    $expectedNames=if($ownExpected){@($own,"SharedNative${singular}")}else{@()}
                    if($PublicMetadataA -and $actor -eq 'b'){$expectedNames+= "PrivateNative${singular}_a";$expected=3}
                    $namesMatch=(@($body.Items.Name|Sort-Object) -join '|') -eq (@($expectedNames|Sort-Object) -join '|')
                    $safe=$r.Status -eq 200 -and $ownPresent -eq $ownExpected -and -not $foreign -and -not $foreignReference -and -not $deleted -and $namesMatch -and @($body.Items).Count -eq $expected -and $body.TotalRecordCount -eq $expected
                    $writes=$after.Writes-$before.Writes
                    $reached=$after.Installed -and $after.AuditedDtoCount -ge 8 -and $after.Requests-$before.Requests -eq 1 -and $after.Queries-$before.Queries -gt 0 -and $writes -eq 1
                    if($actor -eq 'anonymous'){
                        $safe=$r.Status -in @(401,403,404) -and -not $r.Text.Contains('PrivateNative') -and -not $r.Text.Contains('SharedNative') -and -not $r.Text.Contains('TotalRecordCount')
                        $reached=$after.Installed -and $after.Queries-$before.Queries -eq 0 -and $writes -eq 0
                    }
                    if($RequireIsolation){$safe=$safe -and $reached}
                    $rows.Add(@{Label="$phase $actor $kind claimed subject $claim";Kind=$kind;Status=$r.Status;Names=@($body.Items.Name);Items=$body.Items;TotalRecordCount=$body.TotalRecordCount;OwnPresent=$ownPresent;ForeignPresent=$foreign;ForeignReferencePresent=$foreignReference;DeletedPresent=$deleted;RequestsDelta=$after.Requests-$before.Requests;QueriesDelta=$after.Queries-$before.Queries;WritesDelta=$writes;ProductionBoundaryReached=$reached;IsolationPass=$safe})
                    if($ownExpected -and ($r.Status -ne 200 -or -not $ownPresent)){throw 'Metadata own positive control missing'}
                }
            }
        }
        if($InspectMetadataReferences){
            foreach($actor in @('a','b','anonymous')){
                $headers=if($actor -eq 'anonymous'){@{}}else{$subjects[$actor].Headers}
                foreach($owner in @('a','b')){
                    foreach($kind in @('Genres','Studios','Tags')){
                        $metadata=@($subjects[$owner].Metadata.$kind)[0]
                        $styles=if($kind -eq 'Tags'){@('Id')}else{@('Name','NameWithoutUser','Id')}
                        foreach($style in $styles){
                            $uid=if($actor -eq 'anonymous'){$subjects.a.UserId}else{$subjects[$actor].UserId}
                            $path=if($style -eq 'Name'){"$kind/$([Uri]::EscapeDataString($metadata.Name))?UserId=$uid"}elseif($style -eq 'NameWithoutUser'){"$kind/$([Uri]::EscapeDataString($metadata.Name))"}else{"Users/$uid/Items/$($metadata.Id)"}
                            $gateBefore=Call 'PersonalChannelsFixture/ProductionServiceGate'
                            $listBefore=Call 'PersonalChannelsFixture/ProductionItemList'
                            $r=Request $path $headers
                            $gateAfter=Call 'PersonalChannelsFixture/ProductionServiceGate'
                            $listAfter=Call 'PersonalChannelsFixture/ProductionItemList'
                            $expectedOwn=$actor -eq $owner -and ($owner -eq 'b' -or $aActive)
                            if($PublicMetadataA -and $owner -eq 'a' -and $actor -ne 'anonymous'){$expectedOwn=$true}
                            $namePresent=$r.Text.Contains($metadata.Name)
                            $referencePresent=$false
                            if($r.Status -eq 200){$body=$r.Text|ConvertFrom-Json;$referencePresent=ReferencesPrivate $body @([string]$metadata.Id)}
                            $safe=if($expectedOwn){$r.Status -eq 200 -and $namePresent -and $referencePresent}else{$r.Status -in @(401,403,404) -and -not $namePresent -and -not $referencePresent}
                            $checked=$gateAfter.Checked-$gateBefore.Checked;$denied=$gateAfter.Denied-$gateBefore.Denied;$writes=$listAfter.Writes-$listBefore.Writes
                            $reached=$gateAfter.Installed -and $gateAfter.AuditedDtoCount -eq 18 -and $(if($actor -eq 'anonymous'){$checked -eq 0 -and $writes -eq 0}elseif($expectedOwn){$checked -eq 1 -and $denied -eq 0 -and $writes -eq 1}else{$checked -eq 1 -and $denied -eq 1 -and $writes -eq 0})
                            if($RequireIsolation){$safe=$safe -and $reached}
                            $rows.Add(@{Label="$phase $actor direct $kind $style owner $owner";Kind='MetadataReference';Category=$kind;Style=$style;Status=$r.Status;ExpectedAllowed=$expectedOwn;PublicSource=([bool]$PublicMetadataA -and $owner -eq 'a');NamePresent=$namePresent;ReferencePresent=$referencePresent;CheckedDelta=$checked;DeniedDelta=$denied;WritesDelta=$writes;ProductionBoundaryReached=$reached;IsolationPass=$safe})
                            if($expectedOwn -and ($r.Status -ne 200 -or -not $namePresent)){throw 'Own direct metadata positive control missing'}
                        }
                    }
                }
            }
        }
        if($InspectMetadataImages){
            foreach($actor in @('a','b','anonymous')){
                $headers=if($actor -eq 'anonymous'){@{}}else{$subjects[$actor].Headers}
                foreach($owner in @('a','b')){
                    foreach($kind in @('Genres','Studios','Tags')){
                        $metadata=@($subjects[$owner].Metadata.$kind)[0]
                        $styles=if($kind -eq 'Tags'){@('Id')}else{@('Name','NameIndex','Id')}
                        foreach($style in $styles){
                            $path=if($style -eq 'Id'){"Items/$($metadata.Id)/Images/Primary?Format=png"}else{"$kind/$([Uri]::EscapeDataString($metadata.Name))/Images/Primary"+$(if($style -eq 'NameIndex'){'/0'}else{''})+'?Format=png'}
                            if($DerivedMetadataImages){$path+='&MaxWidth=80&MaxHeight=45'}
                            $gateBefore=Call 'PersonalChannelsFixture/ProductionServiceGate'
                            $listBefore=Call 'PersonalChannelsFixture/ProductionItemList'
                            $r=Request $path $headers
                            $gateAfter=Call 'PersonalChannelsFixture/ProductionServiceGate'
                            $listAfter=Call 'PersonalChannelsFixture/ProductionItemList'
                            $expectedAllowed=$actor -eq $owner -and ($owner -eq 'b' -or $aActive)
                            if($PublicMetadataA -and $owner -eq 'a' -and $actor -ne 'anonymous'){$expectedAllowed=$true}
                            $sha=[Security.Cryptography.SHA256]::Create()
                            try{$hash=[BitConverter]::ToString($sha.ComputeHash([byte[]]$r.Bytes)).Replace('-','')}finally{$sha.Dispose()}
                            $matchesSource=$hash -eq $subjects[$owner].MetadataImageHash
                            if($DerivedMetadataImages){$matchesSource=DerivedMetadataImageMatches $r.Bytes $owner}
                            $entity=@($r.HeaderNames|Where-Object {$_ -in @('ETag','Last-Modified','Content-Disposition','Content-Range','Accept-Ranges')})
                            $png=$r.Bytes.Length -ge 8 -and [BitConverter]::ToString([byte[]]$r.Bytes[0..7]) -eq '89-50-4E-47-0D-0A-1A-0A'
                            $anyPrivateSource=$hash -in @($subjects.a.MetadataImageHash,$subjects.b.MetadataImageHash)
                            $generic=$r.Text -eq 'Item not found.' -and $r.Bytes.Length -eq 15
                            $checked=$gateAfter.Checked-$gateBefore.Checked;$denied=$gateAfter.Denied-$gateBefore.Denied;$writes=$listAfter.Writes-$listBefore.Writes
                            $reached=$gateAfter.Installed -and $gateAfter.AuditedDtoCount -eq 18 -and $checked -eq 1 -and $(if($expectedAllowed){$denied -eq 0 -and $writes -eq 1 -and $gateAfter.AssetSources.Installed -and $gateAfter.StaticSources.Installed}else{$denied -eq 1 -and $writes -eq 0})
                            $producers=$gateAfter.AssetSources.Producers-$gateBefore.AssetSources.Producers;$outputs=$gateAfter.AssetSources.Outputs-$gateBefore.AssetSources.Outputs;$reads=$gateAfter.StaticSources.Reads-$gateBefore.StaticSources.Reads
                            if($expectedAllowed){$reached=$reached -and $producers -eq 1 -and $outputs -eq 1 -and $reads -eq 1}
                            $safe=if($expectedAllowed){$r.Status -eq 200 -and $matchesSource -and $png}else{$r.Status -eq 404 -and $generic -and -not $anyPrivateSource -and -not $png -and $entity.Count -eq 0}
                            if($RequireIsolation){$safe=$safe -and $reached}
                            $rows.Add(@{Label="$phase $actor $kind image $style owner $owner";Kind='MetadataImage';Category=$kind;Style=$style;Status=$r.Status;ExpectedAllowed=$expectedAllowed;PublicSource=([bool]$PublicMetadataA -and $owner -eq 'a');Bytes=$r.Bytes.Length;MatchesSource=$matchesSource;PngSignature=$png;GenericDenial=$generic;EntityHeaderCount=$entity.Count;CheckedDelta=$checked;DeniedDelta=$denied;WritesDelta=$writes;ProductionBoundaryReached=$reached;ProducersDelta=$gateAfter.AssetSources.Producers-$gateBefore.AssetSources.Producers;OutputsDelta=$gateAfter.AssetSources.Outputs-$gateBefore.AssetSources.Outputs;ImageRecipesDelta=$gateAfter.AssetSources.ImageRecipes-$gateBefore.AssetSources.ImageRecipes;ReadsDelta=$gateAfter.StaticSources.Reads-$gateBefore.StaticSources.Reads;IsolationPass=$safe})
                            if($expectedAllowed -and ($r.Status -ne 200 -or -not $matchesSource)){throw 'Metadata image own positive control missing'}
                        }
                    }
                }
            }
        }
        return
    }
    foreach($actor in @('a','b')){
        foreach($subject in @($actor,$(if($actor -eq 'a'){'b'}else{'a'}))){
            $uid=$subjects[$subject].UserId
            $kinds=if($DiscoveryFamily -eq 'Suggestions'){@('Suggestions')}elseif($FixtureMovies){@('Views')}else{@('Views','Latest')}
            foreach($kind in $kinds){
                $gateBefore=Call 'PersonalChannelsFixture/ProductionItemList'
                $path=DiscoveryPath $uid $kind
                $r=Request $path $subjects[$actor].Headers
                $gateAfter=Call 'PersonalChannelsFixture/ProductionItemList'
                $items=@()
                $body=$null
                if($r.Status -eq 200){
                    $body=$r.Text|ConvertFrom-Json
                    $items=if($kind -in @('Views','Suggestions')){@($body.Items)}else{@($body)}
                }
                $own=if($kind -eq 'Views'){$subjects[$actor].LibraryName}else{"PrivateNativeVideo_${actor}_client"}
                $other=if($actor -eq 'a'){'b'}else{'a'}
                $foreign=if($kind -eq 'Views'){$subjects[$other].LibraryName}else{"PrivateNativeVideo_${other}_client"}
                $ownPresent=@($items|Where-Object {$_.Name -eq $own}).Count -gt 0
                $foreignReference=ReferencesPrivate $body $subjects[$other].References
                $foreignPresent=$r.Text.Contains($foreign) -or $foreignReference
                $deletedReference= -not $aActive -and (ReferencesPrivate $body $subjects.a.References)
                $deletedPresent= -not $aActive -and ($r.Text.Contains('PrivateNativeVideo_a_client') -or $r.Text.Contains($subjects.a.LibraryName) -or $deletedReference)
                $ownExpected=$actor -eq 'b' -or $aActive
                $subjectSpoof=$subject -ne $actor
                $total=if($kind -in @('Views','Suggestions') -and $r.Status -eq 200){$body.TotalRecordCount}else{@($items).Count}
                $expectedCount=if($ownExpected){1}else{0}
                $safe=$r.Status -eq 200 -and $ownPresent -eq $ownExpected -and -not $foreignPresent -and -not $deletedPresent -and $total -eq $expectedCount -and @($items).Count -eq $expectedCount
                if($subjectSpoof -and $r.Status -in @(403,404)){$safe= -not $ownPresent -and -not $foreignPresent -and -not $deletedPresent}
                $requests=$gateAfter.Requests-$gateBefore.Requests
                $queries=$gateAfter.Queries-$gateBefore.Queries
                $sources=$gateAfter.ViewSources-$gateBefore.ViewSources
                $expectedDtos=if($DiscoveryFamily -eq 'Suggestions'){4}else{3}
                $reached=$gateAfter.Installed -and $gateAfter.AuditedDtoCount -ge $expectedDtos -and $requests -eq 1 -and ($kind -ne 'Views' -or $sources -ge 1) -and ($kind -notin @('Latest','Suggestions') -or $queries -ge 1 -or (-not $ownExpected -and $sources -ge 1))
                if($RequireIsolation){$safe=$safe -and $reached}
                $rows.Add(@{Label="$phase $actor $kind claimed subject $subject";Kind=$kind;Status=$r.Status;OwnExpected=$ownExpected;OwnPresent=$ownPresent;ForeignPresent=$foreignPresent;ForeignReferencePresent=$foreignReference;DeletedPresent=$deletedPresent;DeletedReferencePresent=$deletedReference;SubjectSpoof=$subjectSpoof;ReturnedNames=@($items|ForEach-Object{$_.Name});TotalRecordCount=$total;ExpectedCount=$expectedCount;RequestsDelta=$requests;QueriesDelta=$queries;ViewSourcesDelta=$sources;ProductionBoundaryReached=$reached;IsolationPass=$safe})
                if(-not $subjectSpoof -and $ownExpected -and ($r.Status -ne 200 -or -not $ownPresent)){throw 'Native own discovery positive control missing'}
            }
        }
    }
    if($InspectCounts){
        foreach($actor in @('a','b')){
            foreach($parent in @('all','a','b')){
                $path="Items/Counts?UserId=$($subjects[$actor].UserId)"
                if($parent -ne 'all'){$path+='&ParentId='+$subjects[$parent].LibraryId}
                $before=Call 'PersonalChannelsFixture/ProductionItemList'
                $r=Request $path $subjects[$actor].Headers
                $after=Call 'PersonalChannelsFixture/ProductionItemList'
                $body=if($r.Status -eq 200){$r.Text|ConvertFrom-Json}else{$null}
                $rows.Add(@{Label="$phase $actor native Counts parent $parent";Kind='CountsInspection';Status=$r.Status;Parent=$parent;Counts=$body;RequestsDelta=$after.Requests-$before.Requests;QueriesDelta=$after.Queries-$before.Queries;Scope='Diagnostic count values only; not an isolation pass'})
                if($r.Status -ne 200){throw 'Native counts diagnostic request failed'}
            }
        }
    }
}
try{
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Movies:$FixtureMovies -Metadata:($DiscoveryFamily -eq 'Metadata') -MetadataImages:$InspectMetadataImages|Out-Null
    $fixture=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
    foreach($actor in @('a','b')){
        $u=@($fixture.Users|Where-Object Owner -eq $actor)[0];$lib=@($fixture.Libraries|Where-Object Owner -eq $actor)[0]
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Discovery verification`", Device=`"Isolated`", DeviceId=`"discovery-$actor`", Version=`"1`""} Post @{Username=$u.Name;Pw=''}
        if($login.User.Id -ne $u.UserId -or $login.User.Policy.IsAdministrator){throw 'Wrong ordinary discovery subject'}
        $subjects[$actor]=@{UserId=$u.UserId;LibraryName=$lib.Name;LibraryId=$lib.LibraryId;LibraryGuid=$lib.LibraryGuid;References=@([string]$lib.LibraryId,[string]$lib.VideoId,[string]$lib.LibraryGuid,('mediasource_'+$lib.VideoId));Headers=@{'X-Emby-Token'=$login.AccessToken}}
        if($DiscoveryFamily -eq 'Metadata'){
            $readback=Get-Content (Join-Path $PSScriptRoot ('bin/native-client-metadata-readback-'+$actor+'.json')) -Raw|ConvertFrom-Json
            if($readback.Owner -ne $actor -or @($readback.PrivateIds).Count -ne 3){throw 'Metadata reference control missing'}
            $subjects[$actor].MetadataReferences=@($readback.PrivateIds)
            $subjects[$actor].Metadata=$readback.Metadata
            if($InspectMetadataImages){$subjects[$actor].MetadataImageHash=(Get-FileHash (Join-Path $lib.Folder "fixture-primary-$actor.png") -Algorithm SHA256).Hash}
        }
        $subjects[$actor].Profile=Call 'YouTubePlugin/MyProfile' $subjects[$actor].Headers Post @{ExpectedRevision=0;Channels=@('UC'+($actor*22))}
        if(-not ($PublicMetadataA -and $actor -eq 'a')){
            $bound=Call 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{RootKey=[long]$lib.LibraryId;OwnerUserId=$u.UserId}
            if(-not $bound.Registered){throw 'Discovery native binding missing'}
        }
        $policy=(Call "Users/$($u.UserId)").Policy;$policy.EnableAllFolders=$true
        Call "Users/$($u.UserId)/Policy" $admin Post $policy|Out-Null
        $policy=(Call "Users/$($u.UserId)").Policy
        if(-not $policy.EnableAllFolders -or $policy.IsAdministrator){throw 'Broad ordinary native folder rights missing'}
    }
    $state=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
    $lists=Call 'PersonalChannelsFixture/ProductionItemList'
    if($state.ExperimentalEnabled -or -not $state.Production.Installed -or -not $lists.Installed){throw 'Production-only discovery boundary not ready'}
    $rows.Add(@{Label='Production gates installed, broad ordinary folder rights, experimental guard disabled';Verified=$true})
    Discovery 'Active' $true
    if($InspectSourceInventory){
        $warm=Call 'PersonalChannelsFixture/ProductionItemList'
        if(-not $warm.SourceBarrierInstalled -or $warm.SourceInventoryBuilds -lt 1 -or $warm.SourceInventoryHits -lt 1){throw 'Production source inventory is not active and reused'}
        $rows.Add(@{Label='Production source inventory active and reused';Verified=$true;Builds=$warm.SourceInventoryBuilds;Hits=$warm.SourceInventoryHits})
        foreach($fault in @($false,$true)){
            $audit=Call 'PersonalChannelsFixture/NativeSourceInventoryAudit' $admin Post @{ItemKey=[long]$subjects.a.References[1];Fault=$fault}
            if(-not $audit.Before.Installed -or $audit.Before.Writers -ne 0 -or $audit.During.Writers -lt 1 -or
                $audit.During.Version -le $audit.Before.Version -or $audit.After.Writers -ne 0 -or
                $audit.After.Version -le $audit.During.Version -or $audit.Threw -ne $fault){throw 'Native repository mutation boundary failed'}
            $rows.Add(@{Label='Actual repository mutation observed before native body and finalized';Fault=$fault;IsolationPass=$true;Before=$audit.Before;During=$audit.During;After=$audit.After})
        }
        Discovery 'After-native-source-mutation' $true
        $rebuilt=Call 'PersonalChannelsFixture/ProductionItemList'
        if($rebuilt.SourceInventoryBuilds -le $warm.SourceInventoryBuilds){throw 'Native write did not invalidate the production source inventory'}
        $rows.Add(@{Label='Native write caused production source inventory rebuild';Verified=$true;Before=$warm.SourceInventoryBuilds;After=$rebuilt.SourceInventoryBuilds})
        $readerAudit=Call 'PersonalChannelsFixture/NativeSourceInventoryAudit' $admin Post @{ItemKey=[long]$subjects.a.References[1];Reader=$true}
        if(-not $readerAudit.TransactionWriteRejected -or $readerAudit.Waiting.Readers -lt 1 -or $readerAudit.Waiting.Waiting -lt 1 -or $readerAudit.Waiting.Writers -ne 0 -or
            $readerAudit.After.Readers -ne 0 -or $readerAudit.After.Writers -ne 0 -or $readerAudit.After.Waiting -ne 0){throw 'Native writer/reader lease exclusion failed'}
        $rows.Add(@{Label='Actual native repository write waited for production source reader lease';IsolationPass=$true;Waiting=$readerAudit.Waiting;After=$readerAudit.After})
        $optionsAudit=Call 'PersonalChannelsFixture/NativeSourceInventoryAudit' $admin Post @{ItemKey=[long]$subjects.a.References[1];OptionsRootKey=[long]$subjects.a.References[0]}
        if(-not $optionsAudit.Before.Installed -or $optionsAudit.After.Version -le $optionsAudit.Before.Version -or $optionsAudit.After.Writers -ne 0){throw 'Native collection library-options mutation did not invalidate source inventory'}
        $rows.Add(@{Label='Actual native collection library-options write advances source version';IsolationPass=$true;Before=$optionsAudit.Before;After=$optionsAudit.After})
        $channelPolicies=@{}
        foreach($actor in @('a','b')){
            $policy=(Call "Users/$($subjects[$actor].UserId)").Policy
            $channelPolicies[$actor]=[bool]$policy.EnableAllChannels
            $policy.EnableAllChannels=$true
            Call "Users/$($subjects[$actor].UserId)/Policy" $admin Post $policy | Out-Null
        }
        $publicItems=Call 'Items?Recursive=true&IncludeItemTypes=Video&Limit=100'
        $public=@($publicItems.Items | Where-Object {$_.Name -notlike 'PrivateNative*'})
        if($public.Count -eq 0){throw 'Missing functioning public native source for journal-corruption control'}
        $publicId=[string]$public[0].Id
        $publicQuery='Items?SearchTerm='+[Uri]::EscapeDataString([string]$public[0].Name)+'&Recursive=true&IncludeItemTypes=Video&Limit=100'
        foreach($actor in @('a','b')){
            $baseline=Call $publicQuery $subjects[$actor].Headers
            if(@($baseline.Items|Where-Object Id -eq $publicId).Count -ne 1){throw 'Public native positive control does not function before corruption'}
            $rows.Add(@{Label='Public native positive control before corruption with explicit channel access';Actor=$actor;IsolationPass=$true})
        }
        $journalPath=Join-Path $profileRoot 'publication-journal.json'
        $privateQuery="Items?ParentId=$($subjects.a.References[0])&Recursive=true"
        foreach($actor in @('a','b')){
            $baseline=Call $privateQuery $subjects[$actor].Headers
            $ownCount=@($baseline.Items|Where-Object Id -eq $subjects.a.References[1]).Count
            $safe=if($actor -eq 'a'){$ownCount -eq 1}else{@($baseline.Items).Count -eq 0}
            if(-not $safe){throw 'Private native paired control does not function before corruption'}
            $rows.Add(@{Label='Same private native query has owner positive and foreign negative before corruption';Actor=$actor;IsolationPass=$safe;OwnVideoVisible=$ownCount})
        }
        $journalMarker=Join-Path $profileRoot 'publication-journal.required'
        $savedJournal=if(Test-Path -LiteralPath $journalPath){[IO.File]::ReadAllBytes($journalPath)}else{$null}
        $savedMarker=if(Test-Path -LiteralPath $journalMarker){[IO.File]::ReadAllBytes($journalMarker)}else{$null}
        try{
            [IO.File]::WriteAllText($journalPath,'{')
            [IO.File]::WriteAllBytes($journalMarker,[byte[]]@(1))
            foreach($actor in @('a','b')){
                $visible=Call $publicQuery $subjects[$actor].Headers
                $private=Call $privateQuery $subjects[$actor].Headers
                $safe=@($visible.Items|Where-Object Id -eq $publicId).Count -eq 1 -and @($private.Items).Count -eq 0
                $rows.Add(@{Label='Corrupt native publication journal preserves public source and quarantines private source';Actor=$actor;IsolationPass=$safe;PublicVisible=@($visible.Items).Count;PrivateVisible=@($private.Items).Count})
                if(-not $safe){throw 'Native journal-corruption isolation failed'}
            }
        }finally{
            if($null -eq $savedJournal){Remove-Item -LiteralPath $journalPath}else{[IO.File]::WriteAllBytes($journalPath,$savedJournal)}
            if($null -eq $savedMarker){Remove-Item -LiteralPath $journalMarker}else{[IO.File]::WriteAllBytes($journalMarker,$savedMarker)}
            foreach($actor in @('a','b')){
                $policy=(Call "Users/$($subjects[$actor].UserId)").Policy
                $policy.EnableAllChannels=$channelPolicies[$actor]
                Call "Users/$($subjects[$actor].UserId)/Policy" $admin Post $policy | Out-Null
            }
        }
        Discovery 'After-journal-recovery' $true
    }
    if($InspectNative){
        $inspection=Call 'PersonalChannelsFixture/NativeBoundaryInspection'
        $inspection|ConvertTo-Json -Depth 10|Set-Content (Join-Path $PSScriptRoot 'bin/native-discovery-boundary-inventory.json') -Encoding UTF8
        if($InspectCounts){
            $counts=Call 'PersonalChannelsFixture/NativeAssetProcessingInspection?Counts=true'
            $counts|ConvertTo-Json -Depth 10|Set-Content (Join-Path $PSScriptRoot 'bin/native-counts-processing-inspection.json') -Encoding UTF8
        }
        if($DiscoveryFamily -eq 'Metadata'){
            $metadata=Call 'PersonalChannelsFixture/NativeAssetProcessingInspection?Metadata=true'
            $metadata|ConvertTo-Json -Depth 10|Set-Content (Join-Path $PSScriptRoot 'bin/native-metadata-processing-inspection.json') -Encoding UTF8
            if($metadata.InspectionError){throw ('Native metadata IL inspection failed: '+$metadata.InspectionError)}
        }
        if($DiscoveryFamily -eq 'Search'){
            $search=Call 'PersonalChannelsFixture/NativeAssetProcessingInspection?Search=true'
            $search|ConvertTo-Json -Depth 10|Set-Content (Join-Path $PSScriptRoot 'bin/native-search-hints-processing-inspection.json') -Encoding UTF8
            $searchMethods=@($search.Methods)
            if($search.InspectionError -or $search.Truncated -or $searchMethods.Count -ne 1 -or
                $searchMethods[0].Type -ne 'Emby.Api.Obsolete.SearchService' -or
                $searchMethods[0].BodyHash -ne 'FB1D68D001CCDB4DCB13D7D2D10A50D9191B9903DBEFD12524F5769F78543067' -or
                @($searchMethods[0].Instructions).Count -ne 2 -or
                $searchMethods[0].Instructions[0].Op -ne 'call' -or
                $searchMethods[0].Instructions[0].Operand -ne 'System.Array::System.String[] Empty[String]()' -or
                $searchMethods[0].Instructions[1].Op -ne 'ret'){throw 'Native obsolete search empty-result contract not verified'}
        }
        if($DiscoveryFamily -eq 'SearchHistory'){
            $history=Call 'PersonalChannelsFixture/NativeAssetProcessingInspection?History=true'
            $history|ConvertTo-Json -Depth 10|Set-Content (Join-Path $PSScriptRoot 'bin/native-search-history-processing-inspection.json') -Encoding UTF8
            if($history.InspectionError -or @($history.Methods).Count -eq 0){throw 'Native history IL inspection missing'}
        }
    }
    if($HistoryMutationRace){
        HistoryAction 'A native history clear before mutation timing' a a @() $false Post $true
        $historyBefore=HistorySnapshot
        $gateBefore=Call 'PersonalChannelsFixture/ProductionServiceGate'
        $timing='PersonalChannelsFixture/NativeSearchMutationGate'
        Call $timing $admin Post @{OwnerUserId=$subjects.a.UserId;AfterCheck=[bool]$AfterWriteCheckRace}|Out-Null
        $message=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,($base+"/Users/$($subjects.a.UserId)/SearchedItems/"))
        foreach($key in $subjects.a.Headers.Keys){$message.Headers.TryAddWithoutValidation($key,[string]$subjects.a.Headers[$key])|Out-Null}
        $message.Headers.TryAddWithoutValidation('X-Isolated-Search-Mutation','pause')|Out-Null
        $message.Content=[Net.Http.StringContent]::new((@{Ids=@([string]$subjects.a.References[1]);WasSearched=$true}|ConvertTo-Json),[Text.Encoding]::UTF8,'application/json')
        $pending=$client.SendAsync($message)
        try{
            $deadline=[DateTime]::UtcNow.AddSeconds(10)
            do{$pause=Call $timing;if($pause.Active){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
            $atPause=Call 'PersonalChannelsFixture/ProductionServiceGate';$historyPaused=HistorySnapshot
            $expectedChecked=if($AfterWriteCheckRace){1}else{0}
            if(-not $pause.Active -or $pause.TimedOut -or $pending.IsCompleted -or $pause.AfterCheck -ne [bool]$AfterWriteCheckRace -or
                $atPause.Checked-$gateBefore.Checked -ne $expectedChecked -or $atPause.Denied-$gateBefore.Denied -ne 0 -or
                (@($historyBefore.aDates) -join ',') -ne (@($historyPaused.aDates) -join ',') -or
                (@($historyBefore.bDates) -join ',') -ne (@($historyPaused.bDates) -join ',')){throw 'Native report did not pause at the intended unmutated boundary'}
            $rows.Add(@{Label='Actual report paused before native mutation';AfterCheck=[bool]$AfterWriteCheckRace;CheckedDelta=$expectedChecked;HistoryUnchanged=$true;HttpPending=$true;TimedOut=$false})
            if($AfterWriteCheckRace){
                $deleteMessage=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,($base+'/YouTubePlugin/MyProfile/Delete'))
                foreach($key in $subjects.a.Headers.Keys){$deleteMessage.Headers.TryAddWithoutValidation($key,[string]$subjects.a.Headers[$key])|Out-Null}
                $deleteMessage.Content=[Net.Http.StringContent]::new((@{ExpectedRevision=$subjects.a.Profile.Revision}|ConvertTo-Json),[Text.Encoding]::UTF8,'application/json')
                $deletePending=$client.SendAsync($deleteMessage)
                $deadline=[DateTime]::UtcNow.AddSeconds(5)
                do{$lease=Call "PersonalChannelsFixture/TransferLease?OwnerUserId=$($subjects.a.UserId)";if($lease.Waiting -ge 1){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
                if(-not $lease.Held -or $lease.Waiting -lt 1 -or $deletePending.IsCompleted -or (Call 'YouTubePlugin/MyProfile' $subjects.a.Headers).State -ne 'Draft'){throw 'Deletion did not wait at report mutation lease'}
                $saved=Call 'YouTubePlugin/MyProfile' $subjects.b.Headers Post @{ExpectedRevision=$subjects.b.Profile.Revision;Channels=@('UC'+('b'*22))}
                if($saved.Revision -ne $subjects.b.Profile.Revision+1){throw 'B update blocked by A report mutation'}
                $subjects.b.Profile=$saved
                $rows.Add(@{Label='Deletion waits at report mutation lease while B update succeeds';Held=$true;Waiting=$lease.Waiting;DeletePending=$true;BRevisionAdvanced=$true})
            }else{
                $deleted=Call 'YouTubePlugin/MyProfile/Delete' $subjects.a.Headers Post @{ExpectedRevision=$subjects.a.Profile.Revision}
                if($deleted.State -ne 'Deleted' -or (Call 'YouTubePlugin/MyProfile' $subjects.a.Headers).State -ne 'Deleted'){throw 'Deletion not persisted before report access check'}
                $rows.Add(@{Label='Deletion persisted before report access check';Deleted=$true;HttpPending=$true})
            }
            $pause=Call $timing
            if(-not $pause.Active -or $pause.TimedOut -or $pending.IsCompleted){throw 'Report mutation pause expired'}
        }finally{Call $timing $admin Post @{Release=$true}|Out-Null}
        $response=$pending.GetAwaiter().GetResult()
        try{
            $bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();$text=[Text.Encoding]::UTF8.GetString($bytes)
            $historyAfter=HistorySnapshot;$gateAfter=Call 'PersonalChannelsFixture/ProductionServiceGate'
            $unchanged=(@($historyBefore.aDates) -join ',') -eq (@($historyAfter.aDates) -join ',') -and (@($historyBefore.bDates) -join ',') -eq (@($historyAfter.bDates) -join ',')
            $safe=if($AfterWriteCheckRace){[int]$response.StatusCode -eq 204 -and [string]$subjects.a.References[1] -in @($historyAfter.a) -and @($historyAfter.b).Count -eq 0}else{[int]$response.StatusCode -eq 404 -and $text -eq 'Item not found.' -and $bytes.Length -eq 15 -and $unchanged}
            $expectedDenied=if($AfterWriteCheckRace){0}else{1}
            $safe=$safe -and $gateAfter.Checked-$gateBefore.Checked -eq 1 -and $gateAfter.Denied-$gateBefore.Denied -eq $expectedDenied
            $rows.Add(@{Label='Actual report response after mutation pause';AfterCheck=[bool]$AfterWriteCheckRace;Status=[int]$response.StatusCode;Bytes=$bytes.Length;Before=$historyBefore;After=$historyAfter;Unchanged=$unchanged;CheckedDelta=$gateAfter.Checked-$gateBefore.Checked;DeniedDelta=$gateAfter.Denied-$gateBefore.Denied;IsolationPass=$safe})
            if(-not $safe){throw 'Native report mutation ordering failed'}
        }finally{$response.Dispose();$message.Dispose()}
        if($AfterWriteCheckRace){
            $deleteResponse=$deletePending.GetAwaiter().GetResult()
            try{
                $deleted=$deleteResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json
                $lease=Call "PersonalChannelsFixture/TransferLease?OwnerUserId=$($subjects.a.UserId)"
                if([int]$deleteResponse.StatusCode -ne 200 -or $deleted.State -ne 'Deleted' -or $lease.Held -or $lease.Waiting){throw 'Queued report deletion did not persist after mutation'}
                $rows.Add(@{Label='Queued report deletion persisted after native mutation';State='Deleted';Held=$false;Waiting=0})
            }finally{$deleteResponse.Dispose();$deleteMessage.Dispose()}
        }
    }elseif($WriterRace -ne 'None'){
        $timing=if($isImageWriter){'PersonalChannelsFixture/NativeReferenceWriteGate'}else{'PersonalChannelsFixture/NativeListWriteGate'}
        $before=Call 'PersonalChannelsFixture/ProductionItemList'
        $arm=@{OwnerUserId=$subjects.a.UserId;AfterCheck=[bool]$AfterWriteCheckRace}
        $writerPath=DiscoveryPath $subjects.a.UserId $WriterRace
        if($isImageWriter){
            $imageKind=$WriterRace.Replace('Image','');$imageMetadata=@($subjects.a.Metadata.$imageKind)[0]
            $arm.Asset=if($MetadataImageStyle -eq 'Id'){'Image'}else{'MetadataImage'}
            $writerPath=if($MetadataImageStyle -eq 'Id'){"Items/$($imageMetadata.Id)/Images/Primary?Format=png"}else{"$imageKind/$([Uri]::EscapeDataString($imageMetadata.Name))/Images/Primary"+$(if($MetadataImageStyle -eq 'NameIndex'){'/0'}else{''})+'?Format=png'}
            if($DerivedMetadataImages){$writerPath+='&MaxWidth=80&MaxHeight=45'}
        }
        Call $timing $admin Post $arm|Out-Null
        $message=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,($base+'/'+$writerPath))
        foreach($key in $subjects.a.Headers.Keys){$message.Headers.TryAddWithoutValidation($key,[string]$subjects.a.Headers[$key])|Out-Null}
        if($isImageWriter){$message.Headers.TryAddWithoutValidation('X-Isolated-Reference-Gate','before-write')|Out-Null}
        $pending=$client.SendAsync($message)
        try{
            $deadline=[DateTime]::UtcNow.AddSeconds(10)
            do{$pause=Call $timing;if($pause.Active){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
            if(-not $pause.Active -or $pause.TimedOut -or $pending.IsCompleted -or $pause.AfterCheck -ne [bool]$AfterWriteCheckRace){throw 'Actual selected discovery writer did not pause'}
            if($isImageWriter -and $pause.ResultContract -ne 'Emby.Server.Implementations.HttpServer.FileWriter'){throw 'Expected actual native metadata image FileWriter'}
            $rows.Add(@{Label='Actual selected discovery writer paused';Kind=$WriterRace;AfterCheck=[bool]$AfterWriteCheckRace;HttpPending=$true;TimedOut=$false})
            if($AfterWriteCheckRace){
                $deleteMessage=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,($base+'/YouTubePlugin/MyProfile/Delete'))
                foreach($key in $subjects.a.Headers.Keys){$deleteMessage.Headers.TryAddWithoutValidation($key,[string]$subjects.a.Headers[$key])|Out-Null}
                $deleteMessage.Content=[Net.Http.StringContent]::new((@{ExpectedRevision=$subjects.a.Profile.Revision}|ConvertTo-Json),[Text.Encoding]::UTF8,'application/json')
                $deletePending=$client.SendAsync($deleteMessage)
                $deadline=[DateTime]::UtcNow.AddSeconds(5)
                do{$lease=Call "PersonalChannelsFixture/TransferLease?OwnerUserId=$($subjects.a.UserId)";if($lease.Waiting -ge 1){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
                if(-not $lease.Held -or $lease.Waiting -lt 1 -or $deletePending.IsCompleted -or (Call 'YouTubePlugin/MyProfile' $subjects.a.Headers).State -ne 'Draft'){throw 'Discovery deletion did not wait at owner writer lease'}
                $saved=Call 'YouTubePlugin/MyProfile' $subjects.b.Headers Post @{ExpectedRevision=$subjects.b.Profile.Revision;Channels=@('UC'+('b'*22))}
                if($saved.Revision -ne $subjects.b.Profile.Revision+1){throw 'Independent B discovery profile update failed'}
                $subjects.b.Profile=$saved
                $rows.Add(@{Label='Discovery deletion waits at actual owner lease while B update succeeds';Held=$true;Waiting=$lease.Waiting;DeletePending=$true;BRevisionAdvanced=$true})
            }else{
                $deleted=Call 'YouTubePlugin/MyProfile/Delete' $subjects.a.Headers Post @{ExpectedRevision=$subjects.a.Profile.Revision}
                if($deleted.State -ne 'Deleted' -or (Call 'YouTubePlugin/MyProfile' $subjects.a.Headers).State -ne 'Deleted'){throw 'Discovery deletion not persisted before writer release'}
                $rows.Add(@{Label='Actual discovery profile deletion persisted before writer release';Deleted=$true;HttpPending=$true})
            }
            $pause=Call $timing
            if(-not $pause.Active -or $pause.TimedOut -or $pending.IsCompleted){throw 'Discovery writer pause expired before release'}
        }finally{Call $timing $admin Post @{Release=$true}|Out-Null}
        $response=$pending.GetAwaiter().GetResult()
        try{
            $bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();$text=[Text.Encoding]::UTF8.GetString($bytes)
            $names=@($response.Headers|ForEach-Object{$_.Key})+@($response.Content.Headers|ForEach-Object{$_.Key})
            $entities=@($names|Where-Object {$_ -in @('ETag','Last-Modified','Content-Disposition','Content-Range','Accept-Ranges')})
            $expectedOwn=if($WriterRace -eq 'Views'){$subjects.a.LibraryName}else{'PrivateNativeVideo_a_client'}
            $safe=if($AfterWriteCheckRace){[int]$response.StatusCode -eq 200 -and $text.Contains($expectedOwn) -and -not $text.Contains('PrivateNativeVideo_b_client') -and -not $text.Contains($subjects.b.LibraryName)}else{[int]$response.StatusCode -eq 404 -and $text -eq 'Items not found.' -and $bytes.Length -eq 16 -and $entities.Count -eq 0}
            if($AfterWriteCheckRace -and $WriterRace -eq 'Counts'){$safe=[int]$response.StatusCode -eq 200 -and (ExactCounts ($text|ConvertFrom-Json) 1)}
            if($AfterWriteCheckRace -and $WriterRace -in @('Genres','Studios','Tags')){
                $singular=if($WriterRace -eq 'Genres'){'Genre'}elseif($WriterRace -eq 'Studios'){'Studio'}else{'Tag'}
                $body=if([int]$response.StatusCode -eq 200){$text|ConvertFrom-Json}else{$null}
                $safe=[int]$response.StatusCode -eq 200 -and $body.TotalRecordCount -eq 2 -and @($body.Items).Count -eq 2 -and "PrivateNative${singular}_a" -in $body.Items.Name -and -not $text.Contains("PrivateNative${singular}_b")
                $safe=$safe -and "SharedNative${singular}" -in $body.Items.Name
            }
            if($AfterWriteCheckRace -and $isImageWriter){
                $sha=[Security.Cryptography.SHA256]::Create()
                try{$ownHash=[BitConverter]::ToString($sha.ComputeHash([byte[]]$bytes)).Replace('-','')}finally{$sha.Dispose()}
                $matches=if($DerivedMetadataImages){DerivedMetadataImageMatches $bytes 'a'}else{$ownHash -eq $subjects.a.MetadataImageHash}
                $safe=[int]$response.StatusCode -eq 200 -and $matches
            }
            $rows.Add(@{Label='Actual paused discovery response';Kind=$WriterRace;AfterCheck=[bool]$AfterWriteCheckRace;Status=[int]$response.StatusCode;Bytes=$bytes.Length;EntityHeaderCount=$entities.Count;IsolationPass=$safe})
            if(-not $safe){throw 'Paused discovery response is not safe'}
        }finally{$response.Dispose();$message.Dispose()}
        $after=Call 'PersonalChannelsFixture/ProductionItemList';$denied=$after.WritesDenied-$before.WritesDenied
        $expectedDenials=if($AfterWriteCheckRace){0}else{1}
        if(-not $after.Installed -or $denied -ne $expectedDenials){throw 'Discovery native writer boundary did not account for its response'}
        $rows.Add(@{Label='Actual discovery writer boundary accounted for response';DeniedDelta=$denied;ExpectedDelta=$expectedDenials})
        if($AfterWriteCheckRace){
            $deleteResponse=$deletePending.GetAwaiter().GetResult()
            try{
                $deleted=$deleteResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json
                $lease=Call "PersonalChannelsFixture/TransferLease?OwnerUserId=$($subjects.a.UserId)"
                if([int]$deleteResponse.StatusCode -ne 200 -or $deleted.State -ne 'Deleted' -or $lease.Held -or $lease.Waiting){throw 'Queued discovery deletion did not finish after writer release'}
                $rows.Add(@{Label='Queued discovery deletion persisted after writer release';State=$deleted.State;Held=$false;Waiting=0})
            }finally{$deleteResponse.Dispose();$deleteMessage.Dispose()}
        }
    }else{$deleted=Call 'YouTubePlugin/MyProfile/Delete' $subjects.a.Headers Post @{ExpectedRevision=$subjects.a.Profile.Revision}}
    if($deleted.State -ne 'Deleted' -or (Call 'YouTubePlugin/MyProfile' $subjects.a.Headers).State -ne 'Deleted'){throw 'A discovery profile deletion not persisted'}
    Discovery 'Deleted' $false
    $boot=(Call 'PersonalChannelsFixture/Guard').BootId
    & $control -Stop|Out-Null
    & $control|Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(40)
    do{try{$guard=Call 'PersonalChannelsFixture/Guard';if($guard.Ready -and $guard.BootId -ne $boot){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    if(-not $guard.Ready -or $guard.BootId -eq $boot){throw 'Discovery actual restart not established'}
    $state=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
    if($state.ExperimentalEnabled -or -not $state.Production.Installed -or -not (Call 'PersonalChannelsFixture/ProductionItemList').Installed){throw 'Discovery production-only restart not ready'}
    $rows.Add(@{Label='Actual restart with production gates and experimental guard disabled';Verified=$true})
    Discovery 'Restarted' $false
    $failures=@($rows|Where-Object {$_.ContainsKey('IsolationPass') -and -not $_.IsolationPass})
    if($RequireIsolation -and $failures.Count){throw 'Discovery isolation not achieved'}
    $completed=$true
}finally{
    $name=if($RequireIsolation){'production-discovery-protected-results.json'}else{'production-discovery-diagnostic-results.json'}
    if($InspectCounts){$name=$name.Replace('discovery-','discovery-counts-inspection-')}
    if($InspectSourceInventory){$name=$name.Replace('discovery-','discovery-source-inventory-')}
    if($FixtureMovies){$name=$name.Replace('counts-inspection-','counts-movies-inspection-')}
    if($DiscoveryFamily -ne 'Standard'){$name=$name.Replace('discovery-',('discovery-'+$DiscoveryFamily.ToLowerInvariant()+'-'))}
    if($InspectMetadataReferences){$name=$name.Replace('metadata-','metadata-references-')}
    if($InspectMetadataImages){$name=$name.Replace('metadata-','metadata-images-')}
    if($PublicMetadataA){$name=$name.Replace('metadata-references-','metadata-references-public-a-')}
    if($PublicMetadataA){$name=$name.Replace('metadata-images-','metadata-images-public-a-')}
    if($PublicMetadataA){$name=$name.Replace('searchhistory-','searchhistory-public-a-')}
    if($DerivedMetadataImages){$name=$name.Replace('-results.json','-derived-results.json')}
    if($DynamicViews){$name=$name.Replace('discovery-','discovery-dynamic-views-')}
    if($WriterRace -ne 'None'){$name=$name.Replace('-results.json',('-'+$WriterRace.ToLowerInvariant()+$(if($AfterWriteCheckRace){'-write-lease'}else{'-write-revocation'})+'-results.json'))}
    if($isImageWriter){$name=$name.Replace('-results.json',('-'+$MetadataImageStyle.ToLowerInvariant()+'-results.json'))}
    if($HistoryMutationRace){$name=$name.Replace('-results.json',$(if($AfterWriteCheckRace){'-mutation-lease-results.json'}else{'-mutation-revocation-results.json'}))}
    @{Completed=$completed;DiscoveryFamily=$DiscoveryFamily;DynamicViews=[bool]$DynamicViews;Observations=$rows.ToArray();Scope='Selected actual native discovery family with own native positive controls and counts, broad ordinary folder rights, claimed other user, profile deletion and restart; require actual service/query/root-source counters for isolation verification; no universal discovery or client proof'}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot ('bin/'+$name)) -Encoding UTF8
    try{
        & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null
        if(Test-Path -LiteralPath $profileRoot){
            $dir=[IO.Path]::GetFullPath($profileRoot);$expected=[IO.Path]::GetFullPath((Join-Path $root 'data/data/youtube-personal'))
            if($dir -ne $expected -or -not $dir.StartsWith([IO.Path]::GetFullPath($root)+[IO.Path]::DirectorySeparatorChar)){throw 'Unsafe discovery profile cleanup'}
            $names=@('encryption.key','native-reference-bindings.json','native-reference-bindings.required','private-source-scopes.json','private-source-scopes.required')+@($subjects.Values|ForEach-Object{$_.UserId+'.json'})
            $files=@(Get-ChildItem -LiteralPath $dir -Force)
            if(@($files|Where-Object {$_.PSIsContainer -or $_.Name -notin $names -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)}).Count){throw 'Unexpected discovery profile file'}
            foreach($file in $files){Remove-Item -LiteralPath $file.FullName}
            Remove-Item -LiteralPath $dir
        }
    }finally{$client.Dispose()}
}
Write-Output ('Discovery observations='+$rows.Count+'; isolation failures='+$failures.Count)
