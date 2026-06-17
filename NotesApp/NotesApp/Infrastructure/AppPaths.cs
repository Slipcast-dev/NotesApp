using System.Text.Json;

namespace NotesApp.Infrastructure;

public static class AppPaths
{
    private const string AppFolderName = "NotesApp";
    private const string PortableDataFolderName = "Data";
    private const string StorageLocationFileName = "storage-location.json";

    private sealed record StorageLocation(string FolderPath);

    // Все пути к файлам приложения проходят через один helper, чтобы runtime,
    // design-time фабрика DbContext и сервис настроек всегда использовали
    // одинаковое правило размещения данных.
    //
    // В portable-режиме приоритетный вариант - папка Data рядом с exe, потому
    // что ее можно просто скопировать вместе с приложением. Если папка рядом с
    // exe недоступна на запись, например при запуске с read-only носителя, мы
    // мягко откатываемся к профилю пользователя, чтобы приложение не падало.
    public static string GetDataFolder()
    {
        var configuredFolder = GetConfiguredStorageFolder();
        if (!string.IsNullOrWhiteSpace(configuredFolder) && TryCreateDirectory(configuredFolder))
        {
            return configuredFolder;
        }

        var portableFolder = GetPortableDataFolder();
        if (TryCreateDirectory(portableFolder))
        {
            return portableFolder;
        }

        var appDataRoot = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var fallbackFolder = Path.Combine(appDataRoot, AppFolderName);
        if (TryCreateDirectory(fallbackFolder))
        {
            return fallbackFolder;
        }

        // Если и профиль пользователя неожиданно недоступен, используем temp,
        // чтобы приложение хотя бы могло стартовать и не теряло исключения.
        var tempFolder = Path.Combine(Path.GetTempPath(), AppFolderName);
        TryCreateDirectory(tempFolder);
        return tempFolder;
    }

    public static string GetDatabasePath() => Path.Combine(GetDataFolder(), "notes.db");

    public static string GetSettingsPath() => Path.Combine(GetDataFolder(), "settings.json");

    public static string GetStartupLogPath() => Path.Combine(GetDataFolder(), "startup-error.log");

    public static string? GetConfiguredStorageFolder()
    {
        var locationFilePath = GetStorageLocationFilePath();
        if (!File.Exists(locationFilePath))
        {
            return null;
        }

        try
        {
            var json = File.ReadAllText(locationFilePath);
            var location = JsonSerializer.Deserialize<StorageLocation>(json);
            return string.IsNullOrWhiteSpace(location?.FolderPath)
                ? null
                : Path.GetFullPath(location.FolderPath);
        }
        catch
        {
            // Поврежденный указатель не должен блокировать запуск. В таком
            // случае приложение возвращается к portable-папке Data.
            return null;
        }
    }

    public static bool HasConfiguredStorageFolder()
        => !string.IsNullOrWhiteSpace(GetConfiguredStorageFolder());

    public static void SetConfiguredStorageFolder(string folderPath)
    {
        var normalizedPath = Path.GetFullPath(folderPath);
        Directory.CreateDirectory(normalizedPath);

        var portableDataFolder = GetPortableDataFolder();
        Directory.CreateDirectory(portableDataFolder);

        // Указатель намеренно хранится рядом с приложением, а не внутри
        // выбранной папки: иначе следующий запуск не смог бы узнать, где ее
        // искать.
        var json = JsonSerializer.Serialize(
            new StorageLocation(normalizedPath),
            new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(GetStorageLocationFilePath(), json);
    }

    public static string GetStorageButtonText()
    {
        var configuredFolder = GetConfiguredStorageFolder();
        if (string.IsNullOrWhiteSpace(configuredFolder))
        {
            return Localization.LocalizationManager.Get("Storage");
        }

        var folderName = new DirectoryInfo(configuredFolder).Name;
        return string.IsNullOrWhiteSpace(folderName) ? configuredFolder : folderName;
    }

    private static string GetPortableDataFolder()
        => Path.Combine(AppContext.BaseDirectory, PortableDataFolderName);

    private static string GetStorageLocationFilePath()
        => Path.Combine(GetPortableDataFolder(), StorageLocationFileName);

    private static bool TryCreateDirectory(string path)
    {
        try
        {
            Directory.CreateDirectory(path);
            return true;
        }
        catch
        {
            // Ничего не выбрасываем наружу: portable-путь может быть недоступен,
            // но это не должно ломать запуск до того, как будет выбран fallback.
            return false;
        }
    }
}
