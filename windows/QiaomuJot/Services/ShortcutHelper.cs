using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;

namespace QiaomuJot.Services;

public static class ShortcutHelper
{
    [ComImport]
    [Guid("00021401-0000-0000-C000-000000000046")]
    internal class ShellLink { }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("000214F9-0000-0000-C000-000000000046")]
    internal interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cchMaxPath, out IntPtr pfd, int fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cchMaxName);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cchMaxPath);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cchMaxPath);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        void GetHotkey(out short pwHotkey);
        void SetHotkey(short wHotkey);
        void GetShowCmd(out int piShowCmd);
        void SetShowCmd(int iShowCmd);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cchIconPath, out int piIcon);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, int dwReserved);
        void Resolve(IntPtr hwnd, int fFlags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    public static void CreateShortcut(string shortcutPath, string targetPath, string workingDirectory, string description, string iconPath)
    {
        var link = (IShellLinkW)new ShellLink();
        link.SetPath(targetPath);
        link.SetWorkingDirectory(workingDirectory);
        link.SetDescription(description);
        if (File.Exists(iconPath))
        {
            link.SetIconLocation(iconPath, 0);
        }

        var file = (IPersistFile)link;
        file.Save(shortcutPath, false);
    }

    public static bool InstallShortcuts()
    {
        try
        {
            var exePath = Environment.ProcessPath ?? Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "QiaomuJot.exe");
            var baseDir = Path.GetDirectoryName(exePath) ?? AppDomain.CurrentDomain.BaseDirectory;
            var icoPath = Path.Combine(baseDir, "Resources", "app.ico");

            var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            var startMenu = Environment.GetFolderPath(Environment.SpecialFolder.Programs);

            var desktopLnk = Path.Combine(desktop, "乔木闪记 Jot.lnk");
            var startMenuLnk = Path.Combine(startMenu, "乔木闪记 Jot.lnk");

            CreateShortcut(desktopLnk, exePath, baseDir, "乔木闪记 · Jot", icoPath);
            CreateShortcut(startMenuLnk, exePath, baseDir, "乔木闪记 · Jot", icoPath);

            Console.WriteLine($"✓ 桌面快捷方式已创建: {desktopLnk}");
            Console.WriteLine($"✓ 开始菜单快捷方式已创建: {startMenuLnk}");
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"✗ 创建快捷方式失败: {ex.Message}");
            return false;
        }
    }
}
