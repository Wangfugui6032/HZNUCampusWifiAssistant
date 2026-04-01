using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using HZNUCampusWifiAssistant.Models;
using HZNUCampusWifiAssistant.Utilities;

namespace HZNUCampusWifiAssistant.Services;

public sealed class CampusPortalClient
{
    public async Task<OnlineStatus?> GetOnlineStatusAsync(AppSettings settings, CancellationToken cancellationToken = default)
    {
        var callback = BuildCallback();
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds().ToString();
        var parameters = new Dictionary<string, string>
        {
            ["callback"] = callback,
            ["_"] = timestamp
        };

        var url = BuildUrl($"{settings.Auth.BaseUrl}/cgi-bin/rad_user_info", parameters);
        using var client = CreateHttpClient(settings.TimeoutSeconds, allowRedirect: true);
        var response = await client.GetStringAsync(url, cancellationToken);
        using var json = ParseJsonp(response);
        var root = json.RootElement;
        return new OnlineStatus(
            root.TryGetProperty("error", out var errorElement) ? errorElement.GetString() : null,
            root.TryGetProperty("client_ip", out var ipElement) ? ipElement.GetString() : null);
    }

    public async Task<PortalCheckResult> CheckPortalAsync(AppSettings settings, CancellationToken cancellationToken = default)
    {
        try
        {
            using var client = CreateHttpClient(settings.TimeoutSeconds, allowRedirect: false);
            using var response = await client.GetAsync(settings.NetworkTestUrl, cancellationToken);

            if ((int)response.StatusCode is >= 300 and < 400)
            {
                var redirectUrl = response.Headers.Location?.ToString() ?? settings.Auth.PortalPageUrl;
                return new PortalCheckResult(true, redirectUrl);
            }

            var content = await response.Content.ReadAsStringAsync(cancellationToken);
            var needsAuth = !content.Contains(settings.ExpectedNetworkTestContent, StringComparison.OrdinalIgnoreCase);
            return new PortalCheckResult(needsAuth, settings.Auth.PortalPageUrl);
        }
        catch
        {
            return new PortalCheckResult(true, settings.Auth.PortalPageUrl);
        }
    }

    public PortalContext BuildPortalContext(AppSettings settings, string? portalUrl, string? fallbackIp)
    {
        var effectivePortalUrl = string.IsNullOrWhiteSpace(portalUrl) ? settings.Auth.PortalPageUrl : portalUrl;
        var uri = new Uri(effectivePortalUrl);
        var query = ParseQueryString(uri.Query);

        var ip = GetFirstNonEmpty(
            query.TryGetValue("wlanuserip", out var wlanUserIp) ? wlanUserIp : null,
            query.TryGetValue("userip", out var userIp) ? userIp : null,
            fallbackIp,
            settings.Auth.Ip);

        var acId = GetFirstNonEmpty(
            query.TryGetValue("ac_id", out var acIdValue) ? acIdValue : null,
            settings.Auth.AcId);

        if (string.IsNullOrWhiteSpace(ip))
        {
            throw new InvalidOperationException("无法识别校园网认证所需的 IP 地址。");
        }

        if (string.IsNullOrWhiteSpace(acId))
        {
            throw new InvalidOperationException("无法识别校园网认证所需的 ac_id。");
        }

        return new PortalContext
        {
            BaseUrl = $"{uri.Scheme}://{uri.Authority}",
            PortalUrl = effectivePortalUrl,
            Ip = ip,
            AcId = acId
        };
    }

    public async Task<WorkflowResult> AuthenticateAsync(AppSettings settings, CredentialInfo credential, PortalContext portalContext, IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        progress?.Report($"正在进入认证页面：{portalContext.PortalUrl}");
        progress?.Report("正在获取 challenge。");
        var challenge = await GetChallengeAsync(settings, credential.StudentId, portalContext, cancellationToken);
        if (string.IsNullOrWhiteSpace(challenge))
        {
            return new WorkflowResult { Success = false, Message = "认证服务未返回有效 challenge。" };
        }

        progress?.Report("正在生成加密登录参数。");
        var hmd5 = GetHmacMd5Hex(challenge, credential.Password);
        var info = BuildInfo(settings, credential, portalContext, challenge);
        var checksumSource = string.Concat(
            challenge, credential.StudentId,
            challenge, hmd5,
            challenge, portalContext.AcId,
            challenge, portalContext.Ip,
            challenge, settings.Auth.N,
            challenge, settings.Auth.Type,
            challenge, info);
        var checksum = GetSha1Hex(checksumSource);

        progress?.Report("正在提交认证请求。");
        var callback = BuildCallback();
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds().ToString();
        var responseUrl = BuildUrl($"{portalContext.BaseUrl}/cgi-bin/srun_portal", new Dictionary<string, string>
        {
            ["callback"] = callback,
            ["action"] = "login",
            ["username"] = credential.StudentId,
            ["password"] = "{MD5}" + hmd5,
            ["os"] = settings.Auth.Os,
            ["name"] = settings.Auth.Name,
            ["double_stack"] = settings.Auth.DoubleStack,
            ["chksum"] = checksum,
            ["info"] = info,
            ["ac_id"] = portalContext.AcId,
            ["ip"] = portalContext.Ip,
            ["n"] = settings.Auth.N,
            ["type"] = settings.Auth.Type,
            ["_"] = timestamp
        });

        using (var client = CreateHttpClient(settings.TimeoutSeconds, allowRedirect: true))
        {
            var payload = await client.GetStringAsync(responseUrl, cancellationToken);
            using var json = ParseJsonp(payload);
            var root = json.RootElement;
            var error = root.TryGetProperty("error", out var errorElement) ? errorElement.GetString() : string.Empty;
            progress?.Report($"认证接口返回：{error}");
        }

        progress?.Report("正在验证最终联网结果。");
        var finalStatus = await GetOnlineStatusAsync(settings, cancellationToken);
        if (string.Equals(finalStatus?.Error, "ok", StringComparison.OrdinalIgnoreCase))
        {
            return new WorkflowResult { Success = true, Message = "认证成功，已联网。" };
        }

        return new WorkflowResult { Success = false, Message = "认证请求已完成，但暂未确认最终联网状态。" };
    }

