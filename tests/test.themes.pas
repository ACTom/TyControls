unit test.themes;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel;
type
  TTestThemes = class(TTestCase)
  private
    function ThemePath(const AName: string): string;
    procedure CheckTheme(const AName: string);
    procedure CheckThemeNewTypeKeys(const AName: string);
    procedure CheckThemeTabControlTypeKeys(const AName: string);
    procedure CheckThemeFormTypeKey(const AName: string);
  published
    procedure TestLightLoadsAndResolvesButton;
    procedure TestDarkLoadsAndResolvesButton;
    procedure TestShowcaseLoadsAndResolvesButton;
    { v1.1 typeKey assertions — one method per theme }
    procedure TestLightStylesNewTypeKeys;
    procedure TestDarkStylesNewTypeKeys;
    procedure TestShowcaseStylesNewTypeKeys;
    { v1.2 typeKey assertions — TabControl }
    procedure TestLightStylesTabControlTypeKeys;
    procedure TestDarkStylesTabControlTypeKeys;
    procedure TestShowcaseStylesTabControlTypeKeys;
    { v1.5.1 typeKey assertions — TyForm window background }
    procedure TestLightStylesFormTypeKey;
    procedure TestDarkStylesFormTypeKey;
    procedure TestShowcaseStylesFormTypeKey;
    { Phase 1 on-accent fix }
    procedure TestDarkOnAccentReadable;
    { green = the image-background + frosted-glass theme; guard its resolution }
    procedure TestGreenImageAndGlass;
    { the demo's real path: switch FROM another theme INTO green (REPLACE) }
    procedure TestGreenAfterLightSwitch;
    { every bundled theme ships the ghost variant + TyBadge tokens }
    procedure TestAllThemesHaveGhostAndBadge;
  end;

  { Golden resolved-style dump. Loads each shipped theme, resolves a full grid of
    (typeKey x variant x state) and serializes every TTyStyleSet field, comparing to
    a committed golden. The shipped themes have no other pixel-value test, so this is
    the guard that catches ANY value change (e.g. a Phase 1 tier substitution that is
    not value-preserving). Bootstraps the golden file on first run; writes a .actual
    alongside on mismatch for diffing. }
  TTestThemeGolden = class(TTestCase)
  private
    function ThemePath(const AName: string): string;
    function GoldenPath(const AName: string): string;
    function DumpTheme(const APath: string): string;
    function DumpThemeMode(const APath, AMode: string): string;
    procedure CheckGolden(const AThemeName: string);
    procedure CheckAlias(AModel: TTyStyleModel; const ATheme, ANew, ADonor,
      AVariant: string; ABaseStateOnly: Boolean);
  published
    procedure TestLightGolden;
    procedure TestDarkGolden;
    procedure TestShowcaseGolden;
    { 3.0 themability pass: every key minted by splitting a borrowed one must still
      resolve BYTE-IDENTICALLY to the key it was split from, in EVERY shipped theme —
      the five under themes/ and all fifteen skins. This is the test that proves the
      split moved no pixel anywhere, not just in the three themes the golden covers.
      It also proves the base-layer claim honestly: a skin that overrides the donor key
      does NOT automatically pass, because base-layer inheritance would hand the new key
      light.tycss's values instead of the skin's. That is precisely why the new selectors
      had to be added to the skins' own rules and not left to inherit. }
    procedure TestNewKeysMatchTheirDonorInEveryTheme;
    { P3 (D7) single-file dual-mode fidelity (§7 risk-3 zero-pixel route): auto.tycss in
      'light' mode resolves byte-identically to light.tycss, and in 'dark' mode to
      dark.tycss, across the full (typeKey x variant x state) grid. This is the proof that
      @mode carries both modes pixel-faithfully. }
    procedure TestAutoLightEqualsLight;
    procedure TestAutoDarkEqualsDark;
  end;
implementation

function TTestThemes.ThemePath(const AName: string): string;
begin
  // Resolve relative to the test executable (in /tests) so the path does not
  // depend on the current working directory.
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim
    + 'themes' + PathDelim + AName;
  if not FileExists(Result) then      // structural skins (showcase, …) live in themes/builtin/
    Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim
      + 'themes' + PathDelim + 'builtin' + PathDelim + AName;
end;

procedure TTestThemes.TestAllThemesHaveGhostAndBadge;
const
  Names: array[0..5] of string = ('light', 'dark', 'green', 'showcase', 'system', 'auto');
var
  i: Integer;
  m: TTyStyleModel;
  g, b: TTyStyleSet;
begin
  for i := 0 to High(Names) do
  begin
    m := TTyStyleModel.Create;
    try
      m.LoadFromFile(ThemePath(Names[i] + '.tycss'));
      m.Mode := 'light';   // dual-mode (system/auto) need an active mode; no-op for single-mode themes
      g := m.ResolveStyle('TyButton', 'ghost', []);
      AssertTrue(Names[i] + ': ghost has background', tpBackground in g.Present);
      AssertTrue(Names[i] + ': ghost base transparent (alpha 0)',
        TyAlphaOf(g.Background.Color) = 0);
      b := m.ResolveStyle('TyBadge', '', []);
      AssertTrue(Names[i] + ': TyBadge has background', tpBackground in b.Present);
    finally
      m.Free;
    end;
  end;
end;

procedure TTestThemes.CheckTheme(const AName: string);
var
  model: TTyStyleModel;
  base, prim: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    AssertTrue('theme file must exist: ' + AName,
      FileExists(ThemePath(AName)));
    model.LoadFromFile(ThemePath(AName));
    base := model.ResolveStyle('TyButton', '', []);
    AssertTrue('TyButton base must set Background: ' + AName,
      tpBackground in base.Present);
    AssertTrue('TyButton base must set TextColor: ' + AName,
      tpTextColor in base.Present);
    prim := model.ResolveStyle('TyButton', 'primary', [tysHover]);
    AssertTrue('TyButton.primary:hover must set Background: ' + AName,
      tpBackground in prim.Present);
  finally
    model.Free;
  end;
end;

{ v1.1: assert all 8 new typeKeys are styled correctly in the given theme }
procedure TTestThemes.CheckThemeNewTypeKeys(const AName: string);
var
  model: TTyStyleModel;
  s: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    AssertTrue('theme file must exist: ' + AName,
      FileExists(ThemePath(AName)));
    model.LoadFromFile(ThemePath(AName));

    { TyListBox base: must have Background }
    s := model.ResolveStyle('TyListBox', '', []);
    AssertTrue('TyListBox base must set Background: ' + AName,
      tpBackground in s.Present);

    { TyListItem:active: must have Background (accent selection highlight) }
    s := model.ResolveStyle('TyListItem', '', [tysActive]);
    AssertTrue('TyListItem:active must set Background: ' + AName,
      tpBackground in s.Present);

    { TyProgressFill base: must have Background (the fill colour) }
    s := model.ResolveStyle('TyProgressFill', '', []);
    AssertTrue('TyProgressFill base must set Background: ' + AName,
      tpBackground in s.Present);

    { TyToggleSwitch:active: must have Background (ON-state track colour) }
    s := model.ResolveStyle('TyToggleSwitch', '', [tysActive]);
    AssertTrue('TyToggleSwitch:active must set Background: ' + AName,
      tpBackground in s.Present);

    { TyTrackThumb base: must have Background (thumb fill) }
    s := model.ResolveStyle('TyTrackThumb', '', []);
    AssertTrue('TyTrackThumb base must set Background: ' + AName,
      tpBackground in s.Present);

    { TyGroupBox base: must have BorderColor (the group border line) }
    s := model.ResolveStyle('TyGroupBox', '', []);
    AssertTrue('TyGroupBox base must set BorderColor: ' + AName,
      tpBorderColor in s.Present);

  finally
    model.Free;
  end;
end;

procedure TTestThemes.TestLightLoadsAndResolvesButton;
begin
  CheckTheme('light.tycss');
end;

procedure TTestThemes.TestDarkLoadsAndResolvesButton;
begin
  CheckTheme('dark.tycss');
end;

procedure TTestThemes.TestShowcaseLoadsAndResolvesButton;
begin
  CheckTheme('showcase.tycss');
end;

procedure TTestThemes.TestLightStylesNewTypeKeys;
begin
  CheckThemeNewTypeKeys('light.tycss');
end;

procedure TTestThemes.TestDarkStylesNewTypeKeys;
begin
  CheckThemeNewTypeKeys('dark.tycss');
end;

procedure TTestThemes.TestShowcaseStylesNewTypeKeys;
begin
  CheckThemeNewTypeKeys('showcase.tycss');
end;

{ v1.2: assert TyTabControl base and TyTab:active are styled in the given theme }
procedure TTestThemes.CheckThemeTabControlTypeKeys(const AName: string);
var
  model: TTyStyleModel;
  s: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    AssertTrue('theme file must exist: ' + AName,
      FileExists(ThemePath(AName)));
    model.LoadFromFile(ThemePath(AName));

    { TyTabControl base: must have Background (content area surface) }
    s := model.ResolveStyle('TyTabControl', '', []);
    AssertTrue('TyTabControl base must set Background: ' + AName,
      tpBackground in s.Present);

    { TyTab:active: must have Background (selected tab highlight) }
    s := model.ResolveStyle('TyTab', '', [tysActive]);
    AssertTrue('TyTab:active must set Background: ' + AName,
      tpBackground in s.Present);

  finally
    model.Free;
  end;
end;

procedure TTestThemes.TestLightStylesTabControlTypeKeys;
begin
  CheckThemeTabControlTypeKeys('light.tycss');
end;

procedure TTestThemes.TestDarkStylesTabControlTypeKeys;
begin
  CheckThemeTabControlTypeKeys('dark.tycss');
end;

procedure TTestThemes.TestShowcaseStylesTabControlTypeKeys;
begin
  CheckThemeTabControlTypeKeys('showcase.tycss');
end;

{ v1.5.1: assert TyForm defines a solid window background in the given theme }
procedure TTestThemes.CheckThemeFormTypeKey(const AName: string);
var
  model: TTyStyleModel;
  s: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    AssertTrue('theme file must exist: ' + AName,
      FileExists(ThemePath(AName)));
    model.LoadFromFile(ThemePath(AName));

    { TyForm base: must have Background (the window/form backdrop) }
    s := model.ResolveStyle('TyForm', '', []);
    AssertTrue('TyForm base must set Background: ' + AName,
      tpBackground in s.Present);
    AssertTrue('TyForm background must be solid: ' + AName,
      s.Background.Kind = tfkSolid);

  finally
    model.Free;
  end;
end;

procedure TTestThemes.TestLightStylesFormTypeKey;
begin
  CheckThemeFormTypeKey('light.tycss');
end;

procedure TTestThemes.TestDarkStylesFormTypeKey;
begin
  CheckThemeFormTypeKey('dark.tycss');
end;

procedure TTestThemes.TestShowcaseStylesFormTypeKey;
begin
  CheckThemeFormTypeKey('showcase.tycss');
end;

procedure TTestThemes.TestDarkOnAccentReadable;
var model: TTyStyleModel; s: TTyStyleSet;
begin
  // on-accent fix: dark TyCheckBox:active / TyRadioButton:active ink must be the dark
  // #0B1120 (was #FFFFFF — low-contrast white on the light-blue dark accent). on() unifies.
  model := TTyStyleModel.Create;
  try
    model.LoadFromFile(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' +
      PathDelim + 'dark.tycss');
    s := model.ResolveStyle('TyCheckBox', '', [tysActive]);
    AssertEquals('dark checkbox:active ink = 0B1120', TTyColor($FF0B1120), s.TextColor);
    s := model.ResolveStyle('TyRadioButton', '', [tysActive]);
    AssertEquals('dark radio:active ink = 0B1120', TTyColor($FF0B1120), s.TextColor);
  finally
    model.Free;
  end;
end;

procedure TTestThemes.TestGreenImageAndGlass;
var model: TTyStyleModel; s: TTyStyleSet;
begin
  // Regression guard: green is the image-background demo theme. It must resolve TyForm to an
  // image fill; its CONTAINERS are intentionally clean (no glass) so the sharp photo shows
  // through, while glass remains on the input controls (TyEdit etc.).
  model := TTyStyleModel.Create;
  try
    model.LoadFromFile(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' +
      PathDelim + 'green.tycss');
    s := model.ResolveStyle('TyForm', '', []);
    AssertEquals('green TyForm background kind', Ord(tfkImage), Ord(s.Background.Kind));
    AssertTrue('green TyForm image path set', s.Background.ImagePath <> '');
    // The resolved path must be LOADABLE — the painter loads this file at paint time,
    // long after GThemeBaseDir was cleared, so resolve-time eval must still find it.
    AssertTrue('green TyForm image is a real file: ' + s.Background.ImagePath,
      FileExists(s.Background.ImagePath));
    AssertEquals('green MaxGlassBlur (glass still used by input controls)', 16, model.MaxGlassBlur);
    { Containers are CLEAN (no glass) so the sharp photo shows through; glass stays on inputs. }
    s := model.ResolveStyle('TyPanel', '', []);
    AssertFalse('green TyPanel is clean (no glass)', tpGlass in s.Present);
    s := model.ResolveStyle('TyEdit', '', []);
    AssertTrue('green TyEdit still has glass', tpGlass in s.Present);
  finally
    model.Free;
  end;
end;

procedure TTestThemes.TestGreenAfterLightSwitch;
var model: TTyStyleModel; s: TTyStyleSet; base: string;
begin
  // Reproduce the demo EXACTLY: load light first (FormCreate), then switch to green
  // (Btn click). §3.8 switch = REPLACE; green's image+glass must survive the swap.
  base := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim;
  model := TTyStyleModel.Create;
  try
    model.LoadFromFile(base + 'light.tycss');   // FormCreate
    model.LoadFromFile(base + 'green.tycss');   // BtnGreenClick (REPLACE)
    s := model.ResolveStyle('TyForm', '', []);
    AssertTrue('switched TyForm background present', tpBackground in s.Present);
    AssertEquals('switched TyForm background kind', Ord(tfkImage), Ord(s.Background.Kind));
    AssertTrue('switched TyForm image path set', s.Background.ImagePath <> '');
    AssertTrue('switched TyForm image is a real file: ' + s.Background.ImagePath,
      FileExists(s.Background.ImagePath));
    AssertEquals('switched MaxGlassBlur', 16, model.MaxGlassBlur);
    s := model.ResolveStyle('TyPanel', '', []);
    AssertFalse('switched TyPanel is clean (no glass)', tpGlass in s.Present);
    s := model.ResolveStyle('TyEdit', '', []);
    AssertTrue('switched TyEdit still has glass', tpGlass in s.Present);
  finally
    model.Free;
  end;
end;

{ ── Golden resolved-style dump ─────────────────────────────────────────────── }

function GHex(c: TTyColor): string;
begin
  Result := IntToHex(Cardinal(c), 8);
end;

function GPresent(const p: TTyPropSet): string;
var pr: TTyProp;
begin
  Result := '';
  for pr := Low(TTyProp) to High(TTyProp) do
    if pr in p then Result := Result + IntToStr(Ord(pr)) + ',';
end;

function GDumpStyle(const ts: TTyStyleSet): string;
var bg: string;
begin
  // Kind-aware: only dump fields the fill Kind actually sets. Gradient/solid fills
  // leave the image/glass fields uninitialized (ParseLinearGradient does not
  // Default()-init), so dumping them unconditionally is non-deterministic.
  bg := 'k' + IntToStr(Ord(ts.Background.Kind));
  case ts.Background.Kind of
    tfkSolid: bg := bg + '/' + GHex(ts.Background.Color);
    tfkLinearGradient: bg := bg + '/' + GHex(ts.Background.GradFrom) + '>' +
      GHex(ts.Background.GradTo) + '@' + IntToStr(Round(ts.Background.GradAngleDeg * 100));
    tfkImage: bg := bg + '/' + ts.Background.ImagePath + '/m' +
      IntToStr(Ord(ts.Background.ImageMode)) + '/bl' + IntToStr(ts.Background.Blur);
    tfkNineSlice: bg := bg + '/' + ts.Background.ImagePath;
  end;
  if tpGlass in ts.Present then
    bg := bg + '/glass' + IntToStr(ts.Background.GlassBlur) + ':' + GHex(ts.Background.GlassTint);
  Result :=
    'pres[' + GPresent(ts.Present) + '] bg=' + bg +
    ' ut=' + IntToStr(Ord(ts.BackgroundUnderTitlebar)) +
    ' txt=' + GHex(ts.TextColor) +
    ' bd=' + GHex(ts.BorderColor) + '/' + IntToStr(ts.BorderWidth) + '/' + IntToStr(Ord(ts.BorderStyle)) +
    ' rad=' + IntToStr(ts.BorderRadius) + '/' + IntToStr(ts.Radius.TL) + ',' + IntToStr(ts.Radius.TR) +
      ',' + IntToStr(ts.Radius.BR) + ',' + IntToStr(ts.Radius.BL) +
    ' pad=' + IntToStr(ts.Padding.Left) + ',' + IntToStr(ts.Padding.Top) + ',' +
      IntToStr(ts.Padding.Right) + ',' + IntToStr(ts.Padding.Bottom) +
    ' fnt=' + ts.FontName + '/' + IntToStr(ts.FontSize) + '/' + IntToStr(ts.FontWeight) +
    ' op=' + IntToStr(Round(ts.Opacity * 1000)) +
    ' sh=' + GHex(ts.ShadowColor) + '/' + IntToStr(ts.ShadowBlur) + '/' +
      IntToStr(ts.ShadowOffset.X) + ',' + IntToStr(ts.ShadowOffset.Y) +
    ' ol=' + GHex(ts.OutlineColor) + '/' + IntToStr(ts.OutlineWidth) + '/' + IntToStr(ts.OutlineOffset);
end;

const
  GGRID: array[0..167] of string = (
    'TyForm|', 'TyButton|', 'TyButton|primary', 'TyButton|danger', 'TyLabel|',
    'TyEdit|', 'TyCheckBox|', 'TyRadioButton|', 'TyPanel|', 'TyComboBox|',
    'TyScrollBar|', 'TyScrollThumb|', 'TyTitleBar|', 'TyCaptionButton|',
    'TyCaptionButton|close', 'TyCaptionButton|min', 'TyCaptionButton|max',
    'TyListBox|', 'TyListItem|', 'TyProgressBar|', 'TyProgressFill|',
    'TyGauge|', 'TyGaugeFill|', 'TyHint|', 'TyRibbon|', 'TyRibbonGroup|',
    'TyToggleSwitch|', 'TyToggleKnob|', 'TyTrackBar|', 'TyTrackThumb|', 'TyLinkLabelLink|',
    'TyGroupBox|', 'TyTabControl|', 'TyPageControl|', 'TyTabSheet|',
    'TyTab|', 'TyTabClose|', 'TySpinEdit|',
    'TyMemo|', 'TyTextSelection|', 'TyTextHint|',
    'TyMenuBar|', 'TyMenuItem|', 'TyMenuPopup|', 'TyMenuView|',
    'TySplitter|', 'TyStatusBar|', 'TyToolBar|',
    'TyCalendar|', 'TyCalendarTitle|', 'TyCalendarWeekday|', 'TyCalendarCell|',
    'TyDateTimePicker|', 'TyDateTimeButton|',
    'TyTreeView|', 'TyTreeNode|',
    'TyTreeHeader|', 'TyTreeHeaderSection|',
    'TyTreeCheckBox|',
    { 下面这批一直在册外 —— GGRID 停在 TyTreeCheckBox,于是 AntD 那批控件、
      整个 Grid、Card/Popover/Steps 全都没有任何像素守卫。补齐到与
      light.tycss 的 typeKey 一一对应。 }
    'TyAlert|', 'TyAlertClose|', 'TyBadge|', 'TyBreadcrumb|',
    'TyBreadcrumbItem|', 'TyCard|', 'TyCardActions|', 'TyCardHeader|',
    'TyCascader|', 'TyCascaderItem|', 'TyCascaderPanel|', 'TyChartTooltip|',
    'TyEmpty|', 'TyEmptyImage|', 'TyGrid|', 'TyGridActiveCell|',
    'TyGridButton|', 'TyGridCell|', 'TyGridCellAlt|', 'TyGridCellMarked|',
    'TyGridCellSelectedInactive|', 'TyGridCheckBox|', 'TyGridCommentMark|', 'TyGridFilterRow|',
    'TyGridFixed|', 'TyGridHeader|', 'TyGridHeaderGroup|', 'TyGridHeaderSection|',
    'TyGridHyperlink|', 'TyGridIndicator|', 'TyGridLine|', 'TyGridProgress|',
    'TyGridProgressFill|', 'TyGridRating|', 'TyGridRatingEmpty|', 'TyGridSelection|',
    'TyGridSelectionFrame|', 'TyListGroupHeader|', 'TyListGroupItem|', 'TyNotification|',
    'TyNotificationClose|', 'TyPagination|', 'TyPaginationItem|', 'TyPopover|',
    'TyPopoverTitle|', 'TySegmented|', 'TySegmentedItem|', 'TySteps|',
    'TyStepsConnector|', 'TyStepsItem|', 'TyTag|', 'TyTagClose|',
    'TyTransfer|', 'TyTransferTitle|',
    { 3.0 themability pass. These keys all EXISTED in code and resolved someone else's
      rule (13 instruments hardcoded 'TyGauge'; the list view wore the tree's clothes;
      speed/ribbon buttons wore TyButton). Splitting them is a pure hook addition, so
      every line they add here must be byte-identical to the line their old key already
      dumps — that is exactly what this grid is here to prove.
      The six that dump EMPTY (TyListViewLine/Marquee, the four TyValueListEditor part
      keys) are guarded on purpose: their painters fall back to a state-dependent value,
      so "still undefined" is the assertion. }
    'TyMeter|', 'TyMeterTick|', 'TyMeterNeedle|',
    'TyLevelMeter|', 'TyLevelMeterFill|', 'TyLevelMeterPeak|',
    'TyDial|', 'TyDialPointer|',
    'TyGearDial|', 'TyGearDialTeeth|', 'TyGearDialPointer|',
    'TyAnalogClock|', 'TyAnalogClockHand|', 'TyAnalogClockSecondHand|',
    'TyCircularProgress|', 'TyCircularProgressFill|',
    'TyActivityIndicator|', 'TyActivityIndicatorFill|',
    'TyActivityBar|', 'TyActivityBarFill|',
    'TyGearActivityIndicator|', 'TyGearActivityIndicatorFill|',
    'TySparkline|', 'TySparklineFill|', 'TySparklineDot|',
    'TyRating|', 'TyRatingStar|',
    'TyLColorPicker|', 'TyHSColorPicker|', 'TyColorArea|',
    'TyScrollBox|', 'TyExPanel|', 'TyExPanelHeader|',
    'TyToolGroupPanel|', 'TyToolSeparator|',
    'TySpeedButton|', 'TyGlyphContainerButton|',
    'TyRibbonAppMenu|', 'TyRibbonAppMenu|primary',
    { NOT guarded here: the 'ghost' variant. Adding 'TySpeedButton|ghost' immediately red
      the auto-vs-light/dark equality tests, and the cause is NOT this refactor —
      light.tycss and dark.tycss give TyButton.ghost a rest background of
      alpha(var(--surface-hover), 0) while auto.tycss uses var(--transparent-fill)
      (alpha-0 white / alpha-0 black). Both are invisible at rest, but the RGB of an
      alpha-0 fill is load-bearing: TTyButton cross-fades rest -> hover, so the ramp
      differs. Aligning auto.tycss would MOVE PIXELS mid-fade, which this pass may not do.
      Fix that first, then guard the variant. }
    'TyListView|', 'TyListViewItem|', 'TyListViewHeader|',
    'TyListViewHeaderSection|', 'TyListViewGroupHeader|', 'TyListViewCheckBox|',
    'TyListViewLine|', 'TyListViewMarquee|',
    'TyValueListEditor|', 'TyValueListEditorRow|', 'TyValueListEditorKey|',
    'TyValueListEditorValue|', 'TyValueListEditorDivider|', 'TyValueListEditorExpander|',
    'TyGridGroupRow|', 'TyGridSummaryRow|');

  GMETRICS: array[0..110] of string = (
    '--alert-close-gap',
    '--alert-close-size',
    '--alert-icon-gap',
    '--alert-icon-size',
    '--alert-text-gap',
    '--backstage-back-height',
    '--backstage-icon-size',
    '--backstage-icon-x',
    '--backstage-row-height',
    '--backstage-sidebar-width',
    '--backstage-text-inset',
    '--badge-dot-size',
    '--badge-inset',
    '--breadcrumb-separator-gap',
    '--breadcrumb-separator-size',
    '--caption-button-width',
    '--card-actions-height',
    '--card-header-height',
    '--cascader-column-width',
    '--cascader-expand-gap',
    '--cascader-expand-size',
    '--cascader-row-height',
    '--chart-tooltip-gap',
    '--chart-tooltip-swatch',
    '--chart-tooltip-swatch-gap',
    '--checkbox-gap',
    '--checkbox-size',
    '--control-height',
    '--dialog-edit-width',
    '--dialog-padding',
    '--drop-arrow-width',
    '--empty-action-height',
    '--empty-gap',
    '--empty-image-size',
    '--expander-header-height',
    '--field-button-width',
    '--font-size-sm',
    '--gallery-arrow-width',
    '--gallery-cell-width',
    '--gallery-glyph-pad',
    '--gallery-grid-cell-height',
    '--glyph-button-gap',
    '--grid-comment-mark-size',
    '--header-control-height',
    '--header-height',
    '--header-section-width',
    '--icon-size',
    '--item-height',
    '--listgroup-chevron-size',
    '--listgroup-header-height',
    '--listgroup-icon-gap',
    '--listgroup-icon-size',
    '--listgroup-item-height',
    '--listgroup-item-indent',
    '--listgroup-item-inset',
    '--listview-cell-padding',
    '--listview-check-size',
    '--listview-group-header-height',
    '--listview-hgap',
    '--listview-icon-label-width',
    '--listview-label-height',
    '--listview-large-icon-size',
    '--listview-small-icon-size',
    '--listview-small-label-width',
    '--listview-text-margin',
    '--listview-tile-label-width',
    '--listview-vgap',
    '--menu-arrow-slot',
    '--menu-check-slot',
    '--menu-separator-height',
    '--menu-shortcut-gap',
    '--notification-close-size',
    '--notification-gap',
    '--notification-icon-size',
    '--notification-margin',
    '--notification-stack-gap',
    '--notification-width',
    '--pagination-gap',
    '--pagination-glyph-size',
    '--popover-arrow-size',
    '--popover-offset',
    '--popover-title-gap',
    '--qat-height',
    '--qat-width',
    '--ribbon-appmenu-height',
    '--ribbon-appmenu-width',
    '--ribbon-caption-band-height',
    '--row-height',
    '--scrollbar-size',
    '--segmented-pad',
    '--steps-connector-gap',
    '--steps-connector-length',
    '--steps-gap',
    '--steps-marker-size',
    '--tab-arrow-band',
    '--tab-close-size',
    '--tab-gap',
    '--tab-margin',
    '--tab-min-width',
    '--tab-padding',
    '--tag-close-size',
    '--tag-gap',
    '--titlebar-padding',
    '--transfer-arrow-margin',
    '--transfer-arrow-size',
    '--transfer-button-gap',
    '--transfer-button-height',
    '--transfer-button-width',
    '--transfer-rail-width',
    '--transfer-title-height',
    '--treeselect-drop-height');

function TTestThemeGolden.ThemePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim + AName;
  if not FileExists(Result) then      // structural skins (showcase, …) live in themes/builtin/
    Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim
      + 'builtin' + PathDelim + AName;
end;

function TTestThemeGolden.GoldenPath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'golden' + PathDelim + AName;
end;

function TTestThemeGolden.DumpTheme(const APath: string): string;
const
  STATES: array[0..4] of TTyStateSet = ([], [tysHover], [tysActive], [tysFocused], [tysDisabled]);
var
  model: TTyStyleModel;
  sl: TStringList;
  i, si, bar: Integer;
  key, variant: string;
begin
  model := TTyStyleModel.Create;
  sl := TStringList.Create;
  try
    model.LoadFromFile(APath);
    for i := 0 to High(GGRID) do
    begin
      bar := Pos('|', GGRID[i]);
      key := Copy(GGRID[i], 1, bar - 1);
      variant := Copy(GGRID[i], bar + 1, MaxInt);
      for si := 0 to High(STATES) do
        sl.Add(key + '|' + variant + '|' + IntToStr(si) + ' => ' +
          GDumpStyle(model.ResolveStyle(key, variant, STATES[si])));
    end;
    { 尺寸令牌(密度第三期):运行期几何原先在 golden 之外,令牌抄错或漏定义
      只会静默回退、无守卫。把每个令牌的解析值也 dump 进来,-1 = 未定义。 }
    for i := 0 to High(GMETRICS) do
      sl.Add('metric ' + GMETRICS[i] + ' => ' +
        IntToStr(model.ResolveMetric(GMETRICS[i], -1)));
    Result := sl.Text;
    Result := sl.Text;
  finally
    sl.Free;
    model.Free;
  end;
end;

function TTestThemeGolden.DumpThemeMode(const APath, AMode: string): string;
const
  STATES: array[0..4] of TTyStateSet = ([], [tysHover], [tysActive], [tysFocused], [tysDisabled]);
var
  model: TTyStyleModel;
  sl: TStringList;
  i, si, bar: Integer;
  key, variant: string;
begin
  model := TTyStyleModel.Create;
  sl := TStringList.Create;
  try
    model.LoadFromFile(APath);
    model.SetMode(AMode);   // P3: select the active @mode block before resolving
    for i := 0 to High(GGRID) do
    begin
      bar := Pos('|', GGRID[i]);
      key := Copy(GGRID[i], 1, bar - 1);
      variant := Copy(GGRID[i], bar + 1, MaxInt);
      for si := 0 to High(STATES) do
        sl.Add(key + '|' + variant + '|' + IntToStr(si) + ' => ' +
          GDumpStyle(model.ResolveStyle(key, variant, STATES[si])));
    end;
    { 尺寸令牌(密度第三期):运行期几何原先在 golden 之外,令牌抄错或漏定义
      只会静默回退、无守卫。把每个令牌的解析值也 dump 进来,-1 = 未定义。 }
    for i := 0 to High(GMETRICS) do
      sl.Add('metric ' + GMETRICS[i] + ' => ' +
        IntToStr(model.ResolveMetric(GMETRICS[i], -1)));
    Result := sl.Text;
    Result := sl.Text;
  finally
    sl.Free;
    model.Free;
  end;
end;

procedure TTestThemeGolden.TestAutoLightEqualsLight;
var autoDump, lightDump: string;
begin
  autoDump := DumpThemeMode(ThemePath('auto.tycss'), 'light');
  lightDump := DumpTheme(ThemePath('light.tycss'));
  AssertEquals('auto.tycss in light mode must resolve byte-identically to light.tycss',
    lightDump, autoDump);
end;

procedure TTestThemeGolden.TestAutoDarkEqualsDark;
var autoDump, darkDump: string;
begin
  autoDump := DumpThemeMode(ThemePath('auto.tycss'), 'dark');
  darkDump := DumpTheme(ThemePath('dark.tycss'));
  AssertEquals('auto.tycss in dark mode must resolve byte-identically to dark.tycss',
    darkDump, autoDump);
end;

type
  { One key that USED to be someone else's, plus the key it was taken from. }
  TTyAliasPair = record
    NewKey: string;
    Donor: string;
    BaseStateOnly: Boolean;   { the sub-part is resolved with an EMPTY state set, so it
                                deliberately joined only the donor's stateless rule }
    Variants: string;         { extra StyleClass values to check, comma separated }
  end;

const
  { Every shipped theme: themes/*.tycss plus all fifteen skins under themes/builtin/. }
  ALIAS_THEMES: array[0..19] of string = (
    'light', 'dark', 'auto', 'green', 'system',
    'adwaita', 'aero', 'antdesign', 'bootstrap', 'breeze', 'classic', 'fluent',
    'macos', 'material3', 'office', 'showcase', 'ubuntu', 'win10', 'win11', 'xp');

  ALIAS_PAIRS: array[0..44] of TTyAliasPair = (
    { The instrument family: thirteen controls that hardcoded 'TyGauge' + 'TyGaugeFill'. }
    (NewKey: 'TyMeter';                   Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyLevelMeter';              Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyDial';                    Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyGearDial';                Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyAnalogClock';             Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyCircularProgress';        Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyActivityIndicator';       Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyActivityBar';             Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyGearActivityIndicator';   Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TySparkline';               Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyRating';                  Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyLColorPicker';            Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyHSColorPicker';           Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    { Sub-parts that read the FACE, not the fill — stateless, hence base-state only. }
    (NewKey: 'TyMeterTick';               Donor: 'TyGauge';     BaseStateOnly: True;  Variants: ''),
    (NewKey: 'TyAnalogClockHand';         Donor: 'TyGauge';     BaseStateOnly: True;  Variants: ''),
    (NewKey: 'TyGearDialTeeth';           Donor: 'TyGauge';     BaseStateOnly: True;  Variants: ''),
    (NewKey: 'TyColorArea';               Donor: 'TyGauge';     BaseStateOnly: True;  Variants: ''),
    { Sub-parts that read the accent fill. }
    (NewKey: 'TyMeterNeedle';             Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyLevelMeterFill';          Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyLevelMeterPeak';          Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyDialPointer';             Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyGearDialPointer';         Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyAnalogClockSecondHand';   Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyCircularProgressFill';    Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyActivityIndicatorFill';   Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyActivityBarFill';         Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyGearActivityIndicatorFill'; Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TySparklineFill';           Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TySparklineDot';            Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyRatingStar';              Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    { Containers + toolbar. }
    (NewKey: 'TyScrollBox';               Donor: 'TyPanel';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyExPanel';                 Donor: 'TyPanel';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyToolGroupPanel';          Donor: 'TyGroupBox';  BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyToolSeparator';           Donor: 'TyToolBar';   BaseStateOnly: False; Variants: ''),
    { Buttons. The variants matter: a toolbar stamps 'ghost' on its children and the
      ribbon's File tab ships with 'primary', so those are the DEFAULT renderings. }
    (NewKey: 'TySpeedButton';             Donor: 'TyButton';    BaseStateOnly: False; Variants: 'primary,danger,ghost'),
    (NewKey: 'TyGlyphContainerButton';    Donor: 'TyButton';    BaseStateOnly: False; Variants: 'primary,danger,ghost'),
    (NewKey: 'TyRibbonAppMenu';           Donor: 'TyButton';    BaseStateOnly: False; Variants: 'primary,danger,ghost'),
    { The list view, which wore the tree's clothes entirely. }
    (NewKey: 'TyListView';                Donor: 'TyTreeView';  BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyListViewItem';            Donor: 'TyTreeNode';  BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyListViewHeader';          Donor: 'TyTreeHeader'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyListViewGroupHeader';     Donor: 'TyTreeHeader'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyListViewHeaderSection';   Donor: 'TyTreeHeaderSection'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyListViewCheckBox';        Donor: 'TyTreeCheckBox'; BaseStateOnly: False; Variants: ''),
    { The property grid built on the list box. }
    (NewKey: 'TyValueListEditor';         Donor: 'TyListBox';   BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyValueListEditorRow';      Donor: 'TyListItem';  BaseStateOnly: False; Variants: ''));

procedure TTestThemeGolden.CheckAlias(AModel: TTyStyleModel; const ATheme, ANew,
  ADonor, AVariant: string; ABaseStateOnly: Boolean);
const
  STATES: array[0..4] of TTyStateSet = ([], [tysHover], [tysActive], [tysFocused], [tysDisabled]);
var
  si, last: Integer;
  tag: string;
begin
  if ABaseStateOnly then last := 0 else last := High(STATES);
  for si := 0 to last do
  begin
    tag := ATheme + ': ' + ANew;
    if AVariant <> '' then tag := tag + '.' + AVariant;
    tag := tag + ' state#' + IntToStr(si) + ' must resolve exactly like ' + ADonor;
    AssertEquals(tag,
      GDumpStyle(AModel.ResolveStyle(ADonor, AVariant, STATES[si])),
      GDumpStyle(AModel.ResolveStyle(ANew, AVariant, STATES[si])));
  end;
end;

procedure TTestThemeGolden.TestNewKeysMatchTheirDonorInEveryTheme;
var
  ti, pi: Integer;
  m: TTyStyleModel;
  variants: TStringList;
  vi: Integer;
begin
  for ti := 0 to High(ALIAS_THEMES) do
  begin
    m := TTyStyleModel.Create;
    variants := TStringList.Create;
    try
      AssertTrue('theme file must exist: ' + ALIAS_THEMES[ti],
        FileExists(ThemePath(ALIAS_THEMES[ti] + '.tycss')));
      m.LoadFromFile(ThemePath(ALIAS_THEMES[ti] + '.tycss'));
      m.Mode := 'light';   // dual-mode files need an active mode; no-op for single-mode
      for pi := 0 to High(ALIAS_PAIRS) do
      begin
        CheckAlias(m, ALIAS_THEMES[ti], ALIAS_PAIRS[pi].NewKey,
          ALIAS_PAIRS[pi].Donor, '', ALIAS_PAIRS[pi].BaseStateOnly);
        if ALIAS_PAIRS[pi].Variants = '' then Continue;
        variants.Clear;
        variants.Delimiter := ',';
        variants.StrictDelimiter := True;
        variants.DelimitedText := ALIAS_PAIRS[pi].Variants;
        for vi := 0 to variants.Count - 1 do
          CheckAlias(m, ALIAS_THEMES[ti], ALIAS_PAIRS[pi].NewKey,
            ALIAS_PAIRS[pi].Donor, variants[vi], ALIAS_PAIRS[pi].BaseStateOnly);
      end;
    finally
      variants.Free;
      m.Free;
    end;
  end;
end;

procedure TTestThemeGolden.CheckGolden(const AThemeName: string);
var
  dump, gpath: string;
  sl: TStringList;
begin
  dump := DumpTheme(ThemePath(AThemeName + '.tycss'));
  gpath := GoldenPath(AThemeName + '.golden.txt');
  if FileExists(gpath) then
  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(gpath);
      if sl.Text <> dump then
      begin
        sl.Text := dump;
        sl.SaveToFile(gpath + '.actual');
        Fail('Theme ' + AThemeName + ' resolved styles changed vs golden. Diff ' +
          gpath + ' against ' + gpath + '.actual; if intended, update the golden.');
      end;
    finally
      sl.Free;
    end;
  end
  else
  begin
    ForceDirectories(ExtractFilePath(gpath));
    sl := TStringList.Create;
    try
      sl.Text := dump;
      sl.SaveToFile(gpath);
    finally
      sl.Free;
    end;
    // bootstrap: golden created this run, nothing to assert
  end;
end;

procedure TTestThemeGolden.TestLightGolden;
begin
  CheckGolden('light');
end;

procedure TTestThemeGolden.TestDarkGolden;
begin
  CheckGolden('dark');
end;

procedure TTestThemeGolden.TestShowcaseGolden;
begin
  CheckGolden('showcase');
end;

initialization
  RegisterTest(TTestThemes);
  RegisterTest(TTestThemeGolden);
end.
