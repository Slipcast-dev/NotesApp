using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.UI.Dispatching;
using NotesApp.Localization;
using NotesApp.Models;
using NotesApp.Services;

namespace NotesApp.ViewModels;

public partial class NoteEditorViewModel : ObservableRecipient, IDisposable
{
    private readonly IDataService _dataService;
    private readonly IDialogService _dialogService;
    private readonly DispatcherQueueTimer _autoSaveTimer;
    private Note? _currentNote;
    private int _noteLoadVersion;
    private bool _suppressChangeTracking;
    private bool _disposed;

    public NoteEditorViewModel(IDataService dataService, IDialogService dialogService)
    {
        _dataService = dataService;
        _dialogService = dialogService;
        var dispatcherQueue = DispatcherQueue.GetForCurrentThread() ??
            throw new InvalidOperationException("NoteEditorViewModel must be created on the UI thread.");

        AvailableTags = new ObservableCollection<Tag>();
        NoteTags = new ObservableCollection<Tag>();

        _autoSaveTimer = dispatcherQueue.CreateTimer();
        _autoSaveTimer.Interval = TimeSpan.FromSeconds(3);
        _autoSaveTimer.Tick += OnAutoSaveTick;
    }

    public ObservableCollection<Tag> AvailableTags { get; }

    public ObservableCollection<Tag> NoteTags { get; }

    [ObservableProperty]
    private string _title = string.Empty;

    [ObservableProperty]
    private string _content = string.Empty;

    [ObservableProperty]
    private bool _isAutoSaveEnabled = true;

    [ObservableProperty]
    private bool _isModified;

    [ObservableProperty]
    private bool _hasCurrentNote;

    public event EventHandler<int>? NoteSaved;

    public event EventHandler<int>? NoteDeleted;

    public event EventHandler<int>? InternalNoteLinkRequested;

    public event EventHandler? TagsChanged;

    public string ModificationStatus => IsModified
        ? LocalizationManager.Get("UnsavedChanges")
        : LocalizationManager.Get("AllChangesSaved");

    partial void OnIsModifiedChanged(bool value) => OnPropertyChanged(nameof(ModificationStatus));

    public void RefreshLocalization() => OnPropertyChanged(nameof(ModificationStatus));

