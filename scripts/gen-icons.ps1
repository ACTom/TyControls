$ErrorActionPreference = 'Stop'
$root   = Split-Path $PSScriptRoot -Parent
$genLpi = Join-Path $root 'tools/genicons/genicons.lpi'
$genExe = Join-Path $root 'tools/genicons/genicons.exe'
$icons  = Join-Path $root 'designtime/icons'
$lrs    = Join-Path $root 'designtime/tycontrols_icons.lrs'
$lazres = 'C:\lazarus\tools\lazres.exe'

$classes = @(
  'TTyButton',
  'TTyGlyphButton','TTyGlyphContainerButton','TTySpeedButton','TTyDropDownButton','TTyMenuButton','TTyColorButton','TTyButtonGroup',
  'TTyRibbon','TTyRibbonPage','TTyRibbonGroup','TTyRibbonAppMenu','TTyRibbonQuickAccess','TTyRibbonGallery','TTyRibbonBackstage',
  'TTyLabel','TTyEdit','TTyNumericEdit','TTyCurrencyEdit','TTyMaskEdit','TTyURLEdit','TTyComboEdit','TTyTrackEdit','TTyColorBox','TTyColorComboBox','TTyMRUComboBox','TTyComboBoxEx','TTyOfficeListBox','TTyOfficeComboBox','TTyColorGrid','TTyLColorPicker','TTyHSColorPicker','TTyAdvancedListBox','TTyAdvancedComboBox','TTyCheckComboBox','TTyValueListEditor','TTyCalculator','TTyCalcEdit','TTyCalcCurrencyEdit','TTyColorListBox','TTyFontComboBox','TTyFontListBox','TTyFontSizeComboBox','TTyCheckListBox','TTyCheckBox','TTyRadioButton',
  'TTyComboBox','TTyToggleSwitch','TTyTrackBar','TTyProgressBar','TTyGauge','TTyCircularProgress','TTyActivityIndicator','TTyActivityBar','TTyMeter','TTyLevelMeter','TTyDial','TTyAnalogClock','TTySparkline','TTyRating','TTyGearDial','TTyGearActivityIndicator','TTyUpDown','TTyLinkLabel','TTyShadowLabel','TTyGlowLabel','TTyListBox',
  'TTyPageControl','TTyTabSheet','TTyTabSet','TTyGroupBox','TTyPanel','TTyScrollBar','TTySpinEdit','TTyFloatSpinEdit',
  'TTyMemo','TTyTitleBar','TTyMenuBar','TTyStyleController','TTyPopupMenu','TTyImagesMenu','TTyMenuEx',
  'TTyNativeStyler','TTyHint','TTyBalloonHint',
  'TTyIconFont','TTyLucideIconFont','TTyCharImage','TTyGlyphImageList','TTyImage','TTyImageCollection','TTyVirtualImageList','TTyLCLImageList',
  'TTySplitter','TTyStatusBar','TTyToolBar','TTyToolButton','TTyToolSeparator',
  'TTyCalendar','TTyDateTimePicker',
  'TTyTreeView',
  # Dialogs palette group (RegisterComponents('TyControls Dialogs', ...))
  'TTyMessage','TTyInputDialog','TTyPasswordDialog','TTyTextDialog',
  'TTySelectValueDialog','TTySelectPathDialog','TTyColorDialog','TTyFontDialog',
  'TTyFindDialog','TTyReplaceDialog','TTyProgressDialog','TTyAboutDialog','TTyIconBrowserDialog',
  # Phase 5 containers & layout
  'TTyBevel','TTyDivider','TTyPaintPanel','TTySizeBox',
  'TTyRadioGroup','TTyCheckGroup','TTyToolGroupPanel',
  'TTyScrollBox','TTyScrollPanel','TTyExPanel',
  'TTyGridPanel','TTyRelativePanel',
  'TTyToolBarEx','TTyControlBar','TTyCoolBar',
  'TTyHeaderControl','TTyListGroupPanel',
  # Phase 9 vector shapes
  'TTyShape','TTyStarShape','TTyArrow',
  # Phase 8 data views (pulled forward: Phase 7 depends on it)
  'TTyListView','TTyShellListView','TTyShellTreeView',
  # Grids (same 'TyControls Data Views' palette group)
  'TTyDrawGrid','TTyStringGrid',
  'TTyFilterComboBox','TTyShellComboBox',
  # Phase 7 file dialogs + preview
  'TTyOpenDialog','TTySaveDialog','TTyOpenPictureDialog','TTySavePictureDialog',
  'TTyPreviewBox','TTyOpenPreviewDialog','TTySavePreviewDialog',
  # Phase 9 image viewer + chart + html label
  'TTyImageView','TTyChart','TTyHtmlLabel',
  # Ant Design-gap batch 1
  'TTyCard','TTyTag','TTyBadge',
  # Ant Design-gap batch 1 (second group) + batches 2 & 3
  'TTyAlert','TTyNotification','TTyEmpty','TTySegmented',
  'TTyPagination','TTySteps','TTyBreadcrumb',
  'TTyTransfer','TTyTreeSelect','TTyCascader','TTyPopover'
)

