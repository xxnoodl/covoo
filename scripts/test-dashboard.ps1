param([string]$ReceiverPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $ReceiverPath) { $ReceiverPath = Join-Path $repo 'target\release\windows-receiver.exe' }
$edge = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
if (-not (Test-Path -LiteralPath $ReceiverPath)) { throw 'Build the release receiver first.' }
if (-not (Test-Path -LiteralPath $edge)) { throw 'This browser check requires installed Microsoft Edge.' }
$folder = Join-Path $repo ('build\dashboard-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$recordings = Join-Path $folder 'recordings'
& $ReceiverPath --serve --host 127.0.0.1 --port 0 --seconds 2 --no-discovery --output $recordings > (Join-Path $folder 'receiver.log') 2>&1
if ($LASTEXITCODE -ne 0) { throw "File-only loopback receiver failed. Logs: $folder" }

function Read-BrowserDom([string]$Path, [string]$Name) {
    $uri = ([uri]$Path).AbsoluteUri
    $profile = Join-Path $folder 'browser-profile'
    $result = Join-Path $folder "$Name-dom.html"
    & $edge --headless --disable-gpu --no-first-run "--user-data-dir=$profile" --dump-dom $uri 2> (Join-Path $folder "$Name-browser.log") | Set-Content $result
    if ($LASTEXITCODE -ne 0) { throw "Headless browser failed. Logs: $folder" }
    return Get-Content -LiteralPath $result -Raw
}

$page = Join-Path $recordings 'dashboard.html'
$dom = Read-BrowserDom $page 'stopped'
if ($dom -notmatch '<p id="freshness">Receiver stopped\. Final status snapshot\. Last update:') {
    throw 'Browser did not render the stopped freshness label.'
}
$fixture = (Get-Content -LiteralPath $page -Raw) -replace 'const stopped = true;', 'const stopped = false;'
$fixture = $fixture -replace 'const updated = \d+;', 'const updated = 0;'
$stale = Join-Path $folder 'stale.html'
[IO.File]::WriteAllText($stale, $fixture)
$dom = Read-BrowserDom $stale 'stale'
if ($dom -notmatch '<p id="freshness">Updates paused\. This snapshot may be stale\.' -or
    $dom -notmatch '<p id="state">Status unavailable</p>') {
    throw 'Browser did not mark the old running fixture stale.'
}
Write-Host "Dashboard browser checks passed. Evidence: $folder"
