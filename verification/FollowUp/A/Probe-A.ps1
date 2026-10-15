# Loaded in the existing production-only lifecycle fixture's scope. Never log tokens.
function AState {
    $snapshot=@{}
    foreach($owner in @('a','b')){foreach($source in @('a','b')){
        $snapshot[$owner+$source]=Call "PersonalChannelsFixture/AUserData?UserId=$($subjects[$owner].UserId)&ItemId=$($subjects[$source].References[1])"
    }}
    return ($snapshot|ConvertTo-Json -Depth 5 -Compress)
}
function ARead($label,$path,$actor,$deniedOwner=''){
    $headers=if($actor -eq 'anonymous'){@{}}else{$subjects[$actor].Headers}
    $before=Call 'PersonalChannelsFixture/ProductionItemList'
    $r=Request $path $headers
    $after=Call 'PersonalChannelsFixture/ProductionItemList'
    $privatePresent=$false
    if($deniedOwner){
        $privatePresent=$r.Text.Contains("PrivateNativeVideo_$($deniedOwner)_client") -or (ReferencesPrivate $(if($r.Status -eq 200 -and $r.Text){$r.Text|ConvertFrom-Json}else{$null}) $subjects[$deniedOwner].References)
        $privatePresent=$privatePresent -or $r.Text.Contains("PrivateNativePerson_$deniedOwner") -or $r.Text.Contains("PrivateNativeRating_$deniedOwner")
        if($path.StartsWith('Years?')){$privatePresent=$privatePresent -or $r.Text.Contains($(if($deniedOwner -eq 'a'){'2001'}else{'2002'}))}
    }
    $body=if($r.Status -eq 200 -and $r.Text){$r.Text|ConvertFrom-Json}else{$null}
    $rows.Add(@{Label=$label;Actor=$actor;Status=$r.Status;ForeignContent=$privatePresent;PrivateHeader=if($deniedOwner -eq 'a'){$r.PrivateAHeader}elseif($deniedOwner -eq 'b'){$r.PrivateBHeader}else{$false};
        EntityHeaders=@($r.HeaderNames|Where-Object {$_ -in @('ETag','Last-Modified','Content-Disposition','Content-Range','Accept-Ranges')});
        Total=$body.TotalRecordCount;Names=@($body.Items|ForEach-Object Name);ServiceDelta=$after.Requests-$before.Requests;QueryDelta=$after.Queries-$before.Queries;
        Route=($path -replace '[0-9a-fA-F]{32,36}','{reference}' -replace '\b\d{5,}\b','{item}');Body=$body;
        IsolationPass=-not $privatePresent})
    return $r
}
function Invoke-AProbe($phase,$aActive){
    $a=$subjects.a;$b=$subjects.b
    if($phase -eq 'Active'){
        $audit=Call 'PersonalChannelsFixture/ApiAudit'
        $audit|ConvertTo-Json -Depth 16|Set-Content (Join-Path $PSScriptRoot 'bin/api-audit.json') -Encoding UTF8
        Invoke-APlaylists
    }
    foreach($actor in @('a','b')){
        $uid=$subjects[$actor].UserId;$other=if($actor -eq 'a'){'b'}else{'a'}
        $denied=if($PublicMetadataA -and $other -eq 'a'){''}else{$other}
        foreach($family in @('Items','Movies','Shows','Trailers','Albums','Artists','Games')){
            foreach($seed in @($actor,$other)){
                ARead "$phase $actor $family Similar seed $seed" "$family/$($subjects[$seed].References[1])/Similar?UserId=$uid&Limit=100" $actor $denied|Out-Null
            }
        }
        foreach($family in @('Movies/Recommendations','Years','OfficialRatings','Persons','Artists','Artists/AlbumArtists','Artists/Prefixes','MusicGenres')){
            foreach($claim in @($actor,$other)){
                ARead "$phase $actor $family claimed $claim" "$family`?UserId=$($subjects[$claim].UserId)&Recursive=true&Limit=100" $actor $denied|Out-Null
            }
        }
        foreach($source in @('a','b')){
            $person="PrivateNativePerson_$source"
            ARead "$phase $actor Persons named $source" "Persons/$person`?UserId=$uid" $actor $denied|Out-Null
            $people=Call "Persons?UserId=$uid&Limit=100" $subjects[$actor].Headers
            $reference=@($people.Items|Where-Object Name -eq $person|Select-Object -ExpandProperty Id)
            if($reference.Count -eq 1){
                ARead "$phase $actor Person ID $source" "Items/$($reference[0])?UserId=$uid" $actor $denied|Out-Null
                ARead "$phase $actor Person Credits $source" "Persons/$($reference[0])/Credits?UserId=$uid" $actor $denied|Out-Null
            }
        }
        foreach($route in @('Items',"Users/$uid/Items")){
            foreach($query in @('StartIndex=0&Limit=1&SortBy=SortName&SortOrder=Descending','StartIndex=1&Limit=1','StartIndex=0&Limit=0',
                "Ids=$($a.References[1]),$($b.References[1])", "ParentId=$($subjects[$other].LibraryId)", 'Filters=IsUnplayed','SortBy=DateCreated&SortOrder=Ascending')){
                ARead "$phase $actor page/filter $query" "$route`?UserId=$uid&Recursive=true&IncludeItemTypes=Movie&EnableTotalRecordCount=true&$query" $actor $denied|Out-Null
            }
        }
    }
    foreach($path in @("Items/$($a.References[1])/Similar",'Movies/Recommendations','Years','Persons')){ARead "$phase anonymous $path" $path anonymous a|Out-Null}
    foreach($actor in @('a','b')){
        $other=if($actor -eq 'a'){'b'}else{'a'}
        foreach($target in @($actor,$other)){
            foreach($claim in @($actor,$other)){
                foreach($mutation in @('favorite-set','favorite-delete','favorite-postdelete','played-set','played-delete','played-postdelete','rating-set','rating-delete','rating-postdelete')){
                    if($phase -ne 'Active' -and $target -ne 'a'){continue}
                    $method=if($mutation.EndsWith('-delete')){'Delete'}else{'Post'}
                    $family=if($mutation.StartsWith('favorite')){'FavoriteItems'}elseif($mutation.StartsWith('played')){'PlayedItems'}else{'Items'}
                    $path="Users/$($subjects[$claim].UserId)/$family/$($subjects[$target].References[1])"
                    if($mutation.StartsWith('rating')){$path+='/Rating?Likes=true'}
                    if($mutation.EndsWith('postdelete')){$path=$path.Replace('?Likes=true','')+'/Delete'}
                    $before=AState;$r=Request $path $subjects[$actor].Headers $method;$after=AState
                    $ownState=($after|ConvertFrom-Json).($actor+$target)
                    $beforeState=$before|ConvertFrom-Json;$afterState=$after|ConvertFrom-Json
                    $otherStateStable=$true
                    foreach($key in @('aa','ab','ba','bb')|Where-Object {$_ -ne ($actor+$target)}){
                        if(($beforeState.$key|ConvertTo-Json -Compress) -ne ($afterState.$key|ConvertTo-Json -Compress)){$otherStateStable=$false}
                    }
                    $field=if($mutation.StartsWith('favorite')){'IsFavorite'}elseif($mutation.StartsWith('played')){'Played'}else{'Rating'}
                    $expected=if($mutation.EndsWith('-set')){$true}elseif($mutation.StartsWith('rating')){$null}else{$false}
                    $stateMatches=$ownState.$field -eq $expected
                    if($field -eq 'Rating' -and $mutation.EndsWith('-set')){$stateMatches=$null -ne $ownState.Rating}
                    $allowed=($actor -eq $claim -and ($target -eq $actor -and ($target -ne 'a' -or $aActive) -or ($PublicMetadataA -and $target -eq 'a')))
                    $rows.Add(@{Label="$phase $actor $mutation target $target claimed $claim";Mutation=$mutation;Actor=$actor;Target=$target;Claim=$claim;Status=$r.Status;ExpectedAllowed=$allowed;Changed=$before -ne $after;Before=($before|ConvertFrom-Json);After=($after|ConvertFrom-Json);
                        Route=$path;Method=$method;StateMatches=$stateMatches;OtherStateStable=$otherStateStable;
                        IsolationPass=if($allowed){$r.Status -in @(200,204) -and $stateMatches -and $otherStateStable}else{$r.Status -in @(401,403,404) -and $before -eq $after}})
                }
            }
        }
    }
    # Admin-only requests use valid DTO shape but never delete the sources.
    foreach($actor in @('a','b','anonymous')){
        $headers=if($actor -eq 'anonymous'){@{}}else{$subjects[$actor].Headers}
        foreach($path in @("Items/$($a.References[1])/Refresh?Recursive=false&MetadataRefreshMode=None&ImageRefreshMode=None", "Items/$($a.References[1])")){
            $r=Request $path $headers Post $(if($path.EndsWith($a.References[1])){@{Id=$a.References[1];Name='PrivateNativeVideo_a_client'}}else{$null})
            $rows.Add(@{Label="$phase $actor administrative $path";Status=$r.Status;IsolationPass=$r.Status -in @(401,403,404)})
        }
    }
}
function Invoke-APlaylists {
    $created=[Collections.Generic.List[string]]::new()
    Call 'PersonalChannelsFixture/ACleanupPlaylists' $admin Post|Out-Null
    try{
        foreach($actor in @('a','b')){
            $other=if($actor -eq 'a'){'b'}else{'a'}
            foreach($source in @($actor,$other,'mixed')){
                $ids=if($source -eq 'mixed'){($subjects.a.References[1],$subjects.b.References[1]) -join ','}else{$subjects[$source].References[1]}
                $r=Request 'Playlists' $subjects[$actor].Headers Post @{Name="A-audit-$actor-$source";UserId=$subjects[$actor].UserId;Ids=$ids;MediaType='Video'}
                $body=if($r.Status -eq 200){$r.Text|ConvertFrom-Json}else{$null}
                $rows.Add(@{Label="Active $actor playlist create $source";Status=$r.Status;Created=[bool]$body.Id;IsolationPass=if($source -eq $actor -or ($PublicMetadataA -and $source -eq 'a')){$r.Status -eq 200 -and [bool]$body.Id}else{$r.Status -in @(401,403,404)}})
                if(-not $body.Id){continue}
                $created.Add([string]$body.Id)
                $denied=if($PublicMetadataA -and $other -eq 'a'){''}else{$other}
                ARead "Active $actor playlist $source actual items" "Playlists/$($body.Id)/Items?UserId=$($subjects[$actor].UserId)&Limit=100" $actor $denied|Out-Null
                if($source -eq $actor){
                    $add=Request "Playlists/$($body.Id)/Items?UserId=$($subjects[$actor].UserId)&Ids=$($subjects[$other].References[1])" $subjects[$actor].Headers Post
                    $rows.Add(@{Label="Active $actor playlist add foreign $other";Status=$add.Status;IsolationPass=if($PublicMetadataA -and $other -eq 'a'){$add.Status -in @(200,204)}else{$add.Status -in @(401,403,404)}})
                    ARead "Active $actor playlist read after foreign add" "Playlists/$($body.Id)/Items?UserId=$($subjects[$actor].UserId)&Limit=100" $actor $denied|Out-Null
                    ARead "Active $other other account playlist read" "Playlists/$($body.Id)/Items?UserId=$($subjects[$other].UserId)&Limit=100" $other $actor|Out-Null
                }
            }
        }
    }finally{
        Call 'PersonalChannelsFixture/ACleanupPlaylists' $admin Post|Out-Null
        $remaining=Call 'Items?Recursive=true&IncludeItemTypes=Playlist&SearchTerm=A-audit'
        if(@($remaining.Items|Where-Object Name -like 'A-audit-*').Count){throw 'A playlists remain after cleanup'}
        $rows.Add(@{Label='A playlist cleanup native query readback';Removed=$true;CreatedCount=$created.Count})
    }
}
