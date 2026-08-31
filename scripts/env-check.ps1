#requires -Version 5.1
<#
env-check.ps1 - DSH mobile remote skill: environment three-fact check (READ-ONLY)

Fact 1: who owns TCP port 3080 (is the desktop dshd-web serving?)
Fact 2: is the dshd-web.pid process alive and identical to the 3080 owner?
Fact 3: is the connection.trustedHosts patch in place? (--dump-config compare; offline, no boot)

Usage:
  .\env-check.ps1 -TailnetDomain "desktop-xxxx.tailxxx.ts.net"
  .\env-check.ps1 -TailnetDomain "desktop-xxxx.tailxxx.ts.net" -DataRoot "C:\path\to\app-data"
  .\env-check.ps1 -SkipDumpConfig

Exit codes: 0 = all pass, safe to continue; 1 = hard failure (do not continue); 2 = warning (continue with care)

Layout assumption (desktop build): $env:DSH_HOME points to <data-root>\dsh-home; the data root
contains runtime\<ver>\ and dshd-web.pid. NOTE: keep this file ASCII-only so it parses under any
codepage (GBK/UTF-8); Chinese docs live in references/env-check.md.
#>
param(
  [string]$TailnetDomain = "",
  [string]$DataRoot = "",
  [switch]$SkipDumpConfig
)

$ErrorActionPreference = 'Stop'
$script:failures = @()
$script:warnings = @()

function Write-Fact([string]$name, [string]$status, [string]$detail) {
  Write-Host ("[{0}] {1}: {2}" -f $status, $name, $detail)
  if ($status -eq 'FAIL') { $script:failures += $name }
  if ($status -eq 'WARN') { $script:warnings += $name }
}

# ---------- layout ----------
$dshHome = $env:DSH_HOME
if ([string]::IsNullOrWhiteSpace($dshHome)) {
  Write-Fact 'DSH_HOME' 'FAIL' '$env:DSH_HOME is not set - required precondition; expected ...\Deepseek-Harness-Desktop\dsh-home'
} else {
  Write-Fact 'DSH_HOME' 'PASS' $dshHome
}

if ([string]::IsNullOrWhiteSpace($DataRoot)) {
  if ($dshHome) { $DataRoot = Split-Path -Parent $dshHome }  # desktop data root = parent of dsh-home
}
if ($DataRoot -and -not (Test-Path $DataRoot)) {
  Write-Fact 'DataRoot' 'FAIL' "$DataRoot does not exist"
  $DataRoot = ''
}

# ---------- Fact 2: dshd-web.pid ----------
$webPid = $null
if ($DataRoot) {
  $pidFile = Join-Path $DataRoot 'dshd-web.pid'
  if (Test-Path $pidFile) {
    $raw = (Get-Content $pidFile -Raw).Trim()
    if ($raw -match '^\d+$') {
      $webPid = [int]$raw
      $proc = Get-Process -Id $webPid -ErrorAction SilentlyContinue
      if ($proc) {
        Write-Fact 'dshd-web process' 'PASS' "PID $webPid = $($proc.ProcessName) @ $($proc.Path)"
      } else {
        Write-Fact 'dshd-web process' 'FAIL' "PID file exists but process $webPid is not running (desktop not started or stale PID)"
      }
    } else {
      Write-Fact 'dshd-web.pid' 'WARN' "PID file content is not numeric: '$raw'"
    }
  } else {
    Write-Fact 'dshd-web.pid' 'WARN' "Not found: $pidFile (desktop may not be running, or layout differs)"
  }
} else {
  Write-Fact 'dshd-web.pid' 'SKIP' 'DataRoot missing, skipped'
}

