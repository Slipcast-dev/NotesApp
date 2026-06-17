using Microsoft.EntityFrameworkCore;
using NotesApp.Data;
using NotesApp.Infrastructure;
using NotesApp.Models;

namespace NotesApp.Services;

public class SqliteDataService : IDataService
{
    private readonly AppDbContext _context;

    public SqliteDataService(AppDbContext context)
    {
        _context = context;
    }

    public async Task<IEnumerable<Note>> GetAllNotesAsync(
        bool includeDeleted = false,
        string? searchText = null,
        string? sortBy = null,
        Tag? filterTag = null)
    {
        IQueryable<Note> query = _context.Notes
            .AsNoTracking()
            .Include(n => n.NoteTags)
            .ThenInclude(nt => nt.Tag);

        if (!includeDeleted)
        {
            query = query.Where(n => !n.IsDeleted);
        }

        if (filterTag != null)
        {
            query = query.Where(n => n.NoteTags.Any(nt => nt.TagId == filterTag.Id));
        }

        var notes = await query.ToListAsync();
        await LoadMarkdownContentAsync(notes);

        if (!string.IsNullOrWhiteSpace(searchText))
        {
            var normalizedSearch = searchText.Trim().ToLowerInvariant();
            notes = notes
                .Where(n =>
                    n.Title.ToLower().Contains(normalizedSearch) ||
                    n.Content.ToLower().Contains(normalizedSearch) ||
                    n.NoteTags.Any(nt => nt.Tag.Name.ToLower().Contains(normalizedSearch)))
                .ToList();
        }

        return ApplySorting(notes, sortBy).ToList();
    }

    public async Task<Note?> GetNoteByIdAsync(int id)
    {
        var note = await _context.Notes
            .AsNoTracking()
            .Include(n => n.NoteTags)
            .ThenInclude(nt => nt.Tag)
            .FirstOrDefaultAsync(n => n.Id == id);

        if (note != null)
        {
            await MarkdownNoteFiles.TryReadIntoNoteAsync(note);
        }

        return note;
    }

    public async Task<Note> CreateNoteAsync(string title, string content)
    {
        var now = DateTime.Now;
        var note = new Note
        {
            Title = title,
            Content = content,
            CreatedAt = now,
            UpdatedAt = now
        };

        _context.Notes.Add(note);
        await _context.SaveChangesAsync();

        note.MarkdownFileName = MarkdownNoteFiles.CreateFileName(note.Id);
        await MarkdownNoteFiles.WriteAsync(note);
        await _context.SaveChangesAsync();
        return note;
    }

    public async Task<bool> UpdateNoteAsync(Note note)
    {
        var existing = await _context.Notes.FindAsync(note.Id);
        if (existing == null)
        {
            return false;
        }

        existing.Title = note.Title;
        existing.Content = note.Content;
        existing.UpdatedAt = DateTime.Now;
        existing.MarkdownFileName = string.IsNullOrWhiteSpace(existing.MarkdownFileName)
            ? MarkdownNoteFiles.CreateFileName(existing.Id)
            : existing.MarkdownFileName;
        await MarkdownNoteFiles.WriteAsync(existing);
        return await _context.SaveChangesAsync() > 0;
    }

    public async Task<bool> DeleteNoteAsync(int id)
    {
        var note = await _context.Notes.FindAsync(id);
        if (note == null)
        {
            return false;
        }

        note.IsDeleted = true;
        note.UpdatedAt = DateTime.Now;
        return await _context.SaveChangesAsync() > 0;
    }

    public async Task<bool> HardDeleteNoteAsync(int id)
    {
        var note = await _context.Notes.FindAsync(id);
        if (note == null)
        {
            return false;
        }

        _context.Notes.Remove(note);
        var deleted = await _context.SaveChangesAsync() > 0;
        if (deleted)
        {
            DeleteMarkdownFileIfExists(note);
        }

        return deleted;
    }

    public async Task<bool> RestoreNoteAsync(int id)
    {
        var note = await _context.Notes.FindAsync(id);
        if (note == null || !note.IsDeleted)
        {
            return false;
        }

        note.IsDeleted = false;
        note.UpdatedAt = DateTime.Now;
        return await _context.SaveChangesAsync() > 0;
    }

    public async Task<IEnumerable<Tag>> GetAllTagsAsync()
    {
        return await _context.Tags
            .AsNoTracking()
            .OrderBy(t => t.Name)
            .ToListAsync();
    }

    public async Task<Tag?> GetTagByIdAsync(int id)
    {
        return await _context.Tags.AsNoTracking().FirstOrDefaultAsync(t => t.Id == id);
    }