# Drift guard: the icon set MUST match the components registered in Design.pas. Parse EVERY
# RegisterComponents('TyControls...', [ ... ]) group (the main 'TyControls' palette AND the
# 'TyControls Dialogs' group) and fail loudly if a registered control has no icon (would show
# a blank palette icon) or an icon exists for an unregistered class.
Write-Host '== checking icon set vs RegisterComponents =='
# EVERY design-time unit, not one hardcoded name: a second unit's RegisterComponents would
# otherwise be invisible here and its components would ship with a blank palette icon — the
# exact failure tests/test.paletteicons.pas was rewritten to end.
$designPas = @(Get-ChildItem -Path (Join-Path $root 'designtime') -Filter '*.pas' -File | Sort-Object Name)
if ($designPas.Count -eq 0) { throw "no design-time source found under $(Join-Path $root 'designtime')" }
# Read as real UTF-8: PS 5.1 `Get-Content -Raw` decodes via the ANSI codepage and mangles
# the em-dashes / CJK in Design.pas (the repo-wide rule — see other scripts).
$design = ($designPas | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n"
$groups = [regex]::Matches($design, "RegisterComponents\s*\(\s*'TyControls[^']*'\s*,\s*\[(?<list>[^\]]+)\]")
if ($groups.Count -eq 0) { throw "could not find any RegisterComponents('TyControls...', [...]) in $($designPas.Name -join ', ')" }
$registered = @($groups | ForEach-Object {
  [regex]::Matches($_.Groups['list'].Value, 'TTy\w+') | ForEach-Object { $_.Value }
}) | Sort-Object -Unique
$missingIcon = @($registered | Where-Object { $_ -notin $classes })
$extraIcon   = @($classes    | Where-Object { $_ -notin $registered })
if ($missingIcon.Count -or $extraIcon.Count) {
  throw ("icon set out of sync with RegisterComponents." +
         " registered-but-no-icon: [$($missingIcon -join ', ')];" +
         " icon-but-not-registered: [$($extraIcon -join ', ')]." +
         " Update `$classes here and genicons.lpr Glyphs[]. (tests/test.paletteicons.pas needs" +
         " no edit: it derives its population from the registrations at run time — which is what" +
         " catches this when nobody remembers to run this script.)")
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
# Pass the 'png=name' pairs through a lazres RESPONSE FILE (lazres reads entries from
# a @listfile). A single command line with all ~400+ paths overruns the Windows 32k
# command-line limit once the component count grows -- the response file has no such cap.
$listFile = Join-Path $icons '_lazres_list.txt'
$lines = New-Object System.Collections.Generic.List[string]
$count = 0
foreach ($c in $classes) {
  foreach ($sfx in $suffixes) {
    $name = "$c$sfx"
    $png = Join-Path $icons "$name.png"
    if (-not (Test-Path $png)) { throw "missing PNG: $png" }
    $lines.Add(('{0}={1}' -f $png, $name))
    $count++
  }
}
Set-Content -Encoding ascii -Path $listFile -Value $lines
try {
  & $lazres $lrs "@$listFile"
  if ($LASTEXITCODE -ne 0) { throw 'lazres failed' }
} finally {
  Remove-Item $listFile -ErrorAction SilentlyContinue
}
Write-Host "Packed $count icon resources ($($classes.Count) classes x $($suffixes.Count) sizes) into $lrs"
