param(
    [ValidateSet('all', 'test', 'studio', 'personal', 'x15', 'power-test', 'indicator-test', 'sk6812-test', 'battery-test', 'settings-reset')]
    [string]$Target = 'all',
    [string]$ZmkWorkspace = 'C:\GitHub\zmk',
    [string]$ZephyrSdk = 'C:\Users\morio\zephyr-sdk-0.17.0'
)

$ErrorActionPreference = 'Stop'

$bash = 'C:\Program Files\Git\bin\bash.exe'
$west = Join-Path $ZmkWorkspace '.venv\Scripts\west.exe'
$cmake = Join-Path $ZmkWorkspace '.venv\Scripts\cmake.exe'
$ninja = Join-Path $ZmkWorkspace '.venv\Scripts\ninja.exe'

foreach ($required in @($bash, $west, $cmake, $ninja, $ZephyrSdk)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required ZMK build dependency was not found: $required"
    }
}

$env:ZMK = $ZmkWorkspace -replace '\\', '/'
$env:ZEPHYR_SDK_INSTALL_DIR = $ZephyrSdk -replace '\\', '/'
$env:PATH = "$(Join-Path $ZmkWorkspace '.venv\Scripts');$env:PATH"

& $bash (Join-Path $PSScriptRoot 'build.sh') $Target
if ($LASTEXITCODE -ne 0) {
    throw "ZMK build failed with exit code $LASTEXITCODE"
}
