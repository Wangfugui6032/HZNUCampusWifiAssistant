using System;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace HZNUCampusWifiAssistant.Services;

public sealed class WifiInspector
{
    public WifiSnapshot GetSnapshot()
    {
        var output = ExecuteNetsh("wlan show interfaces");
        if (string.IsNullOrWhiteSpace(output))
        {
            return new WifiSnapshot
            {
                AdapterExists = false,
                WifiEnabled = false,
                IsConnected = false,
                RawOutput = string.Empty
            };
        }

        if (ContainsAny(output, "There is no wireless interface on the system", "系统上没有无线接口"))
        {
            return new WifiSnapshot
            {
                AdapterExists = false,
                WifiEnabled = false,
                IsConnected = false,
                RawOutput = output
            };
        }

        var stateValue = MatchValue(output, "State", "状态");
        var radioValue = MatchValue(output, "Radio status", "无线电状态");
        var ssidValue = MatchSsid(output);

        var wifiEnabled = true;
        if (!string.IsNullOrWhiteSpace(radioValue) && ContainsAny(radioValue, "off", "关闭", "已关闭"))
        {
            wifiEnabled = false;
        }

        var isConnected = !string.IsNullOrWhiteSpace(stateValue)
            && ContainsAny(stateValue, "connected", "已连接")
            && !ContainsAny(stateValue, "disconnected", "未连接");

        return new WifiSnapshot
        {
            AdapterExists = true,
            WifiEnabled = wifiEnabled,
            IsConnected = isConnected,
            CurrentSsid = isConnected ? ssidValue : null,
            RawOutput = output
        };
    }

    private static string ExecuteNetsh(string arguments)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = "netsh",
            Arguments = arguments,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("无法启动 netsh。");
        var output = process.StandardOutput.ReadToEnd();
        var error = process.StandardError.ReadToEnd();
        process.WaitForExit();
        return string.IsNullOrWhiteSpace(error) ? output : output + Environment.NewLine + error;
    }

    private static string? MatchValue(string text, params string[] labels)
    {
        foreach (var label in labels)
        {
            var pattern = $@"^\s*{Regex.Escape(label)}\s*:\s*(.+)$";
            var match = Regex.Match(text, pattern, RegexOptions.Multiline | RegexOptions.IgnoreCase);
            if (match.Success)
            {
                return match.Groups[1].Value.Trim();
            }
        }

        return null;
    }

    private static string? MatchSsid(string text)
    {
        foreach (var line in text.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None))
        {
            var trimmed = line.Trim();
            if (trimmed.StartsWith("BSSID", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (Regex.IsMatch(trimmed, "^SSID\\s*:\\s*", RegexOptions.IgnoreCase))
            {
                var parts = trimmed.Split(':', 2);
                if (parts.Length == 2)
                {
                    var value = parts[1].Trim();
                    return string.IsNullOrWhiteSpace(value) ? null : value;
                }
            }
        }

        return null;
    }

    private static bool ContainsAny(string text, params string[] values)
    {
        return values.Any(value => text.Contains(value, StringComparison.OrdinalIgnoreCase));
    }
}

public sealed class WifiSnapshot
{
    public bool AdapterExists { get; init; }
    public bool WifiEnabled { get; init; }
    public bool IsConnected { get; init; }
    public string? CurrentSsid { get; init; }
    public string RawOutput { get; init; } = string.Empty;
}

