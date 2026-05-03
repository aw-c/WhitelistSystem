namespace WhitelistSystem.Models;

public class CreateSteamIdRequest
{
    public string SteamId { get; set; } = string.Empty;
    public string? Comment { get; set; }
}
