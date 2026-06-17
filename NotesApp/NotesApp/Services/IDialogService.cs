using Microsoft.UI.Xaml;
using NotesApp.Models;

namespace NotesApp.Services;

public interface IDialogService
{
    void AttachWindow(Window window);
    Task ShowInfoAsync(string title, string message);
    Task ShowErrorAsync(string title, string message);
    Task<bool> ShowConfirmationAsync(string title, string message);
    Task<string?> ShowInputDialogAsync(string title, string hint = "");
    Task<TagSelectionResult?> ShowTagSelectionDialogAsync(IReadOnlyList<Tag> availableTags);
    Task<TagEditorResult?> ShowTagEditorDialogAsync(string title, string initialName = "", string? initialColorHex = null);
    Task<string?> ShowTagColorDialogAsync(Tag tag);
}
