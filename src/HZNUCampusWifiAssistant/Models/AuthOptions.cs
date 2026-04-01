namespace HZNUCampusWifiAssistant.Models;
public sealed class AuthOptions
{
    public string BaseUrl { get; set; } = "http://172.31.1.30";
    public string PortalPageUrl { get; set; } = "http://172.31.1.30/srun_portal_pc?ac_id=17&theme=hznu";
    public string AcId { get; set; } = "17";
    public string EncVer { get; set; } = "srun_bx1";
    public string N { get; set; } = "200";
    public string Type { get; set; } = "1";
    public string DoubleStack { get; set; } = "0";
    public string Os { get; set; } = "Windows 10";
    public string Name { get; set; } = "Windows";
    public string Ip { get; set; } = string.Empty;
    public static AuthOptions CreateDefault() => new();
}
