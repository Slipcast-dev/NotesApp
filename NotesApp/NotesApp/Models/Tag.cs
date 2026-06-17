using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace NotesApp.Models;

public class Tag
{
    public const string DefaultColorHex = "#4C8DFF";

    [Key]
    public int Id { get; set; }

    [Required]
    [MaxLength(50)]
    public string Name { get; set; } = string.Empty;

    [Required]
    [MaxLength(9)]
    public string ColorHex { get; set; } = DefaultColorHex;

    public ICollection<NoteTag> NoteTags { get; set; } = new List<NoteTag>();
}
