$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root = Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$base = 'http://127.0.0.1:18096/emby'
$info = Invoke-RestMethod -Uri "$base/System/Info/Public"
if ($info.Version -ne '4.10.1.0' -or $info.ServerName -ne 'Isolated Watch State Test') { throw 'Refusing to mutate a different server.' }
$auth = Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$h = @{ 'X-Emby-Token' = $auth.Token }
$user = $auth.UserId
$second = (Get-Content -LiteralPath (Join-Path $root 'second-user.id')).Trim()
function Call([string]$path, [string]$method = 'Get', $body = $null) {
    $p = @{ Uri = "$base/$path"; Method = $method; Headers = $h }
    if ($null -ne $body) { $p.ContentType = 'application/json'; $p.Body = ($body | ConvertTo-Json -Depth 10) }
    Invoke-RestMethod @p
}
$all = Call "Items?Recursive=true&UserId=$user&Fields=ProviderIds"
$folder = @($all.Items | Where-Object { $_.Name -eq 'Fixture Channel' -and $_.ProviderIds.YouTubeChannel -eq 'youtube_channel_10' })
if ($folder.Count -ne 1) { throw 'Expected one fixture root.' }
$folderId = $folder[0].Id
$dto = Call "Users/$user/Items/$folderId`?Fields=ParentId"
$parentId = $dto.ParentId
if (-not $parentId) { throw 'No fixture parent.' }
$videos = (Call "Items?ParentId=$folderId&UserId=$user&Fields=ProviderIds").Items | Sort-Object Name
if (@($videos).Count -ne 2) { throw 'Start this run with exactly two fixture videos.' }
function Mark([string]$u, [string]$item, [bool]$played) {
    $method = if ($played) { 'Post' } else { 'Delete' }
    Call "Users/$u/PlayedItems/$item" $method | Out-Null
}
function WaitState([string]$u, [bool]$played, [string]$label) {
    $deadline = [DateTime]::UtcNow.AddSeconds(300)
    do {
        $current = Call "Users/$u/Items/$folderId"
        $filtered = Call "Items?ParentId=$parentId&UserId=$u&IsPlayed=false"
        $visible = @($filtered.Items | Where-Object { $_.Id -eq $folderId }).Count -gt 0
        if ($current.UserData.Played -eq $played -and $visible -eq (-not $played)) {
            Write-Output "PASS $label (Played=$played, filter visibility=$visible)"
            return
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out: $label"
}
foreach ($v in $videos) { Mark $user $v.Id $false; Mark $second $v.Id $false }
WaitState $user $false 'two unwatched videos'
Mark $user $videos[0].Id $true
WaitState $user $false 'one watched, one unwatched'
Mark $user $videos[1].Id $true
WaitState $user $true 'last video watched hides folder'
WaitState $second $false 'second user retains unwatched folder'
foreach ($v in $videos) { Mark $second $v.Id $true }
WaitState $second $true 'second user independently watches videos'

Call "Users/$user/Items/$folderId/UserData" 'Post' @{ Played = $false; IsFavorite = $true; Rating = 8; PlayCount = 7; PlaybackPositionTicks = 12345 } | Out-Null
$before = (Call "Users/$user/Items/$folderId").UserData
WaitState $user $true 'folder-only manual mark repaired'
$after = (Call "Users/$user/Items/$folderId").UserData
foreach ($field in @('IsFavorite', 'Rating', 'PlayCount', 'PlaybackPositionTicks')) {
    if ($before.$field -ne $after.$field) { throw "Unrelated folder field changed: $field" }
}
Write-Output 'PASS unrelated folder fields preserved through SDK save'
Mark $user $videos[1].Id $false
WaitState $user $false 'unwatch video reopens folder'
WaitState $second $true 'unwatch does not affect other user'
Mark $user $videos[1].Id $true
WaitState $user $true 'rewatch video hides folder'

$thirdFlag = Join-Path $root 'data/data/fixture-third-video'
New-Item -ItemType File -Path $thirdFlag -Force | Out-Null
Call 'WatchStateFixture/Refresh' 'Post' | Out-Null
$newVideos = (Call "Items?ParentId=$folderId&UserId=$user&Fields=ProviderIds").Items
if (@($newVideos).Count -ne 3) { throw 'Normal refresh did not materialize the third video.' }
WaitState $user $false 'new materialized video reopens folder'
WaitState $second $false 'new video also reopens second user folder'
Remove-Item -LiteralPath $thirdFlag
Call 'WatchStateFixture/Refresh' 'Post' | Out-Null
$remaining = (Call "Items?ParentId=$folderId&UserId=$user").Items
if (@($remaining).Count -ne 2) { throw 'Normal refresh did not remove the third video.' }
WaitState $user $true 'removal of last unwatched video hides folder'
WaitState $second $true 'removal recomputes second user folder'
$emptyFlag = Join-Path $root 'data/data/fixture-empty'
try {
    New-Item -ItemType File -Path $emptyFlag -Force | Out-Null
    Call 'WatchStateFixture/Refresh' 'Post' | Out-Null
    $empty = (Call "Items?ParentId=$folderId&UserId=$user").Items
    if (@($empty).Count -ne 0) { throw 'Normal refresh did not empty the fixture folder.' }
    WaitState $user $false 'empty folder remains unwatched'
    WaitState $second $false 'empty folder remains unwatched for second user'
} finally {
    Remove-Item -LiteralPath $emptyFlag -ErrorAction SilentlyContinue
    Call 'WatchStateFixture/Refresh' 'Post' | Out-Null
}
if (@((Call "Items?ParentId=$folderId&UserId=$user").Items).Count -ne 2) { throw 'Fixture cleanup did not restore two videos.' }
Write-Output 'ISOLATED INTEGRATION PASSED: actual Emby 4.10.1.0 storage and IsPlayed=false transitions.'
