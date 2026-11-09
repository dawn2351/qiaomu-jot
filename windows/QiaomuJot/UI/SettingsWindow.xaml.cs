using System;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Forms;
using Microsoft.Win32;
using QiaomuJot.Models;
using QiaomuJot.Services;
using MessageBox = System.Windows.MessageBox;

namespace QiaomuJot.UI;

public partial class SettingsWindow : Window
{
    public SettingsWindow()
    {
        InitializeComponent();
        Loaded += SettingsWindow_Loaded;
    }

    private void SettingsWindow_Loaded(object sender, RoutedEventArgs e)
    {
        LoadSettings();
        DiscoverObsidianVaults();
        UpdateFormatPreview();
    }

    private void LoadSettings()
    {
        var s = AppSettings.Current;
        TxtVaultPath.Text = s.VaultPath;
        RbObsidian.IsChecked = s.IsObsidian;
        RbPlain.IsChecked = !s.IsObsidian;

        TxtDailyFolder.Text = s.DailyFolder;
        TxtDailyFormat.Text = s.DailyFormat;
        ChkPrependEntries.IsChecked = s.PrependEntries;
        TxtAttachmentFolder.Text = s.AttachmentFolder;

        TxtShortcutCapture.Text = s.CaptureShortcut;
        TxtShortcutQuickSave.Text = s.QuickSaveShortcut;
        TxtShortcutScreenshotOcr.Text = s.ScreenshotOcrShortcut;

        ChkEnableOcr.IsChecked = s.EnableOcr;
        ChkPlaySound.IsChecked = s.PlaySound;
        ChkLaunchAtLogin.IsChecked = s.LaunchAtLogin;

        foreach (ComboBoxItem item in CmbFormatStyle.Items)
        {
            if (item.Tag?.ToString() == s.FormatStyle)
            {
                item.IsSelected = true;
                break;
            }
        }
    }

    private void DiscoverObsidianVaults()
    {
        LstDiscoveredVaults.Items.Clear();
        try
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            var obsidianJson = Path.Combine(appData, "obsidian", "obsidian.json");
            if (File.Exists(obsidianJson))
            {
                var doc = JsonDocument.Parse(File.ReadAllText(obsidianJson));
                if (doc.RootElement.TryGetProperty("vaults", out var vaultsEl))
                {
                    foreach (var prop in vaultsEl.EnumerateObject())
                    {
                        if (prop.Value.TryGetProperty("path", out var pathEl))
                        {
                            var p = pathEl.GetString();
                            if (!string.IsNullOrEmpty(p) && Directory.Exists(p))
                            {
                                LstDiscoveredVaults.Items.Add(p);
                            }
                        }
                    }
                }
            }
        }
        catch { }

