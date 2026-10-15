$ErrorActionPreference='Stop'
$existing=Join-Path $PSScriptRoot '../../PersonalChannels'
$dll=Join-Path $PSScriptRoot 'bin/Release/net6.0/PersonalChannelsFixture.dll'
if(-not(Test-Path -LiteralPath $dll)){throw 'Build BoundaryFixture.csproj first'}
$source=Get-Content (Join-Path $existing 'Start-NativeClientFixture.ps1') -Raw -Encoding UTF8
$source=$source.Replace('$PSScriptRoot','$existing')
$source=$source.Replace("(Join-Path `$existing 'bin/Release/net6.0/PersonalChannelsFixture.dll')",'$dll')
& ([scriptblock]::Create($source))
