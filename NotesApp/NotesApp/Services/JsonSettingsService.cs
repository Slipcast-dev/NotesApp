using System.Text.Json;
using NotesApp.Infrastructure;
using NotesApp.Localization;
using NotesApp.Models;

namespace NotesApp.Services;

public class JsonSettingsService : ISettingsService
{
    private static readonly JsonSerializerOptions PrettyPrintOptions = new()
    {
        WriteIndented = true
    };

    private readonly string _filePath;

    public JsonSettingsService()
    {
        _filePath = AppPaths.GetSettingsPath();
    }

    public async Task<AppSettings> LoadSettingsAsync()
    {
        if (!File.Exists(_filePath))
        {
            return new AppSettings();
        }

        try
        {
            var json = await File.ReadAllTextAsync(_filePath);
            var settings = JsonSerializer.Deserialize<AppSettings>(json) ?? new AppSettings();

            // Старые конфигурации могли не иметь языка, а вручную измененный
            // файл может содержать любой код. Оба случая сводим к двум
            // официально поддерживаемым значениям.
            settings.Language = LocalizationManager.NormalizeLanguage(settings.Language);
            return settings;
        }
        catch
        {
            // Конфигурационный файл должен быть "best effort": если он битый,
            // безопаснее стартовать с дефолтов, чем падать на чтении настроек.
            return new AppSettings();
        }
    }

    public async Task SaveSettingsAsync(AppSettings settings)
    {
        settings.Language = LocalizationManager.NormalizeLanguage(settings.Language);
        var json = JsonSerializer.Serialize(settings, PrettyPrintOptions);
        await File.WriteAllTextAsync(_filePath, json);
    }
}
