using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using QiaomuJot.Models;
using QiaomuJot.Services;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using DragEventArgs = System.Windows.DragEventArgs;
using Clipboard = System.Windows.Clipboard;
using DataFormats = System.Windows.DataFormats;
using OpenFileDialog = Microsoft.Win32.OpenFileDialog;
using MessageBox = System.Windows.MessageBox;

namespace QiaomuJot.UI;

public partial class QuickNoteWindow : Window
{
    private byte[]? _pendingImageData;
    private string? _pendingImageExt;
    private string? _pendingOcrText;
    private bool _isPreviewMode = false;

    public QuickNoteWindow()
    {
        InitializeComponent();
        Loaded += QuickNoteWindow_Loaded;
    }

    private void QuickNoteWindow_Loaded(object sender, RoutedEventArgs e)
    {
        UpdateDestLabel();
        if (!string.IsNullOrEmpty(AppSettings.Current.Draft))
        {
            TxtInput.Text = AppSettings.Current.Draft;
            TxtInput.SelectionStart = TxtInput.Text.Length;
        }
    }

    public void ShowQuickNote()
    {
        UpdateDestLabel();
        if (Visibility != Visibility.Visible)
        {
            Show();
        }
        WindowState = WindowState.Normal;
        Activate();
        TxtInput.Focus();
    }

    public void UpdateDestLabel()
    {
        var s = AppSettings.Current;
        var today = DateTime.Now.ToString("yyyy-MM-dd");
        if (s.IsObsidian)
        {
            var vaultName = Path.GetFileName(s.VaultPath.TrimEnd('\\', '/'));
            TxtDest.Text = $"{vaultName} · 今日日记 ({today})";
        }
        else
        {
            TxtDest.Text = $"今日日记 ({today}.md)";
        }
    }

