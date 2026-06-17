using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace NotesApp.Models;

public class Note
{
    [Key]
    public int Id { get; set; }

    [Required]
    [MaxLength(200)]
    public string Title { get; set; } = string.Empty;

    public string Content { get; set; } = string.Empty;

    [MaxLength(260)]
    public string? MarkdownFileName { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.Now;

    public DateTime UpdatedAt { get; set; } = DateTime.Now;

    public bool IsPinned { get; set; }

    public bool IsDeleted { get; set; }

    public ICollection<NoteTag> NoteTags { get; set; } = new List<NoteTag>();
}
