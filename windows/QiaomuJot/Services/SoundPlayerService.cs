using System;
using System.IO;
using System.Media;
using QiaomuJot.Models;

namespace QiaomuJot.Services;

public static class SoundPlayerService
{
    public static void PlaySuccess()
    {
        if (!AppSettings.Current.PlaySound) return;

        try
        {
            var baseDir = AppDomain.CurrentDomain.BaseDirectory;
            var soundPath = Path.Combine(baseDir, "Resources", "Sounds", "kenney-confirmation_001.wav");
            if (File.Exists(soundPath))
            {
                using var player = new SoundPlayer(soundPath);
                player.Play();
            }
            else
            {
                SystemSounds.Asterisk.Play();
            }
        }
        catch { }
    }

    public static void PlayGlass()
    {
        if (!AppSettings.Current.PlaySound) return;

        try
        {
            var baseDir = AppDomain.CurrentDomain.BaseDirectory;
            var soundPath = Path.Combine(baseDir, "Resources", "Sounds", "kenney-glass_004.wav");
            if (File.Exists(soundPath))
            {
                using var player = new SoundPlayer(soundPath);
                player.Play();
            }
        }
        catch { }
    }
}
