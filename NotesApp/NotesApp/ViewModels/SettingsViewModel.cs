using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NotesApp.Localization;
using NotesApp.Models;
using NotesApp.Services;

namespace NotesApp.ViewModels;

public partial class SettingsViewModel : ObservableRecipient
{
    private readonly ISettingsService _settingsService;
    private readonly IDialogService _dialogService;

    public SettingsViewModel(ISettingsService settingsService, IDialogService dialogService)
    {
        _settingsService = settingsService;
        _dialogService = dialogService;
        Settings = new AppSettings();
    }

    [ObservableProperty]
    private AppSettings _settings = new();

    public event EventHandler<AppSettings>? SettingsSaved;

    public async Task<AppSettings> LoadSettingsAsync()
    {
        try
        {
            Settings = await _settingsService.LoadSettingsAsync();
            return Settings;
        }
        catch (Exception ex)
        {
            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("Error"),
                LocalizationManager.Format("FailedToLoadSettings", ex.Message));
            return Settings;
        }
    }

    [RelayCommand]
    private async Task SaveSettingsAsync()
    {
        try
        {
            Settings.Language = LocalizationManager.NormalizeLanguage(Settings.Language);
            LocalizationManager.SetLanguage(Settings.Language);
            await _settingsService.SaveSettingsAsync(Settings);
            await _dialogService.ShowInfoAsync(
                LocalizationManager.Get("Settings"),
                LocalizationManager.Get("SettingsSaved"));
            SettingsSaved?.Invoke(this, Settings);
        }
        catch (Exception ex)
        {
            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("Error"),
                LocalizationManager.Format("FailedToSave", ex.Message));
        }
    }

    [RelayCommand]
    private async Task ResetToDefaultAsync()
    {
        if (!await _dialogService.ShowConfirmationAsync(
                LocalizationManager.Get("ResetSettings"),
                LocalizationManager.Get("ResetSettingsQuestion")))
        {
            return;
        }

        Settings = new AppSettings();
        await SaveSettingsAsync();
    }
}
