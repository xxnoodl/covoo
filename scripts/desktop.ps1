param([string]$ReceiverPath, [switch]$SmokeTest)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'desktop-common.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
if (-not $ReceiverPath) {
    $ReceiverPath = Join-Path $PSScriptRoot 'covoo-receiver.exe'
    if (-not (Test-Path -LiteralPath $ReceiverPath)) {
        $ReceiverPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'target\debug\windows-receiver.exe'
    }
}
if (-not (Test-Path -LiteralPath $ReceiverPath)) { throw 'Build or unpack the receiver first.' }
$ReceiverPath = (Resolve-Path -LiteralPath $ReceiverPath).Path
$root = Join-Path $env:LOCALAPPDATA 'covoo'
if ($SmokeTest) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('covoo-desktop-ui-check-' + [guid]::NewGuid().ToString('N'))
}
[IO.Directory]::CreateDirectory($root) | Out-Null
$secretPath = Join-Path $root 'pairing.dpapi'
$preferencesPath = Join-Path $root 'preferences.json'
# Hold an exclusive file handle for this account's entire desktop session.
try { $instance = [IO.File]::Open((Join-Path $root 'desktop.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
catch { throw 'Another covoo desktop is open. Close it first.' }
$script:engine = $null
$script:channel = $null
$script:runDirectory = $null
$script:pairingShown = $false
$script:closing = $false
$script:stopping = $false
$script:bootstrapped = $false
$script:processSample = $null
$script:processHealth = 'Receiver process CPU: waiting for samples'

$form = New-Object Windows.Forms.Form
$form.Text = 'covoo'
$form.Size = New-Object Drawing.Size(1000, 820)
$form.MinimumSize = $form.Size
$layout = New-Object Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.ColumnCount = 2
$layout.RowCount = 5
$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 50))) | Out-Null
$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 50))) | Out-Null
foreach ($height in @(32, 40, 42, 420, 220)) {
    $layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', $height))) | Out-Null
}
$form.Controls.Add($layout)
function New-Label([string]$Text) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $Text; $label.Dock = 'Fill'; $label.TextAlign = 'MiddleLeft'
    return $label
}
$layout.Controls.Add((New-Label 'Connection / interface (choose explicitly)'), 0, 0)
$layout.Controls.Add((New-Label 'Audio output (choose explicitly)'), 1, 0)
$network = New-Object Windows.Forms.ComboBox
$output = New-Object Windows.Forms.ComboBox
foreach ($combo in @($network, $output)) { $combo.DropDownStyle = 'DropDownList'; $combo.Dock = 'Fill' }
$layout.Controls.Add($network, 0, 1)
$layout.Controls.Add($output, 1, 1)
$buttons = New-Object Windows.Forms.FlowLayoutPanel
$buttons.Dock = 'Fill'; $layout.Controls.Add($buttons, 0, 2); $layout.SetColumnSpan($buttons, 2)
function New-Button([string]$Text) {
    $button = New-Object Windows.Forms.Button
    $button.Text = $Text; $button.AutoSize = $true; $buttons.Controls.Add($button)
    return $button
}
$start = New-Button 'Start receiver'
$stop = New-Button 'Stop receiver'
$refresh = New-Button 'Refresh choices'
$revoke = New-Button 'Revoke saved pairing'
$stop.Enabled = $false
$pairing = New-Object Windows.Forms.WebBrowser
$pairing.Dock = 'Fill'; $pairing.AllowWebBrowserDrop = $false
$pairing.IsWebBrowserContextMenuEnabled = $false; $pairing.WebBrowserShortcutsEnabled = $false
$pairing.ScriptErrorsSuppressed = $true
$pairing.Add_Navigating({ param($sender, $event)
    if ($event.Url.AbsoluteUri -eq 'about:blank') { return }
    $expected = if ($script:runDirectory) { ([uri](Join-Path $script:runDirectory 'pairing.html')).AbsoluteUri } else { '' }
    if ($event.Url.AbsoluteUri -ne $expected) { $event.Cancel = $true }
})
$layout.Controls.Add($pairing, 0, 3)
$health = New-Object Windows.Forms.TextBox
$health.Multiline = $true; $health.ReadOnly = $true; $health.ScrollBars = 'Vertical'; $health.Dock = 'Fill'
$health.Text = 'Receiver stopped. Saved pairing is reused until revoked. Output uses the legacy backend with a 40 ms source buffer.'
$layout.Controls.Add($health, 1, 3)
$log = New-Object Windows.Forms.TextBox
$log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = 'Vertical'; $log.Dock = 'Fill'
$layout.Controls.Add($log, 0, 4); $layout.SetColumnSpan($log, 2)
function Show-Message([string]$Text) {
    if ($log.TextLength -gt 24000) { $log.Text = $log.Text.Substring($log.TextLength - 12000) }
    $log.AppendText($Text + [Environment]::NewLine)
}
function Set-Running([bool]$Running) {
    foreach ($control in @($network, $output, $start, $refresh, $revoke)) { $control.Enabled = -not $Running }
    $stop.Enabled = $Running
}
function Refresh-Choices {
    $network.Items.Clear(); $output.Items.Clear()
    foreach ($adapter in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($adapter.OperationalStatus -ne 'Up') { continue }
        foreach ($address in $adapter.GetIPProperties().UnicastAddresses) {
            if ($address.Address.AddressFamily -eq 'InterNetwork' -and -not [Net.IPAddress]::IsLoopback($address.Address)) {
                $network.Items.Add($address.Address.ToString() + ' | ' + $adapter.Name) | Out-Null
            }
        }
    }
    $output.Items.Add('File recording only') | Out-Null
    $names = & $ReceiverPath --audio-devices-json
    if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate audio outputs.' }
    foreach ($name in ($names | ConvertFrom-Json)) { $output.Items.Add([string]$name) | Out-Null }
    if (Test-Path -LiteralPath $preferencesPath) {
        $preferences = Get-Content -LiteralPath $preferencesPath -Raw | ConvertFrom-Json
        $network.SelectedIndex = $network.Items.IndexOf([string]$preferences.network)
        $output.SelectedIndex = $output.Items.IndexOf([string]$preferences.output)
    }
}
$refresh.Add_Click({ try { Refresh-Choices } catch { Show-Message $_.Exception.Message } })
$start.Add_Click({
    try {
        if ($network.SelectedIndex -lt 0 -or $output.SelectedIndex -lt 0) { throw 'Choose both a connection and an output.' }
        $record = Read-Pairing $secretPath
        $script:runDirectory = Join-Path $root ('recordings\' + [guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($script:runDirectory) | Out-Null
        $arguments = @('--serve', '--desktop-session', '--host', ([string]$network.SelectedItem).Split(' ')[0],
            '--output', $script:runDirectory, '--seconds', '86400')
        if ($SmokeTest) { $arguments += @('--port', '0', '--no-discovery') }
        if ($output.SelectedIndex -gt 0) { $arguments += @('--audio-device', [string]$output.SelectedItem) }
        $script:engine = New-ReceiverProcess $ReceiverPath $arguments
        $script:engine.ControlInput.WriteLine($record)
        $script:engine.ControlInput.Flush()
        $script:channel = New-Object CovooReceiverChannel($script:engine)
        $script:pairingShown = $false; $script:stopping = $false; $script:bootstrapped = $false
        $script:processSample = $null
        $health.Text = 'Starting receiver. Waiting for protected pairing storage.'
        Set-Running $true
        $preferences = @{ network = [string]$network.SelectedItem; output = [string]$output.SelectedItem } | ConvertTo-Json
        [IO.File]::WriteAllText($preferencesPath, $preferences)
    } catch { Show-Message $_.Exception.Message }
})
function Request-Stop {
    if ($script:engine -and -not $script:engine.HasExited -and -not $script:stopping) {
        $script:stopping = $true; $stop.Enabled = $false
        $script:engine.ControlInput.Close()
        Show-Message 'Stopping receiver. Waiting for recording workers to finish.'
    }
}
$stop.Add_Click({ try { Request-Stop } catch { Show-Message $_.Exception.Message } })
$revoke.Add_Click({
    try {
        foreach ($path in @($secretPath, "$secretPath.pending")) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
        }
        # Only pairing pages inside this desktop's owned recordings directory.
        $ownedRecordings = Join-Path $root 'recordings'
        if (Test-Path -LiteralPath $ownedRecordings) {
            Get-ChildItem -LiteralPath $ownedRecordings -Filter pairing.html -File -Recurse |
                ForEach-Object { Remove-Item -LiteralPath $_.FullName }
        }
        $pairing.Navigate('about:blank')
        Show-Message 'Saved pairing revoked. Start and scan a fresh QR. All old phone links will be rejected.'
    } catch { Show-Message $_.Exception.Message }
})
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 200
$timer.Add_Tick({
    try {
        if (-not $script:engine) { return }
        # Drain bounded batches without blocking the UI or receiver's pipes.
        for ($index = 0; $index -lt 64; $index++) {
                $line = $null
                if (-not $script:channel.TryRead([ref]$line)) { break }
                if ($line.StartsWith('COVOO_PAIRING ')) {
                    if ($script:bootstrapped) { throw 'Unexpected private bootstrap record.' }
                    Protect-Pairing $line.Substring(14) $secretPath
                    $script:bootstrapped = $true
                    $script:engine.ControlInput.WriteLine('START'); $script:engine.ControlInput.Flush()
                } else { Show-Message $line }
        }
        if ($script:engine.HasExited -and $script:channel.Finished) {
            Show-Message ('Receiver exited with code ' + $script:engine.ExitCode)
            $script:engine.Dispose(); $script:engine = $null
            $pairing.Navigate('about:blank')
            $page = Join-Path $script:runDirectory 'pairing.html'
            if (Test-Path -LiteralPath $page) { Remove-Item -LiteralPath $page }
            Set-Running $false
            $health.Text = 'Receiver stopped. See the log and saved reports for final results.'
            if ($script:closing) { $form.Close() }
            return
        }
        if ($script:stopping) { return }
        $now = [Diagnostics.Stopwatch]::GetTimestamp()
        if (-not $script:processSample -or ($now - $script:processSample.tick) -ge [Diagnostics.Stopwatch]::Frequency) {
            $script:engine.Refresh()
            $cpuTime = $script:engine.TotalProcessorTime.TotalSeconds
            $cpu = 'Waiting for second sample'
            if ($script:processSample) {
                $elapsed = ($now - $script:processSample.tick) / [double][Diagnostics.Stopwatch]::Frequency
                $percent = 100 * ($cpuTime - $script:processSample.cpu) / $elapsed / [Environment]::ProcessorCount
                $cpu = ('{0:F1}% of total logical CPU capacity' -f [Math]::Max(0, $percent))
            }
            $script:processSample = @{ tick = $now; cpu = $cpuTime }
            $script:processHealth = "Receiver process CPU: $cpu`r`nReceiver process working set: " +
                ('{0:F1} MiB (OS observation)' -f ($script:engine.WorkingSet64 / 1MB))
        }
        $page = Join-Path $script:runDirectory 'pairing.html'
        if (-not $script:pairingShown -and (Test-Path -LiteralPath $page)) {
            $pairing.Navigate(([uri]$page).AbsoluteUri); $script:pairingShown = $true
        }
        $statusPath = Join-Path $script:runDirectory 'status.json'
        if (Test-Path -LiteralPath $statusPath) {
            $status = [IO.File]::ReadAllText($statusPath) | ConvertFrom-Json
            $age = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [double]$status.updated_ms
            $state = if ($age -gt 5000) { 'Status unavailable: snapshot is stale.' } else { [string]$status.state }
            $rows = $status.rows | Where-Object { $_[0] -ne 'CPU and memory' }
            $health.Text = $state + "`r`n`r`n" + $script:processHealth + "`r`n" +
                (($rows | ForEach-Object { $_[0] + ': ' + $_[1] }) -join "`r`n")
        }
    } catch {
        Show-Message ('Desktop error: ' + $_.Exception.Message)
        # Do not stream after storage/bootstrap failure or hide a broken pipe.
        if (-not $script:bootstrapped) { Request-Stop }
    }
})
$form.Add_FormClosing({ param($sender, $event)
    if ($script:engine) { $event.Cancel = $true; $script:closing = $true; Request-Stop }
})
try {
    try { Refresh-Choices } catch { Show-Message $_.Exception.Message }
    if ($SmokeTest) {
        $script:smokeError = $null
        $script:smokePassed = $false
        $deadline = [DateTime]::UtcNow.AddSeconds(20)
        $smokeTimer = New-Object Windows.Forms.Timer
        $smokeTimer.Interval = 100
        $smokeTimer.Add_Tick({
            try {
                if ([DateTime]::UtcNow -gt $deadline) { throw ('Desktop smoke timed out. ' + $log.Text) }
                if ($script:engine -and $health.Text.StartsWith('Waiting for phone connection') -and
                    $health.Text.Contains('% of total logical CPU capacity') -and $health.Text.Contains('MiB (OS observation)') -and
                    $pairing.Document -and $pairing.Document.GetElementsByTagName('svg').Count -gt 0) {
                    if ($start.Enabled -or -not $stop.Enabled -or $output.Enabled) { throw 'Running controls are inconsistent.' }
                    $script:smokePassed = $true
                    $smokeTimer.Stop()
                    $script:closing = $true
                    Request-Stop
                }
            } catch {
                $script:smokeError = $_.Exception.Message
                $smokeTimer.Stop()
                $script:closing = $true
                if ($script:engine) { Request-Stop } else { $form.Close() }
            }
        })
        $form.Add_Shown({
            if ($network.SelectedIndex -ne -1 -or $output.SelectedIndex -ne -1) { throw 'Output or interface silently selected.' }
            $network.Items.Add('127.0.0.1 | loopback test') | Out-Null
            $network.SelectedIndex = $network.Items.Count - 1
            $output.SelectedIndex = 0
            $start.PerformClick()
            $smokeTimer.Start()
        })
    }
    $timer.Start()
    [Windows.Forms.Application]::Run($form)
    if ($SmokeTest) {
        if ($script:smokeError) { throw $script:smokeError }
        if (-not $script:smokePassed) { throw 'Desktop smoke did not complete.' }
        Write-Host 'Desktop UI controls, embedded QR, loopback status and graceful close passed. No audio endpoint opened.'
    }
} finally {
    $timer.Stop(); $timer.Dispose()
    if ($script:engine) { $script:engine.ControlInput.Close(); $script:engine.Dispose() }
    $form.Dispose(); $instance.Dispose()
    if ($SmokeTest) {
        if ($smokeTimer) { $smokeTimer.Dispose() }
        foreach ($path in @($secretPath, "$secretPath.pending")) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
        }
    }
}
