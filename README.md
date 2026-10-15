# Emby YouTube Plugin

> **Alpha build: 2.0.11-alpha.1.** This branch contains an experimental personal
> YouTube feature for controlled testing on **Emby Server 4.10.1.0**. It is not
> a general production release or a guarantee of complete isolation between users.

## Changes in 2.0.11-alpha.1

- Reuse a native source inventory between library changes, avoiding repeated full database scans for ordinary lists.
- Guard native writes and recheck owner/source authority before responses are written. Persist private source roots and historic aliases; uncertain or corrupt state denies access.
- Improve administrator settings validation and loading feedback, and handle server API keys correctly in the item-list gate.

The source candidate passed 1,351 native observations and 69 component checks on
Emby 4.10.1.0 for Windows. With 62,566 native items, warm sequential Items requests
took about 0.56–0.57 seconds; six concurrent home requests had route medians of
0.65–1.11 seconds. These measurements are from an isolated fixture. See the
[implementation and evidence](verification/FollowUp/PrivateInventory/IMPLEMENTATION.md)
and [remaining work](TODO.md). On Lilflix's Linux installation the native source
barrier is unavailable, so full-scan fallback remains active. Linux source
inventory support and other Emby builds require separate verification; the
access gaps described below remain open.

## Personal YouTube — closed alpha

Each signed-in Emby user can save their own YouTube Data API v3 key and channel
IDs through **YouTube in the Emby web user menu**. Keys are encrypted on the
server. Leaving the key field empty retains the saved key. A background job
fetches metadata, buffers a bounded selection of videos locally, and publishes
the collection as a normal Emby library. Channel updates replace the collection;
deleting it requests collection removal and buffered-media cleanup.

The API key supplies metadata; playback uses locally buffered media obtained
with yt-dlp. The server needs separately installed **yt-dlp, Node.js 24 LTS,
FFmpeg and ffprobe**, persistent storage, and administrator activation of
**Personal YouTube — closed alpha**. Installing the DLL alone does not enable
the worker. Back up the existing DLL and configuration before updating.

Follow the [alpha installation and rollback instructions](verification/PersonalChannels/alpha-package/INSTALL.md)
and read the [known limitations](verification/PersonalChannels/alpha-package/KNOWN-LIMITS.md).
Delete all personal collections and verify cleanup before returning to an older
plugin that may lack their access controls.

Lilflix was updated to 2.0.11-alpha.1 on 2026-10-15. The installed DLL hash,
startup controls, HA integration and selected server-key/user API calls were
verified; the user list calls returned HTTP 200 in about 1.5–1.8 seconds. See the
[deployment record](verification/PersonalChannels/LILFLIX-ALPHA-DEPLOYMENT.md).
Later isolated investigations found access gaps in recommendations, metadata,
playlists, Sync, audio/HLS and cache content. Use controlled test content;
the alpha acceptance applies only to its recorded tests. The
[evidence index and approval levels](verification/FollowUp/K/INDEX.md)
separate the deployed DLL, later test builds and unverified clients.

Verified scope includes Chrome playback, actual Emby AndroidTv **1.8.54g** video
playback and active audio output, and Docker checks with real Google metadata,
two channels, account access checks, restart recovery, interrupted buffering
and deletion. Android mobile and other clients remain unverified. All Emby
routes, offline/Sync and client caches are not covered by a universal privacy
guarantee. Use controlled test accounts and content. See the
[alpha acceptance report](verification/PersonalChannels/CLOSED-ALPHA-ACCEPTANCE.md).

An Emby channel plugin for browsing YouTube content with the official YouTube Data API v3.

The plugin adds a YouTube entry to Emby and lets you browse saved channels, playlists, Watch Later-style playlists, trending videos, categories, and Shorts from one place.

## Changes in this fork

