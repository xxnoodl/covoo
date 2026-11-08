# Public instance metadata only. Never read link credentials into the desktop.
function Invoke-PluginQuery([string]$Executable, [string[]]$QueryArguments) {
    $process = New-ReceiverProcess $Executable $QueryArguments
    try {
        $process.ControlInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(3000)) {
            $process.Kill(); $process.WaitForExit()
            throw 'Plug-in query timed out. Refresh and select the instance again.'
        }
        if ($process.ExitCode -ne 0) { throw ('Plug-in unavailable: ' + $stderr.Result.Trim()) }
        return ($stdout.Result | ConvertFrom-Json)
    } finally { $process.Dispose() }
}

function Get-PluginRouteArguments([string]$Executable, [string]$Instance) {
    if ($Instance -cnotmatch '^[0-9a-f]{32}$') { throw 'Select an available plug-in instance or Off.' }
    $probe = Invoke-PluginQuery $Executable @('--probe-plugin', $Instance)
    if ($probe.authenticated -ne $true -or $probe.instance -cne $Instance) {
        throw 'Selected plug-in did not authenticate. Refresh and select again.'
    }
    return @('--plugin-instance', $Instance)
}
