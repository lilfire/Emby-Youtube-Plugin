# Folder watched-state verification

## Results (2026-10-10)

Release builds pass with zero warnings/errors. The executable regression suite
passes **25 groups**, including confirmed-unavailable enrichment, legacy ownership migration, the real background worker, SDK-shaped manager
fakes, library/user-data/task events, retry, disposal and a fresh-process test of
persisted incomplete loads. The plugin remains net6.0 against SDK 4.9.1.90; the
test runner uses net8.0. The release version remains 2.0.9.3.

```powershell
dotnet build Emby.YouTubePlugin.csproj -c Release
dotnet build verification/WatchState/WatchState.csproj -c Release
dotnet verification/WatchState/bin/Release/net8.0/WatchState.dll
```

An isolated portable **Emby Server 4.10.1.0** loaded the actual plugin and a
separate deterministic fixture channel. The fixture materializes remote YouTube
video items through Emby's channel manager, without Google requests or downloads.
Two local test users have independent watch histories. Every transition checks
both the stored folder `UserData.Played` and actual visibility in
`GET /Items?ParentId=...&UserId=...&IsPlayed=false`:

- Two unwatched videos and mixed watched/unwatched videos remain visible.
- Watching the last video hides the folder.
- Each user retains independent folder state.
- A folder-only manual mark inconsistent with its videos is repaired.
- Favorites, rating, play count and playback position survive the SDK save.
- Unwatching a video restores visibility; rewatching hides the folder.
- A normal channel refresh adding a third unwatched video restores visibility
  for both users; removing that video hides the folder for both.
- A normal refresh emptying the folder sets it unwatched and keeps it visible
  for both users. Cleanup restores the two-video fixture.

A separate restart check seeded and read back an incorrect watched folder above
two unwatched videos, stopped the isolated server before the worker's settling
delay, then restarted it. Startup repaired the folder and the real filter result;
both videos remained unwatched. These tests did not touch production settings,
files, users, watch history or plugin installation.

The actual SDK ancestor query includes the folder itself. The implementation
explicitly excludes that item before descendant/empty-branch evaluation; a local
regression and the real empty-folder transition cover this behavior.

## Reusing the isolated fixture

The existing local test installation is under
`verification/WatchState/bin/emby-isolated`, ignored by Git. Credentials remain
there and are not printed. The helper expects an already extracted portable
4.10.1.0 server, isolated configuration, two users and local authentication files;
it is not a clean-machine setup script. Configuration disables remote access,
UPnP, auto-update and auto-restart and uses ports 18096/18920. The scripts guard
against a different server identity and unrelated process ids.

```powershell
dotnet build verification/EmbyFixture/EmbyFixture.csproj -c Release
powershell -NoProfile -File verification/EmbyFixture/Start-IsolatedServer.ps1
powershell -NoProfile -File verification/EmbyFixture/Run-IsolatedIntegration.ps1
powershell -NoProfile -File verification/EmbyFixture/Start-IsolatedServer.ps1 -Stop
```

`verification/WatchState/Verify-EmbyFilter.ps1` is a standalone read-only check of
the stored field and actual filter result, waiting up to 300 seconds. Set
`EMBY_TEST_URL` and `EMBY_TEST_TOKEN` in the environment; never put a token in
command history. Item/user ids are discovered by the fixture, not hardcoded in
the plugin or integration runner.

```powershell
& ./verification/WatchState/Verify-EmbyFilter.ps1 -UserId $testUserId -FolderId $testFolderId -ExpectedPlayed $true
```

## SDK and implementation coverage

Compilation/reflection confirmed user-scoped recursive `GetItemList` queries,
`AncestorIds`, `ItemIds`, share/content restrictions, provider-id filtering,
`GetUserData`/`SaveUserData`, library/user-data/user-policy events and scheduled
`TaskCompleted` events. The real server confirmed the scheduled channel task key
`RefreshInternetChannels` and its idle state.

Folder saves use `TogglePlayed` and modify only `Played` on current user data.
They never call `Folder.MarkPlayed`/`MarkUnplayed` or change videos. Unchanged
state is not saved; failed saves restore the prior cached value; saves are read
back. SDK-shaped tests cover access restrictions, recursive Videos/Shorts/Live,
shared video occurrences, moves, unknown/nonplayable placeholders, deferred
partial loads, concurrent changes, independent scan gates, cancellation and
manual descendant marks. These cases have not all been repeated on the real
server.

Plugin-triggered scans remain gated until their actual task finishes, including
beyond the existing 120-second tracking timeout. Scheduled channel tasks are
checked independently; successful completion requests reconciliation and failure
defers it. Provider fetches also hold an active-fetch gate, preserve incomplete
results and extend the existing quiet window. No SDK channel-manager completion
event was found. Persisted plugin-owned `youtube-folder-watch-load-state.json`
prevents a known incomplete load becoming complete merely because of restart.
Provider exceptions and failed Shorts/Live discovery mark the load incomplete.

## Remaining client and compatibility checks

### Lilflix legacy-folder check (2026-10-10)

The local DLL was installed on Lilflix (Emby 4.10.1.0), with plugin,
configuration and database backups. For user `thomas`, all 5,717 materialized
YouTube videos were marked played and read back: zero unplayed videos remained.
The normal `RefreshInternetChannels` task then completed successfully; the
video total and zero-unplayed result remained unchanged.

