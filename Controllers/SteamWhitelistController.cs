using Microsoft.AspNetCore.Mvc;
using WhitelistSystem.Models;
using WhitelistSystem.Services;

namespace WhitelistSystem.Controllers;

[ApiController]
[Route("api/steam-ids")]
public class SteamWhitelistController(SteamWhitelistService steamWhitelistService) : ControllerBase
{
    private readonly SteamWhitelistService _steamWhitelistService = steamWhitelistService;

    [HttpGet]
    public async Task<ActionResult<IReadOnlyCollection<string>>> GetAll(CancellationToken cancellationToken)
    {
        var items = await _steamWhitelistService.GetAllAsync(cancellationToken);
        return Ok(items.Select(x => x.SteamId));
    }

    [HttpGet("{steamId}")]
    public async Task<ActionResult<SteamIdExistsResponse>> Exists(string steamId, CancellationToken cancellationToken)
    {
        var item = await _steamWhitelistService.GetOneAsync(steamId, cancellationToken);
        return item is null ? NotFound(new SteamIdExistsResponse(false)) : Ok(new SteamIdExistsResponse(true));
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateSteamIdRequest request, CancellationToken cancellationToken)
    {
        if (request is null || string.IsNullOrWhiteSpace(request.SteamId))
        {
            return BadRequest("SteamId is required.");
        }

        var added = await _steamWhitelistService.AddAsync(request.SteamId, request.Comment, cancellationToken);
        if (!added)
        {
            return Conflict("SteamId already exists or invalid.");
        }

        return CreatedAtAction(nameof(Exists), new { steamId = request.SteamId.Trim() }, request.SteamId.Trim());
    }

    [HttpDelete("{steamId}")]
    public async Task<IActionResult> Delete(string steamId, CancellationToken cancellationToken)
    {
        var removed = await _steamWhitelistService.RemoveAsync(steamId, cancellationToken);
        return removed ? NoContent() : NotFound();
    }
}
