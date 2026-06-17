using Microsoft.EntityFrameworkCore;
using NotesApp.Models;

namespace NotesApp.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<Note> Notes { get; set; }
    public DbSet<Tag> Tags { get; set; }
    public DbSet<NoteTag> NoteTags { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<Note>(entity =>
        {
            entity.HasKey(n => n.Id);
            entity.Property(n => n.Title).IsRequired().HasMaxLength(200);
            entity.Property(n => n.MarkdownFileName).HasMaxLength(260);
            entity.HasIndex(n => n.IsDeleted);
            entity.HasIndex(n => n.CreatedAt);
            entity.HasIndex(n => n.UpdatedAt);
        });

        modelBuilder.Entity<Tag>(entity =>
        {
            entity.HasKey(t => t.Id);
            entity.Property(t => t.Name).IsRequired().HasMaxLength(50);
            entity.Property(t => t.ColorHex).IsRequired().HasMaxLength(9).HasDefaultValue(Tag.DefaultColorHex);
            entity.HasIndex(t => t.Name).IsUnique();
        });

        modelBuilder.Entity<NoteTag>(entity =>
        {
            entity.HasKey(nt => new { nt.NoteId, nt.TagId });
            entity.HasOne(nt => nt.Note).WithMany(n => n.NoteTags).HasForeignKey(nt => nt.NoteId).OnDelete(DeleteBehavior.Cascade);
            entity.HasOne(nt => nt.Tag).WithMany(t => t.NoteTags).HasForeignKey(nt => nt.TagId).OnDelete(DeleteBehavior.Cascade);
        });
    }
}
