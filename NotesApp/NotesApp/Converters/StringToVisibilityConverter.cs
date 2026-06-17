using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Data;

namespace NotesApp.Converters;

public class StringToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
        => !string.IsNullOrWhiteSpace(value as string)
            ? Visibility.Visible
            : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        // Преобразование намеренно одностороннее: по Visibility невозможно
        // восстановить исходную строку без потери данных.
        throw new NotSupportedException(
            $"{nameof(StringToVisibilityConverter)} supports only one-way bindings.");
    }
}
