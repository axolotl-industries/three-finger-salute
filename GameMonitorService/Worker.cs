using System.Collections.Concurrent;
using System.Threading.Channels;

namespace GameMonitorService;

public class Worker : BackgroundService
{
    private readonly ILogger<Worker> _logger;
    private readonly FileSystemWatcher _watcher;
    private readonly Channel<string> _processingQueue;

    public Worker(ILogger<Worker> logger)
    {
        _logger = logger;
        _processingQueue = Channel.CreateUnbounded<string>();

        // Ensure path exists
        if (!Directory.Exists(MonitorSettings.MonitorPath))
        {
            _logger.LogWarning("Monitoring path {Path} does not exist. Creating it...", MonitorSettings.MonitorPath);
            Directory.CreateDirectory(MonitorSettings.MonitorPath);
        }

        _watcher = new FileSystemWatcher(MonitorSettings.MonitorPath)
        {
            IncludeSubdirectories = false,
            EnableRaisingEvents = false
        };

        _watcher.Created += (s, e) => EnqueueItem(e.FullPath);
        _watcher.Renamed += (s, e) => EnqueueItem(e.FullPath);
    }

    private void EnqueueItem(string path)
    {
        _logger.LogInformation("Detected new item: {Path}", path);
        _processingQueue.Writer.TryWrite(path);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Game Monitor Service starting.");
        _watcher.EnableRaisingEvents = true;

        // Processing loop
        _ = Task.Run(async () =>
        {
            await foreach (var itemPath in _processingQueue.Reader.ReadAllAsync(stoppingToken))
            {
                await ProcessItemAsync(itemPath, stoppingToken);
            }
        }, stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            await Task.Delay(1000, stoppingToken);
        }

        _watcher.EnableRaisingEvents = false;
        _logger.LogInformation("Game Monitor Service stopping.");
    }

    private async Task ProcessItemAsync(string path, CancellationToken ct)
    {
        _logger.LogInformation("Processing {Path}...", path);

        // Wait for it to be "ready" (e.g., download complete)
        bool isReady = false;
        int retries = 0;
        const int MaxRetries = 60; // 10 minutes (10s per retry)

        while (!isReady && retries < MaxRetries)
        {
            if (FileLockChecker.IsFileReady(path, _logger))
            {
                isReady = true;
                _logger.LogInformation("{Path} is ready for action.", path);
                break;
            }

            retries++;
            _logger.LogDebug("Waiting for {Path} to be free (Retry {R}/{M})...", path, retries, MaxRetries);
            await Task.Delay(10000, ct); // Wait 10s between checks
        }

        if (!isReady)
        {
            _logger.LogWarning("Timed out waiting for {Path} to be ready. Skipping.", path);
            return;
        }

        // Handle Archives
        string ext = Path.GetExtension(path).ToLower();
        if (MonitorSettings.ArchiveExtensions.Contains(ext))
        {
            string extractionPath = Path.Combine(MonitorSettings.MonitorPath, "extracted_" + Path.GetFileNameWithoutExtension(path));
            Directory.CreateDirectory(extractionPath);
            
            bool success = await ArchiveExtractor.ExtractAsync(path, extractionPath, _logger);
            if (success)
            {
                // TODO: Trigger silent installation in extractionPath
                _logger.LogInformation("Extraction complete. Next: Automated installation logic.");
            }
        }
        else if (Directory.Exists(path))
        {
            // TODO: Trigger silent installation directly in this folder
            _logger.LogInformation("Detected ready folder. Next: Automated installation logic.");
        }
    }
}
