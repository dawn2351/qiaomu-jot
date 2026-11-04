using System;
using System.Text;
using System.Text.RegularExpressions;
using TextBox = System.Windows.Controls.TextBox;

namespace QiaomuJot.Services;

public static class MarkdownEditorHelper
{
    public static void WrapSelection(TextBox textBox, string prefix, string suffix)
    {
        var text = textBox.Text ?? "";
        var start = textBox.SelectionStart;
        var length = textBox.SelectionLength;
        var selected = text.Substring(start, length);

        // Check if already wrapped -> toggle off
        if (start >= prefix.Length && (start + length + suffix.Length) <= text.Length)
        {
            var before = text.Substring(start - prefix.Length, prefix.Length);
            var after = text.Substring(start + length, suffix.Length);
            if (before == prefix && after == suffix)
            {
                // Remove prefix and suffix
                var newText = text.Substring(0, start - prefix.Length) + selected + text.Substring(start + length + suffix.Length);
                textBox.Text = newText;
                textBox.SelectionStart = start - prefix.Length;
                textBox.SelectionLength = length;
                return;
            }
        }

        var replacement = prefix + selected + suffix;
        var sb = new StringBuilder(text);
        sb.Remove(start, length);
        sb.Insert(start, replacement);

        textBox.Text = sb.ToString();
        if (length == 0)
        {
            textBox.SelectionStart = start + prefix.Length;
            textBox.SelectionLength = 0;
        }
        else
        {
            textBox.SelectionStart = start;
            textBox.SelectionLength = replacement.Length;
        }
    }

    public static void InsertOrWrapLink(TextBox textBox)
    {
        var text = textBox.Text ?? "";
        var start = textBox.SelectionStart;
        var length = textBox.SelectionLength;
        var selected = text.Substring(start, length);

        if (string.IsNullOrEmpty(selected))
        {
            WrapSelection(textBox, "[", "]()");
            textBox.SelectionStart = start + 1;
        }
        else if (selected.StartsWith("http://") || selected.StartsWith("https://"))
        {
            var rep = $"[]({selected})";
            var sb = new StringBuilder(text);
            sb.Remove(start, length);
            sb.Insert(start, rep);
            textBox.Text = sb.ToString();
            textBox.SelectionStart = start + 1;
        }
        else
        {
            var rep = $"[{selected}]()";
            var sb = new StringBuilder(text);
            sb.Remove(start, length);
            sb.Insert(start, rep);
            textBox.Text = sb.ToString();
            textBox.SelectionStart = start + selected.Length + 3;
        }
    }

    public static void ToggleLinePrefix(TextBox textBox, string prefix)
    {
        var text = textBox.Text ?? "";
        var start = textBox.SelectionStart;
        var lineIndex = textBox.GetLineIndexFromCharacterIndex(start);
        var lineStart = textBox.GetCharacterIndexFromLineIndex(lineIndex);
        var lineLength = textBox.GetLineLength(lineIndex);
        var line = text.Substring(lineStart, lineLength);

        string newLine;
        if (line.StartsWith(prefix))
        {
            newLine = line.Substring(prefix.Length);
        }
        else
        {
            // Remove other common list prefixes first
            if (line.StartsWith("- [ ] ")) line = line.Substring(6);
            else if (line.StartsWith("- [x] ")) line = line.Substring(6);
            else if (line.StartsWith("- ")) line = line.Substring(2);
            else if (line.StartsWith("> ")) line = line.Substring(2);
            else if (Regex.IsMatch(line, @"^\d+\.\s")) line = Regex.Replace(line, @"^\d+\.\s", "");

            newLine = prefix + line;
        }

        var sb = new StringBuilder(text);
        sb.Remove(lineStart, lineLength);
        sb.Insert(lineStart, newLine);
        textBox.Text = sb.ToString();
        textBox.SelectionStart = Math.Min(lineStart + newLine.Length, textBox.Text.Length);
    }

