using Microsoft.Extensions.Configuration;

namespace Kokoabim.LaunchAgent;

public static class LaunchAgentConfiguration
{
    private static IConfiguration? _configuration;

    public static void Build()
    {
        var builder = new ConfigurationBuilder()
            .SetBasePath(AppDomain.CurrentDomain.BaseDirectory)
            .AddJsonFile("AGENTNAME_CHANGEME.json", optional: false, reloadOnChange: true);

        _configuration = builder.Build();
    }

    public static bool? GetBoolean(string key) => _configuration?.GetValue<bool>(key);

    public static int? GetInteger(string key) => _configuration?.GetValue<int>(key);

    public static string? GetString(string key) => _configuration?.GetValue<string>(key);
}