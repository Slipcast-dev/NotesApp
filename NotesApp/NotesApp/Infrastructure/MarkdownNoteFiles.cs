using NotesApp.Models;

namespace NotesApp.Infrastructure;

public static class MarkdownNoteFiles
{
    public static string CreateFileName(int noteId)
        => $"note-{noteId:D6}.md";

    public static string GetFilePath(Note note)
    {
        var fileName = string.IsNullOrWhiteSpace(note.MarkdownFileName)
            ? CreateFileName(note.Id)
            : note.MarkdownFileName;

        // Файл заметки намеренно лежит прямо в выбранной папке хранилища:
        // пользователь просил отдельные markdown-файлы именно в этой папке,
        // а не во внутреннем служебном каталоге.
        return Path.Combine(AppPaths.GetDataFolder(), fileName);
    }

    public static async Task WriteAsync(Note note)
    {
        note.MarkdownFileName = string.IsNullOrWhiteSpace(note.MarkdownFileName)
            ? CreateFileName(note.Id)
            : note.MarkdownFileName;

        var filePath = GetFilePath(note);
        Directory.CreateDirectory(Path.GetDirectoryName(filePath) ?? AppPaths.GetDataFolder());

        // Заголовок хранится как H1, чтобы каждый файл был валидной и
        // самодостаточной markdown-заметкой, но в редакторе заголовок
        // остается отдельным полем и не дублируется в тексте.
        var markdown = $"# {NormalizeHeading(note.Title)}{Environment.NewLine}{Environment.NewLine}{note.Content}";
        await File.WriteAllTextAsync(filePath, markdown);
    }

    public static async Task<bool> TryReadIntoNoteAsync(Note note)
    {
        var filePath = GetFilePath(note);
        if (!File.Exists(filePath))
        {
            return false;
        }

        var markdown = await File.ReadAllTextAsync(filePath);
        var parsed = Parse(markdown);
        note.Title = parsed.Title;
        note.Content = parsed.Content;
        return true;
    }

    private static (string Title, string Content) Parse(string markdown)
    {
        using var reader = new StringReader(markdown);
        var firstLine = reader.ReadLine();

        if (firstLine != null && firstLine.StartsWith("# ", StringComparison.Ordinal))
        {
            var content = reader.ReadToEnd();
            if (content.StartsWith(Environment.NewLine, StringComparison.Ordinal))
            {
                content = content[Environment.NewLine.Length..];
            }

            var title = firstLine[2..].Trim();
            return (string.IsNullOrWhiteSpace(title) ? "Untitled" : title, content);
        }

        // Если пользователь создал или отредактировал файл без H1, не
        // выбрасываем данные: имя заголовка выводится из первой непустой
        // строки, а весь файл остается содержимым заметки.
        var fallbackTitle = markdown
            .Split(new[] { "\r\n", "\n" }, StringSplitOptions.None)
            .FirstOrDefault(line => !string.IsNullOrWhiteSpace(line))
            ?.Trim();
        return (string.IsNullOrWhiteSpace(fallbackTitle) ? "Untitled" : fallbackTitle, markdown);
    }

    private static string NormalizeHeading(string title)
        => string.IsNullOrWhiteSpace(title)
            ? "Untitled"
            : title.ReplaceLineEndings(" ").Trim();
}
