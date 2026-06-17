using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using NotesApp.Localization;
using NotesApp.Models;
using NotesApp.ViewModels;
using System.ComponentModel;
using System.Globalization;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;

namespace NotesApp.Views;

public sealed partial class NoteEditorView : UserControl
{
    private const double ScrollBarNormalTrackOpacity = 0.26;
    private const double ScrollBarNormalThumbOpacity = 0.58;
    private const double ScrollBarTypingTrackOpacity = 0.08;
    private const double ScrollBarTypingThumbOpacity = 0.24;
    private const double ScrollBarHoverTrackOpacity = 0.74;
    private const double ScrollBarHoverThumbOpacity = 0.96;
    private const double ScrollBarEdgePadding = 2.0;
    private const float HeadingFontSize = 24.0f;

    private ScrollViewer? _contentScrollViewer;
    private NoteEditorViewModel? _boundViewModel;
    private bool _isSynchronizingScrollBar;
    private bool _isContentScrollBarHovered;
    private bool _isContentScrollBarDragging;
    private bool _isContentTextInputActive;
    private bool _isLoadingDocument;
    private bool _isUpdatingViewModel;
    private double _contentScrollDragOffset;
    private readonly DispatcherTimer _contentTypingOpacityTimer = new() { Interval = TimeSpan.FromMilliseconds(900) };

    public NoteEditorViewModel ViewModel => (NoteEditorViewModel)DataContext;
    public LocalizedStrings Strings => LocalizationManager.Strings;

    public NoteEditorView()
    {
        InitializeComponent();
        DataContextChanged += NoteEditorView_DataContextChanged;
        _contentTypingOpacityTimer.Tick += ContentTypingOpacityTimer_Tick;
    }

    public void RefreshLocalization() => Bindings.Update();

    private void NoteEditorView_DataContextChanged(FrameworkElement sender, DataContextChangedEventArgs args)
    {
        if (_boundViewModel != null)
        {
            _boundViewModel.PropertyChanged -= ViewModel_PropertyChanged;
        }

        _boundViewModel = DataContext as NoteEditorViewModel;
        if (_boundViewModel != null)
        {
            _boundViewModel.PropertyChanged += ViewModel_PropertyChanged;
            LoadDocumentFromViewModel();
        }

        Bindings.Update();
    }

