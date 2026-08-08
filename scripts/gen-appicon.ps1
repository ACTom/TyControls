# Renders the shared TyControls application mark and installs it into every example.
#
# Lazarus takes a project's icon from <projectname>.ico sitting beside the .lpi
# (TProjectIcon.ReadFromProjectFile does ChangeFileExt(lpi, '.ico') and nothing
# else), so the file has to be copied per project -- there is no way to point a
# .lpi at a shared path. <Icon Value="0"/> is the flag that says "not empty";
# without it the .ico on disk is ignored.
#
# The same pass fixes the manifest: a project with UseXPManifest but no
# <XPManifest> block links a manifest that declares <dpiAware>False</dpiAware>,
# i.e. Windows bitmap-stretches the window on a HiDPI screen and none of the
# per-monitor DPI code ever runs.

$ErrorActionPreference = 'Stop'
$root     = Split-Path $PSScriptRoot -Parent
$genLpi   = Join-Path $root 'tools/genappicon/genappicon.lpi'
$genExe   = Join-Path $root 'tools/genappicon/genappicon.exe'
$examples = Join-Path $root 'examples'
$tmpIco   = Join-Path ([System.IO.Path]::GetTempPath()) 'tycontrols-appicon.ico'

Write-Host '== building genappicon =='
& lazbuild $genLpi
if ($LASTEXITCODE -ne 0) { throw 'genappicon build failed' }

Write-Host '== rendering the mark =='
& $genExe $tmpIco
if ($LASTEXITCODE -ne 0) { throw 'genappicon run failed' }
$icoBytes = [System.IO.File]::ReadAllBytes($tmpIco)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$copied = 0; $iconFlag = 0; $dpiFixed = 0

# Recurse, but skip the untracked backup/ copies a few example folders carry --
# they are not built and are not in git.
$projects = Get-ChildItem -Path $examples -Recurse -Filter *.lpi |
            Where-Object { $_.FullName -notmatch '\\backup\\' }

foreach ($lpi in $projects) {
  $ico = [System.IO.Path]::ChangeExtension($lpi.FullName, '.ico')
  # Compare content, not length: two different marks can easily come out the same
  # size, and rewriting an identical file would churn 46 entries in every diff.
  $same = $false
  if (Test-Path $ico) {
    $existing = [System.IO.File]::ReadAllBytes($ico)
    $same = ($existing.Length -eq $icoBytes.Length)
    if ($same) {
      for ($i = 0; $i -lt $icoBytes.Length; $i++) {
        if ($existing[$i] -ne $icoBytes[$i]) { $same = $false; break }
      }
    }
  }
  if (-not $same) {
    [System.IO.File]::WriteAllBytes($ico, $icoBytes)
    $copied++
  }

  $t = [System.IO.File]::ReadAllText($lpi.FullName, $utf8NoBom)
  $orig = $t
  # Per-file: the tree is mostly CRLF but not entirely, and a mixed-ending .lpi
  # would show up as a whole-file diff.
  if ($t.Contains("`r`n")) { $nl = "`r`n" } else { $nl = "`n" }

  if ($t -notmatch '<Icon Value=') {
    $t = $t -replace [regex]::Escape("$nl    </General>"),
                     "$nl      <Icon Value=`"0`"/>$nl    </General>"
    $iconFlag++
  }

  if ($t -notmatch '<XPManifest>') {
    $anchor = '      <UseXPManifest Value="True"/>'
    if (-not $t.Contains($anchor)) { throw "no UseXPManifest anchor in $($lpi.Name)" }
    $block = $anchor + $nl +
             '      <XPManifest>' + $nl +
             '        <DpiAware Value="True/PM_V2"/>' + $nl +
             '      </XPManifest>'
    $t = $t.Replace($anchor, $block)
    $dpiFixed++
  }

  if ($t -ne $orig) { [System.IO.File]::WriteAllText($lpi.FullName, $t, $utf8NoBom) }
}

Remove-Item $tmpIco -ErrorAction SilentlyContinue
Write-Host "icons written: $copied; <Icon> flag added: $iconFlag; DpiAware added: $dpiFixed"
