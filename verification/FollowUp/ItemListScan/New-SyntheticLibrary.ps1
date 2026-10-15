# Synthetic, production-sized-ish movie library for item-list gate latency.
# No production data: generated .strm movies with NFO genres, studios, tags
# and actors, so the gate's ordinary and Genre/Studio/Tag paths both get load.
param([int]$Movies = 20000, [string]$Target = (Join-Path $PSScriptRoot 'bin/synthetic-movies'))
$ErrorActionPreference = 'Stop'
$full = [IO.Path]::GetFullPath($Target)
if (-not $full.StartsWith([IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'bin')) + [IO.Path]::DirectorySeparatorChar)) { throw 'Target must stay under this folder''s bin' }
if (Test-Path -LiteralPath $full) { throw 'Synthetic library already exists' }
New-Item -ItemType Directory -Path $full | Out-Null
$random = [Random]::new(20261014)
$utf8 = [Text.UTF8Encoding]::new($false)
for ($i = 1; $i -le $Movies; $i++) {
    $name = 'Synthetic Movie {0:D5} ({1})' -f $i, (1950 + $i % 70)
    $folder = Join-Path $full $name
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    [IO.File]::WriteAllText((Join-Path $folder "$name.strm"), 'http://127.0.0.1:9/synthetic.mp4', $utf8)
    $nfo = [Text.StringBuilder]::new()
    [void]$nfo.Append("<?xml version=`"1.0`" encoding=`"utf-8`" standalone=`"yes`"?>`n<movie>`n  <title>$name</title>`n")
    foreach ($g in 1..2) { [void]$nfo.Append("  <genre>Genre $($random.Next(30))</genre>`n") }
    [void]$nfo.Append("  <studio>Studio $($random.Next(500))</studio>`n")
    foreach ($t in 1..3) { [void]$nfo.Append("  <tag>Tag $($random.Next(3000))</tag>`n") }
    foreach ($a in 1..3) { [void]$nfo.Append("  <actor><name>Actor $($random.Next(20000))</name><type>Actor</type></actor>`n") }
    [void]$nfo.Append("</movie>`n")
    [IO.File]::WriteAllText((Join-Path $folder 'movie.nfo'), $nfo.ToString(), $utf8)
}
Write-Output "Generated $Movies movies under $full"
