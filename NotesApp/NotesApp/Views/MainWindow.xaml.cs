using System.Diagnostics;
using Microsoft.UI.Xaml;
using NotesApp.Infrastructure;
using NotesApp.Localization;
using NotesApp.Models;
using NotesApp.Services;
using NotesApp.ViewModels;
using Microsoft.UI.Xaml.Media;
using Windows.Storage.Pickers;

namespace NotesApp.Views;
public sealed partial class MainWindow : Window
{
    private const double DefaultBodyFontSize = 14.0;
    private const double DefaultSettingsFontSize = 12.0;
    private const double TitleScaleExponent = 0.74;
    private const double SubtitleScaleExponent = 0.86;
    private const double CaptionScaleExponent = 0.90;
    private const double SmallScaleExponent = 0.94;
    public MainWindowViewModel ViewModel { get; }
    public LocalizedStrings Strings => LocalizationManager.Strings;
    private readonly IDialogService _dialogService;

    public MainWindow(ISettingsService settingsService, IDataService dataService, IDialogService dialogService)
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        ApplyWindowIcon();
        _dialogService = dialogService;
        ViewModel = new MainWindowViewModel(dataService, settingsService, dialogService);
        RootGrid.DataContext = ViewModel;
        TagsListViewControl.DataContext = ViewModel.TagsListViewModel;
        NotesListControl.DataContext = ViewModel.NotesListViewModel;
        NoteEditorControl.DataContext = ViewModel.NoteEditorViewModel;
        ViewModel.TagsListViewModel.TagFilterRequested += OnTagFilterRequested;
        ViewModel.SettingsViewModel.SettingsSaved += OnSettingsSaved;
        LocalizationManager.LanguageChanged += OnLanguageChanged;
        UpdateStorageButtonText();
    }

    private void UpdateStorageButtonText()
        => StorageButton.Content = AppPaths.GetStorageButtonText();

    private async void StorageButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var picker = new FolderPicker
            {
                SuggestedStartLocation = PickerLocationId.DocumentsLibrary
            };
            picker.FileTypeFilter.Add("*");

            // Unpackaged WinUI не связывает picker с окном автоматически.
            // Без HWND диалог может открыться за приложением или не открыться.
            var windowHandle = WinRT.Interop.WindowNative.GetWindowHandle(this);
            WinRT.Interop.InitializeWithWindow.Initialize(picker, windowHandle);

            var selectedFolder = await picker.PickSingleFolderAsync();
            if (selectedFolder == null || string.IsNullOrWhiteSpace(selectedFolder.Path))
            {
                return;
            }

            var targetFolder = Path.GetFullPath(selectedFolder.Path);
            var currentFolder = Path.GetFullPath(AppPaths.GetDataFolder());
            if (string.Equals(targetFolder, currentFolder, StringComparison.OrdinalIgnoreCase))
            {
                AppPaths.SetConfiguredStorageFolder(targetFolder);
                UpdateStorageButtonText();
                return;
            }

            Directory.CreateDirectory(targetFolder);

            // Перед отключением текущей базы сохраняем открытую заметку.
            // Саму базу в новую папку не копируем: каждая выбранная папка
            // является самостоятельным хранилищем и сохраняет только свои
            // заметки. Если notes.db отсутствует, она будет создана при
            // следующем запуске; если существует, приложение откроет ее.
            if (!await ViewModel.NoteEditorViewModel.SavePendingChangesAsync())
            {
                return;
            }

            AppPaths.SetConfiguredStorageFolder(targetFolder);
            UpdateStorageButtonText();

            // DbContext и JsonSettingsService получают пути при запуске.
            // Перезапуск гарантирует, что после выбора все новые операции
            // сразу идут только в выбранную папку.
            var executablePath = Environment.ProcessPath;
            if (!string.IsNullOrWhiteSpace(executablePath))
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = executablePath,
                    UseShellExecute = true,
                    WorkingDirectory = AppContext.BaseDirectory
                });
            }

            Environment.Exit(0);
        }
        catch (Exception ex)
        {
            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("Error"),
                LocalizationManager.Format("StorageChangeError", ex.Message));
        }
    }

    private void ApplyWindowIcon()
    {
        try
        {
            // ApplicationIcon задает значок EXE, а AppWindow.SetIcon отдельно
            // гарантирует тот же фиолетово-белый блокнот в панели задач и
            // системных представлениях окна WinUI.
            var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "NotebookPurple.ico");
            if (File.Exists(iconPath))
            {
                AppWindow.SetIcon(iconPath);
            }
        }
        catch
        {
            // Ошибка декоративного ресурса не должна мешать запуску заметок.
            // EXE при этом все равно сохраняет ApplicationIcon из проекта.
        }
    }

    public void ApplySettings(AppSettings settings, bool suppressNotesReload = false)
    {
        LocalizationManager.SetLanguage(settings.Language);

        if (Content is FrameworkElement root)
        {
            // Корневое свойство позволяет применить тему ко всему дереву
            // управления без ручной настройки каждого дочернего контрола.
            root.RequestedTheme = settings.Theme switch
            {
                "Light" => ElementTheme.Light,
                "Dark" => ElementTheme.Dark,
                _ => ElementTheme.Default
            };

        }

        ApplyTypography(settings.FontSize);
        ApplyFontFamily(settings.FontFamily);
        ViewModel.NotesListViewModel.SetCurrentSorting(settings.DefaultSorting, suppressNotesReload);
        ViewModel.NoteEditorViewModel.IsAutoSaveEnabled = settings.AutoSave;
    }

    public System.Threading.Tasks.Task LoadAsync() => LoadDataAsync();

    private async System.Threading.Tasks.Task LoadDataAsync()
    {
        try
        {
            // Стартовые данные подгружаются последовательно, чтобы окно
            // оставалось отзывчивым и проще было локализовать источник ошибки.
            await ViewModel.NotesListViewModel.LoadNotesAsync();
            await ViewModel.TagsListViewModel.LoadTagsAsync();
            await ViewModel.NoteEditorViewModel.LoadAvailableTagsAsync();
        }
        catch (Exception ex)
        {
            // Если что-то неожиданное все же сломалось, показываем ошибку в UI,
            // а не даем фоновому Task завершить процесс молча.
            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("StartupError"),
                LocalizationManager.Format("FailedToInitializeWindow", ex.Message));
        }
    }

    private void OnSettingsSaved(object? sender, AppSettings settings)
    {
        ApplySettings(settings);
        ViewModel.CloseSettingsCommand.Execute(null);
    }

    private void OnLanguageChanged(object? sender, EventArgs e)
    {
        // x:Bind по умолчанию одноразовый, поэтому при смене языка явно
        // обновляем привязки окна и вложенных пользовательских контролов.
        Bindings.Update();
        UpdateStorageButtonText();
        TagsListViewControl.RefreshLocalization();
        NotesListControl.RefreshLocalization();
        NoteEditorControl.RefreshLocalization();
        SettingsViewControl.RefreshLocalization();
        ViewModel.NoteEditorViewModel.RefreshLocalization();
    }

    private static void ApplyTypography(double fontSize)
    {
        // Мы обновляем не один глобальный размер, а небольшую шкалу токенов.
        // Так интерфейс сохраняет пропорции между обычным текстом, заголовками
        // и мелкими подписями, а ползунок действительно масштабирует весь UI.
        var resources = Application.Current.Resources;
        var normalizedScale = Math.Clamp(fontSize / DefaultSettingsFontSize, 0.75, 1.75);
        var bodyFontSize = Math.Round(DefaultBodyFontSize * normalizedScale, 2);

        resources["AppFontSizeBody"] = bodyFontSize;
        resources["AppFontSizeSmall"] = Math.Round(10.0 * Math.Pow(normalizedScale, SmallScaleExponent), 2);
        resources["AppFontSizeInput"] = bodyFontSize;
        resources["AppFontSizeButton"] = bodyFontSize;
        resources["AppFontSizeWindowCaption"] = Math.Round(13.0 * Math.Pow(normalizedScale, CaptionScaleExponent), 2);
        resources["AppFontSizeSubtitle"] = Math.Round(18.0 * Math.Pow(normalizedScale, SubtitleScaleExponent), 2);
        resources["AppFontSizeTitle"] = Math.Round(24.0 * Math.Pow(normalizedScale, TitleScaleExponent), 2);
    }

    private static string NormalizeFontFamily(string? fontFamily)
    {
        var value = fontFamily?.Trim();
        return string.IsNullOrWhiteSpace(value) ? "Segoe UI" : value;
    }

    private static void ApplyFontFamily(string? fontFamily)
    {
        // WinUI не дает поставить FontFamily на произвольный FrameworkElement,
        // поэтому шрифт проходит через общий ресурс, который читают стили
        // TextBlock, TextBox, Button, ComboBox и ToggleSwitch.
        Application.Current.Resources["AppFontFamily"] = new FontFamily(NormalizeFontFamily(fontFamily));
    }

    private void OnTagFilterRequested(object? sender, Tag? tag)
        => ViewModel.NotesListViewModel.ApplyTagFilterCommand.Execute(tag);

    private void Window_Closed(object sender, WindowEventArgs args)
    {
        ViewModel.SettingsViewModel.SettingsSaved -= OnSettingsSaved;
        LocalizationManager.LanguageChanged -= OnLanguageChanged;
        // Закрытие окна может произойти в очень ранней или аварийной фазе,
        // когда часть UI еще не успела полностью инициализироваться.
        // Поэтому освобождаем ресурсы максимально безопасно, без повторного
        // падения поверх уже завершавшегося приложения.
        ViewModel?.NoteEditorViewModel?.Dispose();
    }
}
