using System;
using System.Text;
namespace HZNUCampusWifiAssistant.Utilities;
public static class SrunCodec
{
    private static readonly string StandardAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    private static readonly string CustomAlphabet = "LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA";
    public static string XEncode(string message, string key)
    {
        if (string.IsNullOrEmpty(message))
        {
            return string.Empty;
        }
        var v = SEncode(message, includeLength: true);
        var k = SEncode(key, includeLength: false);
        if (k.Length < 4)
        {
            Array.Resize(ref k, 4);
        }
        var n = v.Length - 1;
        var z = v[n];
        var y = v[0];
        const uint c = 0x9E3779B9;
        uint d = 0;
        var q = 6 + 52 / (n + 1);
        while (q-- > 0)
        {
            d += c;
            var e = (d >> 2) & 3;
            for (var p = 0; p < n; p++)
            {
                y = v[p + 1];
                var m = ((z >> 5) ^ (y << 2)) + (((y >> 3) ^ (z << 4)) ^ (d ^ y));
                m += k[(p & 3) ^ e] ^ z;
                z = v[p] += m;
            }
            y = v[0];
            var last = ((z >> 5) ^ (y << 2)) + (((y >> 3) ^ (z << 4)) ^ (d ^ y));
            last += k[(n & 3) ^ e] ^ z;
            z = v[n] += last;
        }
        var bytes = new byte[v.Length * 4];
        for (var index = 0; index < v.Length; index++)
        {
            bytes[index * 4] = (byte)(v[index] & 0xFF);
            bytes[index * 4 + 1] = (byte)((v[index] >> 8) & 0xFF);
            bytes[index * 4 + 2] = (byte)((v[index] >> 16) & 0xFF);
            bytes[index * 4 + 3] = (byte)((v[index] >> 24) & 0xFF);
        }
        return Encoding.GetEncoding("ISO-8859-1").GetString(bytes);
    }
    public static string ToCustomBase64(string binaryString)
    {
        var bytes = new byte[binaryString.Length];
        for (var i = 0; i < binaryString.Length; i++)
        {
            bytes[i] = (byte)(binaryString[i] & 0xFF);
        }
        var standard = Convert.ToBase64String(bytes);
        var builder = new StringBuilder(standard.Length);
        foreach (var ch in standard)
        {
            if (ch == '=')
            {
                builder.Append('=');
                continue;
            }
            var index = StandardAlphabet.IndexOf(ch);
            if (index < 0)
            {
                throw new InvalidOperationException($"Unexpected base64 character: {ch}");
            }
            builder.Append(CustomAlphabet[index]);
        }
        return builder.ToString();
    }
    private static uint[] SEncode(string text, bool includeLength)
    {
        var size = (text.Length + 3) / 4;
        var result = includeLength ? new uint[size + 1] : new uint[size];
        for (var index = 0; index < text.Length; index++)
        {
            result[index >> 2] |= (uint)(byte)text[index] << ((index & 3) * 8);
        }
        if (includeLength)
        {
            result[size] = (uint)text.Length;
        }
        return result;
    }
}