    private void Window_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            Hide();
            SaveDraft();
            e.Handled = true;
        }
        else if (e.Key == Key.Enter && (Keyboard.Modifiers & ModifierKeys.Control) == ModifierKeys.Control)
        {
            _ = SaveAndCloseAsync();
            e.Handled = true;
        }
    }

    private void TxtInput_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        var ctrl = (Keyboard.Modifiers & ModifierKeys.Control) == ModifierKeys.Control;

        if (e.Key == Key.V && ctrl)
        {
            // Intercept paste to check for image
            if (Clipboard.ContainsImage())
            {
                var img = Clipboard.GetImage();
                if (img != null)
                {
                    HandlePastedImage(img);
                    e.Handled = true;
                    return;
                }
            }
        }
        else if (e.Key == Key.B && ctrl)
        {
            MarkdownEditorHelper.WrapSelection(TxtInput, "**", "**");
            e.Handled = true;
        }
        else if (e.Key == Key.I && ctrl)
        {
            MarkdownEditorHelper.WrapSelection(TxtInput, "*", "*");
            e.Handled = true;
        }
        else if (e.Key == Key.K && ctrl)
        {
            MarkdownEditorHelper.InsertOrWrapLink(TxtInput);
            e.Handled = true;
        }
        else if (e.Key == Key.E && ctrl)
        {
            MarkdownEditorHelper.WrapSelection(TxtInput, "`", "`");
            e.Handled = true;
        }
        else if (e.Key == Key.P && ctrl)
        {
            TogglePreview();
            e.Handled = true;
        }
        else if ((e.Key == Key.D1 || e.Key == Key.NumPad1) && ctrl)
        {
            MarkdownEditorHelper.ToggleHeading(TxtInput, 1);
            e.Handled = true;
        }
        else if ((e.Key == Key.D2 || e.Key == Key.NumPad2) && ctrl)
        {
            MarkdownEditorHelper.ToggleHeading(TxtInput, 2);
            e.Handled = true;
        }
        else if ((e.Key == Key.D3 || e.Key == Key.NumPad3) && ctrl)
        {
            MarkdownEditorHelper.ToggleHeading(TxtInput, 3);
            e.Handled = true;
        }
        else if (e.Key == Key.Enter && !ctrl)
        {
            if (MarkdownEditorHelper.HandleEnterKey(TxtInput))
            {
                e.Handled = true;
            }
        }
    }

    private void TxtInput_TextChanged(object sender, TextChangedEventArgs e)
    {
        var text = TxtInput.Text ?? "";
        TxtPlaceholder.Visibility = string.IsNullOrEmpty(text) ? Visibility.Visible : Visibility.Collapsed;
        TxtCharCount.Text = $"{text.Length} 字";

        if (_isPreviewMode)
        {
            TxtPreviewContent.Text = text;
        }
    }

    private async void HandlePastedImage(BitmapSource img)
    {
        try
        {
            using var ms = new MemoryStream();
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(img));
            encoder.Save(ms);
            _pendingImageData = ms.ToArray();
            _pendingImageExt = ".png";

            PanelAttachments.Visibility = Visibility.Visible;
            TxtAttachmentInfo.Text = "📷 剪贴板图片已附加，正在本地 OCR 识别...";

            if (AppSettings.Current.EnableOcr)
            {
                _pendingOcrText = await OcrService.Instance.RecognizeImageBytesAsync(_pendingImageData);
                if (!string.IsNullOrWhiteSpace(_pendingOcrText))
                {
                    TxtAttachmentInfo.Text = $"📷 截图已附加 (已识别 {_pendingOcrText.Length} 字)";
                }
                else
                {
                    TxtAttachmentInfo.Text = "📷 截图已附加 (未发现文字)";
                }
            }
            else
            {
                TxtAttachmentInfo.Text = "📷 截图已附加";
            }
        }
        catch { }
    }

    private void TxtInput_Drop(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent(DataFormats.FileDrop))
        {
            var files = (string[])e.Data.GetData(DataFormats.FileDrop);
            if (files != null && files.Length > 0)
            {
                var f = files[0];
                var ext = Path.GetExtension(f).ToLowerInvariant();
                if (ext is ".png" or ".jpg" or ".jpeg" or ".bmp" or ".webp")
                {
                    try
                    {
                        _pendingImageData = File.ReadAllBytes(f);
                        _pendingImageExt = ext;
                        PanelAttachments.Visibility = Visibility.Visible;
                        TxtAttachmentInfo.Text = $"📷 附加图片: {Path.GetFileName(f)}";

                        if (AppSettings.Current.EnableOcr)
                        {
                            _ = Task.Run(async () =>
                            {
                                _pendingOcrText = await OcrService.Instance.RecognizeImageFileAsync(f);
                                Dispatcher.Invoke(() =>
                                {
                                    if (!string.IsNullOrWhiteSpace(_pendingOcrText))
                                        TxtAttachmentInfo.Text = $"📷 {Path.GetFileName(f)} (已识别 {_pendingOcrText.Length} 字)";
                                });
                            });
                        }
                    }
                    catch { }
                }
            }
        }
    }

    private void BtnRemoveAttachment_Click(object sender, RoutedEventArgs e)
    {
        _pendingImageData = null;
        _pendingImageExt = null;
        _pendingOcrText = null;
        PanelAttachments.Visibility = Visibility.Collapsed;
    }

    private void BtnBold_Click(object sender, RoutedEventArgs e) => MarkdownEditorHelper.WrapSelection(TxtInput, "**", "**");
    private void BtnItalic_Click(object sender, RoutedEventArgs e) => MarkdownEditorHelper.WrapSelection(TxtInput, "*", "*");
    private void BtnHeading_Click(object sender, RoutedEventArgs e) => MarkdownEditorHelper.ToggleHeading(TxtInput, null);
    private void BtnLink_Click(object sender, RoutedEventArgs e) => MarkdownEditorHelper.InsertOrWrapLink(TxtInput);
    private void BtnCode_Click(object sender, RoutedEventArgs e) => MarkdownEditorHelper.WrapSelection(TxtInput, "`", "`");
    private void BtnQuote_Click(object sender, RoutedEventArgs e) => MarkdownEditorHelper.ToggleLinePrefix(TxtInput, "> ");
    private void BtnList_Click(object sender, RoutedEventArgs e) => MarkdownEditorHelper.ToggleLinePrefix(TxtInput, "- ");
    private void BtnTask_Click(object sender, RoutedEventArgs e) => MarkdownEditorHelper.ToggleLinePrefix(TxtInput, "- [ ] ");

    private void BtnAddImage_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog
        {
            Title = "选择图片",
            Filter = "图片文件 (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp|所有文件 (*.*)|*.*"
        };
        if (dlg.ShowDialog() == true)
        {
            try
            {
                _pendingImageData = File.ReadAllBytes(dlg.FileName);
                _pendingImageExt = Path.GetExtension(dlg.FileName);
                PanelAttachments.Visibility = Visibility.Visible;
                TxtAttachmentInfo.Text = $"📷 附加图片: {Path.GetFileName(dlg.FileName)}";

                if (AppSettings.Current.EnableOcr)
                {
                    _ = Task.Run(async () =>
                    {
                        _pendingOcrText = await OcrService.Instance.RecognizeImageFileAsync(dlg.FileName);
                        Dispatcher.Invoke(() =>
                        {
                            if (!string.IsNullOrWhiteSpace(_pendingOcrText))
                                TxtAttachmentInfo.Text = $"📷 {Path.GetFileName(dlg.FileName)} (已识别 {_pendingOcrText.Length} 字)";
                        });
                    });
                }
            }
            catch { }
        }
    }

    private void BtnTogglePreview_Click(object sender, RoutedEventArgs e) => TogglePreview();

    private void TogglePreview()
    {
        _isPreviewMode = !_isPreviewMode;
        if (_isPreviewMode)
        {
            TxtPreviewContent.Text = TxtInput.Text;
            BorderPreview.Visibility = Visibility.Visible;
            TxtInput.Visibility = Visibility.Collapsed;
            BtnTogglePreview.Content = "✎ 编辑";
        }
        else
        {
            BorderPreview.Visibility = Visibility.Collapsed;
            TxtInput.Visibility = Visibility.Visible;
            BtnTogglePreview.Content = "👁 预览";
            TxtInput.Focus();
        }
    }

    private void BtnSettings_Click(object sender, RoutedEventArgs e)
    {
        App.ShowSettings();
    }

    private void DestPill_Click(object sender, MouseButtonEventArgs e)
    {
        App.ShowSettings();
    }

    private void BtnClose_Click(object sender, RoutedEventArgs e)
    {
        SaveDraft();
        Hide();
    }

    private void SaveDraft()
    {
        AppSettings.Current.Draft = TxtInput.Text ?? "";
        AppSettings.Current.Save();
    }

    private async void BtnSave_Click(object sender, RoutedEventArgs e)
    {
        await SaveAndCloseAsync();
    }

    public async Task SaveAndCloseAsync()
    {
        var text = TxtInput.Text?.Trim() ?? "";
        if (string.IsNullOrEmpty(text) && _pendingImageData == null)
        {
            Hide();
            return;
        }

        var sb = new StringBuilder();
        if (!string.IsNullOrEmpty(text))
        {
            sb.AppendLine(text);
        }

        if (_pendingImageData != null && _pendingImageData.Length > 0)
        {
            var fileName = VaultService.Instance.SaveAttachment(_pendingImageData, _pendingImageExt ?? ".png");
            var imageMd = VaultService.Instance.FormatImageMarkdown(fileName, _pendingOcrText);
            sb.AppendLine(imageMd);
        }

        var entry = VaultService.Instance.FormatEntry(sb.ToString().TrimEnd());
        var ok = await VaultService.Instance.AppendEntryAsync(entry);

        if (ok)
        {
            SoundPlayerService.PlaySuccess();
            ToastWindow.ShowToast("已存入今日日记", text.Length > 30 ? text.Substring(0, 30) + "..." : text);

            // Clear draft and input
            TxtInput.Text = "";
            AppSettings.Current.Draft = "";
            AppSettings.Current.Save();

            _pendingImageData = null;
            _pendingImageExt = null;
            _pendingOcrText = null;
            PanelAttachments.Visibility = Visibility.Collapsed;

            Hide();
        }
        else
        {
            MessageBox.Show("保存失败，请检查保存目录权限或配置。", "乔木闪记", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
}
