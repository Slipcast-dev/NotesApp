using NotesApp.Models;

namespace NotesApp.Services;

/// <summary>
/// Результат диалога добавления тега. Заполняется либо ExistingTag, когда
/// пользователь выбрал готовый тег, либо NewTagName, когда ввел новое имя.
/// Раздельные поля не смешивают UI-выбор с созданием сущности в базе данных.
/// </summary>
public sealed record TagSelectionResult(Tag? ExistingTag, string? NewTagName, string? NewTagColorHex);

public sealed record TagEditorResult(string Name, string ColorHex);
