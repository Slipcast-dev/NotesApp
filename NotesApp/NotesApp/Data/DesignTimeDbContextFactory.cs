using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using NotesApp.Infrastructure;

namespace NotesApp.Data;

public class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    public AppDbContext CreateDbContext(string[] args)
    {
        var optionsBuilder = new DbContextOptionsBuilder<AppDbContext>();
        var dbPath = AppPaths.GetDatabasePath();
        optionsBuilder.UseSqlite($"Data Source={dbPath}");
        return new AppDbContext(optionsBuilder.Options);
    }
}
