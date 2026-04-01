namespace HZNUCampusWifiAssistant.Models;

public sealed class AppSettings
{
    public bool RememberCredentials { get; set; }
    public bool AutoStart { get; set; }
    public string[] CampusSsids { get; set; } = ["HZNU"];
    public string NetworkTestUrl { get; set; } = "http://www.msftconnecttest.com/connecttest.txt";
    public string ExpectedNetworkTestContent { get; set; } = "Microsoft Connect Test";
    public int TimeoutSeconds { get; set; } = 8;
    public AuthOptions Auth { get; set; } = AuthOptions.CreateDefault();

    public static AppSettings CreateDefault() => new();
}
