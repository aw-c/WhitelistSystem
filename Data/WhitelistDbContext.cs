using Microsoft.EntityFrameworkCore;
using WhitelistSystem.Models;

namespace WhitelistSystem.Data;

public class WhitelistDbContext(DbContextOptions<WhitelistDbContext> options) : DbContext(options)
{
    public DbSet<SteamWhitelistEntry> SteamWhitelistEntries => Set<SteamWhitelistEntry>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<SteamWhitelistEntry>(entity =>
        {
            entity.ToTable("steam_whitelist_entries");
            entity.HasKey(e => e.SteamId);
            entity.Property(e => e.SteamId)
                .HasColumnName("steam_id")
                .HasMaxLength(64)
                .IsRequired();
            entity.Property(e => e.AddedAt)
                .HasColumnName("added_at")
                .IsRequired();
            entity.Property(e => e.Comment)
                .HasColumnName("comment")
                .HasMaxLength(512);
        });
    }
}
