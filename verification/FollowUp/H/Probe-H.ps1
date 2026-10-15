param([switch]$RevokeA)
$ErrorActionPreference='Stop'
$workspace=Join-Path $PSScriptRoot 'bin/workspace'
. (Join-Path $workspace 'verification/PersonalChannels/NativeReadyHelpers.ps1')
$actors=Get-Content (Join-Path $PSScriptRoot 'bin/actors.json') -Raw|ConvertFrom-Json
$observations=@()
foreach($actor in @('a','b')){
    $subject=$actors.$actor
    $other=$actors.$(if($actor -eq 'a'){'b'}else{'a'})
    $headers=@{'X-Emby-Token'=$subject.Headers.'X-Emby-Token'}
    foreach($route in @(
        "Users/$($subject.UserId)/HomeSections?displayMode=mobile,desktop",
        "Users/$($subject.UserId)/Sections/smalllibrarytiles/Items?Limit=12",
        "Users/$($subject.UserId)/Sections/latestmedia_$($subject.LibraryId)/Items?Limit=12",
        "Users/$($subject.UserId)/Sections/latestmedia_$($other.LibraryId)/Items?Limit=12",
        "Users/$($subject.UserId)/Views",
        "Users/$($subject.UserId)/Views?AllowDynamicChildren=true",
        "Users/$($subject.UserId)/Views?AllowDynamicChildren=false",
        "Users/$($subject.UserId)/Items/Latest?ParentId=$($other.LibraryId)&Limit=16",
        "Users/$($subject.UserId)/Items/Latest?IncludeItemTypes=Video&GroupItems=false&Limit=100",
        "Users/$($subject.UserId)/Items/$($subject.VideoId)",
        "Users/$($subject.UserId)/Items/$($other.VideoId)",
        "Videos/$($subject.VideoId)/stream.mp4?Static=true",
        "Videos/$($other.VideoId)/stream.mp4?Static=true"
    )){
        $r=Request $route $headers
        $observations+=@{Actor=$actor;Route=$route.Replace($subject.UserId,'SELF');Status=$r.Status;Bytes=$r.Bytes.Length;OwnName=$r.Text.Contains("PrivateNativeVideo_${actor}_client");ForeignName=$r.Text.Contains($(if($actor -eq 'a'){'PrivateNativeVideo_b_client'}else{'PrivateNativeVideo_a_client'}));ForeignLibrary=$r.Text.Contains($(if($actor -eq 'a'){'Private Native Fixture b'}else{'Private Native Fixture a'}))}
    }
}
if($RevokeA){
    # Synthetic H owner only. Preserve the profile tombstone until cleanup.
    $aHeaders=@{'X-Emby-Token'=$actors.a.Headers.'X-Emby-Token'}
    $deleted=Call 'YouTubePlugin/MyProfile/Delete' $aHeaders Post @{ExpectedRevision=$actors.a.ProfileRevision}
    $readback=Call 'YouTubePlugin/MyProfile' $aHeaders
    if($deleted.State -ne 'Deleted' -or $readback.State -ne 'Deleted'){throw 'Revocation not stored'}
    foreach($actor in @('a','b')){
        $headers=@{'X-Emby-Token'=$actors.$actor.Headers.'X-Emby-Token'}
        $r=Request "Videos/$($actors.a.VideoId)/stream.mp4?Static=true" $headers
        if($r.Status -ne 404){throw 'Revoked static stream served'}
        $observations+=@{Actor=$actor;Phase='After stored A deletion';Route='A static video';Status=$r.Status;Bytes=$r.Bytes.Length}
    }
    $positive=Request "Videos/$($actors.b.VideoId)/stream.mp4?Static=true" @{'X-Emby-Token'=$actors.b.Headers.'X-Emby-Token'}
    if($positive.Status -ne 200){throw 'B positive control lost'}
    $observations+=@{Actor='b';Phase='After stored A deletion';Route='B own static video';Status=$positive.Status;Bytes=$positive.Bytes.Length}
}
@{RevokeA=[bool]$RevokeA;Observations=$observations}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot $(if($RevokeA){'REVOCATION.json'}else{'HTTP.json'})) -Encoding UTF8
$client.Dispose()
