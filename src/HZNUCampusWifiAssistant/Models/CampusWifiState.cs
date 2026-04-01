namespace HZNUCampusWifiAssistant.Models;
public enum CampusWifiStateKind
{
    NoWifiAdapter,
    WifiOff,
    NoWifiConnection,
    OtherWifiConnected,
    CampusWifiOnline,
    CampusWifiNeedsAuth
}
public sealed class CampusWifiState
{
    public CampusWifiStateKind Kind { get; init; }
    public string Message { get; init; } = string.Empty;
    public string? CurrentSsid { get; init; }
    public PortalContext? PortalContext { get; init; }
}
