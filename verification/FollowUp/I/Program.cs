using Emby.YouTubePlugin;
using System.Text.Json;

var results = new List<object>();
var temporary = Path.GetTempFileName();
void Check(string name, bool valid, Action action) {
    bool accepted;
    try { action(); accepted = true; } catch (ArgumentException) { accepted = false; }
    results.Add(new { Name = name, Passed = accepted == valid });
    if (accepted != valid) throw new Exception(name);
}
void Validate(bool enabled = false, string path = "", int videos = 50, long video = 1048576, long collection = 2097152, long storage = 4194304)
    => PersonalYouTubeConfigurationValidation.Validate(enabled, path, path, path, videos, video, collection, storage);
try {
    Check("disabled-empty-tools", true, () => Validate());
    Check("enabled-existing-files", true, () => Validate(true, temporary));
    Check("enabled-empty-tools", false, () => Validate(true));
    Check("relative-path", false, () => Validate(path: "tool.exe"));
    Check("missing-absolute-file", false, () => Validate(path: temporary + ".missing"));
    Check("directory-is-not-tool", false, () => Validate(path: Path.GetDirectoryName(temporary)!));
    Check("control-character", false, () => Validate(path: temporary + "\n"));
    Check("zero-videos", false, () => Validate(videos: 0));
    Check("too-many-videos", false, () => Validate(videos: 10001));
    Check("oversized-video", false, () => Validate(video: 4294967297));
    Check("video-over-collection", false, () => Validate(video: 3145728));
    Check("collection-over-storage", false, () => Validate(collection: 5242880));
    Check("oversized-budget", false, () => Validate(storage: 1099511627777));
    Check("maximum-boundaries", true, () => Validate(videos: 10000, video: 4294967296, collection: 1099511627776, storage: 1099511627776));
    var publisher = File.ReadAllText("PersonalYouTubeNativePublisher.cs");
    if (!publisher.Contains("video.Overview = System.Net.WebUtility.HtmlEncode(metadata.Description);")) throw new Exception("Reinspect metadata path.");
    foreach (var raw in new[] { "Rock & roll", "Rock &amp; roll", "<script>alert('synthetic')</script>" })
        results.Add(new { Name = "metadata-current-publisher-expression", Input = raw, Overview = System.Net.WebUtility.HtmlEncode(raw), Passed = true, Limitation = "Expression reproduction, not native Android TV rendering" });
} finally { File.Delete(temporary); }
results.Add(new { Name = "temporary-tool-file-removed", Passed = !File.Exists(temporary) });
Console.WriteLine(JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true }));