    private async Task<string?> GetChallengeAsync(AppSettings settings, string username, PortalContext portalContext, CancellationToken cancellationToken)
    {
        var callback = BuildCallback();
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds().ToString();
        var url = BuildUrl($"{portalContext.BaseUrl}/cgi-bin/get_challenge", new Dictionary<string, string>
        {
            ["callback"] = callback,
            ["username"] = username,
            ["ip"] = portalContext.Ip,
            ["_"] = timestamp
        });

        using var client = CreateHttpClient(settings.TimeoutSeconds, allowRedirect: true);
        var response = await client.GetStringAsync(url, cancellationToken);
        using var json = ParseJsonp(response);
        return json.RootElement.TryGetProperty("challenge", out var challenge) ? challenge.GetString() : null;
    }

    private string BuildInfo(AppSettings settings, CredentialInfo credential, PortalContext portalContext, string token)
    {
        var payload = JsonSerializer.Serialize(new
        {
            username = credential.StudentId,
            password = credential.Password,
            ip = portalContext.Ip,
            acid = portalContext.AcId,
            enc_ver = settings.Auth.EncVer
        });

        var encoded = SrunCodec.XEncode(payload, token);
        return "{SRBX1}" + SrunCodec.ToCustomBase64(encoded);
    }

    private static HttpClient CreateHttpClient(int timeoutSeconds, bool allowRedirect)
    {
        var handler = new HttpClientHandler
        {
            AllowAutoRedirect = allowRedirect,
            AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate
        };

        return new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(timeoutSeconds <= 0 ? 8 : timeoutSeconds)
        };
    }

    private static string BuildCallback()
    {
        return $"jQuery11240{Random.Shared.Next(100000, 999999)}_{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}";
    }

    private static string BuildUrl(string baseUrl, IDictionary<string, string> parameters)
    {
        var builder = new StringBuilder(baseUrl);
        builder.Append('?');
        var first = true;
        foreach (var pair in parameters)
        {
            if (!first)
            {
                builder.Append('&');
            }

            builder.Append(Uri.EscapeDataString(pair.Key));
            builder.Append('=');
            builder.Append(Uri.EscapeDataString(pair.Value));
            first = false;
        }

        return builder.ToString();
    }

    private static JsonDocument ParseJsonp(string text)
    {
        var start = text.IndexOf('(');
        var end = text.LastIndexOf(')');
        if (start < 0 || end <= start)
        {
            throw new InvalidOperationException("认证接口返回格式异常。");
        }

        var json = text[(start + 1)..end];
        return JsonDocument.Parse(json);
    }

    private static Dictionary<string, string> ParseQueryString(string query)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var trimmed = query.TrimStart('?');
        if (string.IsNullOrWhiteSpace(trimmed))
        {
            return result;
        }

        foreach (var part in trimmed.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var pieces = part.Split('=', 2);
            var key = Uri.UnescapeDataString(pieces[0]);
            var value = pieces.Length > 1 ? Uri.UnescapeDataString(pieces[1]) : string.Empty;
            result[key] = value;
        }

        return result;
    }

    private static string GetHmacMd5Hex(string key, string value)
    {
        using var hmac = new HMACMD5(Encoding.UTF8.GetBytes(key));
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    private static string GetSha1Hex(string value)
    {
        using var sha1 = SHA1.Create();
        var hash = sha1.ComputeHash(Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    private static string GetFirstNonEmpty(params string?[] values)
    {
        foreach (var value in values)
        {
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        return string.Empty;
    }
}

public sealed record OnlineStatus(string? Error, string? ClientIp);
public sealed record PortalCheckResult(bool NeedsAuth, string PortalUrl);
