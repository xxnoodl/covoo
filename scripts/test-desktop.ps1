param([string]$ReceiverPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'desktop-common.ps1')
$repo = Split-Path -Parent $PSScriptRoot
if (-not $ReceiverPath) { $ReceiverPath = Join-Path $repo 'target\release\windows-receiver.exe' }
$folder = Join-Path $repo ('build\desktop-check-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($folder) | Out-Null
$secret = Join-Path $folder 'pairing.dpapi'

function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Read-Line($Reader) {
    $task = $Reader.ReadLineAsync()
    if (-not $task.Wait(10000)) { throw 'Receiver pipe timed out.' }
    return $task.GetAwaiter().GetResult()
}
function Run-DesktopSession([string]$Record, [string]$Name) {
    # Spaces and trailing slash exercise Windows argument quoting.
    $output = Join-Path $folder ($Name + ' output\')
    $process = New-ReceiverProcess $ReceiverPath @('--serve', '--desktop-session', '--host', '127.0.0.1',
        '--port', '0', '--no-discovery', '--seconds', '30', '--output', $output)
    try {
        $process.ControlInput.WriteLine($Record); $process.ControlInput.Flush()
        $bootstrap = Read-Line $process.StandardOutput
        if (-not $bootstrap -or -not $bootstrap.StartsWith('COVOO_PAIRING ')) {
            $process.ControlInput.Close()
            if ($process.WaitForExit(10000)) {
                throw ('Private pairing bootstrap missing. Exit ' + $process.ExitCode + ': ' + $process.StandardError.ReadToEnd())
            }
            throw 'Private pairing bootstrap missing; receiver did not exit.'
        }
        $privateRecord = $bootstrap.Substring(14)
        Protect-Pairing $privateRecord $secret
        Assert-True ((Read-Pairing $secret) -eq $privateRecord) 'DPAPI round trip failed.'
        Assert-True (-not ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($secret))).Contains('private_key')) 'Raw secret written to disk.'
        $process.ControlInput.WriteLine('START'); $process.ControlInput.Flush()
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        while (-not (Test-Path -LiteralPath (Join-Path $output 'status.json'))) {
            if ($process.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw 'Receiver did not publish status.' }
            Start-Sleep -Milliseconds 50
        }
        $status = Get-Content -LiteralPath (Join-Path $output 'status.json') -Raw | ConvertFrom-Json
        Assert-True ($status.state -eq 'Waiting for phone connection') 'Idle authentication state is wrong.'
        $page = [IO.File]::ReadAllText((Join-Path $output 'pairing.html'))
        $process.ControlInput.Close()
        Assert-True ($process.WaitForExit(10000)) 'EOF did not gracefully stop receiver.'
        Assert-True ($process.ExitCode -eq 0) 'Receiver exit failed.'
        $final = [IO.File]::ReadAllText((Join-Path $output 'status.json')) | ConvertFrom-Json
        Assert-True ($final.stopped -and $final.state -eq 'Receiver stopped') 'Final snapshot missing.'
        $saved = $privateRecord | ConvertFrom-Json
        $tokenHex = ($saved.token | ForEach-Object { '{0:x2}' -f $_ }) -join ''
        Assert-True ($page.Contains('token=' + $tokenHex)) 'Pairing QR does not use saved token.'
        $publicFiles = [IO.File]::ReadAllText((Join-Path $output 'status.json')) +
            [IO.File]::ReadAllText((Join-Path $output 'dashboard.html')) + $process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()
        Assert-True (-not $publicFiles.Contains($tokenHex) -and -not $publicFiles.Contains('private_key')) 'Credentials leaked into public diagnostics.'
        return @{ record = $privateRecord; page = $page }
    } finally {
        if (-not $process.HasExited) { $process.ControlInput.Close(); $process.WaitForExit(10000) | Out-Null }
        $process.Dispose()
        # Test QR pages are credentials too; never retain them as evidence.
        $pagePath = Join-Path $output 'pairing.html'
        if (Test-Path -LiteralPath $pagePath) { Remove-Item -LiteralPath $pagePath }
    }
}

try {
    # Leave UI consumption stopped while both child pipes exceed pipe capacity.
    $flood = New-ReceiverProcess 'powershell.exe' @('-NoProfile', '-Command',
        'for ($i=0; $i -lt 10000; $i++) { [Console]::Out.WriteLine("output " + $i); [Console]::Error.WriteLine("error " + $i) }')
    try {
        $channel = New-Object CovooReceiverChannel($flood)
        Assert-True ($flood.WaitForExit(15000)) 'UI inactivity blocked diagnostic pipes.'
        Start-Sleep -Milliseconds 100
        $count = 0; $line = $null
        while ($channel.TryRead([ref]$line)) { $count++ }
        Assert-True ($count -gt 0 -and $count -le 256) 'Diagnostic queue is not bounded.'
    } finally { $flood.Dispose() }
    $first = Run-DesktopSession 'null' 'first'
    $second = Run-DesktopSession (Read-Pairing $secret) 'restored'
    Assert-True ($first.record -eq $second.record) 'Restart changed saved identity or token.'
    $revoked = Run-DesktopSession 'null' 'revoked'
    $oldIdentity = $first.record | ConvertFrom-Json
    $newIdentity = $revoked.record | ConvertFrom-Json
    Assert-True (($newIdentity.token -join ',') -ne ($oldIdentity.token -join ',')) 'Revoke did not rotate token.'
    Assert-True (($newIdentity.certificate -join ',') -ne ($oldIdentity.certificate -join ',')) 'Revoke did not rotate certificate.'
    $damaged = [IO.File]::ReadAllBytes($secret)
    $damaged[$damaged.Length - 1] = $damaged[$damaged.Length - 1] -bxor 1
    [IO.File]::WriteAllBytes($secret, $damaged)
    $rejected = $false
    try { Read-Pairing $secret | Out-Null } catch { $rejected = $true }
    Assert-True $rejected 'Damaged protected storage was accepted.'

    $bad = New-ReceiverProcess $ReceiverPath @('--serve', '--desktop-session', '--host', '127.0.0.1', '--no-discovery')
    try {
        $bad.ControlInput.WriteLine('{"version":999}'); $bad.ControlInput.Close()
        Assert-True ($bad.WaitForExit(10000) -and $bad.ExitCode -ne 0) 'Invalid credentials did not fail closed.'
        Assert-True (-not $bad.StandardOutput.ReadToEnd().Contains('COVOO_PAIRING ')) 'Invalid credentials were silently replaced.'
    } finally { $bad.Dispose() }
    Write-Host 'Desktop pipe, DPAPI, restart, rotation, status and graceful stop checks passed. No audio endpoint opened.'
} finally {
    foreach ($path in @($secret, "$secret.pending")) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
}
