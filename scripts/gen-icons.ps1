$ErrorActionPreference = 'Stop'
$root   = Split-Path $PSScriptRoot -Parent
$genLpi = Join-Path $root 'tools/genicons/genicons.lpi'
$genExe = Join-Path $root 'tools/genicons/genicons.exe'
$icons  = Join-Path $root 'designtime/icons'
$lrs    = Join-Path $root 'designtime/tycontrols_icons.lrs'
$lazres = 'C:\lazarus\tools\lazres.exe'

$classes = @(
  'TTyButton','TTyLabel','TTyEdit','TTyCheckBox','TTyRadioButton',
  'TTyComboBox','TTyToggleSwitch','TTyTrackBar','TTyProgressBar','TTyListBox',
  'TTyTabControl','TTyGroupBox','TTyPanel','TTyScrollBar','TTySpinEdit',
  'TTyMemo','TTyTitleBar','TTyMenuBar','TTyStyleController','TTyPopupMenu'
)

Write-Host '== building genicons =='
& lazbuild $genLpi
if ($LASTEXITCODE -ne 0) { throw 'genicons build failed' }

Write-Host '== rendering PNGs =='
New-Item -ItemType Directory -Force $icons | Out-Null
& $genExe $icons
if ($LASTEXITCODE -ne 0) { throw 'genicons run failed' }

Write-Host '== packing .lrs =='
$lazArgs = @($lrs)
foreach ($c in $classes) {
  $png = Join-Path $icons "$c.png"
  if (-not (Test-Path $png)) { throw "missing PNG: $png" }
  $lazArgs += ('{0}={1}' -f $png, $c)
}
& $lazres @lazArgs
if ($LASTEXITCODE -ne 0) { throw 'lazres failed' }
Write-Host "Packed $($classes.Count) icons into $lrs"
