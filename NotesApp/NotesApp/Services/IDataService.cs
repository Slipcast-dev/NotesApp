using NotesApp.Models;

namespace NotesApp.Services;

public interface IDataService
{
    Task<IEnumerable<Note>> GetAllNotesAsync(bool includeDeleted = false, string? searchText = null, string? sortBy = null, Tag? filterTag = null);
    Task<Note?> GetNoteByIdAsync(int id);
    Task<Note> CreateNoteAsync(string title, string content);
    Task<bool> UpdateNoteAsync(Note note);
    Task<bool> DeleteNoteAsync(int id);
    Task<bool> HardDeleteNoteAsync(int id);
    Task<bool> RestoreNoteAsync(int id);
    Task<IEnumerable<Tag>> GetAllTagsAsync();
    Task<Tag?> GetTagByIdAsync(int id);
    Task<Tag?> GetTagByNameAsync(string name);
    Task<Tag> CreateTagAsync(string name, string? colorHex = null);
    Task<bool> UpdateTagColorAsync(int id, string? colorHex);
    Task<bool> DeleteTagAsync(int id);
    Task<bool> AddTagToNoteAsync(int noteId, int tagId);
    Task<bool> RemoveTagFromNoteAsync(int noteId, int tagId);
    Task<IEnumerable<Tag>> GetTagsForNoteAsync(int noteId);
}
