using System;
using System.Linq;
using HZNUCampusWifiAssistant.Models;

namespace HZNUCampusWifiAssistant.Services;

public sealed class CampusWifiService
{
    private readonly WifiInspector _wifiInspector = new();
    private readonly CampusPortalClient _portalClient = new();

    public async Task<CampusWifiState> GetCampusWifiStateAsync(AppSettings settings, CancellationToken cancellationToken = default)
    {
        var snapshot = _wifiInspector.GetSnapshot();
        if (!snapshot.AdapterExists)
        {
            return new CampusWifiState
            {
                Kind = CampusWifiStateKind.NoWifiAdapter,
                Message = "未检测到 Wi-Fi 适配器。"
            };
        }

        if (!snapshot.WifiEnabled)
        {
            return new CampusWifiState
            {
                Kind = CampusWifiStateKind.WifiOff,
                Message = "当前 Wi-Fi 未开启，请先打开 Wi-Fi。"
            };
        }

        if (!snapshot.IsConnected || string.IsNullOrWhiteSpace(snapshot.CurrentSsid))
        {
            return new CampusWifiState
            {
                Kind = CampusWifiStateKind.NoWifiConnection,
                Message = "当前未连接任何 Wi-Fi，请先连接 HZNU 后再继续。"
            };
        }

        if (!settings.CampusSsids.Any(ssid => string.Equals(ssid, snapshot.CurrentSsid, StringComparison.OrdinalIgnoreCase)))
        {
            return new CampusWifiState
            {
                Kind = CampusWifiStateKind.OtherWifiConnected,
                CurrentSsid = snapshot.CurrentSsid,
                Message = $"当前连接的不是校园网：{snapshot.CurrentSsid}\n请先连接 HZNU 后再继续。"
            };
        }

        var onlineStatus = await _portalClient.GetOnlineStatusAsync(settings, cancellationToken);
        if (string.Equals(onlineStatus?.Error, "ok", StringComparison.OrdinalIgnoreCase))
        {
            return new CampusWifiState
            {
                Kind = CampusWifiStateKind.CampusWifiOnline,
                CurrentSsid = snapshot.CurrentSsid,
                Message = "已经完成验证，无需重新验证。"
            };
        }

        var portalCheck = await _portalClient.CheckPortalAsync(settings, cancellationToken);
        if (!portalCheck.NeedsAuth)
        {
            return new CampusWifiState
            {
                Kind = CampusWifiStateKind.CampusWifiOnline,
                CurrentSsid = snapshot.CurrentSsid,
                Message = "已经完成验证，无需重新验证。"
            };
        }

        var portalContext = _portalClient.BuildPortalContext(settings, portalCheck.PortalUrl, onlineStatus?.ClientIp);
        return new CampusWifiState
        {
            Kind = CampusWifiStateKind.CampusWifiNeedsAuth,
            CurrentSsid = snapshot.CurrentSsid,
            PortalContext = portalContext,
            Message = "检测到需要进行校园网认证。"
        };
    }

    public async Task<WorkflowResult> AuthenticateAsync(AppSettings settings, CredentialInfo credential, CampusWifiState state, IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        if (state.Kind == CampusWifiStateKind.CampusWifiOnline)
        {
            return new WorkflowResult { Success = true, Message = state.Message };
        }

        if (state.Kind != CampusWifiStateKind.CampusWifiNeedsAuth || state.PortalContext is null)
        {
            return new WorkflowResult { Success = false, Message = state.Message };
        }

        progress?.Report("正在检查校园网认证状态。");
        return await _portalClient.AuthenticateAsync(settings, credential, state.PortalContext, progress, cancellationToken);
    }
}
