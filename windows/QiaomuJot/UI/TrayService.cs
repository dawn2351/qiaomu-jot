using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using QiaomuJot.Models;
using QiaomuJot.Services;

namespace QiaomuJot.UI;

public class TrayService : IDisposable
{
    private NotifyIcon? _notifyIcon;

    public void Initialize()
    {
        _notifyIcon = new NotifyIcon
        {
            Text = "乔木闪记 · Jot",
            Visible = true
        };

        // Load icon
        try
        {
            var baseDir = AppDomain.CurrentDomain.BaseDirectory;
            var icoPath = Path.Combine(baseDir, "Resources", "app.ico");
            if (File.Exists(icoPath))
            {
                _notifyIcon.Icon = new Icon(icoPath);
            }
            else
            {
                _notifyIcon.Icon = SystemIcons.Application;
            }
        }
        catch
        {
            _notifyIcon.Icon = SystemIcons.Application;
        }

        // Context menu
        var menu = new ContextMenuStrip();

        var mCapture = new ToolStripMenuItem("随手记 (Win+J)", null, (s, e) => App.ShowQuickNote());
        mCapture.Font = new Font(mCapture.Font, FontStyle.Bold);
        menu.Items.Add(mCapture);

        menu.Items.Add(new ToolStripMenuItem("一键收录选中内容 (Win+K)", null, (s, e) => _ = App.TriggerQuickSave()));
        menu.Items.Add(new ToolStripMenuItem("截图并识别文字 (Alt+Shift+S)", null, (s, e) => _ = App.TriggerScreenshotOcr()));

        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(new ToolStripMenuItem("打开今日日记", null, (s, e) => OpenTodayNote()));
        menu.Items.Add(new ToolStripMenuItem("打开保存目录", null, (s, e) => OpenVaultFolder()));

        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(new ToolStripMenuItem("设置...", null, (s, e) => App.ShowSettings()));
        menu.Items.Add(new ToolStripMenuItem("运行自检测试 (--selftest)", null, (s, e) =>
        {
            var (ok, passed, total) = SelfTest.SelfTestRunner.RunInMemory();
            MessageBox.Show(ok ? $"自检全部通过! ({passed}/{total})" : $"自检失败 ({passed}/{total})", "乔木闪记 自检", MessageBoxButtons.OK, ok ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
        }));

        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(new ToolStripMenuItem("退出 乔木闪记", null, (s, e) => App.Quit()));

        _notifyIcon.ContextMenuStrip = menu;
        _notifyIcon.DoubleClick += (s, e) => App.ShowQuickNote();
    }

    private void OpenTodayNote()
    {
        try
        {
            var note = VaultService.Instance.GetTodayNotePath();
            if (File.Exists(note))
            {
                Process.Start(new ProcessStartInfo(note) { UseShellExecute = true });
            }
            else
            {
                var s = AppSettings.Current;
                if (s.IsObsidian)
                {
                    var vaultName = Path.GetFileName(s.VaultPath.TrimEnd('\\', '/'));
                    Process.Start(new ProcessStartInfo($"obsidian://daily?vault={Uri.EscapeDataString(vaultName)}") { UseShellExecute = true });
                }
                else
                {
                    ToastWindow.ShowToast("今天还没有记录", Path.GetFileName(note));
                }
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show($"打开失败: {ex.Message}", "乔木闪记");
        }
    }

    private void OpenVaultFolder()
    {
        try
        {
            var s = AppSettings.Current;
            var dir = string.IsNullOrWhiteSpace(s.VaultPath) ? 
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "乔木闪记") : 
                s.VaultPath;

            Directory.CreateDirectory(dir);
            Process.Start(new ProcessStartInfo("explorer.exe", dir) { UseShellExecute = true });
        }
        catch { }
    }

    public void Dispose()
    {
        if (_notifyIcon != null)
        {
            _notifyIcon.Visible = false;
            _notifyIcon.Dispose();
            _notifyIcon = null;
        }
    }
}
