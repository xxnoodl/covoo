# Secret storage and private process channel. No UI or audio code.
Add-Type -AssemblyName System.Security
if (-not ('CovooReceiverChannel' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Threading;

// Drain both process pipes even while the UI is stalled. Bounded log memory.
public sealed class CovooReceiverChannel {
    private readonly ConcurrentQueue<string> lines = new ConcurrentQueue<string>();
    private int completed;
    public CovooReceiverChannel(Process process) {
        ThreadPool.QueueUserWorkItem(_ => Pump(process.StandardOutput));
        ThreadPool.QueueUserWorkItem(_ => Pump(process.StandardError));
    }
    private void Enqueue(string line) {
        lines.Enqueue(line);
        string ignored;
        while (lines.Count > 256) lines.TryDequeue(out ignored);
    }
    private void Pump(StreamReader reader) {
        try {
            string line;
            while ((line = reader.ReadLine()) != null) Enqueue(line);
        } catch (IOException) { Enqueue("Receiver diagnostic pipe closed."); }
          catch (ObjectDisposedException) { }
        finally { Interlocked.Increment(ref completed); }
    }
    public bool TryRead(out string line) { return lines.TryDequeue(out line); }
    public bool Finished { get { return Volatile.Read(ref completed) == 2 && lines.IsEmpty; } }
}
'@
}

function Protect-Pairing([string]$Record, [string]$Path) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Record)
    try {
        $protected = [Security.Cryptography.ProtectedData]::Protect($bytes, $null,
            [Security.Cryptography.DataProtectionScope]::CurrentUser)
        [IO.File]::WriteAllBytes("$Path.pending", $protected)
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Replace("$Path.pending", $Path, [NullString]::Value)
        } else { [IO.File]::Move("$Path.pending", $Path) }
    } finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Read-Pairing([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return 'null' }
    $bytes = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($Path),
        $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    try { return [Text.Encoding]::UTF8.GetString($bytes) }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Quote-Argument([string]$Value) {
    # Windows CommandLineToArgvW escaping, including quotes and trailing slashes.
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function New-ReceiverProcess([string]$Executable, [string[]]$Arguments) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = ($Arguments | ForEach-Object { Quote-Argument $_ }) -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    if (-not $process.Start()) { throw 'Receiver did not start.' }
    # Framework's StandardInput inherits Console.InputEncoding and can emit a BOM.
    # Use an explicit no-BOM writer; never mix it with the original writer.
    $control = New-Object IO.StreamWriter($process.StandardInput.BaseStream, (New-Object Text.UTF8Encoding($false)))
    $process | Add-Member -NotePropertyName ControlInput -NotePropertyValue $control
    return $process
}
