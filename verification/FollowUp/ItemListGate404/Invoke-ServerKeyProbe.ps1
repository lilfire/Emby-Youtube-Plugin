# Dot-sourced by Test-ProductionDiscoveryLists.ps1 through PERSONAL_YOUTUBE_A_PROBE.
# Uses that script's $subjects, $rows, Request, Call, ReferencesPrivate and $admin.
# Server-API-key requests (as Home Assistant embymedia sends them) must return
# 200 with public fixture content and no personal A/B library, video or source.
function Invoke-AProbe($phase,$aActive){
    if(-not $script:serverKey){
        Call 'Auth/Keys?App=ItemListGateServerKeyProbe' $admin Post | Out-Null
        $script:serverKey=@((Call 'Auth/Keys').Items|Where-Object AppName -eq 'ItemListGateServerKeyProbe')[0].AccessToken
        if(-not $script:serverKey){throw 'Server key probe could not create its API key'}
    }
    $key=@{'X-Emby-Token'=$script:serverKey}
    $private=@($subjects.a.References)+@($subjects.b.References)
    $privateNames=@($subjects.a.LibraryName,$subjects.b.LibraryName,'PrivateNativeVideo')
    $cases=[ordered]@{
        'Counts'='Items/Counts'
        'VirtualFolders'='Library/VirtualFolders'
        'BoxSetLimit0'='Items?IncludeItemTypes=BoxSet&Limit=0&Recursive=true'
        'ItemsAll'='Items?Recursive=true&Fields=Path,ProviderIds&EnableTotalRecordCount=true'
        'ItemsVideos'='Items?Recursive=true&IncludeItemTypes=Video&EnableTotalRecordCount=true'
        'UserAItems'="Users/$($subjects.a.UserId)/Items?Recursive=true&IncludeItemTypes=Video&EnableTotalRecordCount=true"
        'UserBViews'="Users/$($subjects.b.UserId)/Views"
        'UserALatest'="Users/$($subjects.a.UserId)/Items/Latest?IncludeItemTypes=Video&GroupItems=false&Limit=100"
    }
    foreach($name in $cases.Keys){
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $r=Request $cases[$name] $key
        $watch.Stop()
        $body=if($r.Status -eq 200){$r.Text|ConvertFrom-Json}else{$null}
        $leak=(ReferencesPrivate $body $private) -or @($privateNames|Where-Object {$_ -and $r.Text.Contains($_)}).Count -gt 0
        $public=$name -notin @('ItemsAll','ItemsVideos') -or $r.Text.Contains('Fixture Video')
        $publicNames=@(if($body -and $body.Items){$body.Items|ForEach-Object Name|Where-Object {$_ -notlike 'PrivateNativeVideo*'}})
        if($name -eq 'UserAItems'){
            # Expected public result is exactly what B (no access to A) sees for its own account.
            $control=Request "Users/$($subjects.b.UserId)/Items?Recursive=true&IncludeItemTypes=Video&EnableTotalRecordCount=true" $subjects.b.Headers
            $expected=@(($control.Text|ConvertFrom-Json).Items|ForEach-Object Name|Where-Object {$_ -notlike 'PrivateNativeVideo*'})
            $public=(@($publicNames|Sort-Object) -join '|') -eq (@($expected|Sort-Object) -join '|')
        }
        $pass=$r.Status -eq 200 -and -not $leak -and $public
        $rows.Add(@{Label="$phase server key $name";Kind='ServerKey';Status=$r.Status;Ms=$watch.ElapsedMilliseconds;PrivatePresent=$leak;PublicPositive=$public;PublicCount=$publicNames.Count;TotalRecordCount=$body.TotalRecordCount;IsolationPass=$pass})
    }
    # Paired owner controls keep the private items meaningful for the negatives above.
    foreach($actor in @('a','b')){
        if($actor -eq 'a' -and -not $aActive){continue}
        $r=Request "Users/$($subjects[$actor].UserId)/Items?Recursive=true&IncludeItemTypes=Video&EnableTotalRecordCount=true" $subjects[$actor].Headers
        $own=$r.Status -eq 200 -and $r.Text.Contains("PrivateNativeVideo_${actor}_client")
        $other=if($actor -eq 'a'){'b'}else{'a'}
        $foreign=$r.Text.Contains("PrivateNativeVideo_${other}_client")
        $rows.Add(@{Label="$phase owner $actor own private positive";Kind='OwnerControl';Status=$r.Status;OwnPresent=$own;ForeignPresent=$foreign;IsolationPass=($own -and -not $foreign)})
        if(-not $own){throw 'Owner private positive control missing'}
    }
    foreach($bad in @(@{},@{'X-Emby-Token'='0123456789abcdef0123456789abcdef'})){
        $r=Request 'Items/Counts' $bad
        $rows.Add(@{Label="$phase $(if($bad.Count){'invalid key'}else{'anonymous'}) Counts";Kind='ServerKeyNegative';Status=$r.Status;IsolationPass=($r.Status -in @(401,403,404))})
    }
}
