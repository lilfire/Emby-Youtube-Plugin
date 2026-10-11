param(
    [Parameter(Mandatory = $true)][string]$UserId,
    [Parameter(Mandatory = $true)][string]$FolderId,
    [Parameter(Mandatory = $true)][bool]$ExpectedPlayed,
    [string]$Server = $env:EMBY_TEST_URL,
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Server) -or [string]::IsNullOrWhiteSpace($env:EMBY_TEST_TOKEN)) {
    throw 'Set EMBY_TEST_URL and EMBY_TEST_TOKEN for an isolated test server.'
}
$headers = @{ 'X-Emby-Token' = $env:EMBY_TEST_TOKEN }
$base = $Server.TrimEnd('/')
$user = [Uri]::EscapeDataString($UserId)
$folder = [Uri]::EscapeDataString($FolderId)
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

do {
    # Authentication stays in a header; neither tokens nor URLs are printed.
    $item = Invoke-RestMethod -Uri "$base/Users/$user/Items/$folder`?Fields=ParentId" -Headers $headers -Method Get
    if ([string]::IsNullOrWhiteSpace($item.ParentId)) { throw 'The test folder has no ParentId.' }
    $parent = [Uri]::EscapeDataString($item.ParentId)
    $filtered = Invoke-RestMethod -Uri "$base/Items?ParentId=$parent&UserId=$user&IsPlayed=false&Limit=10000" -Headers $headers -Method Get
    if ($filtered.TotalRecordCount -gt 10000) { throw 'Test parent exceeds the fixture limit.' }
    $visible = @($filtered.Items | Where-Object { $_.Id -eq $FolderId }).Count -gt 0
    if ($item.UserData.Played -eq $ExpectedPlayed -and $visible -eq (-not $ExpectedPlayed)) {
        Write-Output "PASS: folder Played=$ExpectedPlayed; visibility in IsPlayed=false=$visible"
        exit 0
    }
    Start-Sleep -Milliseconds 500
} while ([DateTime]::UtcNow -lt $deadline)

throw 'Folder state and/or actual IsPlayed=false filtering did not reach the expected result.'
