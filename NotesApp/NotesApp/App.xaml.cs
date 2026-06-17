using Microsoft.UI.Xaml;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using NotesApp.Data;
using NotesApp.Infrastructure;
using NotesApp.Localization;
using NotesApp.Services;
using NotesApp.Views;
using Microsoft.EntityFrameworkCore;

namespace NotesApp;
public sealed partial class App : Application
{
    private MainWindow? _window;
    private IHost? _host;
    public App()
    {
        try
        {
            // XAML словари загружаются в конструкторе App, то есть раньше
            // любых глобальных обработчиков XAML/Task исключений. Если здесь
            // падает resource lookup или парсинг XAML, мы показываем ошибку
            // сразу, а не даем процессу завершиться без следа.
            InitializeComponent();
        }
        catch (Exception ex)
        {
            StartupErrorReporter.ReportCritical("NotesApp startup error", ex);
            throw;
        }

        // Глобальные обработчики нужны, чтобы фатальная ошибка не исчезала
        // без следа до того, как появится главное окно.
        UnhandledException += OnUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += OnCurrentDomainUnhandledException;
        TaskScheduler.UnobservedTaskException += OnUnobservedTaskException;
    }

    protected override async void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        try
        {
            _host = Host.CreateDefaultBuilder().ConfigureServices((context, services) =>
            {
                var dbPath = AppPaths.GetDatabasePath();
                services.AddDbContext<AppDbContext>(options => options.UseSqlite($"Data Source={dbPath}"));
                services.AddScoped<IDataService, SqliteDataService>();
                services.AddSingleton<ISettingsService, JsonSettingsService>();
                services.AddSingleton<IDialogService, DialogService>();
                services.AddSingleton<MainWindow>();
            }).Build();

            using var scope = _host.Services.CreateScope();
            await DatabaseInitializer.InitializeAsync(scope.ServiceProvider.GetRequiredService<AppDbContext>());

            var settingsService = _host.Services.GetRequiredService<ISettingsService>();
            var settings = await settingsService.LoadSettingsAsync();

            // Язык задается до создания окна, чтобы первый кадр сразу был
            // показан на сохраненном языке без мигания русских строк.
            LocalizationManager.SetLanguage(settings.Language);

            _window = _host.Services.GetRequiredService<MainWindow>();
            _host.Services.GetRequiredService<IDialogService>().AttachWindow(_window);
            _window.ApplySettings(settings, suppressNotesReload: true);
            _window.Activate();
            await _window.LoadAsync();
        }
        catch (Exception ex)
        {
            await StartupErrorReporter.ReportAsync("NotesApp startup error", ex);
        }
    }

    private static async void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
    {
        e.Handled = true;
        await StartupErrorReporter.ReportAsync("NotesApp UI error", e.Exception);
    }

    private static async void OnCurrentDomainUnhandledException(object? sender, System.UnhandledExceptionEventArgs e)
    {
        if (e.ExceptionObject is Exception exception)
        {
            await StartupErrorReporter.ReportAsync("NotesApp domain error", exception);
        }
    }

    private static void OnUnobservedTaskException(object? sender, UnobservedTaskExceptionEventArgs e)
    {
        // Этот хук дополняет XAML/Domain обработчики на случай ошибок
        // в фоне, которые не были awaited.
        e.SetObserved();
        _ = StartupErrorReporter.ReportAsync("NotesApp background error", e.Exception);
    }
}
