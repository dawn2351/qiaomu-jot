using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace QiaomuJot.Models;

public class AppSettings
{
    private static readonly string SettingsFolder = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "QiaomuJot");

    private static readonly string SettingsFile = Path.Combine(SettingsFolder, "settings.json");

    public string VaultPath { get; set; } = string.Empty;
    public bool IsObsidian { get; set; } = true;
    public string DailyFolder { get; set; } = "日记";
    public string DailyFormat { get; set; } = "YYYY-MM-DD";
    public bool PrependEntries { get; set; }
    public string AttachmentFolder { get; set; } = "附件";
    public string CaptureShortcut { get; set; } = "Win+J";
    public string QuickSaveShortcut { get; set; } = "Win+K";
    public string ScreenshotOcrShortcut { get; set; } = "Alt+Shift+S";
    public bool LaunchAtLogin { get; set; } = false;
    public bool EnableOcr { get; set; } = true;
    public bool PlaySound { get; set; } = true;
    public string FormatStyle { get; set; } = "verbatim"; // verbatim, timestamped, quote, list, callout
    public string Draft { get; set; } = string.Empty;
    public bool DarkMode { get; set; } = false;
    public bool ShowFormatBar { get; set; } = true;

    [JsonIgnore]
    public static AppSettings Current { get; private set; } = Load();

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(SettingsFile))
            {
                var json = File.ReadAllText(SettingsFile);
                var settings = JsonSerializer.Deserialize<AppSettings>(json);
                if (settings != null)
                {
                    Current = settings;
                    return settings;
                }
            }
        }
        catch { }

        var def = new AppSettings();
        def.AutoDetectVault();
        Current = def;
        return def;
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(SettingsFolder);
            var json = JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(SettingsFile, json);
        }
        catch { }
    }

    public void AutoDetectVault()
    {
        // 1. Try detecting existing Obsidian vault
        try
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            var obsidianJson = Path.Combine(appData, "obsidian", "obsidian.json");
            if (File.Exists(obsidianJson))
            {
                var doc = JsonDocument.Parse(File.ReadAllText(obsidianJson));
                if (doc.RootElement.TryGetProperty("vaults", out var vaultsEl))
                {
                    string? bestVault = null;
                    foreach (var prop in vaultsEl.EnumerateObject())
                    {
                        if (prop.Value.TryGetProperty("path", out var pathEl))
                        {
                            var p = pathEl.GetString();
                            if (!string.IsNullOrEmpty(p) && Directory.Exists(p))
                            {
                                if (prop.Value.TryGetProperty("open", out var openEl) && openEl.GetBoolean())
                                {
                                    bestVault = p;
                                    break;
                                }
                                bestVault ??= p;
                            }
                        }
                    }

                    if (!string.IsNullOrEmpty(bestVault))
                    {
                        VaultPath = bestVault;
                        IsObsidian = true;

                        // Check daily notes config in vault
                        var dailyNotesConfig = Path.Combine(bestVault, ".obsidian", "daily-notes.json");
                        if (File.Exists(dailyNotesConfig))
                        {
                            var dailyDoc = JsonDocument.Parse(File.ReadAllText(dailyNotesConfig));
                            if (dailyDoc.RootElement.TryGetProperty("folder", out var fEl) && !string.IsNullOrWhiteSpace(fEl.GetString()))
                            {
                                DailyFolder = fEl.GetString()!.Trim('/', '\\');
                            }
                            if (dailyDoc.RootElement.TryGetProperty("format", out var fmtEl) && !string.IsNullOrWhiteSpace(fmtEl.GetString()))
                            {
                                DailyFormat = fmtEl.GetString()!;
                            }
                        }
                        else
                        {
                            // If "日记" folder exists, use it
                            if (Directory.Exists(Path.Combine(bestVault, "日记")))
                            {
                                DailyFolder = "日记";
                            }
                        }
                        return;
                    }
                }
            }
        }
        catch { }

        // 2. Fallback to Documents/乔木闪记
        var docs = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        var defFolder = Path.Combine(docs, "乔木闪记");
        VaultPath = defFolder;
        IsObsidian = false;
        DailyFolder = "日记";
        DailyFormat = "YYYY-MM-DD";
        AttachmentFolder = "附件";
    }
}
