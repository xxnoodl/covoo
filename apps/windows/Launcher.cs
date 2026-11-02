using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows.Forms;

internal static class Launcher {
    [STAThread]
    private static int Main(string[] args) {
        bool smoke = args.Length == 1 && args[0] == "--smoke-test";
        try {
            if (args.Length != 0 && !smoke) throw new Exception("Unknown launcher argument.");
            string folder = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(folder, "desktop.ps1");
            if (!File.Exists(script) || !File.Exists(Path.Combine(folder, "covoo-receiver.exe")))
                throw new Exception("Extract the complete covoo package before opening it.");
            var info = new ProcessStartInfo {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                    @"System32\WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-NoProfile -STA -File \"" + script + "\"" + (smoke ? " -SmokeTest" : ""),
                WorkingDirectory = folder,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            var errors = new StringBuilder();
            using (var process = new Process { StartInfo = info }) {
                DataReceivedEventHandler drain = (sender, e) => {
                    if (e.Data == null) return;
                    lock (errors) {
                        errors.AppendLine(e.Data);
                        if (errors.Length > 16000) errors.Remove(0, errors.Length - 8000);
                    }
                };
                process.OutputDataReceived += drain;
                process.ErrorDataReceived += drain;
                if (!process.Start()) throw new Exception("Could not open covoo.");
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
                process.WaitForExit();
                if (process.ExitCode != 0) throw new Exception(errors.ToString());
            }
            return 0;
        } catch (Exception error) {
            string message = "covoo could not start.\n\n" + error.Message;
            if (smoke) Console.Error.WriteLine(message);
            else MessageBox.Show(message, "covoo", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
