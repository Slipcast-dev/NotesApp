using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NotesApp.Localization;
using NotesApp.Models;
using NotesApp.Services;

namespace NotesApp.ViewModels;

public partial class TagsListViewModel : ObservableRecipient
{
    private readonly IDataService _dataService;
    private readonly IDialogService _dialogService;

    public TagsListViewModel(IDataService dataService, IDialogService dialogService)
    {
        _dataService = dataService;
        _dialogService = dialogService;
        Tags = new ObservableCollection<Tag>();
    }

    public ObservableCollection<Tag> Tags { get; }
    [ObservableProperty]
    private Tag? _selectedTag;

    public event EventHandler<Tag?>? TagFilterRequested;

    public async Task LoadTagsAsync()
    {
        try
        {
            var tags = await _dataService.GetAllTagsAsync();
            Tags.Clear();
            foreach (var tag in tags)
            {
                Tags.Add(tag);
            }
        }
        catch (Exception ex)
        {
            // Загрузка тегов не должна валить все окно: если база еще не готова
            // или повреждена, показываем ошибку и оставляем интерфейс живым.
            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("Error"),
                LocalizationManager.Format("FailedToLoadTags", ex.Message));
        }
    }

    [RelayCommand]
    private async Task CreateTag()
    {
        var tag = await _dialogService.ShowTagEditorDialogAsync(LocalizationManager.Get("NewTagTitle"));
        if (tag == null)
        {
            return;
        }

        await _dataService.CreateTagAsync(tag.Name, tag.ColorHex);
        await LoadTagsAsync();
    }

    [RelayCommand]
    private async Task ChangeTagColor(Tag? tag)
    {
        if (tag == null)
        {
            return;
        }

        var colorHex = await _dialogService.ShowTagColorDialogAsync(tag);
        if (string.IsNullOrWhiteSpace(colorHex))
        {
            return;
        }

        await _dataService.UpdateTagColorAsync(tag.Id, colorHex);
        await LoadTagsAsync();
    }

    [RelayCommand]
    private async Task DeleteTag(Tag? tag)
    {
        if (tag == null)
        {
            return;
        }

        if (!await _dialogService.ShowConfirmationAsync(
                LocalizationManager.Get("DeleteTag"),
                LocalizationManager.Format("DeleteTagQuestion", tag.Name)))
        {
            return;
        }

        await _dataService.DeleteTagAsync(tag.Id);
        await LoadTagsAsync();
        if (SelectedTag?.Id == tag.Id)
        {
            SelectedTag = null;
        }
    }

    [RelayCommand]
    private void FilterByTag(Tag? tag) => TagFilterRequested?.Invoke(this, tag);
}
