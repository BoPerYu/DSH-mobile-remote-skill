#requires -Version 5.1
<#
serve-dsh.ps1 - DSH mobile remote skill: (re)start the Tailscale serve tunnel to port 3080

- Idempotent: re-issuing the same serve config is a no-op on the tailnet node
- Real state change (tailnet serve config) - preview with -WhatIf first
- Serve config persists across restarts (verified 2026-08-31), so this is only needed
  after `tailscale serve off`, `tailscale reset`, or a fresh install

Usage:
  .\serve-dsh.ps1
  .\serve-dsh.ps1 -Port 3080
  .\serve-dsh.ps1 -WhatIf

NOTE: keep this file ASCII-only (pitfall 4.17); Chinese docs live in references/env-check.md.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [int]$Port = 3080
)

$ErrorActionPreference = 'Stop'

$cmd = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $cmd) { throw 'tailscale CLI not found (not on PATH)' }

if ($PSCmdlet.ShouldProcess("tailscale serve --bg $Port", 'Start serve tunnel')) {
  & $cmd.Source serve --bg $Port
  if ($LASTEXITCODE -ne 0) {
    Write-Host "serve --bg $Port failed (exit $LASTEXITCODE). Check: tailscale status / logged in." -ForegroundColor Red
    exit 1
  }
  Write-Host "serve --bg $Port issued. Verify: check-tailscale.ps1 -TailnetDomain <machine>.<tailnet>.ts.net" -ForegroundColor Green
}
exit 0
