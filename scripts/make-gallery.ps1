<#
  Rebuild docs/gallery: a screenshot of every example, in English, light and dark, one per
  page of its page control -- plus the demo in every built-in skin -- and the two gallery
  pages that show them (docs/gallery.md, docs/gallery.en.md).

  Neither the examples nor the library are touched. Each example is copied to
  .gallery-build/<name>/ (git-ignored, at the same depth as examples/<name>/ so its relative
  paths still resolve), its program gets one more unit -- tools/gallery/tyGalleryCapture.pas,
  which takes the pictures and closes the program -- and the copy is built and run.

  The windows open on the desktop while this runs (a few seconds each); leave the mouse
  alone. Windows only.

  Usage, from the repo root:
    powershell -File scripts/make-gallery.ps1
    powershell -File scripts/make-gallery.ps1 -Only grid,demo       # some examples
    powershell -File scripts/make-gallery.ps1 -BuildOnly            # build the copies, no windows
    powershell -File scripts/make-gallery.ps1 -NoBuild              # re-shoot, no rebuild
    powershell -File scripts/make-gallery.ps1 -PagesOnly            # only rewrite the pages

  -Pcp <dir>      a Lazarus config directory for lazbuild (--pcp) in which the tycontrols
                  package is already compiled; lazbuild then skips the dependencies.
                  Without it lazbuild uses your normal Lazarus configuration.
  -Lazbuild <exe> lazbuild.exe, when it is not on PATH or at C:\lazarus.
#>
param(
  [string[]]$Only = @(),
  [string]$Pcp = '',
  [string]$Lazbuild = '',
  [switch]$NoBuild,
  [switch]$BuildOnly,
  [switch]$PagesOnly,
  [int]$Timeout = 180
)
$ErrorActionPreference = 'Stop'
$root    = Split-Path $PSScriptRoot -Parent
$stage   = Join-Path $root '.gallery-build'
$out     = Join-Path $root 'docs\gallery'
$capture = Join-Path $root 'tools\gallery\tyGalleryCapture.pas'
$utf8    = New-Object System.Text.UTF8Encoding($false)

# The skin wall: the default theme, every structural skin, the OS-following one, and green
# (the photo theme the demo finds in themes/).
$skins = @('default') +
  @(Get-ChildItem (Join-Path $root 'themes\builtin\*.tycss') | Sort-Object Name | ForEach-Object { $_.BaseName }) +
  @('system', 'green')

# The README's pictures: copies of gallery pictures under docs/images, so the README in the
# release bundle (which leaves the gallery out) still has them. Refreshed on every run.
$readmePicks = [ordered]@{
  'antd-antdesign.png' = 'antdesign/01-dashboard-light.png'
  'skin-classic.png'   = 'demo/skin-classic.png'
  'skin-win11.png'     = 'demo/skin-win11.png'
  'skin-material3.png' = 'demo/skin-material3.png'
  'demo-light.png'     = 'demo/01-tab-1-light.png'
  'demo-dark.png'      = 'demo/01-tab-1-dark.png'
  'demo-green.png'     = 'demo/skin-green.png'
  'grid.png'           = 'grid/04-editing-cell-types-light.png'
  'treeview.png'       = 'treeview/02-columns-sort-light.png'
  'inputs.png'         = 'inputs/main-light.png'
  'chart.png'          = 'chart/main-light.png'
  'ribbon.png'         = 'ribbon/01-new-document-1-light.png'
  'calendar.png'       = 'calendar/main-light.png'
}

function Get-Examples {
  $all = Get-ChildItem (Join-Path $root 'examples') -Directory |
    Where-Object { @(Get-ChildItem $_.FullName -Filter *.lpi).Count -gt 0 } | Sort-Object Name
  if ($Only.Count -gt 0) {
    $want = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ -ne '' })
    $all = $all | Where-Object { $want -contains $_.Name }
  }
  return @($all)
}

function Resolve-Lazbuild {
  if ($Lazbuild -ne '') { return $Lazbuild }
  $cmd = Get-Command lazbuild -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  if (Test-Path 'C:\lazarus\lazbuild.exe') { return 'C:\lazarus\lazbuild.exe' }
  throw 'lazbuild not found: pass -Lazbuild <path to lazbuild.exe>'
}

