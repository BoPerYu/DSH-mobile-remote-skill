#requires -Version 5.1
<#
verify-access.ps1 - DSH mobile remote skill: end-to-end access check (READ-ONLY)

- HTTPS 200 on the tailnet URL (proves serve + TLS reachable; NOTE: NOT the /api fence)
- -ApiProbe: POST /api/session.list with the client-request envelope and assert
  result.ok=true - this is the real host-fence acceptance test (probe payload is not printed)
- Reuses env-check.ps1 to confirm the trustedHosts patch is in place (-SkipPatchCheck to skip)

Usage:
  .\verify-access.ps1 -TailnetDomain "desktop-xxxx.tailxxx.ts.net"
  .\verify-access.ps1 -TailnetDomain "..." -ApiProbe
  .\verify-access.ps1 -TailnetDomain "..." -SkipPatchCheck

Exit codes: 0 = pass; 1 = failure
NOTE: keep this file ASCII-only (pitfall 4.17); Chinese docs live in references/env-check.md.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$TailnetDomain,
  [switch]$SkipPatchCheck,
  [switch]$ApiProbe
)

$ErrorActionPreference = 'Stop'
$script:failures = @()

function Write-Fact([string]$name, [string]$status, [string]$detail) {
  Write-Host ("[{0}] {1}: {2}" -f $status, $name, $detail)
  if ($status -eq 'FAIL') { $script:failures += $name }
}

# ---------- HTTPS 200 (tunnel layer only) ----------
try {
  $r = Invoke-WebRequest -Uri "https://$TailnetDomain/" -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
  if ($r.StatusCode -eq 200) {
    Write-Fact 'HTTPS 200' 'PASS' "https://$TailnetDomain/ -> 200 (serve+TLS layer only; /api fence needs -ApiProbe)"
  } else {
    Write-Fact 'HTTPS 200' 'FAIL' "unexpected status $($r.StatusCode)"
  }
} catch {
  Write-Fact 'HTTPS 200' 'FAIL' ("probe failed: " + $_.Exception.Message)
}

# ---------- API fence probe (real acceptance) ----------
if ($ApiProbe) {
  $uri = "https://$TailnetDomain/api/session.list"
  $body = @{
    type = 'client-request'
    rpcId = ('probe-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    method = 'session.list'
    payload = @{}
  } | ConvertTo-Json -Depth 6
  try {
    $resp = Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 25 -ErrorAction Stop
    if ($resp.result.ok -eq $true) {
      Write-Fact 'API fence probe' 'PASS' 'session.list result.ok=true (host fence accepts this domain)'
    } else {
      $snippet = ($resp.result | ConvertTo-Json -Compress -Depth 3)
      if ($snippet.Length -gt 160) { $snippet = $snippet.Substring(0, 160) }
      Write-Fact 'API fence probe' 'FAIL' ('result.ok != true: ' + $snippet)
    }
  } catch {
    $status = $_.Exception.Response.StatusCode
    if ($status) {
      Write-Fact 'API fence probe' 'FAIL' "HTTP $([int]$status) - fence rejects this host, or endpoint/envelope differs (see troubleshooting)"
    } else {
      Write-Fact 'API fence probe' 'FAIL' ("probe failed: " + $_.Exception.Message)
    }
  }
} else {
  Write-Fact 'API fence probe' 'SKIP' 'add -ApiProbe to verify the /api host fence (HTTPS 200 alone is not enough)'
}

# ---------- patch check via env-check ----------
if (-not $SkipPatchCheck) {
  $envCheck = Join-Path $PSScriptRoot 'env-check.ps1'
  if (Test-Path $envCheck) {
    & $envCheck -TailnetDomain $TailnetDomain
    if ($LASTEXITCODE -eq 0) {
      Write-Fact 'patch check' 'PASS' 'env-check all pass'
    } else {
      Write-Fact 'patch check' 'FAIL' "env-check exit=$LASTEXITCODE (see output above)"
    }
  } else {
    Write-Fact 'patch check' 'WARN' 'env-check.ps1 not found next to this script; skipped'
  }
} else {
  Write-Fact 'patch check' 'SKIP' 'SkipPatchCheck given'
}

# ---------- summary ----------
Write-Host ''
if ($script:failures.Count -gt 0) {
  Write-Host "Verdict: FAIL - $($script:failures -join ', ')" -ForegroundColor Red
  exit 1
}
Write-Host 'Verdict: PASS' -ForegroundColor Green
exit 0