# ---------- Fact 1: 3080 owner ----------
$owner = Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $owner) {
  Write-Fact 'Port 3080' 'FAIL' 'Nothing listens on 3080 - desktop DSH not running, or port rebound/occupied'
} else {
  $op = Get-Process -Id $owner.OwningProcess -ErrorAction SilentlyContinue
  if ($op) {
    $path = if ($op.Path) { $op.Path } else { '<unreadable>' }
    $looksDesktop = $path -match 'Deepseek-Harness-Desktop'
    $detail = "PID $($owner.OwningProcess) = $($op.ProcessName) @ $path"
    if ($webPid -and $owner.OwningProcess -ne $webPid) {
      Write-Fact 'Port 3080 owner' 'FAIL' "$detail - differs from dshd-web.pid ($webPid)! Possibly a CLI/other instance holds it"
    } elseif ($looksDesktop) {
      Write-Fact 'Port 3080 owner' 'PASS' "$detail - desktop instance is serving"
    } else {
      Write-Fact 'Port 3080 owner' 'WARN' "$detail - path lacks Deepseek-Harness-Desktop; may not be the desktop instance"
    }
  } else {
    Write-Fact 'Port 3080 owner' 'WARN' "Cannot read process info for PID $($owner.OwningProcess)"
  }
}

# ---------- Fact 3: patch in place ----------
if ($SkipDumpConfig) {
  Write-Fact 'trustedHosts patch' 'SKIP' 'SkipDumpConfig given'
} elseif (-not $DataRoot) {
  Write-Fact 'trustedHosts patch' 'FAIL' 'DataRoot missing; cannot run dump-config'
} else {
  $runtimeRoot = Join-Path $DataRoot 'runtime'
  $nodeExe = Join-Path $DataRoot 'resources\node.exe'
  if (-not (Test-Path $runtimeRoot)) {
    Write-Fact 'runtime dir' 'FAIL' "Not found: $runtimeRoot"
  } else {
    $versions = Get-ChildItem $runtimeRoot -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+' }
    $latest = $versions | Sort-Object { [version](($_.Name -replace '^(\d+\.\d+\.\d+).*$', '$1')) } | Select-Object -Last 1
    if (-not $latest) {
      Write-Fact 'runtime dir' 'FAIL' "No version directory under $runtimeRoot (expected e.g. 0.2.7)"
    } else {
      $bin = Join-Path $latest.FullName 'apps\cli\lib\bin.js'
      if (-not (Test-Path $bin)) {
        Write-Fact 'runtime entry' 'FAIL' "Not found: $bin"
      } else {
        $node = $null
        if (Test-Path $nodeExe) { $node = $nodeExe } elseif (Get-Command node -ErrorAction SilentlyContinue) { $node = 'node' }
        if (-not $node) {
          Write-Fact 'node runtime' 'FAIL' "Neither $nodeExe nor a PATH 'node' was found"
        } else {
          Write-Host "    Running dump-config ($($latest.Name)); takes ~10-30 s..."
          $dump = (& $node $bin --profile web --dump-config 2>&1 | Out-String)
          if ($dump -match 'trustedHosts' -and $dump -match 'patched by' -and $dump -match 'cordis\.patch\.yml') {
            if ($TailnetDomain -and $dump -notmatch [regex]::Escape($TailnetDomain)) {
              Write-Fact 'trustedHosts patch' 'FAIL' "Patch layer present but target domain $TailnetDomain not found (overwritten/reset?)"
            } else {
              $note = if ($TailnetDomain) { "contains $TailnetDomain" } else { 'patch layer present (no -TailnetDomain given; cannot confirm target)' }
              Write-Fact 'trustedHosts patch' 'PASS' $note
            }
          } else {
            Write-Fact 'trustedHosts patch' 'FAIL' 'dump-config shows no patched layer (trustedHosts + "patched by cordis.patch.yml") - patch missing or not applied'
          }
        }
      }
    }
  }
}

# ---------- summary ----------
Write-Host ''
if ($script:failures.Count -gt 0) {
  Write-Host "Verdict: FAIL - hard failures: $($script:failures -join ', ')" -ForegroundColor Red
  if ($script:warnings.Count -gt 0) { Write-Host "Also warnings: $($script:warnings -join ', ')" -ForegroundColor Yellow }
  exit 1
} elseif ($script:warnings.Count -gt 0) {
  Write-Host "Verdict: WARN - continue with care: $($script:warnings -join ', ')" -ForegroundColor Yellow
  exit 2
} else {
  Write-Host 'Verdict: PASS - all three facts pass; safe to proceed with patch/verify' -ForegroundColor Green
  exit 0
}
