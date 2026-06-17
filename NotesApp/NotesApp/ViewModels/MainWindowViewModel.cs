using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NotesApp.Services;

namespace NotesApp.ViewModels;

public partial class MainWindowViewModel : ObservableRecipient
{
    public MainWindowViewModel(IDataService dataService, ISettingsService settingsService, IDialogService dialogService)
    {
        NotesListViewModel = new NotesListViewModel(dataService, dialogService);
        NoteEditorViewModel = new NoteEditorViewModel(dataService, dialogService);
        TagsListViewModel = new TagsListViewModel(dataService, dialogService);
        SettingsViewModel = new SettingsViewModel(settingsService, dialogService);

        // Главная ViewModel координирует дочерние панели. Благодаря этому
        // создание или выбор заметки всегда открывает ее в редакторе, а
        // изменения из редактора сразу отражаются в списках.
        NotesListViewModel.PropertyChanged += OnNotesListPropertyChanged;
        NoteEditorViewModel.NoteSaved += OnNoteSaved;
        NoteEditorViewModel.NoteDeleted += OnNoteDeleted;
        NoteEditorViewModel.InternalNoteLinkRequested += OnInternalNoteLinkRequested;
        NoteEditorViewModel.TagsChanged += OnTagsChanged;
    }
    public NotesListViewModel NotesListViewModel { get; }
    public NoteEditorViewModel NoteEditorViewModel { get; }
    public TagsListViewModel TagsListViewModel { get; }
    public SettingsViewModel SettingsViewModel { get; }
    [ObservableProperty] private bool _isSettingsOpen;
    [RelayCommand]
    private async Task OpenSettingsAsync()
    {
        await SettingsViewModel.LoadSettingsAsync();
        IsSettingsOpen = true;
    }

    [RelayCommand] private void CloseSettings() => IsSettingsOpen = false;

    private async void OnNotesListPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(NotesListViewModel.SelectedNote))
        {
            await NoteEditorViewModel.SetNoteAsync(NotesListViewModel.SelectedNote);
        }
    }

    private async void OnNoteSaved(object? sender, int noteId)
    {
        await NotesListViewModel.LoadNotesAsync();
    }

    private async void OnNoteDeleted(object? sender, int noteId)
    {
        NotesListViewModel.SelectedNote = null;
        await NotesListViewModel.LoadNotesAsync();
    }

    private async void OnInternalNoteLinkRequested(object? sender, int noteId)
    {
        await NotesListViewModel.SelectNoteByIdAsync(noteId);
    }

    private async void OnTagsChanged(object? sender, EventArgs e)
    {
        await TagsListViewModel.LoadTagsAsync();
        await NotesListViewModel.LoadNotesAsync();
    }
}
