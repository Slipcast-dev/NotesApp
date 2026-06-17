using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using NotesApp.Infrastructure;
using NotesApp.Models;
using System.Data;

namespace NotesApp.Data;

public static class DatabaseInitializer
{
    public static async Task InitializeAsync(AppDbContext context, ILogger? logger = null)
    {
        try
        {
            // В этом проекте миграции пока не хранятся в репозитории, поэтому
            // первый запуск должен создавать схему напрямую из текущей модели.
            // Это надежнее для MSI-сборки: приложение не зависит от отдельного
            // набора миграций и не падает на старте из-за пустой БД.
            await context.Database.EnsureCreatedAsync();
            await EnsureTagColorColumnAsync(context);
            await EnsureNoteMarkdownColumnAsync(context);
            await EnsureMarkdownFilesAsync(context);
        }
        catch (Exception ex)
        {
            logger?.LogError(ex, "An error occurred while initializing the database.");
            throw;
        }
    }

    private static async Task EnsureTagColorColumnAsync(AppDbContext context)
    {
        if (await HasColumnAsync(context, "Tags", nameof(Tag.ColorHex)))
        {
            return;
        }

        // EnsureCreated не меняет уже существующие таблицы. Узкий
        // ALTER TABLE сохраняет пользовательские базы и задает цвет
        // старым тегам без отдельного набора EF-миграций.
        await context.Database.ExecuteSqlRawAsync(
            $"ALTER TABLE Tags ADD COLUMN {nameof(Tag.ColorHex)} TEXT NOT NULL DEFAULT '{Tag.DefaultColorHex}';");
    }

    private static async Task EnsureNoteMarkdownColumnAsync(AppDbContext context)
    {
        if (await HasColumnAsync(context, "Notes", nameof(Note.MarkdownFileName)))
        {
            return;
        }

        // Колонка nullable: старые заметки сначала получают схему, а затем
        // отдельным шагом материализуются в markdown-файлы.
        await context.Database.ExecuteSqlRawAsync(
            $"ALTER TABLE Notes ADD COLUMN {nameof(Note.MarkdownFileName)} TEXT NULL;");
    }

    private static async Task EnsureMarkdownFilesAsync(AppDbContext context)
    {
        var notes = await context.Notes.ToListAsync();
        foreach (var note in notes)
        {
            if (!string.IsNullOrWhiteSpace(note.MarkdownFileName) && File.Exists(MarkdownNoteFiles.GetFilePath(note)))
            {
                continue;
            }

            note.MarkdownFileName = MarkdownNoteFiles.CreateFileName(note.Id);
            await MarkdownNoteFiles.WriteAsync(note);
        }

        await context.SaveChangesAsync();
    }

    private static async Task<bool> HasColumnAsync(AppDbContext context, string tableName, string columnName)
    {
        var connection = context.Database.GetDbConnection();
        var shouldCloseConnection = connection.State != ConnectionState.Open;

        if (shouldCloseConnection)
        {
            await connection.OpenAsync();
        }

        try
        {
            await using var command = connection.CreateCommand();
            command.CommandText = $"PRAGMA table_info('{tableName}');";

            await using (var reader = await command.ExecuteReaderAsync())
            {
                while (await reader.ReadAsync())
                {
                    if (string.Equals(reader["name"]?.ToString(), columnName, StringComparison.Ordinal))
                    {
                        return true;
                    }
                }
            }

            return false;
        }
        finally
        {
            if (shouldCloseConnection)
            {
                await connection.CloseAsync();
            }
        }
    }
}
