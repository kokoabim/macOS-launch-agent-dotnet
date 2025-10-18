namespace Kokoabim.LaunchAgent;

public static class LaunchAgentLogger
{
    /// <summary>
    /// Maximum log file size in bytes. Once the log file reaches this size, it will be moved to a backup file. Default is 10 MB.
    /// </summary>
    public static int MaxLogSize { get; set; } = 1024 * 1024 * 10; // 10 MB

    private static readonly string LogDir = Environment.ExpandEnvironmentVariables("%HOME%/Library/Caches/me.swsj.launch-agent");
    private static readonly string LogFile = Path.Combine(LogDir, "AGENTNAME_CHANGEME.log");

    public static void InitLogDir()
    {
        if (!Directory.Exists(LogDir)) Directory.CreateDirectory(LogDir);

        if (File.Exists(LogFile) && new FileInfo(LogFile).Length > MaxLogSize) File.Move(LogFile, LogFile + ".bak", overwrite: true);
    }

    public static void Write(string message)
    {
        Console.Write(message);
        File.AppendAllText(LogFile, message);
    }

    public static void WriteLine(string message)
    {
        Console.WriteLine(message);
        File.AppendAllText(LogFile, $"{message}{Environment.NewLine}");
    }

    public static void WriteLines(IEnumerable<string> messages)
    {
        foreach (var message in messages) WriteLine(message);
    }
}