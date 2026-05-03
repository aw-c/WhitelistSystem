using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using WhitelistSystem.Data;
using WhitelistSystem.Models;

namespace WhitelistSystem.Services;

public class SteamWhitelistService(WhitelistDbContext dbContext, IMemoryCache memoryCache)
{
    private const string CacheKey = "steam-whitelist-cache";
    private static readonly SemaphoreSlim CacheLock = new(1, 1);
    private readonly WhitelistDbContext _dbContext = dbContext;
    private readonly IMemoryCache _memoryCache = memoryCache;

    public async Task<IReadOnlyCollection<SteamWhitelistEntry>> GetAllAsync(CancellationToken cancellationToken = default)
    {
        var cache = await GetOrLoadCacheAsync(cancellationToken);
        return cache.Values.OrderBy(e => e.SteamId, StringComparer.Ordinal).ToArray();
    }

    public async Task<SteamWhitelistEntry?> GetOneAsync(string steamId, CancellationToken cancellationToken = default)
    {
        var normalized = NormalizeSteamId(steamId);
        if (normalized is null) return null;

        var cache = await GetOrLoadCacheAsync(cancellationToken);
        cache.TryGetValue(normalized, out var entry);
        return entry;
    }

    public async Task<bool> AddAsync(string steamId, string? comment, CancellationToken cancellationToken = default)
    {
        var normalized = NormalizeSteamId(steamId);
        if (normalized is null) return false;

        await CacheLock.WaitAsync(cancellationToken);
        try
        {
            var cache = await GetOrLoadCacheAsync(cancellationToken);
            if (cache.ContainsKey(normalized)) return false;

            var entry = new SteamWhitelistEntry
            {
                SteamId = normalized,
                AddedAt = DateTime.UtcNow,
                Comment = string.IsNullOrWhiteSpace(comment) ? null : comment.Trim()
            };

            _dbContext.SteamWhitelistEntries.Add(entry);
            await _dbContext.SaveChangesAsync(cancellationToken);

            cache[normalized] = entry;
            return true;
        }
        finally
        {
            CacheLock.Release();
        }
    }

    public async Task<bool> RemoveAsync(string steamId, CancellationToken cancellationToken = default)
    {
        var normalized = NormalizeSteamId(steamId);
        if (normalized is null) return false;

        await CacheLock.WaitAsync(cancellationToken);
        try
        {
            var existing = await _dbContext.SteamWhitelistEntries.FindAsync([normalized], cancellationToken);
            if (existing is null) return false;

            _dbContext.SteamWhitelistEntries.Remove(existing);
            await _dbContext.SaveChangesAsync(cancellationToken);

            var cache = await GetOrLoadCacheAsync(cancellationToken);
            cache.Remove(normalized);
            return true;
        }
        finally
        {
            CacheLock.Release();
        }
    }

    private async Task<Dictionary<string, SteamWhitelistEntry>> GetOrLoadCacheAsync(CancellationToken cancellationToken)
    {
        if (_memoryCache.TryGetValue(CacheKey, out Dictionary<string, SteamWhitelistEntry>? cached) && cached is not null)
            return cached;

        var entries = await _dbContext.SteamWhitelistEntries
            .AsNoTracking()
            .ToListAsync(cancellationToken);

        var loaded = entries.ToDictionary(e => e.SteamId, StringComparer.Ordinal);
        _memoryCache.Set(CacheKey, loaded);
        return loaded;
    }

    private static string? NormalizeSteamId(string? steamId)
    {
        if (string.IsNullOrWhiteSpace(steamId)) return null;
        return steamId.Trim();
    }
}
