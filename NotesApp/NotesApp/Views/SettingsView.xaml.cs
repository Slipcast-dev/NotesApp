using Microsoft.UI.Xaml.Controls;
using NotesApp.Localization;
using NotesApp.ViewModels;

namespace NotesApp.Views;
public sealed partial class SettingsView : UserControl
{
    public SettingsViewModel ViewModel => (SettingsViewModel)DataContext;
    public LocalizedStrings Strings => LocalizationManager.Strings;
    public SettingsView() { InitializeComponent(); DataContextChanged += (s, e) => Bindings.Update(); }
    public void RefreshLocalization() => Bindings.Update();
}
