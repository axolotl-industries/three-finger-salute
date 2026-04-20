namespace GameMonitorService;

public static class FileLockChecker
{
    public static bool IsFileReady(string path, ILogger logger)
    {
        try
        {
            if (Directory.Exists(path))
            {
                return IsDirectoryReady(path, logger);
            }
            else if (File.Exists(path))
            {
                return CanOpenExclusively(path, logger);
            }
            return false;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error checking if {Path} is ready.", path);
            return false;
        }
    }

    private static bool IsDirectoryReady(string directoryPath, ILogger logger)
    {
        var files = Directory.GetFiles(directoryPath, "*", SearchOption.AllDirectories);
        if (files.Length == 0) return true; // Empty folder is "ready"

        // Find the largest file (most likely still being written to)
        var largestFile = files.OrderByDescending(f => new FileInfo(f).Length).First();
        return CanOpenExclusively(largestFile, logger);
    }

    private static bool CanOpenExclusively(string filePath, ILogger logger)
    {
        try
        {
            using var stream = File.Open(filePath, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            return true;
        }
        catch (IOException)
        {
            // Error 32: The process cannot access the file because it is being used by another process.
            return false;
        }
        catch (Exception ex)
        {
            logger.LogDebug(ex, "Could not open file {Path} exclusively.", filePath);
            return false;
        }
    }
}
