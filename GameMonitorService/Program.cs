using GameMonitorService;

var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddWindowsService(options =>
{
    options.ServiceName = "Game Monitor Service";
});

builder.Services.AddHostedService<Worker>();

var host = builder.Build();
host.Run();
