using System;
using System.Drawing;
using System.Windows.Forms;

internal sealed class NativeWinFormsShellContext : ApplicationContext
{
    private readonly NotifyIcon trayIcon;
    private readonly Timer timer;
    private int ticksRemaining;

    public NativeWinFormsShellContext(int runSeconds)
    {
        ticksRemaining = Math.Max(1, runSeconds);
        trayIcon = new NotifyIcon
        {
            Icon = SystemIcons.Application,
            Text = "Codex Pet Dock native shell benchmark",
            Visible = true,
        };
        timer = new Timer { Interval = 1000 };
        timer.Tick += OnTick;
        timer.Start();
    }

    private void OnTick(object sender, EventArgs eventArgs)
    {
        ticksRemaining -= 1;
        if (ticksRemaining <= 0)
        {
            ExitThread();
        }
    }

    protected override void ExitThreadCore()
    {
        timer.Stop();
        timer.Dispose();
        trayIcon.Visible = false;
        trayIcon.Dispose();
        base.ExitThreadCore();
    }
}

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        var runSeconds = 30;
        if (args.Length > 0)
        {
            int.TryParse(args[0], out runSeconds);
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new NativeWinFormsShellContext(runSeconds));
    }
}
