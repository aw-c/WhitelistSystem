using Microsoft.EntityFrameworkCore;
using WhitelistSystem.Components;
using WhitelistSystem.Data;
using WhitelistSystem.Services;

namespace WhitelistSystem;

public class Program
{
    public static void Main(string[] args)
    {
        var builder = WebApplication.CreateBuilder(args);

        builder.Services.AddControllers();
        builder.Services.AddMemoryCache();
        builder.Services.AddRazorComponents()
            .AddInteractiveServerComponents();

        builder.Services.AddDbContext<WhitelistDbContext>(options =>
            options.UseNpgsql(builder.Configuration.GetConnectionString("WhitelistDb")));

        builder.Services.AddScoped<SteamWhitelistService>();

        var app = builder.Build();

        if (app.Environment.IsDevelopment())
        {
            app.UseDeveloperExceptionPage();
        }

        app.UseHttpsRedirection();
        app.UseStaticFiles();
        app.UseAntiforgery();
        app.UseAuthorization();

        using (var scope = app.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<WhitelistDbContext>();
            db.Database.EnsureCreated();
        }

        app.MapControllers();
        app.MapRazorComponents<App>()
            .AddInteractiveServerRenderMode();

        app.Run();
    }
}
