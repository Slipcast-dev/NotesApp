using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using NotesApp.Localization;
using NotesApp.Models;
using NotesApp.Views;
using Windows.UI;

namespace NotesApp.Services;

public class DialogService : IDialogService
{
    private Window? _window;

    public void AttachWindow(Window window)
    {
        // Диалоги WinUI требуют XamlRoot, поэтому окно связываем отдельно
        // и не тянем MainWindow через DI, чтобы не создавать цикл зависимостей.
        _window = window;
    }

    private async Task<ContentDialogResult> ShowDialogAsync(ContentDialog dialog)
    {
        if (_window?.Content is FrameworkElement root)
        {
            dialog.XamlRoot = root.XamlRoot;
        }

        return await dialog.ShowAsync();
    }
    public async Task ShowInfoAsync(string title, string message) => await ShowDialogAsync(new ContentDialog { Title = title, Content = message, CloseButtonText = LocalizationManager.Get("Ok") });
    public async Task ShowErrorAsync(string title, string message) => await ShowDialogAsync(new ContentDialog { Title = title, Content = message, CloseButtonText = LocalizationManager.Get("Ok") });
    public async Task<bool> ShowConfirmationAsync(string title, string message)
    {
        var dialog = new ContentDialog
        {
            Title = title,
            Content = message,
            PrimaryButtonText = LocalizationManager.Get("Yes"),
            CloseButtonText = LocalizationManager.Get("No"),
            DefaultButton = ContentDialogButton.Primary
        };
        return await ShowDialogAsync(dialog) == ContentDialogResult.Primary;
    }
    public async Task<string?> ShowInputDialogAsync(string title, string hint = "")
    {
        var textBox = new TextBox { PlaceholderText = hint };
        var dialog = new ContentDialog
        {
            Title = title,
            Content = textBox,
            PrimaryButtonText = LocalizationManager.Get("Ok"),
            CloseButtonText = LocalizationManager.Get("Cancel"),
            DefaultButton = ContentDialogButton.Primary
        };
        return await ShowDialogAsync(dialog) == ContentDialogResult.Primary ? textBox.Text?.Trim() : null;
    }

    public async Task<TagEditorResult?> ShowTagEditorDialogAsync(
        string title,
        string initialName = "",
        string? initialColorHex = null)
    {
        var textBox = new TextBox
        {
            Header = LocalizationManager.Get("TagName"),
            PlaceholderText = LocalizationManager.Get("EnterTagName"),
            Text = initialName
        };
        var colorPicker = CreateTagColorPicker(initialColorHex);

        var dialog = new ContentDialog
        {
            Title = title,
            Content = CreateTagEditorContent(textBox, colorPicker),
            PrimaryButtonText = LocalizationManager.Get("Ok"),
            CloseButtonText = LocalizationManager.Get("Cancel"),
            DefaultButton = ContentDialogButton.Primary
        };

        if (await ShowDialogAsync(dialog) != ContentDialogResult.Primary)
        {
            return null;
        }

        var name = textBox.Text?.Trim();
        return string.IsNullOrWhiteSpace(name)
            ? null
            : new TagEditorResult(name, ToHex(colorPicker.Color));
    }

    public async Task<TagSelectionResult?> ShowTagSelectionDialogAsync(IReadOnlyList<Tag> availableTags)
    {
        // Один диалог поддерживает оба ожидаемых сценария: повторное
        // использование существующего тега и создание нового. Список не
        // содержит уже прикрепленные теги, поэтому дубли исключаются заранее.
        var existingTagComboBox = new ComboBox
        {
            Header = LocalizationManager.Get("ExistingTag"),
            PlaceholderText = availableTags.Count == 0
                ? LocalizationManager.Get("NoAvailableTags")
                : LocalizationManager.Get("SelectTag"),
            DisplayMemberPath = nameof(Tag.Name),
            ItemsSource = availableTags,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            IsEnabled = availableTags.Count > 0
        };

        var newTagTextBox = new TextBox
        {
            Header = LocalizationManager.Get("OrCreateNewTag"),
            PlaceholderText = LocalizationManager.Get("EnterTagName")
        };
        var newTagColorPicker = CreateTagColorPicker(Tag.DefaultColorHex);

        var content = new StackPanel
        {
            Spacing = 12,
            MinWidth = 320
        };
        content.Children.Add(existingTagComboBox);
        content.Children.Add(newTagTextBox);
        content.Children.Add(CreateTagColorSection(newTagColorPicker));

        var dialog = new ContentDialog
        {
            Title = LocalizationManager.Get("AddTag"),
            Content = content,
            PrimaryButtonText = LocalizationManager.Get("Add"),
            CloseButtonText = LocalizationManager.Get("Cancel"),
            DefaultButton = ContentDialogButton.Primary
        };

        if (await ShowDialogAsync(dialog) != ContentDialogResult.Primary)
        {
            return null;
        }

        var newTagName = newTagTextBox.Text?.Trim();
        if (!string.IsNullOrWhiteSpace(newTagName))
        {
            return new TagSelectionResult(null, newTagName, ToHex(newTagColorPicker.Color));
        }

        return existingTagComboBox.SelectedItem is Tag selectedTag
            ? new TagSelectionResult(selectedTag, null, null)
            : null;
    }

    public async Task<string?> ShowTagColorDialogAsync(Tag tag)
    {
        var colorPicker = CreateTagColorPicker(tag.ColorHex);
        var dialog = new ContentDialog
        {
            Title = LocalizationManager.Format("ChangeTagColorTitle", tag.Name),
            Content = CreateTagColorSection(colorPicker),
            PrimaryButtonText = LocalizationManager.Get("Save"),
            CloseButtonText = LocalizationManager.Get("Cancel"),
            DefaultButton = ContentDialogButton.Primary
        };

        return await ShowDialogAsync(dialog) == ContentDialogResult.Primary
            ? ToHex(colorPicker.Color)
            : null;
    }

    private static StackPanel CreateTagEditorContent(TextBox textBox, ColorPicker colorPicker)
    {
        var content = new StackPanel
        {
            Spacing = 12,
            MinWidth = 320
        };
        content.Children.Add(textBox);
        content.Children.Add(CreateTagColorSection(colorPicker));
        return content;
    }

    private static StackPanel CreateTagColorSection(ColorPicker colorPicker)
    {
        var section = new StackPanel { Spacing = 8, MinWidth = 320 };
        section.Children.Add(new TextBlock
        {
            Text = LocalizationManager.Get("TagColor"),
            Style = Application.Current.Resources["BodyTextBlockStyle"] as Style
        });
        section.Children.Add(colorPicker);
        return section;
    }

    private static ColorPicker CreateTagColorPicker(string? colorHex)
        => new()
        {
            Color = ParseColor(colorHex),
            IsAlphaEnabled = false,
            HorizontalAlignment = HorizontalAlignment.Stretch
        };

    private static Color ParseColor(string? colorHex)
    {
        var value = colorHex?.Trim();
        if (string.IsNullOrWhiteSpace(value))
        {
            value = Tag.DefaultColorHex;
        }

        if (!value.StartsWith('#'))
        {
            value = $"#{value}";
        }

        if (value.Length != 7 || !value.Skip(1).All(Uri.IsHexDigit))
        {
            value = Tag.DefaultColorHex;
        }

        return Color.FromArgb(
            255,
            Convert.ToByte(value.Substring(1, 2), 16),
            Convert.ToByte(value.Substring(3, 2), 16),
            Convert.ToByte(value.Substring(5, 2), 16));
    }

    private static string ToHex(Color color)
        => $"#{color.R:X2}{color.G:X2}{color.B:X2}";
}
