using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using NotesApp.Localization;
using NotesApp.Models;
using NotesApp.ViewModels;

namespace NotesApp.Views;
public sealed partial class NotesListView : UserControl
{
    private const double ScrollBarNormalTrackOpacity = 0.26;
    private const double ScrollBarNormalThumbOpacity = 0.58;
    private const double ScrollBarHoverTrackOpacity = 0.74;
    private const double ScrollBarHoverThumbOpacity = 0.96;
    private const double ScrollBarEdgePadding = 2.0;

    private ScrollViewer? _notesScrollViewer;
    private bool _isSynchronizingScrollBar;
    private bool _isNotesScrollBarHovered;
    private bool _isNotesScrollBarDragging;
    private double _notesScrollDragOffset;

    public NotesListViewModel ViewModel => (NotesListViewModel)DataContext;
    public LocalizedStrings Strings => LocalizationManager.Strings;

    public NotesListView()
    {
        InitializeComponent();
        DataContextChanged += (s, e) => Bindings.Update();
    }

    public void RefreshLocalization() => Bindings.Update();

    private void NotesList_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is Note note)
        {
            ViewModel.SelectedNote = note;
        }
    }

    private void NotesList_Loaded(object sender, RoutedEventArgs e)
    {
        _notesScrollViewer ??= FindDescendant<ScrollViewer>(NotesList);
        if (_notesScrollViewer == null)
        {
            return;
        }

        _notesScrollViewer.ViewChanged -= NotesScrollViewer_ViewChanged;
        _notesScrollViewer.ViewChanged += NotesScrollViewer_ViewChanged;
        NotesList.LayoutUpdated -= NotesList_LayoutUpdated;
        NotesList.LayoutUpdated += NotesList_LayoutUpdated;
        SynchronizeNotesScrollBar();
    }

    private void NotesList_LayoutUpdated(object? sender, object e)
        => SynchronizeNotesScrollBar();

    private void NotesScrollViewer_ViewChanged(object? sender, ScrollViewerViewChangedEventArgs e)
        => SynchronizeNotesScrollBar();

    private void SynchronizeNotesScrollBar()
    {
        if (_notesScrollViewer == null)
        {
            return;
        }

        // Значения берутся из внутреннего ScrollViewer ListView, поэтому
        // колесо мыши и перетаскивание внешнего ползунка остаются синхронными.
        _isSynchronizingScrollBar = true;
        try
        {
            NotesScrollBar.Maximum = Math.Max(0, _notesScrollViewer.ScrollableHeight);
            NotesScrollBar.ViewportSize = Math.Max(1, _notesScrollViewer.ViewportHeight);
            NotesScrollBar.LargeChange = Math.Max(1, _notesScrollViewer.ViewportHeight);
            NotesScrollBar.Value = Math.Min(
                NotesScrollBar.Maximum,
                _notesScrollViewer.VerticalOffset);

            var trackHeight = Math.Max(0, NotesScrollTrack.ActualHeight - 4);
            if (trackHeight <= 0)
            {
                return;
            }

            var extentHeight = _notesScrollViewer.ExtentHeight;
            var viewportHeight = _notesScrollViewer.ViewportHeight;
            var thumbHeight = extentHeight <= 0
                ? trackHeight
                : Math.Min(trackHeight, Math.Max(28, trackHeight * viewportHeight / extentHeight));
            var movableHeight = Math.Max(0, trackHeight - thumbHeight);
            var thumbOffset = _notesScrollViewer.ScrollableHeight <= 0
                ? 0
                : movableHeight * _notesScrollViewer.VerticalOffset / _notesScrollViewer.ScrollableHeight;

            NotesScrollThumb.Height = thumbHeight;
            NotesThumbTransform.Y = thumbOffset;
            UpdateNotesScrollBarOpacity();
        }
        finally
        {
            _isSynchronizingScrollBar = false;
        }
    }

    private void NotesScrollBar_Scroll(object sender, ScrollEventArgs e)
    {
        if (!_isSynchronizingScrollBar && _notesScrollViewer != null)
        {
            _notesScrollViewer.ChangeView(null, e.NewValue, null, disableAnimation: true);
        }
    }

    private void NotesScrollTrack_PointerEntered(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        _isNotesScrollBarHovered = true;
        UpdateNotesScrollBarOpacity();
    }

    private void NotesScrollTrack_PointerExited(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        if (_isNotesScrollBarDragging)
        {
            return;
        }

        _isNotesScrollBarHovered = false;
        UpdateNotesScrollBarOpacity();
    }

    private void NotesScrollTrack_PointerPressed(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        if (_notesScrollViewer == null || NotesScrollBar.Maximum <= 0)
        {
            return;
        }

        var pointer = e.GetCurrentPoint(NotesScrollTrack);
        var localY = Math.Max(0, pointer.Position.Y - ScrollBarEdgePadding);
        var thumbTop = NotesThumbTransform.Y;
        var thumbBottom = thumbTop + NotesScrollThumb.ActualHeight;

        // При клике по самому ползунку сохраняем текущую точку захвата.
        // При клике по треку перемещаем ползунок к курсору, что ожидаемо для
        // короткой боковой панели со списком заметок.
        _notesScrollDragOffset = localY >= thumbTop && localY <= thumbBottom
            ? localY - thumbTop
            : NotesScrollThumb.ActualHeight / 2;
        _isNotesScrollBarDragging = true;
        _isNotesScrollBarHovered = true;
        NotesScrollTrack.CapturePointer(e.Pointer);
        ScrollNotesToPointer(localY);
        UpdateNotesScrollBarOpacity();
        e.Handled = true;
    }

    private void NotesScrollTrack_PointerMoved(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        if (!_isNotesScrollBarDragging)
        {
            return;
        }

        var localY = Math.Max(0, e.GetCurrentPoint(NotesScrollTrack).Position.Y - ScrollBarEdgePadding);
        ScrollNotesToPointer(localY);
        e.Handled = true;
    }

    private void NotesScrollTrack_PointerReleased(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        if (!_isNotesScrollBarDragging)
        {
            return;
        }

        _isNotesScrollBarDragging = false;
        NotesScrollTrack.ReleasePointerCapture(e.Pointer);
        UpdateNotesScrollBarOpacity();
        e.Handled = true;
    }

    private void NotesScrollTrack_PointerCaptureLost(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        _isNotesScrollBarDragging = false;
        UpdateNotesScrollBarOpacity();
    }

    private void ScrollNotesToPointer(double localY)
    {
        if (_notesScrollViewer == null)
        {
            return;
        }

        var trackHeight = Math.Max(0, NotesScrollTrack.ActualHeight - (ScrollBarEdgePadding * 2));
        var thumbHeight = Math.Max(1, NotesScrollThumb.ActualHeight);
        var movableHeight = Math.Max(0, trackHeight - thumbHeight);
        if (movableHeight <= 0)
        {
            _notesScrollViewer.ChangeView(null, 0, null, disableAnimation: true);
            return;
        }

        var thumbOffset = Math.Clamp(localY - _notesScrollDragOffset, 0, movableHeight);
        var scrollOffset = thumbOffset * _notesScrollViewer.ScrollableHeight / movableHeight;
        _notesScrollViewer.ChangeView(null, scrollOffset, null, disableAnimation: true);
    }

    private void UpdateNotesScrollBarOpacity()
    {
        if (NotesScrollBar.Maximum <= 0)
        {
            NotesScrollTrack.Opacity = 0;
            NotesScrollThumb.Opacity = 0;
            return;
        }

        NotesScrollTrack.Opacity = _isNotesScrollBarHovered || _isNotesScrollBarDragging
            ? ScrollBarHoverTrackOpacity
            : ScrollBarNormalTrackOpacity;
        NotesScrollThumb.Opacity = _isNotesScrollBarHovered || _isNotesScrollBarDragging
            ? ScrollBarHoverThumbOpacity
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