        if (LstDiscoveredVaults.Items.Count == 0)
        {
            LstDiscoveredVaults.Items.Add("(未检测到运行中的 Obsidian 仓库)");
        }
    }

    private void LstDiscoveredVaults_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (LstDiscoveredVaults.SelectedItem is string selected && Directory.Exists(selected))
        {
            TxtVaultPath.Text = selected;
            RbObsidian.IsChecked = true;
        }
    }

    private void BtnBrowseVault_Click(object sender, RoutedEventArgs e)
    {
        using var fbd = new FolderBrowserDialog
        {
            Description = "选择保存目录或 Obsidian 仓库",
            UseDescriptionForTitle = true,
            SelectedPath = TxtVaultPath.Text
        };
        if (fbd.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            TxtVaultPath.Text = fbd.SelectedPath;
            var isObs = Directory.Exists(Path.Combine(fbd.SelectedPath, ".obsidian"));
            RbObsidian.IsChecked = isObs;
            RbPlain.IsChecked = !isObs;
        }
    }

    private void RbObsidian_Checked(object sender, RoutedEventArgs e) => UpdateFormatPreview();
    private void RbPlain_Checked(object sender, RoutedEventArgs e) => UpdateFormatPreview();

    private void CmbFormatStyle_SelectionChanged(object sender, SelectionChangedEventArgs e) => UpdateFormatPreview();

    private void UpdateFormatPreview()
    {
        if (TxtFormatPreview == null) return;

        var selectedTag = (CmbFormatStyle?.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? "verbatim";
        var isObs = RbObsidian?.IsChecked == true;

        var preview = selectedTag switch
        {
            "timestamped" => "**14:32** 地方政府在经济发展中扮演了重要角色。\n> 来源: [置身事内 - 读书笔记](https://example.com/book)",
            "list" => "- 14:32 地方政府在经济发展中扮演了重要角色。 · [置身事内 - 读书笔记](https://example.com/book)",
            "quote" => "> 地方政府在经济发展中扮演了重要角色。\n> — 14:32 · [置身事内 - 读书笔记](https://example.com/book)",
            _ => "地方政府在经济发展中扮演了重要角色。\n> 14:32 · [置身事内 - 读书笔记](https://example.com/book)\n\n" +
                 (isObs ? "![[截屏_20261104_143200.png]]\n> [!note]- 图中文字\n> 好的工具让记录这件事消失"
                        : "![](../附件/截屏_20261104_143200.png)\n<details>\n<summary>图中文字</summary>\n好的工具让记录这件事消失\n</details>")
        };

        TxtFormatPreview.Text = preview;
    }

    private void BtnSaveSettings_Click(object sender, RoutedEventArgs e)
    {
        var s = AppSettings.Current;
        s.VaultPath = TxtVaultPath.Text.Trim();
        s.IsObsidian = RbObsidian.IsChecked == true;
        s.DailyFolder = TxtDailyFolder.Text.Trim();
        s.DailyFormat = TxtDailyFormat.Text.Trim();
        s.PrependEntries = ChkPrependEntries.IsChecked == true;
        s.AttachmentFolder = TxtAttachmentFolder.Text.Trim();

        s.CaptureShortcut = TxtShortcutCapture.Text.Trim();
        s.QuickSaveShortcut = TxtShortcutQuickSave.Text.Trim();
        s.ScreenshotOcrShortcut = TxtShortcutScreenshotOcr.Text.Trim();

        s.EnableOcr = ChkEnableOcr.IsChecked == true;
        s.PlaySound = ChkPlaySound.IsChecked == true;
        s.LaunchAtLogin = ChkLaunchAtLogin.IsChecked == true;

        if (CmbFormatStyle.SelectedItem is ComboBoxItem item && item.Tag != null)
        {
            s.FormatStyle = item.Tag.ToString()!;
        }

        s.Save();

        // Update auto-start registry
        UpdateStartupRegistry(s.LaunchAtLogin);

        // Re-register hotkeys
        App.RegisterGlobalShortcuts();

        // Update quick note window label
        App.QuickNoteWin?.UpdateDestLabel();

        ToastWindow.ShowToast("设置已保存并生效");
        Close();
    }

    private static void UpdateStartupRegistry(bool enable)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true);
            if (key != null)
            {
                var exePath = Process.GetCurrentProcess().MainModule?.FileName;
                if (!string.IsNullOrEmpty(exePath))
                {
                    if (enable)
                    {
                        key.SetValue("QiaomuJot", $"\"{exePath}\"");
                    }
                    else
                    {
                        key.DeleteValue("QiaomuJot", false);
                    }
                }
            }
        }
        catch { }
    }

    private void BtnCancel_Click(object sender, RoutedEventArgs e) => Close();

    private void BtnOpenGithub_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo("https://github.com/joeseesun/qiaomu-jot") { UseShellExecute = true });
        }
        catch { }
    }

    private void BtnSelfTest_Click(object sender, RoutedEventArgs e)
    {
        TxtSelfTestResult.Text = "正在执行自检测试...";
        var (ok, passed, total) = SelfTest.SelfTestRunner.RunInMemory();
        if (ok)
        {
            TxtSelfTestResult.Foreground = System.Windows.Media.Brushes.Green;
            TxtSelfTestResult.Text = $"✓ 自检全部通过! ({passed}/{total} 项测试全部 PASS)";
        }
        else
        {
            TxtSelfTestResult.Foreground = System.Windows.Media.Brushes.Red;
            TxtSelfTestResult.Text = $"✗ 部分自检未通过 ({passed}/{total})";
        }
    }
}