    private void ViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(NoteEditorViewModel.Content) && !_isUpdatingViewModel)
        {
            LoadDocumentFromViewModel();
        }
    }

    private void LoadDocumentFromViewModel()
    {
        var content = _boundViewModel?.Content ?? string.Empty;
        _isLoadingDocument = true;
        try
        {
            if (IsRtf(content))
            {
                ContentBox.Document.SetText(TextSetOptions.FormatRtf, content);
            }
            else if (LooksLikeLegacyMarkup(content))
            {
                // До перехода на RichEditBox команды меню вставляли Markdown
                // и HTML прямо в текст. Показываем такие старые заметки как
                // rich text, чтобы пользователь не видел уже вставленные
                // служебные символы из прежней реализации.
                ContentBox.Document.SetText(TextSetOptions.FormatRtf, CreateRtfFromLegacyMarkup(content));
            }
            else
            {
                // Старые заметки могли быть обычным Markdown/plain text.
                // Загружаем их как простой текст, чтобы пользователь не
                // видел управляющие RTF-команды и не терял существующие записи.
                ContentBox.Document.SetText(TextSetOptions.None, content);
            }
        }
        finally
        {
            _isLoadingDocument = false;
        }
    }

    private void SaveDocumentToViewModel()
    {
        if (_boundViewModel == null || _isLoadingDocument)
        {
            return;
        }

        ContentBox.Document.GetText(TextGetOptions.FormatRtf, out var rtf);
        _isUpdatingViewModel = true;
        try
        {
            _boundViewModel.Content = rtf;
        }
        finally
        {
            _isUpdatingViewModel = false;
        }
    }

    private void ContentFormattingFlyout_Opening(object sender, object e)
    {
        var selectedText = GetSelectedText().Trim();

        // Переход по внутренней ссылке имеет смысл только когда пользователь
        // явно выделил wiki-ссылку или название заметки. Саму проверку
        // существования заметки делаем при клике, потому что она асинхронная.
        OpenInternalLinkItem.IsEnabled = !string.IsNullOrWhiteSpace(selectedText);
    }

    private void ApplyBold_Click(object sender, RoutedEventArgs e)
    {
        var selection = EnsureSelectionHasText(LocalizationManager.Get("SelectedTextPlaceholder"));
        selection.CharacterFormat.Bold = selection.CharacterFormat.Bold == FormatEffect.On
            ? FormatEffect.Off
            : FormatEffect.On;
        SaveDocumentToViewModel();
    }

    private void ApplyItalic_Click(object sender, RoutedEventArgs e)
    {
        var selection = EnsureSelectionHasText(LocalizationManager.Get("SelectedTextPlaceholder"));
        selection.CharacterFormat.Italic = selection.CharacterFormat.Italic == FormatEffect.On
            ? FormatEffect.Off
            : FormatEffect.On;
        SaveDocumentToViewModel();
    }

    private void ApplyUppercase_Click(object sender, RoutedEventArgs e)
        => TransformSelection(text => text.ToUpper(CultureInfo.CurrentCulture));

    private void ApplyLowercase_Click(object sender, RoutedEventArgs e)
        => TransformSelection(text => text.ToLower(CultureInfo.CurrentCulture));

    private void ApplyHeading_Click(object sender, RoutedEventArgs e)
    {
        var selection = EnsureSelectionHasText(LocalizationManager.Get("HeadingPlaceholder"));

        // Заголовок теперь является реальным форматированием RichEditBox:
        // пользователь видит крупный жирный текст, а не символ "#".
        selection.CharacterFormat.Size = HeadingFontSize;
        selection.CharacterFormat.Bold = FormatEffect.On;
        SaveDocumentToViewModel();
    }

    private void ApplyFontFamily_Click(object sender, RoutedEventArgs e)
    {
        if (sender is MenuFlyoutItem { Tag: string fontFamily })
        {
            var selection = EnsureSelectionHasText(LocalizationManager.Get("SelectedTextPlaceholder"));
            selection.CharacterFormat.Name = fontFamily;
            SaveDocumentToViewModel();
        }
    }

    private void ApplyFontSize_Click(object sender, RoutedEventArgs e)
    {
        if (sender is MenuFlyoutItem { Tag: string rawSize } &&
            float.TryParse(rawSize, NumberStyles.Number, CultureInfo.InvariantCulture, out var size))
        {
            var selection = EnsureSelectionHasText(LocalizationManager.Get("SelectedTextPlaceholder"));
            selection.CharacterFormat.Size = size;
            SaveDocumentToViewModel();
        }
    }

    private void InsertTable_Click(object sender, RoutedEventArgs e)
    {
        // RichEditBox принимает RTF-фрагменты через Selection.SetText.
        // Таблица вставляется настоящими RTF-ячейками с рамками, поэтому
        // выглядит как таблица в Word, а не как Markdown с вертикальными "|".
        ContentBox.Document.Selection.SetText(TextSetOptions.FormatRtf, CreateDefaultRtfTable());
    }

    private void InsertChecklist_Click(object sender, RoutedEventArgs e)
    {
        var selectedText = GetSelectedText();
        if (!string.IsNullOrWhiteSpace(selectedText))
        {
            var checklist = string.Join(
                Environment.NewLine,
                selectedText.ReplaceLineEndings("\n")
                    .Split('\n')
                    .Select(line => string.IsNullOrWhiteSpace(line) ? line : $"☐ {line.Trim()}"));
            ReplaceSelectionWith(checklist);
            return;
        }

        ReplaceSelectionWith(string.Join(Environment.NewLine, new[]
        {
            "☐ Задача 1",
            "☐ Задача 2",
            "☐ Задача 3"
        }));
    }

    private void ToggleChecklistItem_Click(object sender, RoutedEventArgs e)
        => ToggleChecklistItemAtCaret();

    private void ContentBox_DoubleTapped(object sender, Microsoft.UI.Xaml.Input.DoubleTappedRoutedEventArgs e)
    {
        ToggleChecklistItemAtCaret();
    }

    private async void InsertInternalLink_Click(object sender, RoutedEventArgs e)
    {
        var notes = await ViewModel.GetLinkableNotesAsync();
        if (notes.Count == 0)
        {
            await ShowEditorInfoAsync(LocalizationManager.Get("InternalLink"), LocalizationManager.Get("NoNotesForLink"));
            return;
        }

        var notePicker = new ComboBox
        {
            Header = LocalizationManager.Get("SelectNoteForLink"),
            DisplayMemberPath = nameof(Note.Title),
            ItemsSource = notes,
            SelectedIndex = 0,
            MinWidth = 320,
            HorizontalAlignment = HorizontalAlignment.Stretch
        };

        var dialog = new ContentDialog
        {
            Title = LocalizationManager.Get("InternalLink"),
            Content = notePicker,
            PrimaryButtonText = LocalizationManager.Get("Insert"),
            CloseButtonText = LocalizationManager.Get("Cancel"),
            DefaultButton = ContentDialogButton.Primary,
            XamlRoot = XamlRoot
        };

        if (await dialog.ShowAsync() != ContentDialogResult.Primary ||
            notePicker.SelectedItem is not Note selectedNote)
        {
            return;
        }

        // Wiki-ссылка остается текстовой конструкцией: она должна быть
        // читаемой, сохраняемой и открываемой независимо от визуального
        // форматирования текущего абзаца.
        ReplaceSelectionWith($"[[{selectedNote.Title.Trim()}]]");
    }

    private async void OpenInternalLink_Click(object sender, RoutedEventArgs e)
    {
        var selectedText = GetSelectedText();
        if (string.IsNullOrWhiteSpace(selectedText))
        {
            return;
        }

        await ViewModel.RequestOpenInternalLinkAsync(selectedText);
    }

    private void ContentBox_Loaded(object sender, RoutedEventArgs e)
    {
        _contentScrollViewer ??= FindDescendant<ScrollViewer>(ContentBox);
        if (_contentScrollViewer == null)
        {
            return;
        }

        _contentScrollViewer.ViewChanged -= ContentScrollViewer_ViewChanged;
        _contentScrollViewer.ViewChanged += ContentScrollViewer_ViewChanged;
        ContentBox.LayoutUpdated -= ContentBox_LayoutUpdated;
        ContentBox.LayoutUpdated += ContentBox_LayoutUpdated;
        SynchronizeContentScrollBar();
    }

    private void TransformSelection(Func<string, string> transform)
    {
        var selectedText = GetSelectedText();
        if (string.IsNullOrEmpty(selectedText))
        {
            return;
        }

        ReplaceSelectionWith(transform(selectedText));
    }

    private ITextSelection EnsureSelectionHasText(string placeholder)
    {
        var selection = ContentBox.Document.Selection;
        if (!string.IsNullOrEmpty(GetSelectedText()))
        {
            return selection;
        }

        var start = selection.StartPosition;
        selection.SetText(TextSetOptions.None, placeholder);
        selection.SetRange(start, start + placeholder.Length);
        return selection;
    }

    private string GetSelectedText()
    {
        ContentBox.Document.Selection.GetText(TextGetOptions.None, out var selectedText);
        return NormalizeRichEditText(selectedText);
    }

    private void ReplaceSelectionWith(string replacement)
    {
        ContentBox.Document.Selection.SetText(TextSetOptions.None, replacement);
        ContentBox.Focus(FocusState.Programmatic);
    }

    private void ToggleChecklistItemAtCaret()
    {
        ContentBox.Document.GetText(TextGetOptions.None, out var rawText);
        var text = NormalizeRichEditText(rawText);
        if (text.Length == 0)
        {
            return;
        }

        var selection = ContentBox.Document.Selection;
        var caretPosition = Math.Clamp(selection.StartPosition, 0, Math.Max(0, text.Length - 1));
        var lineStart = FindCurrentLineStart(text, caretPosition);
        if (lineStart >= text.Length)
        {
            return;
        }

        var currentMarker = text[lineStart];
        var newMarker = currentMarker switch
        {
            '☐' => '☑',
            '☑' => '☐',
            _ => '\0'
        };

        if (newMarker == '\0')
        {
            return;
        }

        // Меняем только первый символ строки. Остальной текст строки и его
        // форматирование остаются нетронутыми.
        selection.SetRange(lineStart, lineStart + 1);
        selection.SetText(TextSetOptions.None, newMarker.ToString());
        selection.SetRange(Math.Min(caretPosition, lineStart + 1), Math.Min(caretPosition, lineStart + 1));
    }

    private static int FindCurrentLineStart(string text, int caretPosition)
    {
        var safePosition = Math.Clamp(caretPosition, 0, text.Length);
        var previousBreak = text.LastIndexOf('\r', Math.Max(0, safePosition - 1));
        if (previousBreak < 0)
        {
            previousBreak = text.LastIndexOf('\n', Math.Max(0, safePosition - 1));
        }

        return previousBreak < 0 ? 0 : previousBreak + 1;
    }

    private static bool IsRtf(string content)
        => content.TrimStart().StartsWith(@"{\rtf", StringComparison.Ordinal);

    private static bool LooksLikeLegacyMarkup(string content)
        => content.Contains("<span style=", StringComparison.OrdinalIgnoreCase) ||
            content.Contains("**", StringComparison.Ordinal) ||
            content.Contains("| ---", StringComparison.Ordinal) ||
            content.Contains("- [ ]", StringComparison.Ordinal) ||
            content.Contains("- [x]", StringComparison.OrdinalIgnoreCase) ||
            Regex.IsMatch(content, @"(?<!\w)_[^_\r\n]+_(?!\w)", RegexOptions.CultureInvariant);

    private static string NormalizeRichEditText(string text)
    {
        // RichEditBox добавляет служебный завершающий перевод строки даже
        // при пустом документе. Для действий над выделением он не должен
        // считаться пользовательским текстом.
        return text is "\r" or "\n" or "\r\n"
            ? string.Empty
            : text.TrimEnd('\r', '\n');
    }

    private static string CreateRtfFromLegacyMarkup(string content)
    {
        var lines = content.ReplaceLineEndings("\n").Split('\n');
        var builder = new StringBuilder();
        BeginRtfDocument(builder);

        for (var index = 0; index < lines.Length; index++)
        {
            if (IsMarkdownTableStart(lines, index))
            {
                var tableRows = new List<IReadOnlyList<string>>();
                tableRows.Add(SplitMarkdownTableRow(lines[index]));
                index += 2;

                while (index < lines.Length && IsMarkdownTableRow(lines[index]))
                {
                    tableRows.Add(SplitMarkdownTableRow(lines[index]));
                    index++;
                }

                AppendRtfTable(builder, tableRows);
                index--;
                continue;
            }

            AppendLegacyParagraph(builder, lines[index]);
        }

        builder.Append('}');
        return builder.ToString();
    }

    private static void AppendLegacyParagraph(StringBuilder builder, string line)
    {
        var trimmed = line.TrimStart();
        if (trimmed.StartsWith("- [ ] ", StringComparison.Ordinal))
        {
            builder.Append(@"\pard ");
            AppendLegacyInline(builder, "☐ " + trimmed[6..]);
            builder.Append(@"\par ");
            return;
        }

        if (trimmed.StartsWith("- [x] ", StringComparison.OrdinalIgnoreCase))
        {
            builder.Append(@"\pard ");
            AppendLegacyInline(builder, "☑ " + trimmed[6..]);
            builder.Append(@"\par ");
            return;
        }

        if (trimmed.StartsWith("# ", StringComparison.Ordinal))
        {
            builder.Append(@"\pard\b\fs48 ");
            AppendLegacyInline(builder, trimmed[2..].Trim());
            builder.Append(@"\b0\fs22\par ");
            return;
        }

        builder.Append(@"\pard ");
        AppendLegacyInline(builder, line);
        builder.Append(@"\par ");
    }

    private static void AppendLegacyInline(StringBuilder builder, string text)
    {
        var index = 0;
        while (index < text.Length)
        {
            if (TryAppendLegacySpan(builder, text, ref index) ||
                TryAppendLegacyDelimitedRun(builder, text, ref index, "**", @"\b ", @"\b0 ") ||
                TryAppendLegacyDelimitedRun(builder, text, ref index, "_", @"\i ", @"\i0 "))
            {
                continue;
            }

            AppendEscapedRtfCharacter(builder, text[index]);
            index++;
        }
    }

    private static bool TryAppendLegacySpan(StringBuilder builder, string text, ref int index)
    {
        const string startMarker = "<span style=\"";
        if (!text[index..].StartsWith(startMarker, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var styleStart = index + startMarker.Length;
        var styleEnd = text.IndexOf("\">", styleStart, StringComparison.Ordinal);
        if (styleEnd < 0)
        {
            return false;
        }

        var contentStart = styleEnd + 2;
        var contentEnd = text.IndexOf("</span>", contentStart, StringComparison.OrdinalIgnoreCase);
        if (contentEnd < 0)
        {
            return false;
        }

        var style = text[styleStart..styleEnd];
        var innerText = WebUtility.HtmlDecode(text[contentStart..contentEnd]);
        var fontSize = TryReadLegacyFontSize(style);
        var fontFamily = TryReadLegacyFontFamily(style);

        if (!string.IsNullOrWhiteSpace(fontFamily))
        {
            builder.Append(@"\f1 ");
        }

        if (fontSize.HasValue)
        {
            builder.Append(@"\fs");
            builder.Append(((int)Math.Round(fontSize.Value * 2)).ToString(CultureInfo.InvariantCulture));
            builder.Append(' ');
        }

        AppendPlainRtfText(builder, innerText);

        if (fontSize.HasValue)
        {
            builder.Append(@"\fs22 ");
        }

        if (!string.IsNullOrWhiteSpace(fontFamily))
        {
            builder.Append(@"\f0 ");
        }

        index = contentEnd + "</span>".Length;
        return true;
    }

    private static bool TryAppendLegacyDelimitedRun(
        StringBuilder builder,
        string text,
        ref int index,
        string delimiter,
        string openRtf,
        string closeRtf)
    {
        if (!text[index..].StartsWith(delimiter, StringComparison.Ordinal))
        {
            return false;
        }

        var contentStart = index + delimiter.Length;
        var contentEnd = text.IndexOf(delimiter, contentStart, StringComparison.Ordinal);
        if (contentEnd < 0)
        {
            return false;
        }

        builder.Append(openRtf);
        AppendPlainRtfText(builder, text[contentStart..contentEnd]);
        builder.Append(closeRtf);
        index = contentEnd + delimiter.Length;
        return true;
    }

    private static float? TryReadLegacyFontSize(string style)
    {
        var match = Regex.Match(style, @"font-size\s*:\s*(\d+(?:\.\d+)?)px", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        return match.Success && float.TryParse(match.Groups[1].Value, NumberStyles.Number, CultureInfo.InvariantCulture, out var size)
            ? size
            : null;
    }

    private static string? TryReadLegacyFontFamily(string style)
    {
        var match = Regex.Match(style, @"font-family\s*:\s*'?([^;']+)'?", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        return match.Success ? match.Groups[1].Value.Trim() : null;
    }

    private static bool IsMarkdownTableStart(IReadOnlyList<string> lines, int index)
        => index + 1 < lines.Count &&
            IsMarkdownTableRow(lines[index]) &&
            IsMarkdownTableSeparator(lines[index + 1]);

    private static bool IsMarkdownTableRow(string line)
    {
        var trimmed = line.Trim();
        return trimmed.StartsWith('|') && trimmed.EndsWith('|') && trimmed.Count(character => character == '|') >= 3;
    }

    private static bool IsMarkdownTableSeparator(string line)
    {
        var cells = SplitMarkdownTableRow(line);
        return cells.Count > 0 && cells.All(cell =>
        {
            var normalized = cell.Trim().Trim(':');
            return normalized.Length >= 3 && normalized.All(character => character == '-');
        });
    }

    private static IReadOnlyList<string> SplitMarkdownTableRow(string line)
    {
        var trimmed = line.Trim();
        if (trimmed.StartsWith('|'))
        {
            trimmed = trimmed[1..];
        }

        if (trimmed.EndsWith('|'))
        {
            trimmed = trimmed[..^1];
        }

        return trimmed.Split('|').Select(cell => cell.Trim()).ToArray();
    }

    private static string CreateDefaultRtfTable()
    {
        var rows = new[]
        {
            new[] { "Колонка 1", "Колонка 2" },
            new[] { "Значение", "Значение" }
        };

        var builder = new StringBuilder();
        BeginRtfDocument(builder);
        AppendRtfTable(builder, rows);
        builder.Append('}');
        return builder.ToString();
    }

    private static void BeginRtfDocument(StringBuilder builder)
    {
        builder.Append(@"{\rtf1\ansi\deff0{\fonttbl{\f0 Segoe UI;}{\f1 Arial;}}\fs22 ");
    }

    private static void AppendRtfTable(StringBuilder builder, IReadOnlyList<IReadOnlyList<string>> rows)
    {
        for (var rowIndex = 0; rowIndex < rows.Count; rowIndex++)
        {
            builder.Append(@"\trowd\trgaph108\trleft0");
            for (var columnIndex = 0; columnIndex < rows[rowIndex].Count; columnIndex++)
            {
                var cellRight = (columnIndex + 1) * 2400;
                builder.Append(@"\clbrdrt\brdrs\brdrw10");
                builder.Append(@"\clbrdrl\brdrs\brdrw10");
                builder.Append(@"\clbrdrb\brdrs\brdrw10");
                builder.Append(@"\clbrdrr\brdrs\brdrw10");
                builder.Append(@"\cellx");
                builder.Append(cellRight.ToString(CultureInfo.InvariantCulture));
            }

            for (var columnIndex = 0; columnIndex < rows[rowIndex].Count; columnIndex++)
            {
                builder.Append(@"\intbl ");
                if (rowIndex == 0)
                {
                    builder.Append(@"\b ");
                }

                builder.Append(EscapeRtf(rows[rowIndex][columnIndex]));
                if (rowIndex == 0)
                {
                    builder.Append(@"\b0 ");
                }

                builder.Append(@"\cell ");
            }

            builder.Append(@"\row ");
        }

        builder.Append(@"\pard\par ");
    }

    private static string EscapeRtf(string text)
    {
        var builder = new StringBuilder(text.Length);
        AppendPlainRtfText(builder, text);
        return builder.ToString();
    }

    private static void AppendPlainRtfText(StringBuilder builder, string text)
    {
        foreach (var character in text)
        {
            AppendEscapedRtfCharacter(builder, character);
        }
    }

    private static void AppendEscapedRtfCharacter(StringBuilder builder, char character)
    {
        switch (character)
        {
            case '\\':
            case '{':
            case '}':
                builder.Append('\\');
                builder.Append(character);
                break;
            case '\r':
            case '\n':
                builder.Append(@"\line ");
                break;
            default:
                if (character <= 0x7f)
                {
                    builder.Append(character);
                }
                else
                {
                    // RTF хранит Unicode как signed 16-bit значение с
                    // fallback-символом. Так кириллица и чекбоксы не
                    // зависят от локальной кодовой страницы Windows.
                    var code = character > 0x7fff ? character - 0x10000 : character;
                    builder.Append(@"\u");
                    builder.Append(((int)code).ToString(CultureInfo.InvariantCulture));
                    builder.Append('?');
                }

                break;
        }
    }

    private async Task ShowEditorInfoAsync(string title, string message)
    {
        var dialog = new ContentDialog
        {
            Title = title,
            Content = message,
            CloseButtonText = LocalizationManager.Get("Ok"),
            XamlRoot = XamlRoot
        };
        await dialog.ShowAsync();
    }

    private void ContentBox_LayoutUpdated(object? sender, object e)
        => SynchronizeContentScrollBar();

    private void ContentScrollViewer_ViewChanged(object? sender, ScrollViewerViewChangedEventArgs e)
        => SynchronizeContentScrollBar();

    private void SynchronizeContentScrollBar()
    {
        if (_contentScrollViewer == null)
        {
            return;
        }

        // Внешняя полоса повторяет диапазон встроенного ScrollViewer
        // RichEditBox. Это дает стабильную видимость и не зависит от
        // системного авто-скрытия стандартных полос прокрутки Windows.
        _isSynchronizingScrollBar = true;
        try
        {
            ContentScrollBar.Maximum = Math.Max(0, _contentScrollViewer.ScrollableHeight);
            ContentScrollBar.ViewportSize = Math.Max(1, _contentScrollViewer.ViewportHeight);
            ContentScrollBar.LargeChange = Math.Max(1, _contentScrollViewer.ViewportHeight);
            ContentScrollBar.Value = Math.Min(
                ContentScrollBar.Maximum,
                _contentScrollViewer.VerticalOffset);

            var trackHeight = Math.Max(0, ContentScrollTrack.ActualHeight - 4);
            if (trackHeight <= 0)
            {
                return;
            }

            var extentHeight = _contentScrollViewer.ExtentHeight;
            var viewportHeight = _contentScrollViewer.ViewportHeight;
            var thumbHeight = extentHeight <= 0
                ? trackHeight
                : Math.Min(trackHeight, Math.Max(28, trackHeight * viewportHeight / extentHeight));
            var movableHeight = Math.Max(0, trackHeight - thumbHeight);
            var thumbOffset = _contentScrollViewer.ScrollableHeight <= 0
                ? 0
                : movableHeight * _contentScrollViewer.VerticalOffset / _contentScrollViewer.ScrollableHeight;

            ContentScrollThumb.Height = thumbHeight;
            ContentThumbTransform.Y = thumbOffset;
            UpdateContentScrollBarOpacity();
        }
        finally
        {
            _isSynchronizingScrollBar = false;
        }
    }

    private void ContentScrollBar_Scroll(object sender, ScrollEventArgs e)
    {
        if (!_isSynchronizingScrollBar && _contentScrollViewer != null)
        {
            _contentScrollViewer.ChangeView(null, e.NewValue, null, disableAnimation: true);
        }
    }

    private void ContentBox_TextChanged(object sender, RoutedEventArgs e)
    {
        if (!_isLoadingDocument)
        {
            SaveDocumentToViewModel();
        }

        if (ContentBox.FocusState == FocusState.Unfocused)
        {
            return;
        }

        // Во время ввода текста полоса остается на месте, но становится
        // прозрачнее, чтобы не отвлекать от набора и не спорить с курсором.
        _isContentTextInputActive = true;
        _contentTypingOpacityTimer.Stop();
        _contentTypingOpacityTimer.Start();
        UpdateContentScrollBarOpacity();
    }

    private void ContentTypingOpacityTimer_Tick(object? sender, object e)
    {
        _contentTypingOpacityTimer.Stop();
        _isContentTextInputActive = false;
        UpdateContentScrollBarOpacity();
    }

    private void ContentScrollTrack_PointerEntered(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        _isContentScrollBarHovered = true;
        UpdateContentScrollBarOpacity();
    }

    private void ContentScrollTrack_PointerExited(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        if (_isContentScrollBarDragging)
        {
            return;
        }

        _isContentScrollBarHovered = false;
        UpdateContentScrollBarOpacity();
    }

    private void ContentScrollTrack_PointerPressed(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        if (_contentScrollViewer == null || ContentScrollBar.Maximum <= 0)
        {
            return;
        }

        var pointer = e.GetCurrentPoint(ContentScrollTrack);
        var localY = Math.Max(0, pointer.Position.Y - ScrollBarEdgePadding);
        var thumbTop = ContentThumbTransform.Y;
        var thumbBottom = thumbTop + ContentScrollThumb.ActualHeight;

        // Если пользователь нажал прямо на ползунок, сохраняем точку захвата,
        // чтобы во время drag ползунок не прыгал под курсором. Нажатие по
        // пустому треку центрирует ползунок в месте клика и сразу начинает drag.
        _contentScrollDragOffset = localY >= thumbTop && localY <= thumbBottom
            ? localY - thumbTop
            : ContentScrollThumb.ActualHeight / 2;
        _isContentScrollBarDragging = true;
        _isContentScrollBarHovered = true;
        ContentScrollTrack.CapturePointer(e.Pointer);
        ScrollContentToPointer(localY);
        UpdateContentScrollBarOpacity();
        e.Handled = true;
    }

    private void ContentScrollTrack_PointerMoved(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        if (!_isContentScrollBarDragging)
        {
            return;
        }

        var localY = Math.Max(0, e.GetCurrentPoint(ContentScrollTrack).Position.Y - ScrollBarEdgePadding);
        ScrollContentToPointer(localY);
        e.Handled = true;
    }

    private void ContentScrollTrack_PointerReleased(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        if (!_isContentScrollBarDragging)
        {
            return;
        }

        _isContentScrollBarDragging = false;
        ContentScrollTrack.ReleasePointerCapture(e.Pointer);
        UpdateContentScrollBarOpacity();
        e.Handled = true;
    }

    private void ContentScrollTrack_PointerCaptureLost(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        _isContentScrollBarDragging = false;
        UpdateContentScrollBarOpacity();
    }

    private void ScrollContentToPointer(double localY)
    {
        if (_contentScrollViewer == null)
        {
            return;
        }

        var trackHeight = Math.Max(0, ContentScrollTrack.ActualHeight - (ScrollBarEdgePadding * 2));
        var thumbHeight = Math.Max(1, ContentScrollThumb.ActualHeight);
        var movableHeight = Math.Max(0, trackHeight - thumbHeight);
        if (movableHeight <= 0)
        {
            _contentScrollViewer.ChangeView(null, 0, null, disableAnimation: true);
            return;
        }

        var thumbOffset = Math.Clamp(localY - _contentScrollDragOffset, 0, movableHeight);
        var scrollOffset = thumbOffset * _contentScrollViewer.ScrollableHeight / movableHeight;
        _contentScrollViewer.ChangeView(null, scrollOffset, null, disableAnimation: true);
    }

    private void UpdateContentScrollBarOpacity()
    {
        if (ContentScrollBar.Maximum <= 0)
        {
            ContentScrollTrack.Opacity = 0;
            ContentScrollThumb.Opacity = 0;
            return;
        }

        if (_isContentScrollBarHovered || _isContentScrollBarDragging)
        {
            ContentScrollTrack.Opacity = ScrollBarHoverTrackOpacity;
            ContentScrollThumb.Opacity = ScrollBarHoverThumbOpacity;
            return;
        }

        ContentScrollTrack.Opacity = _isContentTextInputActive
            ? ScrollBarTypingTrackOpacity
            : ScrollBarNormalTrackOpacity;
        ContentScrollThumb.Opacity = _isContentTextInputActive
            ? ScrollBarTypingThumbOpacity
            : ScrollBarNormalThumbOpacity;
    }

    private static T? FindDescendant<T>(DependencyObject root) where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            if (child is T match)
            {
                return match;
            }

            var nestedMatch = FindDescendant<T>(child);
            if (nestedMatch != null)
            {
                return nestedMatch;
            }
        }

        return null;
    }
}
