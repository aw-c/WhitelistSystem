namespace WhitelistSystem.Models;

public class SteamIdExistsResponse(bool exists = false)
{
    public bool Exists { get; set; } = exists;
}