using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Data;

namespace NotesApp.Converters;

public class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
        => value is true ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        // Конвертер применяется только к OneWay-привязкам. Обратное
        // преобразование Visibility не должно неявно менять boolean-модель.
        throw new NotSupportedException(
            $"{nameof(BoolToVisibilityConverter)} supports only one-way bindings.");
    }
}
