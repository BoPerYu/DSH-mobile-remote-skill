#requires -Version 5.1
<#
restart-dshd.ps1 - DSH mobile remote skill: restart the desktop web process (dshd-web)

- Kills the process recorded in <data-root>\dshd-web.pid (harnessAutoRestart brings it back)
- Polls port 3080 until it listens again (up to ~25 s; auto-restart is 1-3 s x3 + boot)
- Reports old/new PID and final state
- Does NOT touch the patch file or Tailscale

Usage:
  .\restart-dshd.ps1
  .\restart-dshd.ps1 -DataRoot "C:\path\to\app-data"
  .\restart-dshd.ps1 -WhatIf

NOTE: keep this file ASCII-only (pitfall 4.17); Chinese docs live in references/desktop-app.md.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$DataRoot = ""
)

$ErrorActionPreference = 'Stop'

$dshHome = $env:DSH_HOME
if ([string]::IsNullOrWhiteSpace($dshHome)) { throw 'DSH_HOME is not set - required precondition (desktop build)' }
if ([string]::IsNullOrWhiteSpace($DataRoot)) { $DataRoot = Split-Path -Parent $dshHome }

$pidFile = Join-Path $DataRoot 'dshd-web.pid'
if (-not (Test-Path $pidFile)) { throw "PID file not found: $pidFile (desktop not running?)" }

$oldPid = [int]((Get-Content $pidFile -Raw).Trim())
$oldProc = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
$stopped = $false

if (-not $oldProc) {
  Write-Host "PID $oldPid from $pidFile is not running; checking whether 3080 is already served..." -ForegroundColor Yellow
} elseif ($PSCmdlet.ShouldProcess("PID $oldPid ($($oldProc.ProcessName))", 'Stop dshd-web for auto-restart')) {
  Stop-Process -Id $oldPid -Force
  $stopped = $true
  Write-Host "Stopped PID $oldPid; waiting for harnessAutoRestart to bring it back..." -ForegroundColor Cyan
}

if (-not $stopped -and $oldProc -and $PSCmdlet.MyInvocation.BoundParameters.ContainsKey('WhatIf')) {
  Write-Host 'WhatIf: no changes made. Run without -WhatIf to actually restart.' -ForegroundColor Yellow
  exit 0
}

# poll for 3080 (skip polling if nothing was stopped and the process was already gone)
$deadline = (Get-Date).AddSeconds(25)
$newOwner = $null
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Milliseconds 800
  $c = Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { $newOwner = $c.OwningProcess; break }
}

if (-not $newOwner) {
  Write-Host 'TIMEOUT: 3080 did not come back within 25 s. Check the desktop app window / dshd-web.pid.' -ForegroundColor Red
  exit 1
}

$newProc = Get-Process -Id $newOwner -ErrorAction SilentlyContinue
Write-Host "Back on 3080: PID $newOwner = $($newProc.ProcessName) @ $($newProc.Path)" -ForegroundColor Green
Write-Host 'Restart OK. Verify next: scripts/env-check.ps1 and phone access.' -ForegroundColor Green
exit 0