This fork builds on [the original Emby YouTube Plugin](https://github.com/eliasbruno124-dev/Emby-Youtube-Plugin), version 2.0.9.3, and adds:

- **Automatic watched channel folders.** A saved channel and its Videos/Shorts/Live folders become watched when their displayed listing contains at least one accessible video and every accessible video is watched. They disappear from Emby's unwatched filter and reappear when a new unwatched video arrives or a video is marked unwatched.
- **Separate state for each Emby user.** Folder status follows that user's existing video history. Synchronization changes only the folder's watched flag; it preserves favorites, ratings, playback position and other user data.
- **Migration of existing channel folders.** Existing folders gain the ownership marker needed for synchronization after their owning YouTube provider is verified. Migration runs on startup and after successful channel refreshes.
- **Correct handling of filtered and bounded listings.** Confirmed unavailable videos, including age-restricted videos and videos that disable embedding, no longer incorrectly leave a channel's load marked incomplete. Reaching the deliberate pagination limit after successful requests also counts as a completed listing. Actual fetch failures and unresolved playable videos still defer folder updates.
- **Fresher channel uploads.** Upload-list cache duration is reduced from six hours to 55 minutes to support hourly channel refreshes. Set **Refresh Internet Channels** to run every hour in Emby's scheduled tasks; installing the fork does not change that schedule automatically. Ordinary playlists retain their six-hour cache.

The changes have passed 25 local regression groups and server-side checks on Emby 4.10.1.0, including existing-folder migration and watched/unwatched filter transitions. See [verification results and remaining client checks](docs/folder-watch-state-verification.md).

## Highlights

- Add YouTube channels by `@handle` or channel ID.
- Add playlists as their own Emby folders.
- Add search folders for occasional YouTube searches.
- Create Watch Later-style folders from playlist IDs.
- Show Trending and category folders for a selected region.
- Split channels into Videos and Shorts when those folders have content.
- Hide Shorts globally if you prefer a long-form-only view.
- Hide empty playlists, categories, and Shorts folders.
- Optionally show YouTube root folders at the top level and, on Emby 4.10+, add one latest-videos home row per saved channel while reversibly hiding both forms of combined YouTube-latest row.
- Track estimated daily YouTube API quota usage.
- Derive saved-channel and Videos/Shorts/Live folder watched state from each user's accessible videos.


## Screenshots

### Setup Guide

<img width="740" alt="Setup guide 1" src="docs/screenshots/setup%201.png" />
<br>
<img width="740" alt="Setup guide 2" src="docs/screenshots/setup%202.png" />
<br>
<img width="740" alt="Setup guide 3" src="docs/screenshots/setup%203.png" />
<br>
<img width="740" alt="Setup guide 4" src="docs/screenshots/setup%204.png" />
<br>
<img width="740" alt="Setup guide 5" src="docs/screenshots/setup%205.png" />

### Emby Root Folder

<img width="900" alt="Emby root folder" src="docs/screenshots/Root%20Folder.png" />

### Channel Folders

<img width="900" alt="Channel folder layout" src="docs/screenshots/channel%20folder.png" />

### Video Listing

<img width="900" alt="Trending video listing" src="docs/screenshots/trending%20videos.png" />

## Requirements

- An Emby Server.
- A YouTube Data API v3 key from Google Cloud. The built-in Setup Guide walks you through creating one.
- .NET 8 SDK, only if you want to build the plugin from source.

The API key only needs access to public YouTube data. After installation, open the plugin settings and use the built-in **Setup Guide** to create and restrict the key.

## Installation

For **2.0.10-alpha.1 personal libraries**, use the alpha instructions above.
The following steps describe the existing shared YouTube channel feature;
that feature uses the administrator's settings and key.

1. Download the latest `Emby.YouTubePlugin.dll` release.
2. Copy the DLL into Emby's  `programdata/plugins` folder.
3. Restart Emby.
4. Open the YouTube plugin settings.
5. Use the **Setup Guide** tab to create a YouTube Data API v3 key.
6. Paste the API key into the **Settings** tab.
7. Add at least one channel, playlist, or search entry.
8. Save the settings.

Useful Google Cloud pages:

- YouTube Data API v3: https://console.cloud.google.com/apis/library/youtube.googleapis.com
- Credentials: https://console.cloud.google.com/apis/credentials

## Saved Content

The **My YouTube Content** field accepts:

- `@handle`, for example `@MrBeast`
- Channel IDs starting with `UC...`
- Playlist IDs starting with `PL...`
- Plain search text

Handles, channel IDs, and playlist IDs are the best options because they avoid the separate daily `search.list` limit. Plain search text works too, but each result page uses one Search Queries call.

The **Watch Later Playlists** field accepts playlist IDs. Each playlist becomes its own top-level folder and can be checked regularly for new videos.


## Watched channel folders

Saved channels and their Videos/Shorts/Live folders are watched when they contain
at least one accessible, materialized video and every such video is watched for
that Emby user. A new unwatched video or an unwatched mark makes the folder
unwatched again. Empty folders default to unwatched. Incomplete loads defer the
calculation until a successful refresh. Updates wait for scanning to settle.

This uses Emby's existing video history, separately for each user, and only
changes the folder's `Played` field. It does not sync Google watch history or
describe videos beyond the configured listing limit.

If a client's manual folder action changes its videos, those video states drive
the result. If it changes only the folder, the derived state is restored. The
plugin never interprets a folder update as a command to mark videos.

Ownership is verified with the plugin's provider marker and stable external ids.
On startup and after a completed channel refresh, folders from older versions
acquire that marker only after their parent channel is mapped to this plugin's
registered provider. Emby does not reliably merge provider markers into existing
folders during refresh, so the plugin saves and reads back the marker explicitly.
Playlists, search folders, trending and categories are excluded.

Build and local checks are described in
[folder-watch-state verification](docs/folder-watch-state-verification.md).

## Quota

Most browsing uses low-cost YouTube API endpoints:

| Action | Endpoint | Typical cost |
| --- | --- | --- |
| Channel uploads | `playlistItems.list` | 1 unit |
| Playlist videos | `playlistItems.list` | 1 unit |
| Video details | `videos.list` | 1 unit per batch |
| Categories | `videoCategories.list` | 1 unit |
| Search folders | `search.list` | 1 Search Queries call |

The plugin caches responses on disk. Channel upload lists expire after 55
minutes so an hourly Emby channel refresh can discover new videos. The refresh
schedule itself is controlled by Emby's **Refresh Internet Channels** task;
changing its interval does not change ordinary media-library disk monitoring.
Other playlists retain their six-hour cache. Search results are cached longer because
`search.list` has a separate default limit of 100 calls per day, while most
other endpoints share the regular 10,000-unit daily bucket.

## Notes

- The existing shared channel feature uses the official YouTube API and player.
  The personal-library alpha downloads and buffers video locally for native Emby playback.
- The plugin requests captions off, but some TV and Android players may ignore this.
- Resume and player cleanup depend on the Emby client. Bundled players may not use the server-side fixes.
- Private account data is not supported. Use channels and playlists accessible with your API key.
- After updating, restart Emby. If the web app still looks outdated, clear its browser cache.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Support the Developer

This plugin is free and open-source, maintained with a lot of love in my spare time. If it brings value to your Emby setup, a small donation would mean the world to me.

<p align="center">
  <a href="https://paypal.me/eliasbruno123">
    <img src="https://img.shields.io/badge/Donate%20with-PayPal-0070BA?style=for-the-badge&logo=paypal&logoColor=white" alt="Donate with PayPal">
  </a>
</p>
