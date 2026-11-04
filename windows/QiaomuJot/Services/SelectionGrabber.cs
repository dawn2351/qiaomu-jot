using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Automation;
using System.Windows.Media.Imaging;
using QiaomuJot.Models;
using Clipboard = System.Windows.Clipboard;
using IDataObject = System.Windows.IDataObject;

namespace QiaomuJot.Services;

public class GrabResult
{
    public string Text { get; set; } = string.Empty;
    public byte[]? ImageData { get; set; }
    public string? ImageExt { get; set; }
    public string[]? Files { get; set; }
    public SourceContext? Context { get; set; }
    public bool IsFromSelection { get; set; }
    public bool IsEmpty => string.IsNullOrWhiteSpace(Text) && (ImageData == null || ImageData.Length == 0) && (Files == null || Files.Length == 0);
}

public static class SelectionGrabber
{
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);

    private const byte VK_CONTROL = 0x11;
    private const byte VK_C = 0x43;
    private const uint KEYEVENTF_KEYUP = 0x0002;

    public static SourceContext? GetActiveSourceContext()
    {
        var hWnd = GetForegroundWindow();
        if (hWnd == IntPtr.Zero) return null;

        GetWindowThreadProcessId(hWnd, out var pid);
        if (pid == 0 || pid == Environment.ProcessId) return null;

        try
        {
            var proc = Process.GetProcessById((int)pid);
            var procName = proc.ProcessName;

            var sb = new StringBuilder(512);
            GetWindowText(hWnd, sb, 512);
            var title = sb.ToString();

            var kind = SourceContext.ClassifyProcess(procName);
            var ctx = new SourceContext
            {
                AppName = procName,
                ProcessName = procName,
                Kind = kind,
                WindowTitle = title
            };

            // Enhance AppName
            ctx.AppName = procName.ToLowerInvariant() switch
            {
                "chrome" => "Google Chrome",
                "msedge" => "Microsoft Edge",
                "firefox" => "Firefox",
                "brave" => "Brave",
                "code" => "VS Code",
                "cursor" => "Cursor",
                "windsurf" => "Windsurf",
                "obsidian" => "Obsidian",
                "wechat" => "微信",
                _ => procName
            };

            if (kind == SourceKind.Browser)
            {
                ctx.PageTitle = SourceContext.CleanBrowserTitle(title, ctx.AppName);
                ctx.Url = TryGetBrowserUrl(hWnd, procName);
            }
            else if (kind == SourceKind.Code)
            {
                ctx.FileName = SourceContext.ExtractFileNameFromTitle(title);
            }

            return ctx;
        }
        catch
        {
            return null;
        }
    }

    public static string? TryGetBrowserUrl(IntPtr hWnd, string procName)
    {
        try
        {
            var p = procName.ToLowerInvariant();
            if (p is not ("chrome" or "msedge" or "brave" or "vivaldi"))
                return null;

            var element = AutomationElement.FromHandle(hWnd);
            if (element == null) return null;

            // Search for edit control in the browser toolbar/address bar
            var condition = new AndCondition(
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Edit),
                new PropertyCondition(AutomationElement.IsKeyboardFocusableProperty, true)
            );

            var editElements = element.FindAll(TreeScope.Descendants, condition);
            foreach (AutomationElement edit in editElements)
            {
                if (edit.TryGetCurrentPattern(ValuePattern.Pattern, out var vpObj) && vpObj is ValuePattern vp)
                {
                    var val = vp.Current.Value;
                    if (!string.IsNullOrWhiteSpace(val) && (val.StartsWith("http://") || val.StartsWith("https://") || val.Contains(".com") || val.Contains(".org") || val.Contains(".cn") || val.Contains(".net") || val.Contains(".io") || val.Contains("/")))
                    {
                        if (!val.StartsWith("http://") && !val.StartsWith("https://"))
                        {
                            val = "https://" + val;
                        }
                        return val;
                    }
                }
            }
        }
        catch { }

        return null;
    }

    public static GrabResult Grab(SourceContext? ctx = null)
    {
        var context = ctx ?? GetActiveSourceContext();
        var result = new GrabResult { Context = context };

        // 1. Try synthetic copy to grab selection
        string? originalText = null;
        IDataObject? originalData = null;

        try
        {
            if (Clipboard.ContainsText()) originalText = Clipboard.GetText();
            originalData = Clipboard.GetDataObject();
        }
        catch { }

        // Clear clipboard temporarily so we know if Ctrl+C produced something new
        try { Clipboard.Clear(); } catch { }

        // Send Ctrl+C
        keybd_event(VK_CONTROL, 0, 0, 0);
        keybd_event(VK_C, 0, 0, 0);
        Thread.Sleep(30);
        keybd_event(VK_C, 0, KEYEVENTF_KEYUP, 0);
        keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, 0);

        // Poll for clipboard change up to 150ms
        bool copied = false;
        string? copiedText = null;
        for (int i = 0; i < 6; i++)
        {
            Thread.Sleep(25);
            try
            {
                if (Clipboard.ContainsText())
                {
                    copiedText = Clipboard.GetText();
                    if (!string.IsNullOrEmpty(copiedText))
                    {
                        copied = true;
                        break;
                    }
                }
            }
            catch { }
        }

        if (copied && !string.IsNullOrWhiteSpace(copiedText))
        {
            result.Text = copiedText.Trim();
            result.IsFromSelection = true;

            // Restore original clipboard so we don't pollute user's clipboard
            try
            {
                if (originalData != null) Clipboard.SetDataObject(originalData, true);
                else if (originalText != null) Clipboard.SetText(originalText);
            }
            catch { }

            return result;
        }

        // Restore original clipboard if nothing copied
        try
        {
            if (originalData != null) Clipboard.SetDataObject(originalData, true);
            else if (originalText != null) Clipboard.SetText(originalText);
        }
        catch { }

        // 2. If nothing selected, grab whatever was already in clipboard!
        try
        {
            if (Clipboard.ContainsImage())
            {
                var image = Clipboard.GetImage();
                if (image != null)
                {
                    using var ms = new MemoryStream();
                    var encoder = new PngBitmapEncoder();
                    encoder.Frames.Add(BitmapFrame.Create(image));
                    encoder.Save(ms);
                    result.ImageData = ms.ToArray();
                    result.ImageExt = ".png";
                    result.IsFromSelection = false;
                    return result;
                }
            }

            if (Clipboard.ContainsFileDropList())
            {
                var files = Clipboard.GetFileDropList();
                if (files.Count > 0)
                {
                    var fileList = new string[files.Count];
                    files.CopyTo(fileList, 0);
                    result.Files = fileList;
                    result.IsFromSelection = false;
                    return result;
                }
            }

            if (Clipboard.ContainsText())
            {
                var text = Clipboard.GetText();
                if (!string.IsNullOrWhiteSpace(text))
                {
                    result.Text = text.Trim();
                    result.IsFromSelection = false;
                    return result;
                }
            }
        }
        catch { }

        // 3. Check for recently taken screenshot in Screenshots folder
        try
        {
            var pictures = Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
            var screenshots = Path.Combine(pictures, "Screenshots");
            if (Directory.Exists(screenshots))
            {
                var di = new DirectoryInfo(screenshots);
                var latest = di.GetFiles("*.png").OrderByDescending(f => f.LastWriteTime).FirstOrDefault();
                if (latest != null && (DateTime.Now - latest.LastWriteTime).TotalSeconds < 120)
                {
                    result.ImageData = File.ReadAllBytes(latest.FullName);
                    result.ImageExt = ".png";
                    result.IsFromSelection = false;
                    return result;
                }
            }
        }
        catch { }

        return result;
    }
}
