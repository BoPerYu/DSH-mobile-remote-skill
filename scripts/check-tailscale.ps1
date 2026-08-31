#requires -Version 5.1
<#
check-tailscale.ps1 - DSH mobile remote skill: check Tailscale tunnel facts (READ-ONLY)

Fact A: tailscale CLI found and node online (not logged out)
Fact B: serve config present (serve status shows a 3080 proxy)
Fact C: (optional) serve URL answers HTTPS 200 from this machine (needs -TailnetDomain)

Usage:
  .\check-tailscale.ps1
  .\check-tailscale.ps1 -TailnetDomain "desktop-xxxx.tailxxx.ts.net"

Exit codes: 0 = pass; 1 = hard failure; 2 = warning
NOTE: keep this file ASCII-only (pitfall 4.17); Chinese docs live in references/env-check.md.
#>
[CmdletBinding()]
param(
  [string]$TailnetDomain = ""
)

$ErrorActionPreference = 'Stop'
$script:failures = @()
$script:warnings = @()
$script:tsExe = $null

function Write-Fact([string]$name, [string]$status, [string]$detail) {
  Write-Host ("[{0}] {1}: {2}" -f $status, $name, $detail)
  if ($status -eq 'FAIL') { $script:failures += $name }
  if ($status -eq 'WARN') { $script:warnings += $name }
}

# ---------- Fact A: CLI ----------
$cmd = Get-Command tailscale -ErrorAction SilentlyContinue
if ($cmd) {
  $script:tsExe = $cmd.Source
  Write-Fact 'tailscale CLI' 'PASS' $cmd.Source
} else {
  $cands = @(
    (Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'),
    (Join-Path $env:LOCALAPPDATA 'Tailscale\tailscale.exe')
  )
  $exe = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($exe) {
    $script:tsExe = $exe
    Write-Fact 'tailscale CLI' 'PASS' $exe
  } else {
    Write-Fact 'tailscale CLI' 'FAIL' 'tailscale not on PATH nor in common install locations'
  }
}

if ($script:tsExe) {
  $st = (& $script:tsExe status 2>&1 | Out-String)
  if ($st -match 'Logged out|not logged in') {
    Write-Fact 'node online' 'FAIL' 'tailscale reports logged out - log in first (manual step)'
  } elseif ($st -match 'Backend') {
    Write-Fact 'node online' 'WARN' 'daemon/backend message in status output; verify manually'
  } else {
    Write-Fact 'node online' 'PASS' 'tailscale status returned'
  }

  $sv = (& $script:tsExe serve status 2>&1 | Out-String)
  if ($sv -match 'proxy http://127\.0\.0\.1:3080') {
    Write-Fact 'serve config' 'PASS' 'serve is proxying to 127.0.0.1:3080'
  } elseif ([string]::IsNullOrWhiteSpace($sv)) {
    Write-Fact 'serve config' 'FAIL' 'serve status is empty - run serve-dsh.ps1 first'
  } else {
    Write-Fact 'serve config' 'WARN' ("unexpected serve output: " + (($sv -split "`r?`n" | Where-Object { $_ -ne '' } | Select-Object -First 2) -join ' | '))
  }

  # serve URL domain vs -TailnetDomain consistency (mismatch => /api 403 even if everything else passes)
  $serveDomain = $null
  if ($sv -match 'https://([^\s/]+)') { $serveDomain = $Matches[1] }
  if ($TailnetDomain -and $serveDomain) {
    if ($serveDomain -ieq $TailnetDomain) {
      Write-Fact 'serve/domain match' 'PASS' "serve URL domain == $TailnetDomain"
    } else {
      Write-Fact 'serve/domain match' 'FAIL' "serve serves '$serveDomain' but -TailnetDomain is '$TailnetDomain' - /api will 403"
    }
  } else {
    $note = if ($serveDomain) { 'no -TailnetDomain given' } else { 'serve URL not found in output' }
    Write-Fact 'serve/domain match' 'SKIP' $note
  }
}

# ---------- Fact C: HTTPS probe (optional) ----------
if ($TailnetDomain -and $script:tsExe) {
  try {
    $r = Invoke-WebRequest -Uri "https://$TailnetDomain/" -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
    Write-Fact 'serve URL' 'PASS' "HTTPS $($r.StatusCode)"
  } catch {
    Write-Fact 'serve URL' 'FAIL' ("HTTPS probe failed: " + $_.Exception.Message)
  }
} elseif ($TailnetDomain) {
  Write-Fact 'serve URL' 'SKIP' 'tailscale CLI unavailable'
} else {
  Write-Fact 'serve URL' 'SKIP' 'no -TailnetDomain given'
}

# ---------- summary ----------
Write-Host ''
if ($script:failures.Count -gt 0) {
  Write-Host "Verdict: FAIL - $($script:failures -join ', ')" -ForegroundColor Red
  if ($script:warnings.Count -gt 0) { Write-Host "Also warnings: $($script:warnings -join ', ')" -ForegroundColor Yellow }
  exit 1
} elseif ($script:warnings.Count -gt 0) {
  Write-Host "Verdict: WARN - $($script:warnings -join ', ')" -ForegroundColor Yellow
  exit 2
} else {
  Write-Host 'Verdict: PASS' -ForegroundColor Green
  exit 0
}
