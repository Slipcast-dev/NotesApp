namespace NotesApp.Localization;

/// <summary>
/// Хранит единственный активный язык приложения и предоставляет строки интерфейса.
/// Используется собственный небольшой словарь, потому что приложению нужны ровно два
/// языка и мгновенное переключение без перезапуска WinUI-процесса.
/// </summary>
public static class LocalizationManager
{
    public const string RussianLanguage = "ru";
    public const string EnglishLanguage = "en";

    private static readonly IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>> Translations =
        new Dictionary<string, IReadOnlyDictionary<string, string>>(StringComparer.OrdinalIgnoreCase)
        {
            [RussianLanguage] = new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["Tags"] = "Теги",
                ["Search"] = "Поиск",
                ["SearchPlaceholder"] = "Найти заметку...",
                ["SortBy"] = "Сортировка",
                ["RecentFirst"] = "Сначала недавние",
                ["OldestFirst"] = "Сначала старые",
                ["TitleAscending"] = "Название А-Я",
                ["TitleDescending"] = "Название Я-А",
                ["CreatedNewestFirst"] = "Сначала новые",
                ["CreatedOldestFirst"] = "Сначала давно созданные",
                ["ShowDeleted"] = "Показывать удаленные",
                ["Hide"] = "Скрыть",
                ["Show"] = "Показать",
                ["NewNote"] = "Новая заметка",
                ["Settings"] = "Настройки",
                ["Storage"] = "Хранилище",
                ["StorageFolderTitle"] = "Выберите папку для хранения заметок",
                ["StorageChangeError"] = "Не удалось изменить хранилище: {0}",
                ["Exit"] = "Выход",
                ["Title"] = "Название",
                ["NoteTitle"] = "Название заметки",
                ["Content"] = "Содержание",
                ["WriteNoteHere"] = "Введите текст заметки...",
                ["AddTag"] = "Добавить тег",
                ["Add"] = "Добавить",
                ["ExistingTag"] = "Существующий тег",
                ["SelectTag"] = "Выберите тег",
                ["NoAvailableTags"] = "Нет доступных тегов",
                ["OrCreateNewTag"] = "Или создайте новый тег",
                ["UnsavedChanges"] = "Есть несохраненные изменения",
                ["AllChangesSaved"] = "Все изменения сохранены",
                ["Delete"] = "Удалить",
                ["Restore"] = "Восстановить",
                ["NewTag"] = "+ Новый тег",
                ["NewTagTitle"] = "Новый тег",
                ["TagColor"] = "Цвет тега",
                ["ChangeColor"] = "Цвет",
                ["ChangeTagColorTitle"] = "Цвет тега «{0}»",
                ["Theme"] = "Тема",
                ["Light"] = "Светлая",
                ["Dark"] = "Темная",
                ["System"] = "Системная",
                ["FontSize"] = "Размер шрифта",
                ["FontFamily"] = "Шрифт",
                ["Formatting"] = "Форматирование",
                ["Bold"] = "Жирный",
                ["Italic"] = "Курсив",
                ["TextCase"] = "Регистр и заголовок",
                ["Uppercase"] = "Заглавные",
                ["Lowercase"] = "Строчные",
                ["Heading"] = "Заголовок",
                ["Blocks"] = "Блоки",
                ["Table"] = "Таблица",
                ["Checklist"] = "Чек-лист",
                ["ToggleChecklistItem"] = "Отметить / снять",
                ["InternalLink"] = "Внутренняя ссылка",
                ["InsertInternalLink"] = "Вставить ссылку",
                ["OpenInternalLink"] = "Открыть ссылку",
                ["SelectNoteForLink"] = "Выберите заметку",
                ["NoNotesForLink"] = "Нет других заметок для ссылки.",
                ["Insert"] = "Вставить",
                ["SelectedTextPlaceholder"] = "выделенный текст",
                ["HeadingPlaceholder"] = "Заголовок",
                ["CodePlaceholder"] = "код",
                ["InternalLinkNotFound"] = "Заметка «{0}» не найдена.",
                ["AutoSave"] = "Автосохранение",
                ["DefaultSorting"] = "Сортировка по умолчанию",
                ["Language"] = "Язык",
                ["Russian"] = "Русский",
                ["English"] = "Английский",
                ["ResetToDefault"] = "Сбросить",
                ["Save"] = "Сохранить",
                ["Close"] = "Закрыть",
                ["Error"] = "Ошибка",
                ["SaveError"] = "Ошибка сохранения",
                ["StartupError"] = "Ошибка запуска",
                ["SettingsSaved"] = "Настройки сохранены.",
                ["FailedToLoadSettings"] = "Не удалось загрузить настройки: {0}",
                ["FailedToSave"] = "Не удалось сохранить: {0}",
                ["ResetSettings"] = "Сброс настроек",
                ["ResetSettingsQuestion"] = "Вернуть настройки по умолчанию?",
                ["ExitQuestion"] = "Закрыть приложение?",
                ["FailedToInitializeWindow"] = "Не удалось инициализировать главное окно: {0}",
                ["FailedToLoadNotes"] = "Не удалось загрузить заметки: {0}",
                ["FailedToCreateNote"] = "Не удалось создать заметку: {0}",
                ["DeletePermanently"] = "Удалить навсегда",
                ["DeleteNoteQuestion"] = "Удалить заметку «{0}»?",
                ["FailedToDelete"] = "Не удалось удалить: {0}",
                ["FailedToRestore"] = "Не удалось восстановить: {0}",
                ["FailedToSaveNote"] = "Не удалось сохранить заметку: {0}",
                ["EnterTagName"] = "Введите название тега",
                ["FailedToAddTag"] = "Не удалось добавить тег: {0}",
                ["FailedToRemoveTag"] = "Не удалось удалить тег: {0}",
                ["FailedToLoadAvailableTags"] = "Не удалось загрузить доступные теги: {0}",
                ["FailedToLoadTags"] = "Не удалось загрузить теги: {0}",
                ["TagName"] = "Название тега",
                ["DeleteTag"] = "Удалить тег",
                ["DeleteTagQuestion"] = "Удалить тег «{0}»?",
                ["Yes"] = "Да",
                ["No"] = "Нет",
                ["Cancel"] = "Отмена",
                ["Ok"] = "ОК"
            },
            [EnglishLanguage] = new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["Tags"] = "Tags",
                ["Search"] = "Search",
                ["SearchPlaceholder"] = "Search notes...",
                ["SortBy"] = "Sort by",
                ["RecentFirst"] = "Recent first",
                ["OldestFirst"] = "Oldest first",
                ["TitleAscending"] = "Title A-Z",
                ["TitleDescending"] = "Title Z-A",
                ["CreatedNewestFirst"] = "Created new first",
                ["CreatedOldestFirst"] = "Created old first",
                ["ShowDeleted"] = "Show deleted",
                ["Hide"] = "Hide",
                ["Show"] = "Show",
                ["NewNote"] = "New note",
                ["Settings"] = "Settings",
                ["Storage"] = "Storage",
                ["StorageFolderTitle"] = "Choose a folder for stored notes",
                ["StorageChangeError"] = "Failed to change storage: {0}",
                ["Exit"] = "Exit",
                ["Title"] = "Title",
                ["NoteTitle"] = "Note title",
                ["Content"] = "Content",
                ["WriteNoteHere"] = "Write your note here...",
                ["AddTag"] = "Add tag",
                ["Add"] = "Add",
                ["ExistingTag"] = "Existing tag",
                ["SelectTag"] = "Select a tag",
                ["NoAvailableTags"] = "No available tags",
                ["OrCreateNewTag"] = "Or create a new tag",
                ["UnsavedChanges"] = "Unsaved changes",
                ["AllChangesSaved"] = "All changes saved",
                ["Delete"] = "Delete",
                ["Restore"] = "Restore",
                ["NewTag"] = "+ New tag",
                ["NewTagTitle"] = "New tag",
                ["TagColor"] = "Tag color",
                ["ChangeColor"] = "Color",
                ["ChangeTagColorTitle"] = "Tag color \"{0}\"",
                ["Theme"] = "Theme",
                ["Light"] = "Light",
                ["Dark"] = "Dark",
                ["System"] = "System",
                ["FontSize"] = "Font size",
                ["FontFamily"] = "Font",
                ["Formatting"] = "Formatting",
                ["Bold"] = "Bold",
                ["Italic"] = "Italic",
                ["TextCase"] = "Case and heading",
                ["Uppercase"] = "Uppercase",
                ["Lowercase"] = "Lowercase",
                ["Heading"] = "Heading",
                ["Blocks"] = "Blocks",
                ["Table"] = "Table",
                ["Checklist"] = "Checklist",
                ["ToggleChecklistItem"] = "Check / uncheck",
                ["InternalLink"] = "Internal link",
                ["InsertInternalLink"] = "Insert link",
                ["OpenInternalLink"] = "Open link",
                ["SelectNoteForLink"] = "Select a note",
                ["NoNotesForLink"] = "There are no other notes to link.",
                ["Insert"] = "Insert",
                ["SelectedTextPlaceholder"] = "selected text",
                ["HeadingPlaceholder"] = "Heading",
                ["CodePlaceholder"] = "code",
                ["InternalLinkNotFound"] = "Note \"{0}\" was not found.",
                ["AutoSave"] = "Auto-save",
                ["DefaultSorting"] = "Default sorting",
                ["Language"] = "Language",
                ["Russian"] = "Russian",
                ["English"] = "English",
                ["ResetToDefault"] = "Reset to default",
                ["Save"] = "Save",
                ["Close"] = "Close",
                ["Error"] = "Error",
                ["SaveError"] = "Save Error",
                ["StartupError"] = "Startup error",
                ["SettingsSaved"] = "Settings saved.",
                ["FailedToLoadSettings"] = "Failed to load settings: {0}",
                ["FailedToSave"] = "Failed to save: {0}",
                ["ResetSettings"] = "Reset Settings",
                ["ResetSettingsQuestion"] = "Reset to defaults?",
                ["ExitQuestion"] = "Close the application?",
                ["FailedToInitializeWindow"] = "Failed to initialize the main window: {0}",
                ["FailedToLoadNotes"] = "Failed to load notes: {0}",
                ["FailedToCreateNote"] = "Failed to create the note: {0}",
                ["DeletePermanently"] = "Delete permanently",
                ["DeleteNoteQuestion"] = "Delete \"{0}\"?",
                ["FailedToDelete"] = "Failed to delete: {0}",
                ["FailedToRestore"] = "Failed to restore: {0}",
                ["FailedToSaveNote"] = "Failed to save the note: {0}",
                ["EnterTagName"] = "Enter tag name",
                ["FailedToAddTag"] = "Failed to add tag: {0}",
                ["FailedToRemoveTag"] = "Failed to remove tag: {0}",
                ["FailedToLoadAvailableTags"] = "Failed to load available tags: {0}",
                ["FailedToLoadTags"] = "Failed to load tags: {0}",
                ["TagName"] = "Tag name",
                ["DeleteTag"] = "Delete Tag",
                ["DeleteTagQuestion"] = "Delete \"{0}\"?",
                ["Yes"] = "Yes",
                ["No"] = "No",
                ["Cancel"] = "Cancel",
                ["Ok"] = "OK"
            }
        };

    private static string _currentLanguage = RussianLanguage;

    public static event EventHandler? LanguageChanged;

    public static string CurrentLanguage => _currentLanguage;

    public static LocalizedStrings Strings { get; } = new();

    /// <summary>
    /// Все устаревшие и неизвестные коды намеренно переводятся в русский:
    /// это гарантирует, что приложение поддерживает только русский и английский.
    /// </summary>
    public static string NormalizeLanguage(string? language)
        => string.Equals(language, EnglishLanguage, StringComparison.OrdinalIgnoreCase)
            ? EnglishLanguage
            : RussianLanguage;

    public static void SetLanguage(string? language)
    {
        var normalizedLanguage = NormalizeLanguage(language);
        if (string.Equals(_currentLanguage, normalizedLanguage, StringComparison.Ordinal))
        {
            return;
        }

        _currentLanguage = normalizedLanguage;
        LanguageChanged?.Invoke(null, EventArgs.Empty);
    }

    public static string Get(string key)
    {
        if (Translations[_currentLanguage].TryGetValue(key, out var value))
        {
            return value;
        }

        // Русский является основным и одновременно резервным языком.
        return Translations[RussianLanguage].TryGetValue(key, out var fallback) ? fallback : key;
    }

    public static string Format(string key, params object[] arguments)
        => string.Format(System.Globalization.CultureInfo.CurrentCulture, Get(key), arguments);
}

