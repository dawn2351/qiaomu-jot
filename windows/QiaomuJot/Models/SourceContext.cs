using System;
using System.IO;
using System.Text.RegularExpressions;

namespace QiaomuJot.Models;

public enum SourceKind
{
    Browser,
    Code,
    Pdf,
    Mail,
    Notes,
    Terminal,
    Explorer,
    Other
}

public class SourceContext
{
    public string AppName { get; set; } = string.Empty;
    public string ProcessName { get; set; } = string.Empty;
    public SourceKind Kind { get; set; } = SourceKind.Other;
    public string? WindowTitle { get; set; }
    public string? Url { get; set; }
    public string? PageTitle { get; set; }
    public string? FileName { get; set; }

    public static SourceKind ClassifyProcess(string processName)
    {
        var p = processName.ToLowerInvariant();
        if (p is "chrome" or "msedge" or "firefox" or "brave" or "opera" or "vivaldi" or "zen" or "arc")
            return SourceKind.Browser;
        if (p is "code" or "cursor" or "windsurf" or "devenv" or "idea64" or "pycharm64" or "webstorm64" or "clion64" or "rider64" or "sublime_text" or "notepad++")
            return SourceKind.Code;
        if (p is "acrobat" or "acrord32" or "foxitreader" or "sumatrapdf")
            return SourceKind.Pdf;
        if (p is "outlook" or "thunderbird" or "mail")
            return SourceKind.Mail;
        if (p is "obsidian" or "notion" or "logseq" or "typora")
            return SourceKind.Notes;
        if (p is "windowsterminal" or "cmd" or "powershell" or "pwsh" or "mintty" or "wezterm-gui" or "alacritty")
            return SourceKind.Terminal;
        if (p is "explorer")
            return SourceKind.Explorer;

        return SourceKind.Other;
    }

    public static string CleanBrowserTitle(string title, string appName)
    {
        if (string.IsNullOrWhiteSpace(title)) return title;

        // Typical Windows browser title suffixes:
        // "Page Title - Google Chrome"
        // "Page Title - Microsoft​ Edge"
        // "Page Title — Mozilla Firefox"
        var suffixes = new[]
        {
            " - Google Chrome",
            " - Microsoft Edge",
            " - Microsoft​ Edge",
            " — Mozilla Firefox",
            " - Brave",
            " - Vivaldi",
            " - Opera",
            $" - {appName}",
            $" — {appName}"
        };

        var cleaned = title;
        foreach (var suf in suffixes)
        {
            if (cleaned.EndsWith(suf, StringComparison.OrdinalIgnoreCase))
            {
                cleaned = cleaned.Substring(0, cleaned.Length - suf.Length).Trim();
                break;
            }
        }
        return cleaned;
    }

    public static string? ExtractFileNameFromTitle(string title)
    {
        if (string.IsNullOrWhiteSpace(title)) return null;

        // E.g. "● main.swift — qiaomu-ob-helper"
        // "AppSettings.cs - QiaomuJot - Visual Studio Code"
        var t = title.TrimStart('●', '*', ' ').Trim();
        var dashIdx = t.IndexOf(" - ", StringComparison.Ordinal);
        if (dashIdx > 0)
        {
            var part = t.Substring(0, dashIdx).Trim();
            if (part.Contains('.')) return Path.GetFileName(part);
        }
        var emDashIdx = t.IndexOf(" — ", StringComparison.Ordinal);
        if (emDashIdx > 0)
        {
            var part = t.Substring(0, emDashIdx).Trim();
            if (part.Contains('.')) return Path.GetFileName(part);
        }

        return null;
    }

    public string ToMarkdownSource()
    {
        if (!string.IsNullOrWhiteSpace(Url))
        {
            var t = !string.IsNullOrWhiteSpace(PageTitle) ? PageTitle : (!string.IsNullOrWhiteSpace(WindowTitle) ? WindowTitle : Url);
            t = t.Replace("[", "\\[").Replace("]", "\\]");
            return $"[{t}]({Url})";
        }

        if (!string.IsNullOrWhiteSpace(FileName))
        {
            return $"`{FileName}` · {AppName}";
        }

        if (!string.IsNullOrWhiteSpace(WindowTitle))
        {
            return $"{WindowTitle} · {AppName}";
        }

        return AppName;
    }
}