    public async Task SetNoteAsync(Note? note)
    {
        var loadVersion = ++_noteLoadVersion;
        StopAutoSaveTimer();

        if (note == null)
        {
            ResetEditorState();
            return;
        }

        try
        {
            // Сначала загружаем все данные во временные переменные. Если
            // пользователь за это время выбрал другую строку, устаревший
            // результат не должен перезаписать более новый выбор.
            var loadedNote = await _dataService.GetNoteByIdAsync(note.Id);
            var loadedTags = loadedNote == null
                ? Array.Empty<Tag>()
                : (await _dataService.GetTagsForNoteAsync(loadedNote.Id)).ToArray();

            if (loadVersion != _noteLoadVersion)
            {
                return;
            }

            if (loadedNote == null)
            {
                ResetEditorState();
                return;
            }

            _currentNote = loadedNote;
            _suppressChangeTracking = true;
            try
            {
                HasCurrentNote = true;
                Title = loadedNote.Title;
                Content = loadedNote.Content;
                IsModified = false;
            }
            finally
            {
                _suppressChangeTracking = false;
            }

            NoteTags.Clear();
            foreach (var tag in loadedTags)
            {
                NoteTags.Add(tag);
            }

            if (IsAutoSaveEnabled)
            {
                StartAutoSaveTimer();
            }
        }
        catch (Exception ex)
        {
            if (loadVersion == _noteLoadVersion)
            {
                ResetEditorState();
            }

            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("Error"),
                LocalizationManager.Format("FailedToLoadNotes", ex.Message));
        }
    }

    partial void OnTitleChanged(string value) => OnContentModified();

    partial void OnContentChanged(string value) => OnContentModified();

    partial void OnIsAutoSaveEnabledChanged(bool value)
    {
        if (!value)
        {
            StopAutoSaveTimer();
            return;
        }

        if (_currentNote != null && IsModified)
        {
            StartAutoSaveTimer();
        }
    }

    private void OnContentModified()
    {
        if (_currentNote == null || _disposed || _suppressChangeTracking)
        {
            return;
        }

        IsModified = true;

        if (IsAutoSaveEnabled)
        {
            StartAutoSaveTimer();
        }
    }

    private async void OnAutoSaveTick(DispatcherQueueTimer sender, object args)
    {
        sender.Stop();
        await SaveNoteAsync();
    }

    private void StartAutoSaveTimer()
    {
        _autoSaveTimer.Stop();
        _autoSaveTimer.Start();
    }

    private void StopAutoSaveTimer()
    {
        _autoSaveTimer.Stop();
    }

    private void ResetEditorState()
    {
        _currentNote = null;
        HasCurrentNote = false;
        Title = string.Empty;
        Content = string.Empty;
        IsModified = false;
        NoteTags.Clear();
    }

    [RelayCommand]
    private async Task SaveNoteAsync()
        => await SavePendingChangesAsync();

    public async Task<bool> SavePendingChangesAsync()
    {
        if (_currentNote == null || !IsModified)
        {
            return true;
        }

        try
        {
            _currentNote.Title = Title;
            _currentNote.Content = Content;
            if (await _dataService.UpdateNoteAsync(_currentNote))
            {
                IsModified = false;
                NoteSaved?.Invoke(this, _currentNote.Id);
            }

            // Если запись не была обновлена, не разрешаем вызывающему коду
            // закрывать текущую базу: несохраненный текст должен остаться
            // открытым, пока пользователь не решит проблему сохранения.
            return !IsModified;
        }
        catch (Exception ex)
        {
            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("SaveError"),
                LocalizationManager.Format("FailedToSaveNote", ex.Message));
            return false;
        }
    }

    [RelayCommand]
    private async Task DeleteCurrentNote()
    {
        if (_currentNote == null)
        {
            return;
        }

        var noteId = _currentNote.Id;
        var noteTitle = string.IsNullOrWhiteSpace(Title)
            ? LocalizationManager.Get("NewNote")
            : Title.Trim();
        var dialogTitle = _currentNote.IsDeleted
            ? LocalizationManager.Get("DeletePermanently")
            : LocalizationManager.Get("Delete");

        if (!await _dialogService.ShowConfirmationAsync(
                dialogTitle,
                LocalizationManager.Format("DeleteNoteQuestion", noteTitle)))
        {
            return;
        }

        try
        {
            var deleted = _currentNote.IsDeleted
                ? await _dataService.HardDeleteNoteAsync(noteId)
                : await _dataService.DeleteNoteAsync(noteId);

            if (!deleted)
            {
                return;
            }

            StopAutoSaveTimer();
            ResetEditorState();
            NoteDeleted?.Invoke(this, noteId);
        }
        catch (Exception ex)
        {
            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("Error"),
                LocalizationManager.Format("FailedToDelete", ex.Message));
        }
    }

    [RelayCommand]
    private async Task AddTag()
    {
        if (_currentNote == null)
        {
            return;
        }

        try
        {
            // Перечитываем список перед каждым открытием диалога: тег мог
            // быть создан в правой панели после первоначальной загрузки окна.
            await LoadAvailableTagsAsync();
            var attachedTagIds = NoteTags.Select(tag => tag.Id).ToHashSet();
            var selectableTags = AvailableTags
                .Where(tag => !attachedTagIds.Contains(tag.Id))
                .OrderBy(tag => tag.Name)
                .ToList();

            var selection = await _dialogService.ShowTagSelectionDialogAsync(selectableTags);
            if (selection == null)
            {
                return;
            }

            var tag = selection.ExistingTag;
            if (tag == null && !string.IsNullOrWhiteSpace(selection.NewTagName))
            {
                tag = await _dataService.CreateTagAsync(selection.NewTagName, selection.NewTagColorHex);
            }

            if (tag == null)
            {
                return;
            }

            if (await _dataService.AddTagToNoteAsync(_currentNote.Id, tag.Id) && !NoteTags.Any(t => t.Id == tag.Id))
            {
                NoteTags.Add(tag);
                if (!AvailableTags.Any(t => t.Id == tag.Id))
                {
                    AvailableTags.Add(tag);
                }

                // Связь NoteTag уже сохранена отдельной транзакцией. Не
                // помечаем текст заметки измененным, иначе автосохранение
                // создает ложный статус несохраненных изменений.
                TagsChanged?.Invoke(this, EventArgs.Empty);
            }
        }
        catch (Exception ex)
        {
            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("Error"),
                LocalizationManager.Format("FailedToAddTag", ex.Message));
        }
    }

    [RelayCommand]
    private async Task RemoveTag(Tag tag)
    {
        if (_currentNote == null || tag == null)
        {
            return;
        }

        try
        {
            if (await _dataService.RemoveTagFromNoteAsync(_currentNote.Id, tag.Id))
            {
                NoteTags.Remove(tag);
                TagsChanged?.Invoke(this, EventArgs.Empty);
            }
        }
        catch (Exception ex)
        {
            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("Error"),
                LocalizationManager.Format("FailedToRemoveTag", ex.Message));
        }
    }

    public async Task LoadAvailableTagsAsync()
    {
        try
        {
            var tags = await _dataService.GetAllTagsAsync();
            AvailableTags.Clear();
            foreach (var tag in tags)
            {
                AvailableTags.Add(tag);
            }
        }
        catch (Exception ex)
        {
            // Этот список вторичный: лучше показать пустую панель редактора,
            // чем позволить фоновой загрузке оборвать весь запуск приложения.
            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("Error"),
                LocalizationManager.Format("FailedToLoadAvailableTags", ex.Message));
        }
    }

    public async Task<IReadOnlyList<Note>> GetLinkableNotesAsync()
    {
        try
        {
            var currentNoteId = _currentNote?.Id;
            var notes = await _dataService.GetAllNotesAsync();

            // Текущую заметку исключаем из списка вставки, чтобы обычный
            // сценарий вел на другую заметку. Уже существующие self-ссылки
            // при этом не ломаем: открыть их можно через выделенный текст.
            return notes
                .Where(note => note.Id != currentNoteId)
                .OrderBy(note => note.Title)
                .ToList();
        }
        catch (Exception ex)
        {
            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("Error"),
                LocalizationManager.Format("FailedToLoadNotes", ex.Message));
            return Array.Empty<Note>();
        }
    }

    public async Task RequestOpenInternalLinkAsync(string rawLinkText)
    {
        var normalizedTitle = NormalizeInternalLinkTitle(rawLinkText);
        if (string.IsNullOrWhiteSpace(normalizedTitle))
        {
            return;
        }

        try
        {
            var notes = await _dataService.GetAllNotesAsync();
            var matchedNote = notes.FirstOrDefault(note =>
                string.Equals(note.Title.Trim(), normalizedTitle, StringComparison.CurrentCultureIgnoreCase));

            if (matchedNote == null)
            {
                await _dialogService.ShowErrorAsync(
                    LocalizationManager.Get("InternalLink"),
                    LocalizationManager.Format("InternalLinkNotFound", normalizedTitle));
                return;
            }

            // Редактор не выбирает строку списка напрямую: он публикует
            // намерение, а MainWindowViewModel координирует панели как и при
            // обычном клике пользователя по списку заметок.
            InternalNoteLinkRequested?.Invoke(this, matchedNote.Id);
        }
        catch (Exception ex)
        {
            await _dialogService.ShowErrorAsync(
                LocalizationManager.Get("Error"),
                LocalizationManager.Format("FailedToLoadNotes", ex.Message));
        }
    }

    private static string NormalizeInternalLinkTitle(string rawLinkText)
    {
        var value = rawLinkText.Trim();
        if (value.StartsWith("[[", StringComparison.Ordinal) &&
            value.EndsWith("]]", StringComparison.Ordinal) &&
            value.Length > 4)
        {
            value = value[2..^2].Trim();
        }

        return value;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        StopAutoSaveTimer();
        _disposed = true;
    }
}