    public static void ToggleHeading(TextBox textBox, int? targetLevel = null)
    {
        var text = textBox.Text ?? "";
        var start = textBox.SelectionStart;
        var lineIndex = textBox.GetLineIndexFromCharacterIndex(start);
        var lineStart = textBox.GetCharacterIndexFromLineIndex(lineIndex);
        var lineLength = textBox.GetLineLength(lineIndex);
        var line = text.Substring(lineStart, lineLength);

        var match = Regex.Match(line, @"^(#{1,6})\s");
        string stripped = match.Success ? line.Substring(match.Length) : line;

        string newLine;
        if (targetLevel.HasValue)
        {
            if (match.Success && match.Groups[1].Value.Length == targetLevel.Value)
            {
                newLine = stripped;
            }
            else
            {
                newLine = new string('#', targetLevel.Value) + " " + stripped;
            }
        }
        else
        {
            // Cycle: none -> # -> ## -> ### -> none
            int currentLevel = match.Success ? match.Groups[1].Value.Length : 0;
            int nextLevel = (currentLevel % 3) + 1;
            if (currentLevel >= 3)
            {
                newLine = stripped;
            }
            else
            {
                newLine = new string('#', nextLevel) + " " + stripped;
            }
        }

        var sb = new StringBuilder(text);
        sb.Remove(lineStart, lineLength);
        sb.Insert(lineStart, newLine);
        textBox.Text = sb.ToString();
        textBox.SelectionStart = Math.Min(lineStart + newLine.Length, textBox.Text.Length);
    }

    public static bool HandleEnterKey(TextBox textBox)
    {
        var text = textBox.Text ?? "";
        var selStart = textBox.SelectionStart;
        var lineIndex = textBox.GetLineIndexFromCharacterIndex(selStart);
        var lineStart = textBox.GetCharacterIndexFromLineIndex(lineIndex);
        var lineLength = textBox.GetLineLength(lineIndex);
        var line = text.Substring(lineStart, lineLength).TrimEnd('\r', '\n');

        // Check task: "- [ ] " or "- [x] "
        var taskMatch = Regex.Match(line, @"^(\s*-\s*\[[ xX]\]\s*)");
        if (taskMatch.Success)
        {
            if (line.Trim() == "- [ ]" || line.Trim() == "- [x]")
            {
                // Empty task -> exit list
                var sb1 = new StringBuilder(text);
                sb1.Remove(lineStart, lineLength);
                sb1.Insert(lineStart, "\n");
                textBox.Text = sb1.ToString();
                textBox.SelectionStart = lineStart + 1;
                return true;
            }
            var nextPrefix = "\n" + taskMatch.Groups[1].Value.Replace("[x]", "[ ]").Replace("[X]", "[ ]");
            InsertTextAt(textBox, selStart, nextPrefix);
            return true;
        }

        // Check bullet: "- " or "* "
        var bulletMatch = Regex.Match(line, @"^(\s*[-*]\s+)");
        if (bulletMatch.Success)
        {
            if (line.Trim() == "-" || line.Trim() == "*")
            {
                // Empty item -> exit list
                var sb1 = new StringBuilder(text);
                sb1.Remove(lineStart, lineLength);
                sb1.Insert(lineStart, "\n");
                textBox.Text = sb1.ToString();
                textBox.SelectionStart = lineStart + 1;
                return true;
            }
            var nextPrefix = "\n" + bulletMatch.Groups[1].Value;
            InsertTextAt(textBox, selStart, nextPrefix);
            return true;
        }

        // Check numbered: "1. "
        var numMatch = Regex.Match(line, @"^(\s*)(\d+)\.\s+");
        if (numMatch.Success)
        {
            if (Regex.IsMatch(line.Trim(), @"^\d+\.$"))
            {
                var sb1 = new StringBuilder(text);
                sb1.Remove(lineStart, lineLength);
                sb1.Insert(lineStart, "\n");
                textBox.Text = sb1.ToString();
                textBox.SelectionStart = lineStart + 1;
                return true;
            }
            int currentNum = int.Parse(numMatch.Groups[2].Value);
            var nextPrefix = $"\n{numMatch.Groups[1].Value}{currentNum + 1}. ";
            InsertTextAt(textBox, selStart, nextPrefix);
            return true;
        }

        return false;
    }

    private static void InsertTextAt(TextBox textBox, int index, string insertText)
    {
        var text = textBox.Text ?? "";
        var sb = new StringBuilder(text);
        sb.Insert(index, insertText);
        textBox.Text = sb.ToString();
        textBox.SelectionStart = index + insertText.Length;
        textBox.SelectionLength = 0;
    }
}