/// <summary>
/// Типизированная оболочка нужна для надежных x:Bind-привязок в XAML.
/// Значения вычисляются при каждом обновлении привязок и не дублируют словари.
/// </summary>
public sealed class LocalizedStrings
{
    public string Tags => LocalizationManager.Get(nameof(Tags));
    public string Search => LocalizationManager.Get(nameof(Search));
    public string SearchPlaceholder => LocalizationManager.Get(nameof(SearchPlaceholder));
    public string SortBy => LocalizationManager.Get(nameof(SortBy));
    public string RecentFirst => LocalizationManager.Get(nameof(RecentFirst));
    public string OldestFirst => LocalizationManager.Get(nameof(OldestFirst));
    public string TitleAscending => LocalizationManager.Get(nameof(TitleAscending));
    public string TitleDescending => LocalizationManager.Get(nameof(TitleDescending));
    public string CreatedNewestFirst => LocalizationManager.Get(nameof(CreatedNewestFirst));
    public string CreatedOldestFirst => LocalizationManager.Get(nameof(CreatedOldestFirst));
    public string ShowDeleted => LocalizationManager.Get(nameof(ShowDeleted));
    public string Hide => LocalizationManager.Get(nameof(Hide));
    public string Show => LocalizationManager.Get(nameof(Show));
    public string NewNote => LocalizationManager.Get(nameof(NewNote));
    public string Settings => LocalizationManager.Get(nameof(Settings));
    public string Storage => LocalizationManager.Get(nameof(Storage));
    public string Exit => LocalizationManager.Get(nameof(Exit));
    public string Title => LocalizationManager.Get(nameof(Title));
    public string NoteTitle => LocalizationManager.Get(nameof(NoteTitle));
    public string Content => LocalizationManager.Get(nameof(Content));
    public string WriteNoteHere => LocalizationManager.Get(nameof(WriteNoteHere));
    public string AddTag => LocalizationManager.Get(nameof(AddTag));
    public string Delete => LocalizationManager.Get(nameof(Delete));
    public string Restore => LocalizationManager.Get(nameof(Restore));
    public string NewTag => LocalizationManager.Get(nameof(NewTag));
    public string ChangeColor => LocalizationManager.Get(nameof(ChangeColor));
    public string Theme => LocalizationManager.Get(nameof(Theme));
    public string Light => LocalizationManager.Get(nameof(Light));
    public string Dark => LocalizationManager.Get(nameof(Dark));
    public string System => LocalizationManager.Get(nameof(System));
    public string FontSize => LocalizationManager.Get(nameof(FontSize));
    public string FontFamily => LocalizationManager.Get(nameof(FontFamily));
    public string Formatting => LocalizationManager.Get(nameof(Formatting));
    public string Bold => LocalizationManager.Get(nameof(Bold));
    public string Italic => LocalizationManager.Get(nameof(Italic));
    public string TextCase => LocalizationManager.Get(nameof(TextCase));
    public string Uppercase => LocalizationManager.Get(nameof(Uppercase));
    public string Lowercase => LocalizationManager.Get(nameof(Lowercase));
    public string Heading => LocalizationManager.Get(nameof(Heading));
    public string Blocks => LocalizationManager.Get(nameof(Blocks));
    public string Table => LocalizationManager.Get(nameof(Table));
    public string Checklist => LocalizationManager.Get(nameof(Checklist));
    public string ToggleChecklistItem => LocalizationManager.Get(nameof(ToggleChecklistItem));
    public string InternalLink => LocalizationManager.Get(nameof(InternalLink));
    public string InsertInternalLink => LocalizationManager.Get(nameof(InsertInternalLink));
    public string OpenInternalLink => LocalizationManager.Get(nameof(OpenInternalLink));
    public string AutoSave => LocalizationManager.Get(nameof(AutoSave));
    public string DefaultSorting => LocalizationManager.Get(nameof(DefaultSorting));
    public string Language => LocalizationManager.Get(nameof(Language));
    public string Russian => LocalizationManager.Get(nameof(Russian));
    public string English => LocalizationManager.Get(nameof(English));
    public string ResetToDefault => LocalizationManager.Get(nameof(ResetToDefault));
    public string Save => LocalizationManager.Get(nameof(Save));
    public string Close => LocalizationManager.Get(nameof(Close));
}
