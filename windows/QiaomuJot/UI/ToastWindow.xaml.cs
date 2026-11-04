using System;
using System.Windows;
using System.Windows.Threading;
using QiaomuJot.Services;
using WpfApplication = System.Windows.Application;

namespace QiaomuJot.UI;

public partial class ToastWindow : Window
{
    private static ToastWindow? _current;
    private DispatcherTimer? _timer;

    public ToastWindow(string title, string detail)
    {
        InitializeComponent();
        TxtTitle.Text = title;
        TxtDetail.Text = detail;
        TxtDetail.Visibility = string.IsNullOrWhiteSpace(detail) ? Visibility.Collapsed : Visibility.Visible;

        Loaded += ToastWindow_Loaded;
    }

    private void ToastWindow_Loaded(object sender, RoutedEventArgs e)
    {
        // Position at bottom-right of screen
        var workArea = SystemParameters.WorkArea;
        Left = workArea.Right - Width - 20;
        Top = workArea.Bottom - Height - 20;

        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2.8) };
        _timer.Tick += (s, ev) =>
        {
            _timer.Stop();
            Close();
            if (_current == this) _current = null;
        };
        _timer.Start();
    }

    public static void ShowToast(string title, string detail = "")
    {
        WpfApplication.Current?.Dispatcher.Invoke(() =>
        {
            try
            {
                _current?.Close();
                _current = new ToastWindow(title, detail);
                _current.Show();
            }
            catch { }
        });
    }

    private void BtnUndo_Click(object sender, RoutedEventArgs e)
    {
        _timer?.Stop();
        var ok = VaultService.Instance.UndoLast();
        if (ok)
        {
            TxtTitle.Text = "已成功撤销上一条记录";
            TxtDetail.Text = "";
            BtnUndo.Visibility = Visibility.Collapsed;

            var closeTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.2) };
            closeTimer.Tick += (s, ev) =>
            {
                closeTimer.Stop();
                Close();
                if (_current == this) _current = null;
            };
            closeTimer.Start();
        }
        else
        {
            TxtTitle.Text = "撤销失败";
            TxtDetail.Text = "文件已被修改或未找到记录";
        }
    }
}
