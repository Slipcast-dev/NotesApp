using System.Runtime.InteropServices;
using System.Text;

namespace NotesApp.Infrastructure;

public static class StartupErrorReporter
{
    private const string DefaultAppName = "NotesApp";

    public static void ReportCritical(string title, Exception exception)
    {
        var message = BuildMessage(exception, out var logPath);

        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(logPath)!);
            File.WriteAllText(logPath, message, Encoding.UTF8);
        }
        catch
        {
            // Если запись лога не удалась, все равно показываем окно с ошибкой.
        }

        // Этот вариант синхронный и используется в самых ранних точках старта,
        // где асинхронный путь мог бы добавить лишнюю сложность и скрыть падение.
        MessageBoxW(
            IntPtr.Zero,
            $"{exception.Message}\n\nПодробности сохранены в:\n{logPath}",
            title,
            0x00000010);
    }

    public static async Task ReportAsync(string title, Exception exception)
    {
        var message = BuildMessage(exception, out var logPath);

        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(logPath)!);
            await File.WriteAllTextAsync(logPath, message, Encoding.UTF8);
        }
        catch
        {
            // Если файл лога записать не удалось, не блокируем показ ошибки.
        }

        // MessageBox работает без XAML-окна, поэтому подходит для фатальных
        // ошибок, которые произошли до создания MainWindow.
        MessageBoxW(
            IntPtr.Zero,
            $"{exception.Message}\n\nПодробности сохранены в:\n{logPath}",
            title,
            0x00000010);
    }

    private static string BuildMessage(Exception exception, out string logPath)
    {
        // Для диагностики используем тот же путь, что и основное приложение.
        // Это упрощает перенос папки целиком и не разносит логи по разным местам.
        logPath = AppPaths.GetStartupLogPath();

        var builder = new StringBuilder();
        builder.AppendLine($"[{DateTimeOffset.Now:O}] {DefaultAppName} startup failure");
        builder.AppendLine(exception.ToString());
        builder.AppendLine();

        return builder.ToString();
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);
}
