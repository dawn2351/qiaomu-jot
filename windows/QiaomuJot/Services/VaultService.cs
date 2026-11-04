using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using QiaomuJot.Models;

namespace QiaomuJot.Services;

public class VaultService
{
    private static VaultService? _instance;
    public static VaultService Instance => _instance ??= new VaultService();

    private string? _lastNotePath;
    private string? _lastNoteOriginalContent;

    public string GetTodayNotePath(DateTime? date = null)
    {
        var d = date ?? DateTime.Now;
        var s = AppSettings.Current;
        var vault = string.IsNullOrWhiteSpace(s.VaultPath) ? 
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "乔木闪记") : 
            s.VaultPath;

        var dailyDir = string.IsNullOrWhiteSpace(s.DailyFolder) ? vault : Path.Combine(vault, s.DailyFolder);

        // Check if there is a year subfolder existing, e.g. "日记/2026"
        var yearDir = Path.Combine(dailyDir, d.ToString("yyyy"));
        if (Directory.Exists(yearDir))
        {
            return Path.Combine(yearDir, $"{d:yyyy-MM-dd}.md");
        }

        return Path.Combine(dailyDir, $"{d:yyyy-MM-dd}.md");
    }

    public string GetAttachmentDirectory(string? notePath = null)
    {
        var s = AppSettings.Current;
        var vault = string.IsNullOrWhiteSpace(s.VaultPath) ? 
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "乔木闪记") : 
            s.VaultPath;

        var attachDirName = string.IsNullOrWhiteSpace(s.AttachmentFolder) ? "附件" : s.AttachmentFolder;
        var attachDir = Path.Combine(vault, attachDirName);
        Directory.CreateDirectory(attachDir);
        return attachDir;
    }

    public string SaveAttachment(byte[] data, string ext = ".png", string? baseName = null)
    {
        var dir = GetAttachmentDirectory();
        if (string.IsNullOrWhiteSpace(ext)) ext = ".png";
        if (!ext.StartsWith(".")) ext = "." + ext;

        var name = string.IsNullOrWhiteSpace(baseName) ? 
            $"截屏_{DateTime.Now:yyyyMMdd_HHmmss}" : 
            Path.GetFileNameWithoutExtension(baseName);

        var finalName = $"{name}{ext}";
        var fullPath = Path.Combine(dir, finalName);
        int counter = 1;
        while (File.Exists(fullPath))
        {
            finalName = $"{name}_{counter}{ext}";
            fullPath = Path.Combine(dir, finalName);
            counter++;
        }

        File.WriteAllBytes(fullPath, data);
        return finalName;
    }

    public string FormatImageMarkdown(string attachmentFileName, string? ocrText = null)
    {
        var s = AppSettings.Current;
        var sb = new StringBuilder();

        if (s.IsObsidian)
        {
            sb.AppendLine($"![[{attachmentFileName}]]");
            if (!string.IsNullOrWhiteSpace(ocrText))
            {
                sb.AppendLine("> [!note]- 图中文字");
                foreach (var line in ocrText.Split('\n'))
                {
                    sb.AppendLine($"> {line.TrimEnd('\r')}");
                }
            }
        }
        else
        {
            sb.AppendLine($"![](../附件/{attachmentFileName})");
            if (!string.IsNullOrWhiteSpace(ocrText))
            {
                sb.AppendLine("<details>");
                sb.AppendLine("<summary>图中文字</summary>\n");
                sb.AppendLine(ocrText);
                sb.AppendLine("\n</details>");
            }
        }

        return sb.ToString().TrimEnd();
    }

    public string FormatEntry(string content, SourceContext? source = null, DateTime? date = null)
    {
        var d = date ?? DateTime.Now;
        var s = AppSettings.Current;
        var timeStr = d.ToString("HH:mm");
        var text = content.Trim();

        var sourceMarkdown = source?.ToMarkdownSource();
        var hasSource = !string.IsNullOrWhiteSpace(sourceMarkdown);

        switch (s.FormatStyle?.ToLowerInvariant())
        {
            case "timestamped":
                if (hasSource)
                    return $"**{timeStr}** {text}\n> 来源: {sourceMarkdown}";
                return $"**{timeStr}** {text}";

            case "list":
                if (hasSource)
                    return $"- {timeStr} {text} · {sourceMarkdown}";
                return $"- {timeStr} {text}";

            case "quote":
                if (hasSource)
                    return $"> {text}\n> — {timeStr} · {sourceMarkdown}";
                return $"> {text}\n> — {timeStr}";

            case "verbatim":
            default:
                if (hasSource)
                {
                    return $"{text}\n> {timeStr} · {sourceMarkdown}";
                }
                return $"{text}\n> {timeStr}";
        }
    }

    public async Task<bool> AppendEntryAsync(string markdownEntry, string? targetNotePath = null)
    {
        try
        {
            var notePath = targetNotePath ?? GetTodayNotePath();
            var dir = Path.GetDirectoryName(notePath);
            if (!string.IsNullOrEmpty(dir))
            {
                Directory.CreateDirectory(dir);
            }

            string originalContent = string.Empty;
            if (File.Exists(notePath))
            {
                originalContent = await File.ReadAllTextAsync(notePath, Encoding.UTF8).ConfigureAwait(false);
            }
            else
            {
                // New daily note header
                var title = Path.GetFileNameWithoutExtension(notePath);
                originalContent = $"# {title}\n\n";
            }

            _lastNotePath = notePath;
            _lastNoteOriginalContent = originalContent;

            var sb = new StringBuilder();
            sb.Append(originalContent.TrimEnd());
            if (!string.IsNullOrEmpty(originalContent.Trim()))
            {
                sb.Append("\n\n");
            }
            sb.Append(markdownEntry.Trim());
            sb.Append("\n");

            await File.WriteAllTextAsync(notePath, sb.ToString(), new UTF8Encoding(false)).ConfigureAwait(false);
            return true;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Failed to append entry: {ex.Message}");
            return false;
        }
    }

    public bool UndoLast()
    {
        if (string.IsNullOrEmpty(_lastNotePath) || _lastNoteOriginalContent == null)
            return false;

        try
        {
            File.WriteAllText(_lastNotePath, _lastNoteOriginalContent, new UTF8Encoding(false));
            _lastNotePath = null;
            _lastNoteOriginalContent = null;
            return true;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Failed to undo: {ex.Message}");
            return false;
        }
    }
}
