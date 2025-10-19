using Kokoabim.CommandLineInterface;
using Kokoabim.LaunchAgent;

var runOnceCommand = new ConsoleCommand(
    "run",
    titleText: "Run once",
    arguments: [
    ],
    syncFunction: ctx =>
    {
        LaunchAgentLogger.WriteLine("Running once");
        return 0;
    }
);

var startLoopingCommand = new ConsoleCommand(
    "loop",
    titleText: "Start looping",
    arguments: [
    ],
    asyncFunction: async (ctx) =>
    {
        LaunchAgentLogger.WriteLine("Starting loop");
        while (true)
        {
            LaunchAgentLogger.WriteLine("Looping every second");
            await Task.Delay(1000);
        }
    }
);

var consoleApp = new ConsoleApp(
    [startLoopingCommand, runOnceCommand],
    titleText: "AGENTTITLE_CHANGEME"
);

LaunchAgentLogger.InitLogDir();
// Optional: LaunchAgentConfiguration.Build();

return await consoleApp.RunAsync(args);