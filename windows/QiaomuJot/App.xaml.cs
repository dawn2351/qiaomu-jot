using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using QiaomuJot.Models;
using QiaomuJot.SelfTest;
using QiaomuJot.Services;
using QiaomuJot.UI;
using WpfApplication = System.Windows.Application;

namespace QiaomuJot;

public partial class App : WpfApplication
{
    [DllImport("kernel32.dll")]
    private static extern bool AttachConsole(int dwProcessId);
    private const int ATTACH_PARENT_PROCESS = -1;

    private static Mutex? _mutex;
    private static Window? _messageWindow;
    public static QuickNoteWindow? QuickNoteWin { get; private set; }
    public static SettingsWindow? SettingsWin { get; private set; }
    public static TrayService? Tray { get; private set; }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        if (e.Args.Length > 0 && e.Args[0] == "--selftest")
        {
            AttachConsole(ATTACH_PARENT_PROCESS);
            var (success, passed, total) = SelfTestRunner.RunInMemory();
            Environment.Exit(success ? 0 : 1);
            return;
        }

        if (e.Args.Length > 0 && e.Args[0] == "--install")
        {
            AttachConsole(ATTACH_PARENT_PROCESS);
            var ok = ShortcutHelper.InstallShortcuts();
            Environment.Exit(ok ? 0 : 1);
            return;
        }

        // Single instance check
        _mutex = new Mutex(true, "QiaomuJot_SingleInstance_Mutex", out var isNew);
        if (!isNew)
        {
            Shutdown();
            return;
        }

        // Create invisible window to host Win32 hotkey messages
        _messageWindow = new Window
        {
            Width = 0,
            Height = 0,
            WindowStyle = WindowStyle.None,
            ShowInTaskbar = false,
            Visibility = Visibility.Hidden
        };
        _messageWindow.Show();
        _messageWindow.Hide();

        var hwnd = new WindowInteropHelper(_messageWindow).Handle;
        HotkeyManager.Instance.Initialize(hwnd);

        // Initialize QuickNote window
        QuickNoteWin = new QuickNoteWindow();

        // Initialize Tray Icon
        Tray = new TrayService();
        Tray.Initialize();

        // Register Global Hotkeys
        RegisterGlobalShortcuts();

        // Preload OCR service in background
        _ = Task.Run(() => _ = OcrService.Instance.IsAvailable);

        // Show welcome toast
        var s = AppSettings.Current;
        var vaultName = Path.GetFileName(s.VaultPath.TrimEnd('\\', '/'));
        ToastWindow.ShowToast("乔木闪记 已启动", $"快捷键: {s.CaptureShortcut} 随手记 · {s.QuickSaveShortcut} 一键收录 ({vaultName})");
    }

    public static void RegisterGlobalShortcuts()
    {
        var hk = HotkeyManager.Instance;
        hk.UnregisterAll();

        var s = AppSettings.Current;

        // 1. 随手记 (Alt+Shift+J)
        hk.Register(s.CaptureShortcut, () =>
        {
            Current.Dispatcher.Invoke(ShowQuickNote);
        });

        // 2. 一键收录 (Alt+Shift+K)
        hk.Register(s.QuickSaveShortcut, () =>
        {
            Current.Dispatcher.Invoke(() => _ = TriggerQuickSave());
        });

        // 3. 截屏/图片收录 (Alt+Shift+S)
        hk.Register(s.ScreenshotOcrShortcut, () =>
        {
            Current.Dispatcher.Invoke(() => _ = TriggerScreenshotOcr());
        });
    }

    public static void ShowQuickNote()
    {
        QuickNoteWin ??= new QuickNoteWindow();
        if (QuickNoteWin.IsVisible)
        {
            QuickNoteWin.Hide();
        }
        else
        {
            QuickNoteWin.ShowQuickNote();
        }
    }

    public static void ShowSettings()
    {
        if (SettingsWin == null || !SettingsWin.IsLoaded)
        {
            SettingsWin = new SettingsWindow();
        }
        SettingsWin.Show();
        SettingsWin.Activate();
    }

    public static async Task TriggerQuickSave()
    {
        // 1. Capture foreground app context BEFORE our toast or anything pops up
        var ctx = SelectionGrabber.GetActiveSourceContext();

        // 2. Grab selection or clipboard
        var grab = SelectionGrabber.Grab(ctx);

        if (grab.IsEmpty)
        {
            // Nothing selected and clipboard is empty -> show quick note input
            ShowQuickNote();
            return;
        }

        var sb = new StringBuilder();

        // If has text
        if (!string.IsNullOrWhiteSpace(grab.Text))
        {
            sb.AppendLine(grab.Text);
        }

        // If has image (e.g. copied image or fresh screenshot)
        if (grab.ImageData != null && grab.ImageData.Length > 0)
        {
            string? ocrText = null;
            if (AppSettings.Current.EnableOcr)
            {
                ocrText = await OcrService.Instance.RecognizeImageBytesAsync(grab.ImageData);
            }

            var fileName = VaultService.Instance.SaveAttachment(grab.ImageData, grab.ImageExt ?? ".png");
            var imageMd = VaultService.Instance.FormatImageMarkdown(fileName, ocrText);
            sb.AppendLine(imageMd);
        }

        var rawContent = sb.ToString().TrimEnd();
        var formattedEntry = VaultService.Instance.FormatEntry(rawContent, grab.Context);

        var ok = await VaultService.Instance.AppendEntryAsync(formattedEntry);
        if (ok)
        {
            SoundPlayerService.PlaySuccess();
            var detail = grab.Context?.PageTitle ?? grab.Context?.WindowTitle ?? (rawContent.Length > 30 ? rawContent.Substring(0, 30) + "..." : rawContent);
            ToastWindow.ShowToast(grab.IsFromSelection ? "已收录选中内容" : "已收录剪贴板内容", detail);
        }
        else
        {
            ToastWindow.ShowToast("收录失败", "请检查日记文件保存路径");
        }
    }

    public static async Task TriggerScreenshotOcr()
    {
        // Check clipboard for image first
        var grab = SelectionGrabber.Grab();
        if (grab.ImageData != null && grab.ImageData.Length > 0)
        {
            string? ocrText = null;
            if (AppSettings.Current.EnableOcr)
            {
                ocrText = await OcrService.Instance.RecognizeImageBytesAsync(grab.ImageData);
            }

            var fileName = VaultService.Instance.SaveAttachment(grab.ImageData, grab.ImageExt ?? ".png");
            var imageMd = VaultService.Instance.FormatImageMarkdown(fileName, ocrText);
            var entry = VaultService.Instance.FormatEntry(imageMd, grab.Context);

            var ok = await VaultService.Instance.AppendEntryAsync(entry);
            if (ok)
            {
                SoundPlayerService.PlaySuccess();
                ToastWindow.ShowToast("已收录截图并识别文字", !string.IsNullOrWhiteSpace(ocrText) ? $"识别文字: {(ocrText.Length > 25 ? ocrText.Substring(0, 25) + "..." : ocrText)}" : fileName);
            }
        }
        else
        {
            ToastWindow.ShowToast("未检测到剪贴板图片", "按 Win+Shift+S 截图后，再按 Alt+Shift+S 即可自动收录识别");
        }
    }

    public static void Quit()
    {
        Tray?.Dispose();
        HotkeyManager.Instance.Dispose();
        _mutex?.ReleaseMutex();
        _mutex?.Dispose();
        Current?.Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        Tray?.Dispose();
        HotkeyManager.Instance.Dispose();
        base.OnExit(e);
    }
}