# One example: copy, add the capture unit, build. Returns the exe, or $null.
function Build-Copy($ex, $lb) {
  $name = $ex.Name
  $dst = Join-Path $stage $name
  robocopy $ex.FullName $dst /MIR /XD lib backup /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { Write-Warning "${name}: copy failed"; return $null }
  Copy-Item $capture $dst -Force
  $lpi = Get-ChildItem $dst -Filter *.lpi | Select-Object -First 1
  $lpr = Join-Path $dst ($lpi.BaseName + '.lpr')
  $text = [IO.File]::ReadAllText($lpr)
  if ($text -notmatch 'tyGalleryCapture') {
    $re = [regex]'(?i)\bInterfaces\s*,'
    if (-not $re.IsMatch($text)) { Write-Warning "${name}: no 'Interfaces,' in the program's uses"; return $null }
    [IO.File]::WriteAllText($lpr, $re.Replace($text, 'Interfaces, tyGalleryCapture,', 1), $utf8)
  }
  $lbArgs = @()
  if ($Pcp -ne '') { $lbArgs += "--pcp=$Pcp"; $lbArgs += '--skip-dependencies' }
  $lbArgs += '-B'; $lbArgs += $lpi.FullName
  $log = Join-Path $dst 'gallery-build.log'
  & $lb @lbArgs *> $log
  if ($LASTEXITCODE -ne 0) { Write-Warning "${name}: build failed, see $log"; return $null }
  return Find-Exe $dst
}

function Find-Exe($dir) {
  $exe = Get-ChildItem $dir -Recurse -Filter *.exe -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  return $exe
}

function Shoot($name, $exe) {
  $dir = Join-Path $out $name
  if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
  New-Item -ItemType Directory $dir | Out-Null
  $env:TY_GALLERY_DIR = $dir
  if ($name -eq 'demo') { $env:TY_GALLERY_SKINS = ($skins -join ',') } else { $env:TY_GALLERY_SKINS = '' }
  try {
    $p = Start-Process $exe.FullName -ArgumentList '--lang=en' -WorkingDirectory $exe.DirectoryName -PassThru
    if (-not $p.WaitForExit($Timeout * 1000)) {
      Stop-Process -Id $p.Id -Force
      Write-Warning "${name}: still running after $Timeout s, stopped"
    }
  } finally {
    Remove-Item Env:TY_GALLERY_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:TY_GALLERY_SKINS -ErrorAction SilentlyContinue
  }
  $shots = @(Get-ChildItem $dir -Filter *.png).Count
  # the log stays with the build copy, out of docs/
  $log = Join-Path (Join-Path $stage $name) 'capture.log'
  if (Test-Path (Join-Path $dir 'capture.log')) { Move-Item (Join-Path $dir 'capture.log') $log -Force }
  $bad = @()
  if (Test-Path $log) { $bad = @(Select-String -Path $log -Pattern 'FAILED|no Dark|not in ThemeCombo|no ThemeCombo|BitBlt failed' | ForEach-Object { $_.Line }) }
  "{0,-22} {1,3} picture(s){2}" -f $name, $shots, $(if ($bad.Count) { '  ! ' + ($bad -join ' | ') } else { '' })
}

# ---- the pages ------------------------------------------------------------------------------

# The views of one example: "01-basic" etc., from the light pictures, in order.
function Get-Views($dir) {
  return @(Get-ChildItem $dir -Filter '*-light.png' | Sort-Object Name | ForEach-Object { $_.Name -replace '-light\.png$', '' })
}

function View-Title($view) {
  $t = $view -replace '^(\w+-)?\d\d-', '' -replace '^main$', ''
  return ($t -replace '-', ' ')
}

