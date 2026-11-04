using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Windows.Interop;

namespace QiaomuJot.Services;

public class HotkeyManager : IDisposable
{
    private static HotkeyManager? _instance;
    public static HotkeyManager Instance => _instance ??= new HotkeyManager();

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_HOTKEY = 0x0312;

    private const int VK_LWIN = 0x5B;
    private const int VK_RWIN = 0x5C;
    private const int VK_CONTROL = 0x11;
    private const int VK_MENU = 0x12; // Alt
    private const int VK_SHIFT = 0x10;

    public const uint MOD_ALT = 0x0001;
    public const uint MOD_CONTROL = 0x0002;
    public const uint MOD_SHIFT = 0x0004;
    public const uint MOD_WIN = 0x0008;
    public const uint MOD_NOREPEAT = 0x4000;

    private readonly Dictionary<int, Action> _handlers = new();
    private readonly List<(uint modifiers, uint vk, Action action)> _hookShortcuts = new();

    private int _currentId = 1000;
    private HwndSource? _source;
    private IntPtr _handle;

    private LowLevelKeyboardProc? _hookProc;
    private IntPtr _hookId = IntPtr.Zero;

    public void Initialize(IntPtr windowHandle)
    {
        _handle = windowHandle;
        _source = HwndSource.FromHwnd(_handle);
        _source?.AddHook(HwndHook);
    }

    public bool Register(string shortcutString, Action action)
    {
        if (!ParseShortcut(shortcutString, out var modifiers, out var vk)) return false;

        // If the shortcut uses the Win key (such as Win+J or Win+K),
        // we use a low-level keyboard hook so we can intercept it cleanly
        // and suppress default Windows shell actions (e.g. Win+K Cast flyout).
        if ((modifiers & MOD_WIN) != 0)
        {
            _hookShortcuts.Add((modifiers, vk, action));
            EnsureHookInstalled();
            return true;
        }

        if (_handle == IntPtr.Zero) return false;

        var id = ++_currentId;
        if (RegisterHotKey(_handle, id, modifiers | MOD_NOREPEAT, vk))
        {
            _handlers[id] = action;
            return true;
        }

        // Fallback to hook if RegisterHotKey failed
        _hookShortcuts.Add((modifiers, vk, action));
        EnsureHookInstalled();
        return true;
    }

    public void UnregisterAll()
    {
        if (_handle != IntPtr.Zero)
        {
            foreach (var id in _handlers.Keys)
            {
                UnregisterHotKey(_handle, id);
            }
        }
        _handlers.Clear();
        _hookShortcuts.Clear();

        if (_hookId != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_hookId);
            _hookId = IntPtr.Zero;
        }
    }

    private void EnsureHookInstalled()
    {
        if (_hookId == IntPtr.Zero)
        {
            _hookProc = HookCallback;
            using var curProcess = Process.GetCurrentProcess();
            using var curModule = curProcess.MainModule;
            var hMod = GetModuleHandle(curModule?.ModuleName);
            _hookId = SetWindowsHookEx(WH_KEYBOARD_LL, _hookProc, hMod, 0);
        }
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && (wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN))
        {
            int vkCode = Marshal.ReadInt32(lParam);

            bool win = (GetAsyncKeyState(VK_LWIN) & 0x8000) != 0 || (GetAsyncKeyState(VK_RWIN) & 0x8000) != 0;
            bool alt = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
            bool ctrl = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
            bool shift = (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;

            uint currentMods = 0;
            if (alt) currentMods |= MOD_ALT;
            if (ctrl) currentMods |= MOD_CONTROL;
            if (shift) currentMods |= MOD_SHIFT;
            if (win) currentMods |= MOD_WIN;

            foreach (var (mod, key, act) in _hookShortcuts)
            {
                if (key == vkCode && mod == currentMods)
                {
                    // Suppress key event from reaching Windows shell and execute action
                    Task.Run(act);
                    return (IntPtr)1;
                }
            }
        }

        return CallNextHookEx(_hookId, nCode, wParam, lParam);
    }

    private IntPtr HwndHook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY)
        {
            int id = wParam.ToInt32();
            if (_handlers.TryGetValue(id, out var action))
            {
                action?.Invoke();
                handled = true;
            }
        }
        return IntPtr.Zero;
    }

    public static bool ParseShortcut(string shortcut, out uint modifiers, out uint vk)
    {
        modifiers = 0;
        vk = 0;
        if (string.IsNullOrWhiteSpace(shortcut)) return false;

        var parts = shortcut.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        string? keyPart = null;

        foreach (var part in parts)
        {
            var p = part.ToLowerInvariant();
            if (p is "alt") modifiers |= MOD_ALT;
            else if (p is "ctrl" or "control") modifiers |= MOD_CONTROL;
            else if (p is "shift") modifiers |= MOD_SHIFT;
            else if (p is "win" or "windows") modifiers |= MOD_WIN;
            else keyPart = part;
        }

        if (string.IsNullOrEmpty(keyPart)) return false;

        if (Enum.TryParse<Keys>(keyPart, true, out var key))
        {
            vk = (uint)key;
            return true;
        }

        if (keyPart.Length == 1)
        {
            char c = char.ToUpperInvariant(keyPart[0]);
            if (c >= 'A' && c <= 'Z' || c >= '0' && c <= '9')
            {
                vk = (uint)c;
                return true;
            }
        }

        return false;
    }

    public void Dispose()
    {
        UnregisterAll();
        _source?.RemoveHook(HwndHook);
    }
}