Migration did **not** pass: all 126 saved-channel roots still returned empty
`ProviderIds`; none acquired `YouTubeChannel=youtube_channel_10`. Only the
previously played root remained played. The other 125 roots still appeared in
the unplayed filter. A normal refresh alone therefore did not migrate these
existing folders on this server. The intended next-day new-video test is not
ready until legacy ownership migration is repaired and verified. Folder states
were not manually marked to conceal this failure.

The subsequent local repair explicitly persists ownership through Emby's SDK.
It maps the parent `Channel` through the runtime `GetChannelProvider(Channel)`
method and requires an actual `YouTubeChannel` provider with the expected stable
id. Names and database ids are not used as ownership evidence. Only saved roots
and their managed branches qualify; conflicting markers remain untouched. The
worker waits for scanning to settle, reads back markers, retries failed writes
and performs the existing per-user watched-state calculation.

After installing the repaired DLL, Lilflix migrated all 126 existing roots and
read them back through REST. For `thomas`, 110 roots became played and disappeared
from `IsPlayed=false`. The remaining 16 roots were confirmed in the persisted
incomplete-load set; three of these contained no materialized videos. They are
intentionally deferred until a successful provider load. All 5,717 videos stayed
played. A reversible test on 3D Printing Nerd changed one video to unplayed: the
folder became unplayed and appeared in the filter. Restoring the video's prior
user data made the folder played and removed it from the filter again. This
checks actual event handling and filtering on migrated production folders; Web
badges and automatic client refresh remain unverified.

The regression suite covers migration ownership independent of channel names,
foreign providers, conflicting markers, excluded playlists, managed branches,
scan gating, transient marker-save failure, idempotency and subsequent video
events. The isolated Emby 4.10.1.0 integration suite also passed after this repair.

### Investigation of the 16 deferred channels

Enrichment initially placed every candidate in its unresolved-Shorts set when
Shorts were disabled. Videos definitively removed as missing, unembeddable,
age-restricted or otherwise unplayable were not removed from that set. Its
nonzero count therefore incorrectly marked otherwise successful folder loads
incomplete. The repair excludes only confirmed-unavailable ids before deciding
whether unresolved playable candidates remain; failed detail requests and
unknown playable classifications still defer the calculation.

The repaired DLL was installed with another backup and matching SHA-256. A normal
channel refresh completed on Lilflix, changing 11 of the 16 persisted incomplete
states to complete. The remaining five have distinct causes: Cleo Abram and
Lindsey Stirling hit the ten-page pagination cap before filling the configured
video limit; Music and BRUH Automation report zero videos in the YouTube Data
API; the saved id behind Channel is absent from the API and its channel-page
probes fail. Those states are not a background download still making progress.
Unavailable saved channels are not changed by this repair.

The subsequent listing-bound correction distinguishes a deliberately bounded
listing from a failed fetch: reaching the ten-page cap after successful requests
no longer sets the incomplete flag solely because filtering yielded fewer
playable videos than the requested maximum. This retains the existing quota
bound and displayed-video scope. Failed page requests, repeated page tokens,
failed discovery/enrichment and unknown playable classifications still mark the
load incomplete. Folder state is derived from accessible materialized videos,
not from older uploads beyond the displayed listing.

After installing that correction and completing another normal refresh, both
Cleo Abram and Lindsey Stirling had persisted complete-load states. Following
the existing post-scan quiet window, both folders became played for `thomas`
and disappeared from the real `IsPlayed=false` results. There were 123 played
roots and three remaining visible roots (the empty/unavailable saved channels).
All 5,717 materialized videos remained played. Neither correction manually set
channel-folder user data to hide a failing synchronization.

The new regression verifies successful loads excluding confirmed missing or
unplayable videos and continued deferral for failed detail lookups or unknown
playable classifications. All 25 regression groups pass.

### Hourly refresh on Lilflix

At the user's request, `RefreshInternetChannels` was changed from a 24-hour
interval to one hour (`IntervalTicks=36000000000`) through Emby's scheduled-task
API. The trigger was read back before and after the plugin restart. Channel
upload-playlist API cache TTL was reduced from six hours to 55 minutes; ordinary
playlists and trending retain their existing cache durations. The rebuilt local
DLL was installed after backup, its hash matched, the plugin entry point started,
and the 123 configured channels remained present. Build and all 25 regression
groups passed. This verifies deployment and scheduling, not a measured end-to-end
delay for a future YouTube publication.

The user selected **Emby Web** for the client check. The Web UI check could not
run in this session: computer-use reported no available browser, and its Windows
native connection was unavailable. Therefore automatic client refresh from
user-data notifications, visible badges and Web manual folder/recursive actions
are **not verified**. Server-side REST filtering is verified and must not be
presented as a completed Web UI test. A native-client check is outside the chosen
client scope.

Legacy folders without the persisted `YouTubeChannel=youtube_channel_10` marker
are migrated on startup and after successful scheduled channel refreshes, after
verifying the actual owning provider. This runtime mapping is not part of the
4.9 SDK interface; a runtime without that method leaves unmarked folders alone.
The new channel data revision invalidates cached folder responses on the next
query. Actual legacy production migration is verified above after backup.
No extra YouTube fetch is forced to compute state.

Real-server access restriction changes, Shorts/Live branches, failed provider
loads, long scheduled scans and concurrent materialization still need dedicated
runtime checks; their current coverage is the regression suite. Runtime testing
covers Emby 4.10.1.0 only. SDK compilation is not a compatibility claim for older
server versions. The complete plan's client acceptance criteria remain open.
