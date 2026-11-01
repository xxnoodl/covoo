param(
    [string]$PhoneAddress,
    [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$snapshot = [ordered]@{
    schema_version = 1
    captured_utc = [DateTime]::UtcNow.ToString('o')
    note = 'Read-only Windows route snapshot, not packet-path verification or a latency measurement.'
    phone_address = $null
    adapters = @()
    addresses = @()
    best_route = @()
    errors = @()
}
if ($PhoneAddress) {
    $parsedAddress = $null
    if (-not [System.Net.IPAddress]::TryParse($PhoneAddress, [ref]$parsedAddress) -or
        $parsedAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'PhoneAddress must be a literal IPv4 address. No DNS lookup is performed.'
    }
    $snapshot.phone_address = $parsedAddress.ToString()
}
try {
    $snapshot.adapters = @(Get-NetAdapter | Select-Object ifIndex, Name,
        InterfaceDescription, Status, LinkSpeed, PnPDeviceID, PhysicalMediaType)
} catch { $snapshot.errors += "Adapters: $($_.Exception.Message)" }
try {
    $snapshot.addresses = @(Get-NetIPAddress -AddressFamily IPv4 |
        Select-Object InterfaceIndex, InterfaceAlias, IPAddress, PrefixLength, AddressState)
} catch { $snapshot.errors += "Addresses: $($_.Exception.Message)" }
if ($snapshot.phone_address) {
    try {
        # Find-NetRoute returns both the selected local address and route objects.
        $snapshot.best_route = @(Find-NetRoute -RemoteIPAddress $snapshot.phone_address |
            Select-Object InterfaceIndex, InterfaceAlias, IPAddress, DestinationPrefix,
                NextHop, RouteMetric, InterfaceMetric)
    } catch { $snapshot.errors += "Route: $($_.Exception.Message)" }
}
$json = $snapshot | ConvertTo-Json -Depth 5
if ($OutputPath) {
    [System.IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath), $json)
} else { $json }
if ($snapshot.errors.Count -gt 0) {
    Write-Warning 'Some queries failed. The snapshot contains the errors; no settings were changed.'
}
