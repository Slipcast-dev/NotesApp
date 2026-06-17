using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.UI.Dispatching;
using NotesApp.Localization;
using NotesApp.Models;
using NotesApp.Services;

namespace NotesApp.ViewModels;

public partial class NotesListViewModel : ObservableRecipient
{
    private readonly IDataService _dataService;
    private readonly IDialogService _dialogService;
    private readonly DispatcherQueueTimer _searchDebounceTimer;
    private bool _suppressAutoReload;

    public NotesListViewModel(IDataService dataService, IDialogService dialogService)
    {
        _dataService = dataService;
        _dialogService = dialogService;
        _searchDebounceTimer = DispatcherQueue.GetForCurrentThread()?
            .CreateTimer() ?? throw new InvalidOperationException("NotesListViewModel must be created on the UI thread.");

        _searchDebounceTimer.Interval = TimeSpan.FromMilliseconds(500);
        _searchDebounceTimer.Tick += OnSearchDebounceTick;

        Notes = new ObservableCollection<Note>();
        SelectedFilterTags = new ObservableCollection<Tag>();
    }

    public ObservableCollection<Note> Notes { get; }

    public ObservableCollection<Tag> SelectedFilterTags { get; }

    [ObservableProperty]
    private Note? _selectedNote;

    [ObservableProperty]
    private bool _showDeleted;

    [ObservableProperty]
    private string _searchText = string.Empty;

    [ObservableProperty]
    private string _currentSorting = "updateddesc";

    [ObservableProperty]
    private int _notesCount;

    [ObservableProperty]
    private bool _isSearching;

    partial void OnSearchTextChanged(string value)
    {
        _searchDebounceTimer.Stop();
        IsSearching = true;
        _searchDebounceTimer.Start();
    }

    partial void OnShowDeletedChanged(bool value)
    {
        if (!_suppressAutoReload)
        {
            _ = LoadNotesAsync();
        }
    }

    partial void OnCurrentSortingChanged(string value)
    {
        if (!_suppressAutoReload)
        {
            _ = LoadNotesAsync();
        }
    }

    public void SetCurrentSorting(string sorting, bool suppressReload = false)
    {
        if (!suppressReload)
        {
            CurrentSorting = sorting;
            return;
        }

        _suppressAutoReload = true;
        try
        {
            CurrentSorting = sorting;
        }
        finally
        {
            _suppressAutoReload = false;
        }
    }

    private async void OnSearchDebounceTick(DispatcherQueueTimer sender, object args)
    {
        sender.Stop();
        await LoadNotesAsync();
    }

    public async Task LoadNotesAsync()
    {
        try
        {
            // Сохраняем идентификатор, а не ссылку на объект: запрос EF Core
            // возвращает новые экземпляры Note, поэтому старая ссылка больше
            // не принадлежит обновленной ObservableCollection.
            var selectedNoteId = SelectedNote?.Id;
            Tag? filterTag = SelectedFilterTags.Count == 1 ? SelectedFilterTags[0] : null;
            string? searchText = string.IsNullOrWhiteSpace(SearchText) ? null : SearchText;

            var notes = await _dataService.GetAllNotesAsync(ShowDeleted, searchText, CurrentSorting, filterTag);
            var noteList = notes as IList<Note> ?? notes.ToList();

            Notes.Clear();
            foreach (var note in noteList)
            {
                Notes.Add(note);
            }

            NotesCount = noteList.Count;
            SelectedNote = selectedNoteId.HasValue
                ? Notes.FirstOrDefault(note => note.Id == selectedNoteId.Value)
                : null;
        }
        catch (Exception ex)
        {
            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("Error"),
                LocalizationManager.Format("FailedToLoadNotes", ex.Message));
        }
        finally
        {
            IsSearching = false;
        }
    }

    public async Task SelectNoteByIdAsync(int noteId)
    {
        var existingNote = Notes.FirstOrDefault(note => note.Id == noteId);
        if (existingNote != null)
        {
            SelectedNote = existingNote;
            return;
        }

        // Внутренняя ссылка должна открываться даже тогда, когда текущий
        // поиск или фильтр по тегу скрывает целевую заметку. Сбрасываем эти
        // ограничения явно и останавливаем debounce-таймер, чтобы отложенный
        // поиск не перезагрузил список еще раз поверх выбранной заметки.
        SearchText = string.Empty;
        SelectedFilterTags.Clear();
        ShowDeleted = false;
        _searchDebounceTimer.Stop();
        IsSearching = false;

        await LoadNotesAsync();
        SelectedNote = Notes.FirstOrDefault(note => note.Id == noteId);
    }

    [RelayCommand]
    private async Task CreateNewNote()
    {
        try
        {
            var newNote = await _dataService.CreateNoteAsync(LocalizationManager.Get("NewNote"), string.Empty);
            SelectedNote = null;
            await LoadNotesAsync();

            // После перезагрузки выбираем объект именно из коллекции ListView.
            // Присваивание экземпляра, возвращенного CreateNoteAsync, не
            // выбирало строку, потому что его нет среди ItemsSource.
            SelectedNote = Notes.FirstOrDefault(note => note.Id == newNote.Id);
        }
        catch (Exception ex)
        {
            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("Error"),
                LocalizationManager.Format("FailedToCreateNote", ex.Message));
        }
    }

    [RelayCommand]
    private async Task DeleteNote(Note? note)
    {
        if (note == null)
        {
            return;
        }

        try
        {
            if (!ShowDeleted)
            {
                await _dataService.DeleteNoteAsync(note.Id);
            }
            else if (await _dialogService.ShowConfirmationAsync(
                         LocalizationManager.Get("DeletePermanently"),
                         LocalizationManager.Format("DeleteNoteQuestion", note.Title)))
            {
                await _dataService.HardDeleteNoteAsync(note.Id);
            }
            else
            {
                return;
            }

            await LoadNotesAsync();

            if (SelectedNote?.Id == note.Id)
            {
                SelectedNote = null;
            }
        }
        catch (Exception ex)
        {
            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("Error"),
                LocalizationManager.Format("FailedToDelete", ex.Message));
        }
    }

    [RelayCommand]
    private async Task RestoreNote(Note? note)
    {
        if (note == null || !note.IsDeleted)
        {
            return;
        }

        try
        {
            await _dataService.RestoreNoteAsync(note.Id);
            await LoadNotesAsync();
        }
        catch (Exception ex)
        {
            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("Error"),
                LocalizationManager.Format("FailedToRestore", ex.Message));
        }
    }

    [RelayCommand]
    private void ApplyTagFilter(Tag? tag)
    {
        SelectedFilterTags.Clear();

        if (tag != null)
        {
            SelectedFilterTags.Add(tag);
        }

        _ = LoadNotesAsync();
    }

    [RelayCommand]
    private void ClearTagFilter()
    {
        SelectedFilterTags.Clear();
        _ = LoadNotesAsync();
    }

    [RelayCommand]
    private void ClearSearch()
    {
        SearchText = string.Empty;
        ClearTagFilter();
    }
}
