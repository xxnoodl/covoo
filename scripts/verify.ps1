$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    $localCargo = Join-Path $repoRoot '.tools\cargo\bin\cargo.exe'
    if (Test-Path -LiteralPath $localCargo) {
        $env:CARGO_HOME = Join-Path $repoRoot '.tools\cargo'
        $env:RUSTUP_HOME = Join-Path $repoRoot '.tools\rustup'
        $env:PATH = (Split-Path -Parent $localCargo) + ';' + $env:PATH
    }
    if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
        throw 'Cargo is unavailable. Install Rust and MSVC as described in README.md.'
    }
    function Invoke-Cargo {
        param([string[]]$CargoArgs)
        Write-Host ('cargo ' + ($CargoArgs -join ' '))
        & cargo @CargoArgs
        if ($LASTEXITCODE -ne 0) { throw "Cargo check failed with exit code $LASTEXITCODE" }
    }
    Invoke-Cargo -CargoArgs @('fmt', '--all', '--', '--check')
    Invoke-Cargo -CargoArgs @('clippy', '--workspace', '--all-targets', '--locked', '--', '-D', 'warnings')
    Invoke-Cargo -CargoArgs @('test', '--workspace', '--locked')
    Invoke-Cargo -CargoArgs @('build', '--workspace', '--release', '--locked')
    Invoke-Cargo -CargoArgs @('run', '-p', 'windows-receiver', '--locked')
} finally {
    Pop-Location
}
