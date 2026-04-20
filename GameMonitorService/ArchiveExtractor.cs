using System.Diagnostics;

namespace GameMonitorService;

public static class ArchiveExtractor
{
    public static async Task<bool> ExtractAsync(string archivePath, string destinationPath, ILogger logger)
    {
        try
        {
            if (!File.Exists(MonitorSettings.SevenZipPath))
            {
                logger.LogError("7-Zip not found at {Path}", MonitorSettings.SevenZipPath);
                return false;
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = MonitorSettings.SevenZipPath,
                Arguments = $"x \"{archivePath}\" -o\"{destinationPath}\" -y",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = new Process { StartInfo = startInfo };
            process.Start();

            // Read output/error to avoid hanging
            var outputTask = process.StandardOutput.ReadToEndAsync();
            var errorTask = process.StandardError.ReadToEndAsync();

            await process.WaitForExitAsync();

            if (process.ExitCode == 0)
            {
                logger.LogInformation("Successfully extracted {Archive} to {Destination}", archivePath, destinationPath);
                return true;
            }
            else
            {
                var error = await errorTask;
                logger.LogError("Error extracting {Archive}. Exit Code: {Code}. Error: {Error}", archivePath, process.ExitCode, error);
                return false;
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error occurred during extraction of {Archive}", archivePath);
            return false;
        }
    }
}
