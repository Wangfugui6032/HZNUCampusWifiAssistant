using System.IO;
using System.Text.Encodings.Web;
using System.Text.Json;
using HZNUCampusWifiAssistant.Models;
namespace HZNUCampusWifiAssistant.Services;
public sealed class SettingsService
{
    private readonly AppPaths _paths;
    private readonly JsonSerializerOptions _serializerOptions = new()
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };
    public SettingsService(AppPaths paths)
    {
        _paths = paths;
    }
    public AppSettings Load()
    {
        if (!File.Exists(_paths.SettingsFile))
        {
            var defaults = AppSettings.CreateDefault();
            Save(defaults);
            return defaults;
        }
        var json = File.ReadAllText(_paths.SettingsFile);
        var settings = JsonSerializer.Deserialize<AppSettings>(json, _serializerOptions) ?? AppSettings.CreateDefault();
        settings.CampusSsids ??= ["HZNU"];
        settings.Auth ??= AuthOptions.CreateDefault();
        if (settings.TimeoutSeconds <= 0)
        {
            settings.TimeoutSeconds = 8;
        }
        return settings;
    }
    public void Save(AppSettings settings)
    {
        Directory.CreateDirectory(_paths.AppDataDirectory);
        var json = JsonSerializer.Serialize(settings, _serializerOptions);
        File.WriteAllText(_paths.SettingsFile, json);
    }
}
