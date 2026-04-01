using System;
using System.Linq;
using System.Windows;

namespace HZNUCampusWifiAssistant;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var autoStart = e.Args.Any(arg => string.Equals(arg, "--autostart", StringComparison.OrdinalIgnoreCase));
        var mainWindow = new MainWindow(autoStart);
        MainWindow = mainWindow;
        mainWindow.Show();
    }
}
