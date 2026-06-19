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

# Drift guard: the icon set MUST match the components registered in Design.pas. Parse the
# RegisterComponents('TyControls', [ ... ]) list and fail loudly if a registered control has
# no icon (would show a blank palette icon) or an icon exists for an unregistered class.
Write-Host '== checking icon set vs RegisterComponents =='
$designPas = Join-Path $root 'designtime/tyControls.Design.pas'
$design = Get-Content $designPas -Raw
$m = [regex]::Match($design, "RegisterComponents\s*\(\s*'TyControls'\s*,\s*\[(?<list>[^\]]+)\]")
if (-not $m.Success) { throw "could not find RegisterComponents('TyControls', [...]) in $designPas" }
$registered = [regex]::Matches($m.Groups['list'].Value, 'TTy\w+') | ForEach-Object { $_.Value } | Sort-Object -Unique
$missingIcon = @($registered | Where-Object { $_ -notin $classes })
$extraIcon   = @($classes    | Where-Object { $_ -notin $registered })
if ($missingIcon.Count -or $extraIcon.Count) {
  throw ("icon set out of sync with RegisterComponents." +
         " registered-but-no-icon: [$($missingIcon -join ', ')];" +
         " icon-but-not-registered: [$($extraIcon -join ', ')]." +
         " Update `$classes here, genicons.lpr Glyphs[], and test.paletteicons.pas CClasses.")
}
Write-Host "  OK: $($registered.Count) registered components all have icons"

Write-Host '== building genicons =='
& lazbuild $genLpi
if ($LASTEXITCODE -ne 0) { throw 'genicons build failed' }

Write-Host '== rendering PNGs =='
New-Item -ItemType Directory -Force $icons | Out-Null
& $genExe $icons
if ($LASTEXITCODE -ne 0) { throw 'genicons run failed' }

Write-Host '== packing .lrs (3 sizes per class for HiDPI) =='
# base = 100% (24px), _150 = 150% (36px), _200 = 200% (48px). The IDE picks the variant
# matching the display scaling, so palette icons stay crisp instead of upscaling 24px.
$suffixes = @('', '_150', '_200')
$lazArgs = @($lrs)
$count = 0
foreach ($c in $classes) {
  foreach ($sfx in $suffixes) {
    $name = "$c$sfx"
    $png = Join-Path $icons "$name.png"
    if (-not (Test-Path $png)) { throw "missing PNG: $png" }
    $lazArgs += ('{0}={1}' -f $png, $name)
    $count++
  }
}
& $lazres @lazArgs
if ($LASTEXITCODE -ne 0) { throw 'lazres failed' }
Write-Host "Packed $count icon resources ($($classes.Count) classes x $($suffixes.Count) sizes) into $lrs"
