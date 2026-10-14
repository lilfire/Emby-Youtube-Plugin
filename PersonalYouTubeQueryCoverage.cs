namespace Emby.YouTubePlugin;

// A late denial is safe only if every native query already excluded that ID.
internal sealed class PersonalYouTubeQueryCoverage
{
    private readonly object _gate = new();
    private readonly HashSet<long> _initial;
    private HashSet<long>? _everyQuery;
    internal PersonalYouTubeQueryCoverage(IEnumerable<long> initial) => _initial = new(initial);
    internal void Record(IEnumerable<long> exclusions)
    {
        var snapshot = exclusions.ToHashSet();
        lock (_gate)
        {
            if (_everyQuery == null) _everyQuery = snapshot;
            else _everyQuery.IntersectWith(snapshot);
        }
    }
    internal bool Covers(IEnumerable<long> denied)
    {
        // An inventory is not proof that an actual result source was filtered.
        lock (_gate) return _everyQuery != null && _initial.Concat(denied).All(_everyQuery.Contains);
    }
}
