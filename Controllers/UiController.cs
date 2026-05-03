using Microsoft.AspNetCore.Mvc;

namespace WhitelistSystem.Controllers;

[ApiController]
[Route("ui")]
public class UiController : ControllerBase
{
    [HttpGet]
    public IActionResult Index()
    {
        return Redirect("/");
    }
}