function Write-Pages {
  $zh = New-Object System.Text.StringBuilder
  $en = New-Object System.Text.StringBuilder
  [void]$zh.AppendLine('# 图库')
  [void]$zh.AppendLine('')
  [void]$zh.AppendLine('每个示例的截图：有多个标签页的每页一张，亮色、暗色各一张。界面语言为英文，缩放 100%。')
  [void]$zh.AppendLine('')
  [void]$zh.AppendLine('> English: [gallery.en.md](gallery.en.md).')
  [void]$zh.AppendLine('')
  [void]$zh.AppendLine('截图由脚本生成，示例改动后重新运行即可：`powershell -File scripts/make-gallery.ps1`。')
  [void]$zh.AppendLine('')
  [void]$en.AppendLine('# Gallery')
  [void]$en.AppendLine('')
  [void]$en.AppendLine('Every example, one picture per tab page, in light and in dark. English UI, 100% scaling.')
  [void]$en.AppendLine('')
  [void]$en.AppendLine('> 中文版见 [gallery.md](gallery.md)。')
  [void]$en.AppendLine('')
  [void]$en.AppendLine('The pictures are generated; rerun `powershell -File scripts/make-gallery.ps1` after changing an example.')
  [void]$en.AppendLine('')

  $demo = Join-Path $out 'demo'
  $skinShots = @()
  if (Test-Path $demo) { $skinShots = @($skins | Where-Object { Test-Path (Join-Path $demo "skin-$_.png") }) }
  if ($skinShots.Count -gt 0) {
    [void]$zh.AppendLine('## 皮肤')
    [void]$zh.AppendLine('')
    [void]$zh.AppendLine('同一个 demo 窗口，换上每一套内置皮肤，另加 `themes/` 里的图片主题 green。')
    [void]$zh.AppendLine('')
    [void]$en.AppendLine('## Skins')
    [void]$en.AppendLine('')
    [void]$en.AppendLine('The same demo window in every built-in skin, plus green, the photo theme in `themes/`.')
    [void]$en.AppendLine('')
    foreach ($sb in @($zh, $en)) {
      [void]$sb.AppendLine('| | | |')
      [void]$sb.AppendLine('|---|---|---|')
      for ($i = 0; $i -lt $skinShots.Count; $i += 3) {
        $cells = @()
        for ($j = $i; $j -lt $i + 3; $j++) {
          if ($j -lt $skinShots.Count) {
            $s = $skinShots[$j]
            $cells += "**$s**<br>![$s](gallery/demo/skin-$s.png)"
          } else { $cells += ' ' }
        }
        [void]$sb.AppendLine('| ' + ($cells -join ' | ') + ' |')
      }
      [void]$sb.AppendLine('')
    }
  }

  [void]$zh.AppendLine('## 示例')
  [void]$zh.AppendLine('')
  [void]$en.AppendLine('## Examples')
  [void]$en.AppendLine('')
  foreach ($d in (Get-ChildItem $out -Directory | Sort-Object Name)) {
    $views = Get-Views $d.FullName
    if ($views.Count -eq 0) { continue }
    foreach ($pair in @(@($zh, '亮色', '暗色'), @($en, 'Light', 'Dark'))) {
      $sb = $pair[0]
      [void]$sb.AppendLine("### $($d.Name)")
      [void]$sb.AppendLine('')
      [void]$sb.AppendLine("| $($pair[1]) | $($pair[2]) |")
      [void]$sb.AppendLine('|---|---|')
      foreach ($v in $views) {
        $t = View-Title $v
        $l = "gallery/$($d.Name)/$v-light.png"
        $k = "gallery/$($d.Name)/$v-dark.png"
        $cap = if ($t -ne '') { "$t<br>" } else { '' }
        $alt = ("$($d.Name) $t").Trim()
        [void]$sb.AppendLine("| $cap![$alt]($l) | $cap![$alt]($k) |")
      }
      [void]$sb.AppendLine('')
    }
  }
  [IO.File]::WriteAllText((Join-Path $root 'docs\gallery.md'), $zh.ToString(), $utf8)
  [IO.File]::WriteAllText((Join-Path $root 'docs\gallery.en.md'), $en.ToString(), $utf8)
  'pages: docs\gallery.md, docs\gallery.en.md'
}

function Update-ReadmeImages {
  $dst = Join-Path $root 'docs\images'
  New-Item -ItemType Directory -Force $dst | Out-Null
  foreach ($k in $readmePicks.Keys) {
    $src = Join-Path $out ($readmePicks[$k] -replace '/', '\')
    if (Test-Path $src) { Copy-Item $src (Join-Path $dst $k) -Force }
    else { Write-Warning "README picture ${k}: $($readmePicks[$k]) is not in the gallery (a page renamed?)" }
  }
  "README pictures: $($readmePicks.Count) in docs\images"
}

# ---- run ------------------------------------------------------------------------------------

if (-not $PagesOnly) {
  $lb = $null
  if (-not $NoBuild) { $lb = Resolve-Lazbuild }
  New-Item -ItemType Directory -Force $stage | Out-Null
  New-Item -ItemType Directory -Force $out | Out-Null
  foreach ($ex in (Get-Examples)) {
    if ($NoBuild) { $exe = Find-Exe (Join-Path $stage $ex.Name) } else { $exe = Build-Copy $ex $lb }
    if ($null -eq $exe) { Write-Warning "$($ex.Name): nothing to run"; continue }
    if ($BuildOnly) { "{0,-22} built" -f $ex.Name; continue }
    Shoot $ex.Name $exe
  }
}
if (-not $BuildOnly) {
  Write-Pages
  if ($Only.Count -eq 0 -or $PagesOnly) { Update-ReadmeImages }
}
