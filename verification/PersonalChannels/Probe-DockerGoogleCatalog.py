"""Read a small real Google catalog without exporting the existing key."""
import json
import pathlib
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

ROOT = pathlib.Path("/tmp/emby-youtube-alpha-verification")
SOURCE = pathlib.Path("/srv/dev-disk-by-uuid-f02cbf33-574c-4779-8aac-21508166ad72/appdata/emby/config/plugins/configurations/Emby.YouTubePlugin.xml")

def main():
    key = ET.parse(SOURCE).getroot().findtext("ApiKey")
    assert key, "Existing YouTube key unavailable"
    def google(resource, **params):
        url = "https://www.googleapis.com/youtube/v3/" + resource + "?" + urllib.parse.urlencode(dict(params, key=key))
        try:
            with urllib.request.urlopen(url, timeout=20) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            # Never emit the provider message or URL, which may contain the key.
            print(json.dumps(dict(GoogleCallFailed=True, Status=error.code)))
            raise RuntimeError("Real Google catalog request failed") from None
        except Exception:
            raise RuntimeError("Real Google catalog transport failed") from None
    sample = google("videos", part="snippet", id="DTi8wZ1a1TA")["items"]
    assert len(sample) == 1
    channel = sample[0]["snippet"]["channelId"]
    details = google("channels", part="contentDetails", id=channel)["items"]
    uploads = details[0]["contentDetails"]["relatedPlaylists"]["uploads"]
    items = google("playlistItems", part="snippet,contentDetails", playlistId=uploads, maxResults=2)["items"]
    ids = [item["contentDetails"]["videoId"] for item in items]
    durations = google("videos", part="contentDetails", id=",".join(ids))["items"]
    report = dict(RealGoogle=True, KeyExported=False, SampleChannel=channel, CatalogVideos=len(ids),
                  RecentVideos=[dict(Id=item["id"], Duration=item["contentDetails"]["duration"]) for item in durations])
    (ROOT / "google-catalog.json").write_text(json.dumps(report))
    print(json.dumps(report))

if __name__ == "__main__":
    main()
