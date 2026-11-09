using System;
using System.Text.RegularExpressions;

namespace QiaomuJot.Services;

internal static class NoteTopInsertion
{
    private static (string Body, int End, string Newline) LineAt(string note, int start)
    {
        int contentsEnd = note.IndexOfAny(['\r', '\n'], start);
        if (contentsEnd < 0)
            return (note[start..], note.Length, "");
        int end = contentsEnd + 1;
        if (note[contentsEnd] == '\r' && end < note.Length && note[end] == '\n')
            end++;
        return (note[start..contentsEnd], end, note[contentsEnd..end]);
    }

    public static string Insert(string note, string entry)
    {
        int start = note.StartsWith('\uFEFF') ? 1 : 0;
        var first = LineAt(note, start);
        string newline = first.Newline.Length == 0 ? "\n" : first.Newline;
        int offset = start;
        if (first.Body.TrimEnd(' ', '\t') == "---")
        {
            for (int cursor = first.End; cursor < note.Length;)
            {
                var line = LineAt(note, cursor);
                if (line.Body.TrimEnd(' ', '\t') is "---" or "...")
                {
                    offset = line.End;
                    break;
                }
                cursor = line.End;
            }
        }

        bool followsBlankLine = false;
        void SkipBlankLines()
        {
            while (offset < note.Length)
            {
                var line = LineAt(note, offset);
                if (!string.IsNullOrWhiteSpace(line.Body))
                    break;
                offset = line.End;
                followsBlankLine = true;
            }
        }

        SkipBlankLines();
        var title = LineAt(note, offset);
        if (Regex.IsMatch(title.Body, @"^ {0,3}#(?:[ \t]|$)"))
        {
            offset = title.End;
            followsBlankLine = false;
        }
        else if (Regex.IsMatch(title.Body, @"^[\p{L}\p{N}]") &&
                 Regex.IsMatch(LineAt(note, title.End).Body, @"^ {0,3}=+[ \t]*$"))
        {
            offset = LineAt(note, title.End).End;
            followsBlankLine = false;
        }
        SkipBlankLines();

        string leading = "";
        if (offset > start)
        {
            if (note[offset - 1] is not ('\r' or '\n'))
                leading += newline;
            if (!followsBlankLine)
                leading += newline;
        }
        if (offset == start && offset < note.Length && LineAt(entry, 0).Body.TrimEnd(' ', '\t') == "---")
        {
            // Keep a captured delimiter in the body, outside the document properties.
            leading = newline;
        }
        string trailing = offset < note.Length ? newline : "";
        return note.Insert(offset, leading + entry.ReplaceLineEndings(newline) + newline + trailing);
    }
}
