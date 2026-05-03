namespace WhitelistSystem.Models;

public class SteamWhitelistEntry
{
    public required string SteamId { get; set; }
    public DateTime AddedAt { get; set; }
    public string? Comment { get; set; }
}
