using NotesApp.Models;

namespace NotesApp.Services;

public interface ISettingsService
{
    Task<AppSettings> LoadSettingsAsync();
    Task SaveSettingsAsync(AppSettings settings);
}