    public async Task<Tag?> GetTagByNameAsync(string name)
    {
        string normalizedName = name.Trim().ToLowerInvariant();
        return await _context.Tags.AsNoTracking().FirstOrDefaultAsync(t => t.Name.ToLower() == normalizedName);
    }

    public async Task<Tag> CreateTagAsync(string name, string? colorHex = null)
    {
        var existing = await GetTagByNameAsync(name);
        if (existing != null)
        {
            return existing;
        }

        var tag = new Tag
        {
            Name = name.Trim(),
            ColorHex = NormalizeTagColor(colorHex)
        };
        _context.Tags.Add(tag);
        await _context.SaveChangesAsync();
        return tag;
    }

    public async Task<bool> UpdateTagColorAsync(int id, string? colorHex)
    {
        var tag = await _context.Tags.FindAsync(id);
        if (tag == null)
        {
            return false;
        }

        tag.ColorHex = NormalizeTagColor(colorHex);
        return await _context.SaveChangesAsync() > 0;
    }

    public async Task<bool> DeleteTagAsync(int id)
    {
        var tag = await _context.Tags.FindAsync(id);
        if (tag == null)
        {
            return false;
        }

        _context.Tags.Remove(tag);
        return await _context.SaveChangesAsync() > 0;
    }

    public async Task<bool> AddTagToNoteAsync(int noteId, int tagId)
    {
        if (await _context.NoteTags.AnyAsync(nt => nt.NoteId == noteId && nt.TagId == tagId))
        {
            return true;
        }

        _context.NoteTags.Add(new NoteTag { NoteId = noteId, TagId = tagId });
        return await _context.SaveChangesAsync() > 0;
    }

    public async Task<bool> RemoveTagFromNoteAsync(int noteId, int tagId)
    {
        var noteTag = await _context.NoteTags.FirstOrDefaultAsync(x => x.NoteId == noteId && x.TagId == tagId);
        if (noteTag == null)
        {
            return false;
        }

        _context.NoteTags.Remove(noteTag);
        return await _context.SaveChangesAsync() > 0;
    }

    public async Task<IEnumerable<Tag>> GetTagsForNoteAsync(int noteId)
    {
        var note = await _context.Notes
            .AsNoTracking()
            .Include(n => n.NoteTags)
            .ThenInclude(nt => nt.Tag)
            .FirstOrDefaultAsync(n => n.Id == noteId);

        return note?.NoteTags.Select(nt => nt.Tag).ToList() ?? new List<Tag>();
    }

    private static IEnumerable<Note> ApplySorting(IEnumerable<Note> notes, string? sortBy)
    {
        return sortBy?.Trim().ToLowerInvariant() switch
        {
            "titleasc" => notes.OrderBy(n => n.Title),
            "titledesc" => notes.OrderByDescending(n => n.Title),
            "createdasc" => notes.OrderBy(n => n.CreatedAt),
            "createddesc" => notes.OrderByDescending(n => n.CreatedAt),
            "updatedasc" => notes.OrderBy(n => n.UpdatedAt),
            "updateddesc" => notes.OrderByDescending(n => n.UpdatedAt),
            _ => notes.OrderByDescending(n => n.UpdatedAt)
        };
    }

    private static async Task LoadMarkdownContentAsync(IEnumerable<Note> notes)
    {
        foreach (var note in notes)
        {
            await MarkdownNoteFiles.TryReadIntoNoteAsync(note);
        }
    }

    private static void DeleteMarkdownFileIfExists(Note note)
    {
        try
        {
            var filePath = MarkdownNoteFiles.GetFilePath(note);
            if (File.Exists(filePath))
            {
                File.Delete(filePath);
            }
        }
        catch
        {
            // Удаление файла является best effort после успешного удаления из
            // базы: если файл занят внешним редактором, приложение не должно
            // откатывать уже выполненную операцию с заметкой.
        }
    }

    private static string NormalizeTagColor(string? colorHex)
    {
        var value = colorHex?.Trim();
        if (string.IsNullOrWhiteSpace(value))
        {
            return Tag.DefaultColorHex;
        }

        if (!value.StartsWith('#'))
        {
            value = $"#{value}";
        }

        // В базе храним только web-hex #RRGGBB. Это защищает UI от
        // неожиданных строк и оставляет формат совместимым с SQLite.
        return value.Length == 7 && value.Skip(1).All(Uri.IsHexDigit)
            ? value.ToUpperInvariant()
            : Tag.DefaultColorHex;
    }
}
