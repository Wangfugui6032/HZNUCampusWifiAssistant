using System;
using System.IO;

namespace HZNUCampusWifiAssistant.Services;

public sealed class ShortcutService
{
    private readonly AppPaths _paths;

    public ShortcutService(AppPaths paths)
    {
        _paths = paths;
    }

    public void EnsureDesktopShortcut()
    {
        CreateShortcut(_paths.DesktopShortcutFile, string.Empty, "杭州师范大学校园网助手");
    }

    public void SetStartupEnabled(bool enabled)
    {
        if (enabled)
        {
            CreateShortcut(_paths.StartupShortcutFile, "--autostart", "HZNU 校园网自动认证");
            return;
        }

        if (File.Exists(_paths.StartupShortcutFile))
        {
            File.Delete(_paths.StartupShortcutFile);
        }
    }

    private void CreateShortcut(string shortcutPath, string arguments, string description)
    {
        var shellType = Type.GetTypeFromProgID("WScript.Shell")
            ?? throw new InvalidOperationException("无法创建快捷方式，系统缺少 WScript.Shell。");

        dynamic shell = Activator.CreateInstance(shellType)!;
        dynamic shortcut = shell.CreateShortcut(shortcutPath);
        shortcut.TargetPath = _paths.ExecutablePath;
        shortcut.Arguments = arguments;
        shortcut.WorkingDirectory = _paths.ExecutableDirectory;
        shortcut.Description = description;
        shortcut.IconLocation = _paths.ExecutablePath;
        shortcut.Save();
    }
}
