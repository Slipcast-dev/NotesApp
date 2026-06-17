using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Media;
using NotesApp.Models;
using Windows.UI;

namespace NotesApp.Converters;

public class TagColorBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
        => new SolidColorBrush(ParseColor(value as string));

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        // Кисть создается только для отображения тега. Обратное
        // преобразование в hex-строку выполняется через ColorPicker.
        throw new NotSupportedException(
            $"{nameof(TagColorBrushConverter)} supports only one-way bindings.");
    }

    internal static Color ParseColor(string? colorHex)
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
            System.Convert.ToByte(value.Substring(1, 2), 16),
            System.Convert.ToByte(value.Substring(3, 2), 16),
            System.Convert.ToByte(value.Substring(5, 2), 16));
    }
}

public class TagForegroundBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        var color = TagColorBrushConverter.ParseColor(value as string);
        var luminance = (0.2126 * color.R) + (0.7152 * color.G) + (0.0722 * color.B);

        // Порог выбран по воспринимаемой яркости: на светлых цветах нужен
        // почти черный текст, на темных - белый.
        return luminance > 150
            ? new SolidColorBrush(Color.FromArgb(255, 24, 24, 24))
            : new SolidColorBrush(Color.FromArgb(255, 255, 255, 255));
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        // Цвет текста является производным от фона и не должен сохраняться
        // отдельно от выбранного пользователем цвета тега.
        throw new NotSupportedException(
            $"{nameof(TagForegroundBrushConverter)} supports only one-way bindings.");
    }
}
