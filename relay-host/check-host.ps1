# ─────────────────────────────────────────────────────────────────────────────
# RELAY HOST CHECK — run this FIRST, on the candidate machine.
#
#   powershell -ExecutionPolicy Bypass -File check-host.ps1
#
# It answers one question: which of the two relays can this box actually run?
# The two relays have completely different requirements and a machine that can
# run one often cannot run the other.
#
#   SQL relay  needs a TAILNET ROUTE to 100.72.35.56,4230
#   CRB relay  needs a WHITELISTED PUBLIC EGRESS IP (Metropol opens 22225 only
#              for registered addresses, so a successful handshake IS the proof)
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Continue"
function Line($s) { Write-Host $s }
function Ok($s)   { Write-Host "  [ OK ] $s"   -ForegroundColor Green }
function No($s)   { Write-Host "  [FAIL] $s"   -ForegroundColor Red }
function Note($s) { Write-Host "         $s"   -ForegroundColor DarkGray }

Line ""
Write-Host "RELAY HOST CHECK  --  $env:COMPUTERNAME" -ForegroundColor White
Line ""

# ── Toolchain ────────────────────────────────────────────────────────────────
Write-Host "1 - Toolchain" -ForegroundColor White
$node = (Get-Command node -ErrorAction SilentlyContinue)
if ($node) { Ok "node $(node -v)  ($($node.Source))" }
else { No "node is not on PATH - neither relay can run"; Note "https://nodejs.org - LTS x64 MSI" }

$npm = (Get-Command npm -ErrorAction SilentlyContinue)
if ($npm) { Ok "npm $(npm -v)" }
else { No "npm is not on PATH - the SQL relay needs it (the CRB relay does not)" }

# ── CRB eligibility ──────────────────────────────────────────────────────────
Line ""
Write-Host "2 - CRB relay: is this box whitelisted by Metropol?" -ForegroundColor White
$crb = Test-NetConnection api.metropol.co.ke -Port 22225 -WarningAction SilentlyContinue
if ($crb.TcpTestSucceeded) {
  Ok "port 22225 open - this address IS registered"
  # .SourceAddress is a CIM MSFT_NetIPAddress instance, not a string - without
  # .IPAddress it stringifies to an unreadable object dump.
  Note "source $($crb.SourceAddress.IPAddress) via $($crb.InterfaceAlias)"
  $CAN_CRB = $true
} else {
  No "port 22225 did not open - this address is NOT registered"
  Note "Unregistered addresses hang and die rather than refusing, so this is"
  Note "proof of exclusion, not a transient network fault. Do not run the CRB"
  Note "relay here: every bureau call would be dropped silently at their edge."
  $CAN_CRB = $false
}

try {
  $pub = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10)
  Note "public egress appears to be $pub"
  if ($pub -eq "102.214.69.233" -or $pub -eq "102.210.148.110") { Note "-> on the 2026-08-27 whitelist form" }
  else { Note "-> NOT on the 2026-08-27 form (102.214.69.233 / 102.210.148.110)" }
} catch { Note "could not determine public egress IP (the relay prints it on boot anyway)" }

# ── SQL eligibility ──────────────────────────────────────────────────────────
Line ""
Write-Host "3 - SQL relay: can this box reach Micromart's server?" -ForegroundColor White
$sql = Test-NetConnection 100.72.35.56 -Port 4230 -WarningAction SilentlyContinue
if ($sql.TcpTestSucceeded) {
  Ok "100.72.35.56,4230 reachable via $($sql.InterfaceAlias)"
  $CAN_SQL = $true
} else {
  No "100.72.35.56,4230 unreachable (went out via $($sql.InterfaceAlias))"
  Note "100.64.0.0/10 is Tailscale CGNAT space. If the interface above is not a"
  Note "Tailscale adapter, this box has no tailnet route and CANNOT host the SQL"
  Note "relay - install/repair Tailscale, or host that relay elsewhere."
  $CAN_SQL = $false
}

# ── Tailscale / publishing ───────────────────────────────────────────────────
Line ""
Write-Host "4 - Publishing" -ForegroundColor White
$ts = (Get-Command tailscale -ErrorAction SilentlyContinue)
if ($ts) {
  Ok "tailscale present"
  Write-Host ""
  tailscale funnel status
} else {
  No "tailscale not on PATH - cannot publish with Funnel from this box"
  Note "Either install Tailscale, or reverse-proxy 127.0.0.1:8787/8788 from IIS."
}

# ── Verdict ──────────────────────────────────────────────────────────────────
Line ""
Write-Host "VERDICT" -ForegroundColor White
if ($CAN_SQL) { Ok "run the SQL relay here (port 8787)" } else { No "do NOT run the SQL relay here" }
if ($CAN_CRB) { Ok "run the CRB relay here (port 8788)" } else { No "do NOT run the CRB relay here" }
if ($CAN_SQL -and $CAN_CRB) {
  Line ""
  Note "BOTH on this node: they collide on 443. Funnel offers 443/8443/10000, so"
  Note "publish one on each - see README section 5."
}
Line ""
