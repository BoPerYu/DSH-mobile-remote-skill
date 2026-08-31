#requires -Version 5.1
<#
patch-trusted-host.ps1 - DSH mobile remote skill: apply/refresh the trustedHosts patch
(static replacement, A-plan).

- Edits $env:DSH_HOME\profiles\web\cordis.patch.yml
- Replaces or appends the dsh-mobile-remote block: trustedHosts = [<domain>]
- Backs up the patch file before writing (cordis.patch.yml.bak-<timestamp>)
- Writes via temp file + restore-on-any-failure (try/catch, not just verify failure)
- Verifies via `--dump-config` (offline, no boot); restores backup if verify fails
- Does NOT restart dshd-web (HMR disabled; use restart-dshd.ps1 as a confirmed step)

Usage:
  .\patch-trusted-host.ps1 -TailnetDomain "desktop-xxxx.tailxxx.ts.net"
  .\patch-trusted-host.ps1 -TailnetDomain "..." -DataRoot "C:\path\to\app-data" -SkipVerify
  .\patch-trusted-host.ps1 -TailnetDomain "..." -WhatIf      # preview only, no writes

NOTE: keep this file ASCII-only (pitfall 4.17); Chinese docs live in references/desktop-app.md.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(Mandatory = $true)][string]$TailnetDomain,
  [string]$DataRoot = "",
  [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'

if ($TailnetDomain -match '[\s"''<>]' -or $TailnetDomain -eq '') {
  throw 'TailnetDomain must be a bare host name (no spaces/quotes/angle brackets), e.g. desktop-xxxx.tailxxx.ts.net'
}

$dshHome = $env:DSH_HOME
if ([string]::IsNullOrWhiteSpace($dshHome)) { throw 'DSH_HOME is not set - required precondition (desktop build)' }
if ([string]::IsNullOrWhiteSpace($DataRoot)) { $DataRoot = Split-Path -Parent $dshHome }
if (-not (Test-Path $dshHome)) { throw "DSH_HOME does not exist: $dshHome" }

$patchFile = Join-Path $dshHome 'profiles\web\cordis.patch.yml'
if (-not (Test-Path $patchFile)) { throw "Patch file not found: $patchFile (run the desktop app once so it is generated)" }

# ---- build the new block (ASCII markers) ----
$begin = '# --- dsh-mobile-remote-begin ---'
$end   = '# --- dsh-mobile-remote-end ---'
$lines = @(
  $begin,
  '# connection.trustedHosts: z.array(String) - DSH host fence (DNS-rebinding protection).',
  '# Static replacement (A-plan): this list fully replaces runtime-derived entries.',
  '# Desktop build binds 127.0.0.1, so no LAN entries are lost.',
  '- id: connection',
  '  config:',
  '    trustedHosts:',
  "      - $TailnetDomain",
  $end
)
$block = ($lines -join "`r`n")

# ---- locate existing connection entry (never cross foreign "# --- end " comment chains) ----
$pattern = '(?ms)^(?:(?!# --- end )#[^\r\n]*\r?\n)*?- id: connection\b[^\r\n]*(?:\r?\n(?:[ \t]+[^\r\n]*|#[^\r\n]*))*'

$raw = [System.IO.File]::ReadAllText($patchFile)
if ($raw -match $pattern) {
  $new = [regex]::Replace($raw, $pattern, { param($m) $block }, 1)
} else {
  $new = $raw.TrimEnd("`r", "`n") + "`r`n" + $block + "`r`n"
}

if ($new -eq $raw) {
  Write-Host "Already in place: $TailnetDomain in $patchFile (no change needed)." -ForegroundColor Green
  exit 0
}

Write-Host 'Proposed new block:'
Write-Host '----------------------------------------'
Write-Host $block
Write-Host '----------------------------------------'

if ($PSCmdlet.ShouldProcess($patchFile, 'Apply trustedHosts static replacement')) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $backup = "$patchFile.bak-$stamp"
  $tmp = "$patchFile.tmp"
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  $written = $false
  try {
    Copy-Item $patchFile $backup -Force
    Write-Host "Backup written: $backup" -ForegroundColor Cyan
    [System.IO.File]::WriteAllText($tmp, $new, $utf8)
    Copy-Item $tmp $patchFile -Force
    Remove-Item $tmp -Force
    $written = $true

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
          Write-Host 'Verifying via dump-config (offline, ~10-30 s)...'
          $dump = (& $node $bin --profile web --dump-config 2>&1 | Out-String)
          if ($dump -match [regex]::Escape($TailnetDomain) -and $dump -match 'patched by') {
            Write-Host 'Verify OK: composed config now contains the domain.' -ForegroundColor Green
          } else {
            throw 'Verify FAILED - restoring backup'
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
    if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    throw
  }
  Write-Host 'Patch applied. NEXT (confirmed step): restart dshd-web via restart-dshd.ps1, then phone 200 check.' -ForegroundColor Green
}
exit 0
