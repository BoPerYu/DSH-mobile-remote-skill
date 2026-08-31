#requires -Version 5.1
<#
revoke-access.ps1 - DSH mobile remote skill: revoke remote access (A9)
- Removes the dsh-mobile-remote (trustedHosts / connection) block from cordis.patch.yml
  (backup first: cordis.patch.yml.bak-<timestamp>)
- Verifies removal via `--dump-config` (offline): the begin marker must be gone; restores
  backup if it is still present (-SkipVerify to bypass)
- Optionally stops the Tailscale serve tunnel (-AlsoStopServe; requires tailscale on PATH)
- Restart of dshd-web (restart-dshd.ps1) + phone-403 confirmation stay with the user

Usage:
  .\revoke-access.ps1
  .\revoke-access.ps1 -AlsoStopServe
  .\revoke-access.ps1 -SkipVerify
  .\revoke-access.ps1 -WhatIf

NOTE: keep this file ASCII-only (pitfall 4.17); Chinese docs live in references/desktop-app.md.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$DataRoot = "",
  [switch]$AlsoStopServe,
  [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'

$dshHome = $env:DSH_HOME
if ([string]::IsNullOrWhiteSpace($dshHome)) { throw 'DSH_HOME is not set - required precondition (desktop build)' }
if ([string]::IsNullOrWhiteSpace($DataRoot)) { $DataRoot = Split-Path -Parent $dshHome }

$patchFile = Join-Path $dshHome 'profiles\web\cordis.patch.yml'
if (-not (Test-Path $patchFile)) { throw "Patch file not found: $patchFile" }

$pattern = '(?ms)^(?:(?!# --- end )#[^\r\n]*\r?\n)*?- id: connection\b[^\r\n]*(?:\r?\n(?:[ \t]+[^\r\n]*|#[^\r\n]*))*'
$raw = [System.IO.File]::ReadAllText($patchFile)

if ($raw -notmatch $pattern) {
  Write-Host 'No trustedHosts (connection) block found; nothing to remove.' -ForegroundColor Yellow
} else {
  $new = [regex]::Replace($raw, $pattern, '', 1)
  $new = $new.TrimEnd("`r", "`n") + "`r`n"
  if ($PSCmdlet.ShouldProcess($patchFile, 'Remove trustedHosts (connection) block')) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$patchFile.bak-$stamp"
    $written = $false
    try {
      Copy-Item $patchFile $backup -Force
      Write-Host "Backup written: $backup" -ForegroundColor Cyan
      [System.IO.File]::WriteAllText($patchFile, $new, (New-Object System.Text.UTF8Encoding($false)))
      $written = $true
      Write-Host 'Removed trustedHosts block.' -ForegroundColor Green

      if (-not $SkipVerify) {
        $runtimeRoot = Join-Path $DataRoot 'runtime'
        $nodeExe = Join-Path $DataRoot 'resources\node.exe'
        $versions = Get-ChildItem $runtimeRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+\.\d+\.\d+' }
        $latest = $versions | Sort-Object { [version](($_.Name -replace '^(\d+\.\d+\.\d+).*$', '$1')) } | Select-Object -Last 1
        $node = $null
        if (Test-Path $nodeExe) { $node = $nodeExe } elseif (Get-Command node -ErrorAction SilentlyContinue) { $node = 'node' }
        if ($latest -and $node) {
          $bin = Join-Path $latest.FullName 'apps\cli\lib\bin.js'
          if (Test-Path $bin) {
            Write-Host 'Verifying removal via dump-config (offline, ~10-30 s)...'
            $dump = (& $node $bin --profile web --dump-config 2>&1 | Out-String)
            if ($dump -notmatch 'dsh-mobile-remote-begin') {
              Write-Host 'Verify OK: patch block is gone from the composed config.' -ForegroundColor Green
            } else {
              throw 'Verify FAILED - block still present; restoring backup'
            }
          } else {
            Write-Host 'WARN: runtime entry not found - skipped dump-config verify.' -ForegroundColor Yellow
          }
        } else {
          Write-Host 'WARN: node/runtime not found - skipped dump-config verify.' -ForegroundColor Yellow
        }
      }
    } catch {
      if ($written -and (Test-Path $backup)) {
        Copy-Item $backup $patchFile -Force
        Write-Host 'Restored backup after failure.' -ForegroundColor Red
      }
      throw
    }
    Write-Host 'NEXT (user steps): restart dshd-web via restart-dshd.ps1, then phone should get 403.' -ForegroundColor Green
  }
}

if ($AlsoStopServe) {
  $cmd = Get-Command tailscale -ErrorAction SilentlyContinue
  if (-not $cmd) {
    Write-Host 'WARN: tailscale not on PATH - skipped serve off.' -ForegroundColor Yellow
  } elseif ($PSCmdlet.ShouldProcess('tailscale', 'serve off')) {
    & $cmd.Source serve off
    Write-Host 'Issued: tailscale serve off. Phone should now fail to reach the URL (403 or timeout).' -ForegroundColor Green
  }
}
