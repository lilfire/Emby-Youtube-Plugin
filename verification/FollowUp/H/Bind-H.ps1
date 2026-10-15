$ErrorActionPreference='Stop'
$workspace=Join-Path $PSScriptRoot 'bin/workspace'
. (Join-Path $workspace 'verification/PersonalChannels/NativeReadyHelpers.ps1')
$fixture=Get-Content (Join-Path $workspace 'verification/PersonalChannels/bin/native-client-state.json') -Raw|ConvertFrom-Json
$actors=@{}
foreach($actor in @('a','b')){
    $u=@($fixture.Users|Where-Object Owner -eq $actor)[0]
    $lib=@($fixture.Libraries|Where-Object Owner -eq $actor)[0]
    $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"H control`", Device=`"Isolated`", DeviceId=`"h-$actor`", Version=`"1`""} Post @{Username=$u.Name;Pw=''}
    $headers=@{'X-Emby-Token'=$login.AccessToken}
    $profile=Call 'YouTubePlugin/MyProfile' $headers Post @{ExpectedRevision=0;Channels=@('UC'+('a'*22))}
    $bound=Call 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{RootKey=[long]$lib.LibraryId;OwnerUserId=$u.UserId}
    if(-not $bound.Registered){throw 'Missing production binding'}
    $actors[$actor]=@{UserId=$u.UserId;Headers=$headers;VideoId=$lib.VideoId;LibraryId=$lib.LibraryId;ProfileRevision=$profile.Revision}
}
$mode=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
if($mode.ExperimentalEnabled -or -not $mode.Production.Installed){throw 'Production gate not active'}
# Both ordinary clients see all native folders; filtering must come from the plugin.
foreach($actor in @('a','b')){
    $policy=(Call ('Users/'+$actors[$actor].UserId)).Policy
    $policy.EnableAllFolders=$true
    Call ('Users/'+$actors[$actor].UserId+'/Policy') $admin Post $policy|Out-Null
    if(-not (Call ('Users/'+$actors[$actor].UserId)).Policy.EnableAllFolders){throw 'Policy readback failed'}
}
$actors|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot 'bin/actors.json') -Encoding UTF8
$evidence=@()
foreach($actor in @('a','b')){
    $other=if($actor -eq 'a'){'b'}else{'a'}
    $own=Request ('Users/'+$actors[$actor].UserId+'/Items/'+$actors[$actor].VideoId) $actors[$actor].Headers
    $foreign=Request ('Users/'+$actors[$actor].UserId+'/Items/'+$actors[$other].VideoId) $actors[$actor].Headers
    if($own.Status -ne 200 -or $foreign.Status -ne 404){throw 'Owner/foreign preflight failed'}
    $evidence+=@{Actor=$actor;OwnDetail=$own.Status;ForeignDetail=$foreign.Status;BroadNativeFolders=$true}
}
@{ProductionGate=$mode.Production.Installed;ExperimentalGuard=$mode.ExperimentalEnabled;Controls=$evidence}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $PSScriptRoot 'PREFLIGHT.json') -Encoding UTF8
$client.Dispose()
