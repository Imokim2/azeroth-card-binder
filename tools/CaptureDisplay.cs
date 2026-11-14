// Manual, read-only diagnostic. Build with the Windows .NET Framework compiler.
// Captures process names and WoW window state, never titles, input or game data.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

internal static class CaptureDisplay {
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    private static readonly string[] GameNames = { "Wow", "WowClassic", "WowB", "WowT", "WowForever" };

    private static int Main(string[] args) {
        int seconds = 3600;
        if (args.Length > 0 && (!int.TryParse(args[0], out seconds) || seconds < 10 || seconds > 3600)) return 2;
        string folder = Path.GetFullPath(args.Length > 1 ? args[1] : Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "display-captures"));
        Directory.CreateDirectory(folder);
        string path = Path.Combine(folder, "display-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss-fff") + ".jsonl");
        var json = new JavaScriptSerializer();
        var clock = Stopwatch.StartNew();
        var games = new List<Process>();
        long lastDiscovery = -1000;
        string previous = null;
        try {
            using (var writer = new StreamWriter(path, false, new UTF8Encoding(false))) {
                writer.AutoFlush = true; // Evidence survives a forced client exit.
                writer.WriteLine(json.Serialize(new { type = "start", utc = DateTime.UtcNow.ToString("o"), seconds,
                    note = "Process names, IDs and game window state only. No titles, screenshots, keys or account data." }));
                while (clock.Elapsed.TotalSeconds < seconds) {
                    if (clock.ElapsedMilliseconds - lastDiscovery >= 1000) {
                        foreach (var game in games) game.Dispose();
                        games.Clear();
                        foreach (var name in GameNames) games.AddRange(Process.GetProcessesByName(name));
                        games = games.OrderBy(game => game.Id).ToList();
                        lastDiscovery = clock.ElapsedMilliseconds;
                    }
                    IntPtr front = GetForegroundWindow();
                    uint foregroundId;
                    GetWindowThreadProcessId(front, out foregroundId);
                    string foregroundProcess = null;
                    try {
                        using (var process = Process.GetProcessById((int)foregroundId)) foregroundProcess = process.ProcessName;
                    } catch (ArgumentException) {} // Process ended between the two reads.
                    catch (System.ComponentModel.Win32Exception) {} // Foreground process cannot be inspected.
                    var windows = new List<object>();
                    foreach (var game in games) {
                        try {
                            game.Refresh();
                            IntPtr window = game.MainWindowHandle;
                            Rect rect;
                            int[] bounds = window != IntPtr.Zero && GetWindowRect(window, out rect)
                                ? new[] { rect.Left, rect.Top, rect.Right, rect.Bottom } : null;
                            windows.Add(new { process = game.ProcessName, id = game.Id, window = window.ToInt64(),
                                minimized = window != IntPtr.Zero && IsIconic(window),
                                visible = window != IntPtr.Zero && IsWindowVisible(window), bounds });
                        } catch (InvalidOperationException) {} // A client can exit during sampling.
                        catch (System.ComponentModel.Win32Exception) {} // An elevated client may be unreadable.
                    }
                    var state = new { foregroundProcess, foregroundId, games = windows };
                    string encoded = json.Serialize(state);
                    if (encoded != previous) {
                        writer.WriteLine(json.Serialize(new { type = "change", utc = DateTime.UtcNow.ToString("o"), elapsedMs = clock.ElapsedMilliseconds, state }));
                        previous = encoded;
                    }
                    Thread.Sleep(100);
                }
                writer.WriteLine(json.Serialize(new { type = "stop", utc = DateTime.UtcNow.ToString("o"), elapsedMs = clock.ElapsedMilliseconds }));
            }
            Console.WriteLine(path);
            return 0;
        } catch (Exception error) {
            File.WriteAllText(path + ".error.txt", error.Message);
            return 1;
        } finally { foreach (var game in games) game.Dispose(); }
    }
}
