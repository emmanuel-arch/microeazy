# ─────────────────────────────────────────────────────────────────────────────
# INSTALL THE RELAYS AS WINDOWS SERVICES.
#
#   powershell -ExecutionPolicy Bypass -File install-services.ps1 -Crb
#   powershell -ExecutionPolicy Bypass -File install-services.ps1 -Sql -Crb
#
# Run as Administrator. Install ONLY the relays check-host.ps1 approved.
#
# WHY THIS MATTERS: `npm run relay` in an RDP window dies the moment you log
# off. That is the entire gap between "it worked when I tested it" and "it is
# still working at 6am". A service also comes back after a reboot, which is the
# only failure that takes all six systems down at once.
#
# Needs NSSM on PATH (https://nssm.cc) - Node has no service wrapper of its own.
#
# To undo:  nssm stop <name> ; nssm remove <name> confirm
# ─────────────────────────────────────────────────────────────────────────────

param(
  [switch]$Sql,
  [switch]$Crb,
  [string]$Nssm = "nssm"
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

if (-not $Sql -and -not $Crb) {
  Write-Host "Nothing to do. Pass -Sql and/or -Crb (run check-host.ps1 first)." -ForegroundColor Yellow
  exit 1
}
if (-not (Get-Command $Nssm -ErrorAction SilentlyContinue)) {
  Write-Host "NSSM not found. Install it or pass -Nssm C:\path\to\nssm.exe" -ForegroundColor Red
  exit 1
}
if (-not (Test-Path (Join-Path $root ".env"))) {
  Write-Host "No .env beside package.json. Copy .env.example to .env and fill it in first." -ForegroundColor Red
  exit 1
}

$node = (Get-Command node).Source
$logs = Join-Path $root "logs"
if (-not (Test-Path $logs)) { New-Item -ItemType Directory $logs | Out-Null }

function Install-Relay($name, $params) {
  Write-Host "installing $name ..." -ForegroundColor White
  & $Nssm install $name $node $params
  # AppDirectory is load-bearing: both relays resolve .env relative to it.
  & $Nssm set $name AppDirectory $root
  & $Nssm set $name Start SERVICE_AUTO_START
  & $Nssm set $name AppStdout (Join-Path $logs "$name.out.log")
  & $Nssm set $name AppStderr (Join-Path $logs "$name.err.log")
  & $Nssm set $name AppRotateFiles 1
  & $Nssm set $name AppRotateBytes 10485760
  # Come back after a crash, but stop flapping if it cannot start at all.
  & $Nssm set $name AppExit Default Restart
  & $Nssm set $name AppRestartDelay 5000
  & $Nssm start $name
  Write-Host "  started $name" -ForegroundColor Green
}

if ($Sql) {
  $tsx = Join-Path $root "node_modules\tsx\dist\cli.mjs"
  if (-not (Test-Path $tsx)) {
    Write-Host "node_modules\tsx not found - run `npm install` in $root first." -ForegroundColor Red
    exit 1
  }
  # node + tsx CLI directly, NOT npx.cmd: a .cmd shim under a service wrapper
  # is an extra process that swallows exit codes and confuses restarts.
  Install-Relay "MicroEazySqlRelay" "`"$tsx`" scripts\sql-relay.ts"
}

if ($Crb) {
  Install-Relay "MicroEazyCrbRelay" "scripts\crb-relay.mjs"
}

Write-Host ""
Write-Host "Check the logs directory for the boot lines - the CRB relay prints" -ForegroundColor DarkGray
Write-Host "the public IP it egresses from, which is the address Metropol checks." -ForegroundColor DarkGray
Write-Host ""
Write-Host "Now REBOOT and confirm both come back. That is the only real test." -ForegroundColor Yellow
Write-Host ""
