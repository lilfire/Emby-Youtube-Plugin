$ErrorActionPreference='Stop'
$base='http://127.0.0.1:18096/emby/'
$auth=Get-Content (Join-Path $PSScriptRoot '../WatchState/bin/emby-isolated/test-auth.json') -Raw|ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$state=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
$rows=[Collections.Generic.List[object]]::new();$subjects=@{}
function Request($path,$headers=$admin,$method='Get',$body=$null){
    $args=@{Uri=$base+$path;Headers=$headers;Method=$method;TimeoutSec=20;UseBasicParsing=$true}
    if($null -ne $body){$args.ContentType='application/json';$args.Body=$body|ConvertTo-Json -Depth 12}
    try{$r=Invoke-WebRequest @args;return @{Status=[int]$r.StatusCode;Text=$r.Content}}
    catch{if(-not $_.Exception.Response){throw};return @{Status=[int]$_.Exception.Response.StatusCode;Text=[string]$_.ErrorDetails.Message}}
}
function Control($path,$headers=$admin,$method='Get',$body=$null){$r=Request $path $headers $method $body;if($r.Status -lt 200 -or $r.Status -ge 300){throw 'Shared channel control failed'};if($r.Text){return ($r.Text|ConvertFrom-Json)}}
function Observe($label,$path,$headers,$expected,$method='Get'){
    $r=Request $path $headers $method;$rows.Add(@{Label=$label;Status=$r.Status});if($r.Status -ne $expected){throw 'Shared video access failed'};return $r
}
try{
    $info=Control 'System/Info/Public';$guard=Control 'PersonalChannelsFixture/Guard'
    if($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0' -or -not $guard.Enabled -or -not $guard.Ready -or -not $state.SetupReady){throw 'Wrong isolated fixture'}
    foreach($owner in @('a','b')){
        $u=@($state.Users|Where-Object Owner -eq $owner)[0]
        $login=Control 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Shared video test`", Device=`"Isolated`", DeviceId=`"shared-$owner`", Version=`"1.0`""} Post @{Username=$u.Name;Pw=''}
        if($login.User.Id -ne $u.UserId -or $login.User.Policy.IsAdministrator){throw 'Wrong ordinary account'}
        $subjects[$owner]=@{UserId=$u.UserId;Headers=@{'X-Emby-Token'=$login.AccessToken}}
    }
    Control 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@(@{Owner='a';Revision=1},@{Owner='b';Revision=1});Prune=$true}|Out-Null
    $channels=(Control 'Channels').Items
    $ownership=@{};foreach($library in $state.Libraries){$ownership[$library.LibraryId]=($state.Users|Where-Object Owner -eq $library.Owner).UserId}
    foreach($owner in @('a','b')){
        $channel=@($channels|Where-Object Name -eq "Personal Fixture $owner")
        if($channel.Count -ne 1){throw 'Personal channel missing'}
        $items=(Control "Items?ParentId=$($channel[0].Id)&Recursive=true&IncludeItemTypes=Video&Fields=ProviderIds").Items
        $shared=@($items|Where-Object {$_.ProviderIds.YouTube -eq 'shared00001'})
        if($shared.Count -ne 1){throw 'Shared video not materialized'}
        $subjects[$owner].ChannelId=$channel[0].Id;$subjects[$owner].ItemId=$shared[0].Id
    }
    $distinct=$subjects.a.ItemId -ne $subjects.b.ItemId -and $subjects.a.ChannelId -ne $subjects.b.ChannelId
    if(-not $distinct){throw 'Shared raw video collapsed private identities'}
    Control 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId;OwnerUserIds=@{a=$subjects.a.UserId;b=$subjects.b.UserId};RootOwnerUserIds=$ownership}|Out-Null
    foreach($owner in @('a','b')){
        $s=$subjects[$owner];$other=if($owner -eq 'a'){'b'}else{'a'}
        Observe "$owner own shared copy" "Users/$($s.UserId)/Items/$($s.ItemId)" $s.Headers 200|Out-Null
        Observe "$owner foreign shared copy" "Users/$($s.UserId)/Items/$($subjects[$other].ItemId)" $s.Headers 404|Out-Null
    }
    Observe 'A mark own shared copy played' "Users/$($subjects.a.UserId)/PlayedItems/$($subjects.a.ItemId)" $subjects.a.Headers 200 Post|Out-Null
    $a=(Observe 'A own shared state after mark' "Users/$($subjects.a.UserId)/Items/$($subjects.a.ItemId)" $subjects.a.Headers 200).Text|ConvertFrom-Json
    $b=(Observe 'B own shared state before foreign mark' "Users/$($subjects.b.UserId)/Items/$($subjects.b.ItemId)" $subjects.b.Headers 200).Text|ConvertFrom-Json
    if(-not $a.UserData.Played -or $b.UserData.Played){throw 'Shared video watch state collapsed'}
    Observe 'A cannot mark B shared copy' "Users/$($subjects.a.UserId)/PlayedItems/$($subjects.b.ItemId)" $subjects.a.Headers 404 Post|Out-Null
    $after=(Observe 'B state after foreign mark' "Users/$($subjects.b.UserId)/Items/$($subjects.b.ItemId)" $subjects.b.Headers 200).Text|ConvertFrom-Json
    if($after.UserData.Played){throw 'Foreign mark changed B watch state'}
    @{Completed=$true;Scope='Synthetic per-owner Emby channels with same raw YouTube video ID; ordinary accounts; no YouTube network/playback';DistinctChannelAndItemIds=$distinct;IndependentWatchedState=$true;ForeignMutationDenied=$true;Observations=$rows}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'bin/shared-channel-video-results.json') -Encoding UTF8
    Write-Output ("Shared channel video test completed; observations="+$rows.Count)
}catch{
    @{Completed=$false;ErrorCategory=$_.Exception.GetType().Name;Observations=$rows}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot 'bin/shared-channel-video-incomplete.json') -Encoding UTF8
    throw
}finally{
    Control 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@();Prune=$true}|Out-Null
    $remaining=(Control 'Channels').Items|Where-Object {$_.Name -in @('Personal Fixture a','Personal Fixture b')}
    if(@($remaining).Count){throw 'Shared channel cleanup failed readback'}
    $path=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../WatchState/bin/emby-isolated/data/data/personal-channels-fixture.json'))
    $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../WatchState/bin/emby-isolated'))+[IO.Path]::DirectorySeparatorChar
    if(-not $path.StartsWith($root)){throw 'Unsafe shared profile cleanup'}
    Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
}
