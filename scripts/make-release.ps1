<#
  Build a TyControls release bundle for a GitHub release.

  Ships ONLY what a consumer needs to use the library — the runtime + design-time
  source, the Lazarus packages, themes, user docs and examples — laid out exactly
  as in the repo so `tycontrols.lpk` / `tycontrols_dt.lpk` install unchanged.

  EXCLUDED: tests, tools/ (icon generator), scripts/, docs/superpowers (specs/plans),
  designtime/icons (PNG regeneration source — the packed .lrs is shipped instead),
  the auto-generated package units, and every build artifact (lib/, *.ppu/.o/.exe, ...).

  Output: dist/TyControls-<version>.zip  (dist/ is git-ignored).
  Usage:  pwsh -File scripts/make-release.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

# --- version (from the single source of truth) -----------------------------
$typesPath = Join-Path $root 'source/tyControls.Types.pas'
$m = [regex]::Match((Get-Content $typesPath -Raw), "TyVersion\s*=\s*'([^']+)'")
if (-not $m.Success) { throw "could not read TyVersion from $typesPath" }
$version = $m.Groups[1].Value
Write-Host "== TyControls release v$version =="

# --- staging ---------------------------------------------------------------
$distDir = Join-Path $root 'dist'
$stage   = Join-Path $distDir "TyControls-$version"
$zip     = Join-Path $distDir "TyControls-$version.zip"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
if (Test-Path $zip)   { Remove-Item $zip -Force }
New-Item -ItemType Directory -Force $stage | Out-Null

# build artifacts / dev dirs to skip wherever they appear in a copied tree
$skip = '(^|[\\/])(lib|backup|\.git)([\\/]|$)'

function Add-Tree {
  param([string]$SrcRel, [string[]]$Exts, [string]$SkipRegex = '')
  $srcDir = Join-Path $root $SrcRel
  if (-not (Test-Path $srcDir)) { return }
  $base = (Resolve-Path $srcDir).Path
  Get-ChildItem -Path $srcDir -Recurse -File | ForEach-Object {
    if ($Exts -and ($_.Extension.ToLower() -notin $Exts)) { return }
    $rel = $_.FullName.Substring($base.Length).TrimStart('\', '/')
    if ($rel -match $skip) { return }
    if ($SkipRegex -and ($rel -match $SkipRegex)) { return }
    $dst = Join-Path $stage (Join-Path $SrcRel $rel)
    New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
    Copy-Item -LiteralPath $_.FullName -Destination $dst
  }
}

function Add-File {
  param([string]$Rel)
  $src = Join-Path $root $Rel
  if (-not (Test-Path $src)) { Write-Host "  (skip, not found: $Rel)"; return }
  $dst = Join-Path $stage $Rel
  New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
  Copy-Item -LiteralPath $src -Destination $dst
}

Write-Host '-- root + packages'
'README.md', 'README.en.md', 'CHANGELOG.md', 'CHANGELOG.en.md',
'COPYING.LGPL.txt', 'COPYING.modifiedLGPL.txt',
'tycontrols.lpk', 'tycontrols_dt.lpk' | ForEach-Object { Add-File $_ }

Write-Host '-- runtime source'
Add-Tree 'source' @('.pas', '.inc')

Write-Host '-- design-time (Design unit + packed icons .lrs; NOT the png source)'
Add-File 'designtime/tyControls.Design.pas'
Add-File 'designtime/tycontrols_icons.lrs'

Write-Host '-- themes'
Add-Tree 'themes' @('.tycss')

Write-Host '-- docs (excluding docs/superpowers)'
Add-Tree 'docs' @('.md', '.png', '.svg', '.gif') '(^|[\\/])superpowers([\\/]|$)'

Write-Host '-- examples (source only)'
Add-Tree 'examples' @('.pas', '.lpr', '.lpi', '.lfm', '.ico', '.tycss', '.inc')

# --- zip -------------------------------------------------------------------
Write-Host '-- zipping'
Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal
Remove-Item $stage -Recurse -Force    # keep dist/ tidy: just the .zip

$fileCount = (Get-ChildItem -Path $zip).Length
$sizeKB = [math]::Round((Get-Item $zip).Length / 1KB, 1)
Write-Host ""
Write-Host "Wrote $zip  ($sizeKB KB)" -ForegroundColor Green
Write-Host "Upload this to the GitHub release for v$version."
