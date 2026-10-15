$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'bin/workspace'))
$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'bin'))+[IO.Path]::DirectorySeparatorChar
if(-not $workspace.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($workspace) -ne 'workspace'){throw 'Unsafe H cleanup target'}
if(-not (Test-Path $workspace)){throw 'H workspace missing; inspect existing cleanup evidence'}
$control=Join-Path $workspace 'verification/PersonalChannels/Start-NativeClientFixture.ps1'
& $control -Stop
$native=Get-Content (Join-Path $workspace 'verification/PersonalChannels/bin/native-client-cleanup.json') -Raw|ConvertFrom-Json
if(-not $native.UsersGone -or -not $native.LibrariesGone -or -not $native.MediaGone){throw 'Native cleanup not confirmed'}
$executable=Join-Path $workspace 'verification/WatchState/bin/emby-isolated/server/system/EmbyServer.exe'
$processes=@(Get-Process EmbyServer -ErrorAction SilentlyContinue|Where-Object Path -eq $executable)
if($processes.Count -or (Get-NetTCPConnection -LocalPort 18108 -State Listen -ErrorAction SilentlyContinue)){throw 'H process/port remains active'}
if((Get-Item $workspace).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'H workspace became a link'}
Remove-Item -LiteralPath $workspace -Recurse -Force
$credentials=Join-Path $PSScriptRoot 'bin/actors.json'
Remove-Item -LiteralPath $credentials -Force
$clean=@{UsersGone=$native.UsersGone;LibrariesGone=$native.LibrariesGone;MediaGone=$native.MediaGone;FixtureGone=$native.FixtureGone;ServerStopped=($processes.Count -eq 0);PortClosed=(-not[bool](Get-NetTCPConnection -LocalPort 18108 -State Listen -ErrorAction SilentlyContinue));WorkspaceGone=(-not(Test-Path $workspace));LocalActorTokensGone=(-not(Test-Path $credentials))}
if(@($clean.Values|Where-Object {$_ -ne $true}).Count){throw 'H cleanup readback failed'}
$clean|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot 'CLEANUP.json') -Encoding UTF8
