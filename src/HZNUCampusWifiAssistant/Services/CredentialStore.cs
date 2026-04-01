using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using HZNUCampusWifiAssistant.Models;
namespace HZNUCampusWifiAssistant.Services;
public sealed class CredentialStore
{
    private readonly AppPaths _paths;
    public CredentialStore(AppPaths paths)
    {
        _paths = paths;
    }
    public CredentialInfo? Load()
    {
        if (!File.Exists(_paths.CredentialFile))
        {
            return null;
        }
        var protectedBytes = File.ReadAllBytes(_paths.CredentialFile);
        var plainBytes = ProtectedData.Unprotect(protectedBytes, null, DataProtectionScope.CurrentUser);
        var json = Encoding.UTF8.GetString(plainBytes);
        return JsonSerializer.Deserialize<CredentialInfo>(json);
    }
    public void Save(CredentialInfo credential)
    {
        Directory.CreateDirectory(_paths.AppDataDirectory);
        var json = JsonSerializer.Serialize(credential);
        var plainBytes = Encoding.UTF8.GetBytes(json);
        var protectedBytes = ProtectedData.Protect(plainBytes, null, DataProtectionScope.CurrentUser);
        File.WriteAllBytes(_paths.CredentialFile, protectedBytes);
    }
    public void Delete()
    {
        if (File.Exists(_paths.CredentialFile))
        {
            File.Delete(_paths.CredentialFile);
        }
    }
}
