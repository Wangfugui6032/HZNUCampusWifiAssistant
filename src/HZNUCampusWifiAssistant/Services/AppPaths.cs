using System;
using System.IO;

namespace HZNUCampusWifiAssistant.Services;

public sealed class AppPaths
{
    public AppPaths()
    {
        ExecutablePath = Environment.ProcessPath ?? throw new InvalidOperationException("无法识别程序路径。");
        ExecutableDirectory = AppContext.BaseDirectory;
        AppDataDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "HZNUCampusWifiAssistant");
        Directory.CreateDirectory(AppDataDirectory);

        SettingsFile = Path.Combine(AppDataDirectory, "settings.json");
        CredentialFile = Path.Combine(AppDataDirectory, "credential.dat");
        DesktopShortcutFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "杭州师范大学校园网助手.lnk");
        StartupShortcutFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "HZNUCampusWifiAssistant.lnk");
    }

    public string ExecutablePath { get; }
    public string ExecutableDirectory { get; }
    public string AppDataDirectory { get; }
    public string SettingsFile { get; }
    public string CredentialFile { get; }
    public string DesktopShortcutFile { get; }
    public string StartupShortcutFile { get; }
}
