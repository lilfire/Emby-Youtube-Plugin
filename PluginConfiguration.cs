using MediaBrowser.Model.Plugins;
using System.Xml.Serialization;

namespace Emby.YouTubePlugin
{
    // Settings persisted by the custom configuration page.
    public class PluginConfiguration : BasePluginConfiguration
    {
        public bool PersonalYouTubeAlphaEnabled { get; set; }
        public string PersonalYouTubeDownloaderPath { get; set; } = "";
        public string PersonalYouTubeFfmpegPath { get; set; } = "";
        public string PersonalYouTubeNodePath { get; set; } = "";
        public int PersonalYouTubeMaxVideos { get; set; } = 50;
        public long PersonalYouTubeMaxVideoBytes { get; set; } = 512L * 1024 * 1024;
        public long PersonalYouTubeMaxCollectionBytes { get; set; } = 2L * 1024 * 1024 * 1024;
        public long PersonalYouTubeMaxStorageBytes { get; set; } = 10L * 1024 * 1024 * 1024;
        public string ApiKey { get; set; } = "";

        public string SavedItems { get; set; } = "";

        public string WatchLaterPlaylist { get; set; } = "";

        public bool ShowTrending { get; set; } = true;

        public bool ShowCategories { get; set; } = true;

        public bool ShowRootFoldersAtTopLevel { get; set; } = false;

        public bool ShowShorts { get; set; } = true;

        // Kept around so older saved configs migrate cleanly.
        public bool HideShorts { get; set; } = false;

        [XmlIgnore]
        public bool ShortsEnabled => ShowShorts && !HideShorts;

        public string TrendingRegion { get; set; } = "";

        public string TrendingCategory { get; set; } = "";

        public bool ShowLikeCount { get; set; } = true;

        public bool ShowCommentCount { get; set; } = false;

        public string ChannelSortBy { get; set; } = "date";

        public int MaxChannelVideos { get; set; } = 50;

        public int MaxSearchVideos { get; set; } = 50;

        public int WatchLaterPollMinutes { get; set; } = 3;

        public string Donate { get; set; } = "https://paypal.me/eliasbruno123";

        [XmlIgnore]
        public string QuotaStatus => QuotaTracker.FormatStatus();

        // Legacy structured fields retained for configuration compatibility. They
        // now represent only the common non-search bucket instead of mixing two
        // unrelated quota systems.
        [XmlIgnore]
        public long QuotaUsedToday => QuotaTracker.GetStats().OtherUnitsToday;

        [XmlIgnore]
        public long QuotaDailyLimit => QuotaTracker.GetStats().OtherUnitLimit;

        [XmlIgnore]
        public long QuotaResetSeconds
        {
            get
            {
                var sec = (long)QuotaTracker.GetStats().UntilReset.TotalSeconds;
                return sec < 0 ? 0 : sec;
            }
        }

        [XmlIgnore]
        public long QuotaLifetime => QuotaTracker.GetStats().TotalOtherUnits;

        [XmlIgnore]
        public long QuotaSearchCallsToday => QuotaTracker.GetStats().SearchCallsToday;

        [XmlIgnore]
        public long QuotaSearchDailyLimit => QuotaTracker.GetStats().SearchCallLimit;

        [XmlIgnore]
        public long QuotaOtherUnitsToday => QuotaTracker.GetStats().OtherUnitsToday;

        [XmlIgnore]
        public long QuotaOtherDailyLimit => QuotaTracker.GetStats().OtherUnitLimit;

        [XmlIgnore]
        public long QuotaTotalSearchCalls => QuotaTracker.GetStats().TotalSearchCalls;

        [XmlIgnore]
        public long QuotaTotalOtherUnits => QuotaTracker.GetStats().TotalOtherUnits;
    }
}
