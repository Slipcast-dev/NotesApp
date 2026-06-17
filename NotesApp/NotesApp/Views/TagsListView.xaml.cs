using Microsoft.UI.Xaml.Controls;
using NotesApp.Localization;
using NotesApp.ViewModels;

namespace NotesApp.Views;
public sealed partial class TagsListView : UserControl
{
    public TagsListViewModel ViewModel => (TagsListViewModel)DataContext;
    public LocalizedStrings Strings => LocalizationManager.Strings;
    public TagsListView() { InitializeComponent(); DataContextChanged += (s, e) => Bindings.Update(); }
    public void RefreshLocalization() => Bindings.Update();
}
