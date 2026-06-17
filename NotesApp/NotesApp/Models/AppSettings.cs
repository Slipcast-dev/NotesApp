namespace NotesApp.Models;

public class AppSettings
{
    public string Theme { get; set; } = "System";
    public double FontSize { get; set; } = 12.0;
    public string FontFamily { get; set; } = "Segoe UI";
    public bool AutoSave { get; set; } = true;
    public string DefaultSorting { get; set; } = "updateddesc";
    public string Language { get; set; } = "ru";
}
