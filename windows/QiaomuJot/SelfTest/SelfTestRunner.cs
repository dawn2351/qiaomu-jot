using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using QiaomuJot.Models;
using QiaomuJot.Services;

namespace QiaomuJot.SelfTest;

public static class SelfTestRunner
{
    public static (bool success, int passed, int total) RunInMemory()
    {
        return Task.Run(RunAsync).GetAwaiter().GetResult();
    }

    public static async Task<(bool success, int passed, int total)> RunAsync()
    {
        try
        {
            Console.OutputEncoding = Encoding.UTF8;
        }
        catch { }

        int passed = 0;
        int failed = 0;

        void Assert(string name, bool condition, string detail = "")
        {
            if (condition)
            {
                passed++;
                Console.WriteLine($"✓ {name}");
            }
            else
            {
                failed++;
                Console.WriteLine($"✗ {name}: {detail}");
            }
        }

        Console.WriteLine("=== 乔木闪记 · Jot Windows版 自检开始 ===");

        // 1. Settings & Vault Test
        var s = AppSettings.Current;
        Assert("AppSettings loaded", s != null);
        Assert("Vault path configured", !string.IsNullOrWhiteSpace(s?.VaultPath));

        // 2. Source Context & Title Cleaning
        Assert("Clean Chrome title", SourceContext.CleanBrowserTitle("GitHub - joeseesun/qiaomu-jot - Google Chrome", "Google Chrome") == "GitHub - joeseesun/qiaomu-jot");
        Assert("Clean Edge title", SourceContext.CleanBrowserTitle("百度一下，你就知道 - Microsoft Edge", "Microsoft Edge") == "百度一下，你就知道");
        Assert("Extract VS Code file", SourceContext.ExtractFileNameFromTitle("● main.swift — qiaomu-ob-helper") == "main.swift");
        Assert("Extract C# file", SourceContext.ExtractFileNameFromTitle("AppSettings.cs - QiaomuJot - Visual Studio Code") == "AppSettings.cs");

        // 3. Source Markdown format
        var src = new SourceContext
        {
            AppName = "Google Chrome",
            Url = "https://github.com/joeseesun/qiaomu-jot",
            PageTitle = "乔木闪记 Jot [官方]"
        };
        Assert("Web source markdown", src.ToMarkdownSource() == "[乔木闪记 Jot \\[官方\\]](https://github.com/joeseesun/qiaomu-jot)");

        // 4. Hotkey parsing
        Assert("Parse Win+J", HotkeyManager.ParseShortcut("Win+J", out var modW, out var vkW) && modW == 8 && vkW == 'J');
        Assert("Parse Win+K", HotkeyManager.ParseShortcut("Win+K", out var modK, out var vkK) && modK == 8 && vkK == 'K');
        Assert("Parse Alt+Shift+J", HotkeyManager.ParseShortcut("Alt+Shift+J", out var mod1, out var vk1) && mod1 == 5 && vk1 == 'J');
        Assert("Parse Alt+Shift+K", HotkeyManager.ParseShortcut("Alt+Shift+K", out var mod2, out var vk2) && mod2 == 5 && vk2 == 'K');
        Assert("Parse Ctrl+Shift+S", HotkeyManager.ParseShortcut("Ctrl+Shift+S", out var mod3, out var vk3) && mod3 == 6 && vk3 == 'S');

        // 5. Daily Note Writing & Atomic Undo test
        var tempDir = Path.Combine(Path.GetTempPath(), "QiaomuJot_Test_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDir);
        try
        {
            var oldVault = s!.VaultPath;
            var oldIsObsidian = s.IsObsidian;
            s.VaultPath = tempDir;
            s.IsObsidian = true;

            var todayNote = VaultService.Instance.GetTodayNotePath();
            Assert("Today note path valid", todayNote.EndsWith(".md"));

            var entryText = "地方政府不只是“守夜人”，而是深度参与经济发展的“运动员”。";
            var formatted = VaultService.Instance.FormatEntry(entryText, src);
            var writeOk = await VaultService.Instance.AppendEntryAsync(formatted);
            Assert("Append entry to daily note", writeOk && File.Exists(todayNote));

            var content = await File.ReadAllTextAsync(todayNote);
            Assert("Daily note contains entry", content.Contains(entryText));

            // Test Undo
            var undoOk = VaultService.Instance.UndoLast();
            Assert("Undo last entry", undoOk);
            var contentAfterUndo = await File.ReadAllTextAsync(todayNote);
            Assert("Content restored after undo", !contentAfterUndo.Contains(entryText));

            // Restore
            s.VaultPath = oldVault;
            s.IsObsidian = oldIsObsidian;
        }
        finally
        {
            try { Directory.Delete(tempDir, true); } catch { }
        }

        // 6. Native OCR Test
        var ocr = OcrService.Instance;
        Assert("Native OCR engine initialized", ocr.IsAvailable, $"Lang: {ocr.LanguageTag}");
        if (ocr.IsAvailable)
        {
            try
            {
                // Generate a clear test image in memory
                using var bmp = new Bitmap(300, 80);
                using (var g = Graphics.FromImage(bmp))
                {
                    g.Clear(Color.White);
                    using var brush = new SolidBrush(Color.Black);
                    using var font = new Font("Arial", 20, FontStyle.Bold);
                    g.DrawString("Jot OCR 2026", font, brush, new PointF(10, 20));
                }
                using var ms = new MemoryStream();
                bmp.Save(ms, ImageFormat.Png);
                var ocrText = await ocr.RecognizeImageBytesAsync(ms.ToArray());
                Assert("OCR recognize test text", ocrText.Contains("Jot") || ocrText.Contains("OCR") || ocrText.Contains("2026"), $"Got: '{ocrText}'");
            }
            catch (Exception ex)
            {
                Assert("OCR execution", false, ex.Message);
            }
        }

        int total = passed + failed;
        Console.WriteLine($"=== 自检完成: {passed}/{total} 项通过 ===");
        if (failed == 0)
        {
            Console.WriteLine("ALL PASS");
        }

        return (failed == 0, passed, total);
    }
}
