using System;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Text;
using System.Threading.Tasks;
using Windows.Globalization;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;

namespace QiaomuJot.Services;

public class OcrService
{
    private static OcrService? _instance;
    public static OcrService Instance => _instance ??= new OcrService();

    private OcrEngine? _engine;
    public bool IsAvailable => _engine != null;
    public string? LanguageTag => _engine?.RecognizerLanguage?.LanguageTag;

    public OcrService()
    {
        InitializeEngine();
    }

    private void InitializeEngine()
    {
        try
        {
            // Try zh-Hans-CN first
            var zhLang = new Language("zh-Hans-CN");
            if (OcrEngine.IsLanguageSupported(zhLang))
            {
                _engine = OcrEngine.TryCreateFromLanguage(zhLang);
            }

            // Fallback to en-US or UserProfileLanguages
            if (_engine == null)
            {
                var enLang = new Language("en-US");
                if (OcrEngine.IsLanguageSupported(enLang))
                {
                    _engine = OcrEngine.TryCreateFromLanguage(enLang);
                }
            }

            // Fallback to first available recognizer
            if (_engine == null)
            {
                var first = OcrEngine.AvailableRecognizerLanguages.FirstOrDefault();
                if (first != null)
                {
                    _engine = OcrEngine.TryCreateFromLanguage(first);
                }
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Failed to init OCR engine: {ex.Message}");
        }
    }

    public async Task<string> RecognizeImageFileAsync(string imagePath)
    {
        if (_engine == null || !File.Exists(imagePath))
            return string.Empty;

        try
        {
            var bytes = await File.ReadAllBytesAsync(imagePath).ConfigureAwait(false);
            return await RecognizeImageBytesAsync(bytes).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"OCR error for {imagePath}: {ex.Message}");
            return string.Empty;
        }
    }

    public async Task<string> RecognizeImageBytesAsync(byte[] imageBytes)
    {
        if (_engine == null || imageBytes == null || imageBytes.Length == 0)
            return string.Empty;

        try
        {
            using var stream = new InMemoryRandomAccessStream();
            await stream.WriteAsync(imageBytes.AsBuffer()).AsTask().ConfigureAwait(false);
            stream.Seek(0);

            var decoder = await BitmapDecoder.CreateAsync(stream).AsTask().ConfigureAwait(false);
            var softwareBitmap = await decoder.GetSoftwareBitmapAsync().AsTask().ConfigureAwait(false);

            // Convert bitmap to Bgra8 if needed
            if (softwareBitmap.BitmapPixelFormat != BitmapPixelFormat.Bgra8 ||
                softwareBitmap.BitmapAlphaMode != BitmapAlphaMode.Premultiplied)
            {
                softwareBitmap = SoftwareBitmap.Convert(
                    softwareBitmap,
                    BitmapPixelFormat.Bgra8,
                    BitmapAlphaMode.Premultiplied);
            }

            var ocrResult = await _engine.RecognizeAsync(softwareBitmap).AsTask().ConfigureAwait(false);
            if (ocrResult == null || ocrResult.Lines.Count == 0)
                return string.Empty;

            var sb = new StringBuilder();
            foreach (var line in ocrResult.Lines)
            {
                if (!string.IsNullOrWhiteSpace(line.Text))
                {
                    sb.AppendLine(line.Text.Trim());
                }
            }

            return sb.ToString().TrimEnd();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"OCR recognition error: {ex.Message}");
            return string.Empty;
        }
    }
}
