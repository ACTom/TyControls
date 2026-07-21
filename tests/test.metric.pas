unit test.metric;
{ Theme-system v3 · Phase C: skin-tunable geometry metrics. ResolveMetric/Metric read a named
  LENGTH token (e.g. --checkbox-size) from the merged vars, falling back to the built-in
  constant when unset (so the golden is unaffected). C1 wires the checkbox/radio indicator
  size + caption gap to metrics; this proves the mechanism and the checkbox integration. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, BGRABitmap, BGRABitmapTypes,
  fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller, tyControls.CheckBox,
  tyControls.GroupBox, tyControls.ListView, tyControls.Grid, tyControls.ExPanel,
  tyControls.BuiltinThemes;
type
  TCheckBoxProbe = class(TTyCheckBox)   // expose the protected RenderTo for headless sampling
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TGroupBoxProbe = class(TTyGroupBox)   // expose the reserved top inset (caption band)
  public
    function TopInset: Integer;
  end;

  { Exposes the protected CurrentMetrics so a test can read the row height the
    layout/paint path actually uses. }
  TLVMetricsAccess = class(TTyListView)
  public
    function RowHeightPx: Integer;
  end;

  TMetricTest = class(TTestCase)
  private
    function CheckBoxBoxIsRedAt(const AThemeCss: string; AX: Integer): Boolean;
  published
    procedure TestMetricAbsentReturnsDefault;
    procedure TestMetricPxValue;
    procedure TestMetricBareNumber;
    procedure TestMetricViaVar;
    procedure TestMetricBadValueReturnsDefault;
    procedure TestMetricLeadingDashesNormalised;
    procedure TestControllerMetricPassthrough;
    procedure TestCheckBoxBoxSizeFollowsMetric;
    procedure TestGroupBoxCaptionBandFollowsMetric;
    { 密度尺度第四期 }
    procedure TestDensityClassicIsDefault;
    procedure TestDensityModernEnlargesTokens;
    procedure TestDensitySurvivesThemeSwitch;
    procedure TestDensityTogglesBackToClassic;
    procedure TestListViewRowHeightFollowsDensity;
    procedure TestGridRowHeightFollowsDensity;
    procedure TestExPanelHeaderHeightFollowsDensity;
  end;

implementation

function TLVMetricsAccess.RowHeightPx: Integer;
begin
  Result := CurrentMetrics.RowH;
end;

procedure TCheckBoxProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TGroupBoxProbe.TopInset: Integer;
var r: TRect;
begin
  r := Rect(0, 0, 100, 100);
  AdjustClientRect(r);   // reserves the caption band at the top
  Result := r.Top;
end;

procedure TMetricTest.TestMetricAbsentReturnsDefault;
var m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TyButton { background: #FFFFFF; }');
    AssertEquals('absent metric -> default', 16, m.ResolveMetric('--checkbox-size', 16));
  finally
    m.Free;
  end;
end;

procedure TMetricTest.TestMetricPxValue;
var m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(':root { --checkbox-size: 24px; } TyButton { background: #FFFFFF; }');
    AssertEquals('px metric parsed', 24, m.ResolveMetric('--checkbox-size', 16));
  finally
    m.Free;
  end;
end;

procedure TMetricTest.TestMetricBareNumber;
var m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(':root { --checkbox-size: 20; } TyButton { background: #FFFFFF; }');
    AssertEquals('bare-number metric parsed', 20, m.ResolveMetric('--checkbox-size', 16));
  finally
    m.Free;
  end;
end;

procedure TMetricTest.TestMetricViaVar;
var m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(':root { --unit: 22px; --checkbox-size: var(--unit); } TyButton { background: #FFFFFF; }');
    AssertEquals('var() metric resolved', 22, m.ResolveMetric('--checkbox-size', 16));
  finally
    m.Free;
  end;
end;

procedure TMetricTest.TestMetricBadValueReturnsDefault;
var m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(':root { --checkbox-size: notalength; } TyButton { background: #FFFFFF; }');
    AssertEquals('unparseable metric -> default', 16, m.ResolveMetric('--checkbox-size', 16));
  finally
    m.Free;
  end;
end;

procedure TMetricTest.TestMetricLeadingDashesNormalised;
var m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(':root { --checkbox-size: 18px; } TyButton { background: #FFFFFF; }');
    // caller may pass the name with or without the leading '--'
    AssertEquals('with dashes', 18, m.ResolveMetric('--checkbox-size', 16));
    AssertEquals('without dashes', 18, m.ResolveMetric('checkbox-size', 16));
  finally
    m.Free;
  end;
end;

procedure TMetricTest.TestControllerMetricPassthrough;
var c: TTyStyleController;
begin
  c := TTyStyleController.Create(nil);
  try
    c.LoadThemeCss(':root { --checkbox-size: 26px; } TyButton { background: #FFFFFF; }');
    AssertEquals('controller Metric delegates to the model', 26, c.Metric('--checkbox-size', 16));
    AssertEquals('controller Metric default when unset', 16, c.Metric('--nope', 16));
  finally
    c.Free;
  end;
end;

function TMetricTest.CheckBoxBoxIsRedAt(const AThemeCss: string; AX: Integer): Boolean;
var
  ctrl: TTyStyleController;
  cb: TCheckBoxProbe;
  bmp: TBitmap;
  reread: TBGRABitmap;
  px: TBGRAPixel;
begin
  ctrl := TTyStyleController.Create(nil);
  cb := TCheckBoxProbe.Create(nil);
  bmp := TBitmap.Create;
  try
    ctrl.LoadThemeCss(AThemeCss);
    cb.Controller := ctrl;
    cb.Caption := 'x';
    bmp.SetSize(120, 40);
    cb.Render(bmp.Canvas, Rect(0, 0, 120, 40), 96);
    reread := TBGRABitmap.Create(bmp);
    try
      px := reread.GetPixel(AX, 20);   // vertical centre
      Result := (px.red > 200) and (px.green < 80) and (px.blue < 80);
    finally
      reread.Free;
    end;
  finally
    bmp.Free;
    cb.Free;
    ctrl.Free;
  end;
end;

procedure TMetricTest.TestCheckBoxBoxSizeFollowsMetric;
const
  BOX_THEME = 'TyCheckBox { background: #FF0000; border-width: 0; padding: 0; }';
begin
  // The red indicator box is left-aligned. At the default size (16) x=25 is PAST the box;
  // with --checkbox-size: 30px the box reaches x=25. So the metric moves the box edge.
  AssertFalse('default box (16) does not reach x=25', CheckBoxBoxIsRedAt(BOX_THEME, 25));
  AssertTrue('metric box (30) reaches x=25',
    CheckBoxBoxIsRedAt(':root { --checkbox-size: 30px; } ' + BOX_THEME, 25));
end;

procedure TMetricTest.TestGroupBoxCaptionBandFollowsMetric;
var ctrlDef, ctrlBig: TTyStyleController; gbDef, gbBig: TGroupBoxProbe; topDef, topBig: Integer;
begin
  // The reserved top inset is the caption band. Growing --groupbox-caption-height must grow it.
  ctrlDef := TTyStyleController.Create(nil);
  ctrlBig := TTyStyleController.Create(nil);
  gbDef := TGroupBoxProbe.Create(nil);
  gbBig := TGroupBoxProbe.Create(nil);
  try
    ctrlDef.LoadThemeCss('TyGroupBox { background: #FFFFFF; }');                          // band = 16 (default)
    ctrlBig.LoadThemeCss(':root { --groupbox-caption-height: 30px; } TyGroupBox { background: #FFFFFF; }');
    gbDef.Controller := ctrlDef;
    gbBig.Controller := ctrlBig;
    topDef := gbDef.TopInset;
    topBig := gbBig.TopInset;
    AssertTrue('caption band reserves a positive top inset', topDef > 0);
    AssertTrue('metric grows the caption band (30 vs 16)', topBig > topDef);
  finally
    gbBig.Free; gbDef.Free; ctrlBig.Free; ctrlDef.Free;
  end;
end;

{ 密度默认是经典:什么都不叠,令牌 = 现值。 }
procedure TMetricTest.TestDensityClassicIsDefault;
var c: TTyStyleController;
begin
  c := TTyStyleController.Create(nil);
  try
    TyRegisterBuiltinThemes;
    c.ThemeName := 'default';
    AssertTrue('默认是经典', c.Density = tdClassic);
    AssertEquals('经典 checkbox 16', 16, c.Metric('--checkbox-size', 99));
    AssertEquals('经典 row-height 22', 22, c.Metric('--row-height', 99));
  finally
    c.Free;
  end;
end;

{ 开现代:几何令牌变大(证明密度包叠上去、被读到)。 }
{ The report row height must ride the density axis: an unset RowHeight follows the
  --row-height token (22 classic -> 32 modern), while an explicit RowHeight pins itself
  and ignores density. Before the fix the constructor cached --row-height once at classic
  density, so a modern-density list stayed at 22-px rows -- the antdesign list page's
  "Win32 grid" look. Observed through CurrentMetrics.RowH (the value layout/paint use). }
procedure TMetricTest.TestListViewRowHeightFollowsDensity;
var
  c: TTyStyleController;
  lv: TLVMetricsAccess;
  classicH, modernH, explicitH: Integer;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  lv := TLVMetricsAccess.Create(nil);
  try
    c.ThemeName := 'default';
    lv.Controller := c;
    lv.SetBounds(0, 0, 300, 200);

    c.Density := tdClassic;
    classicH := lv.RowHeightPx;
    c.Density := tdModern;
    modernH := lv.RowHeightPx;
    AssertTrue('未设 RowHeight 时,现代行高应明显高于经典', modernH > classicH + 4);

    lv.RowHeight := 20;                      { explicit -> pinned, density no longer applies }
    explicitH := lv.RowHeightPx;
    AssertTrue('显式 RowHeight 在现代密度下仍被钉住(不跟随)', explicitH < modernH);
  finally
    lv.Free;
    c.Free;
  end;
end;

{ Same density gap, same fix on TTyStringGrid: DefaultRowHeight was a hardcoded 22.
  The getter now returns the live --row-height when unset (so a modern grid gets roomy
  rows) and the pinned value when set. }
procedure TMetricTest.TestGridRowHeightFollowsDensity;
var
  c: TTyStyleController;
  g: TTyStringGrid;
  classicH, modernH: Integer;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  g := TTyStringGrid.Create(nil);
  try
    c.ThemeName := 'default';
    g.Controller := c;
    c.Density := tdClassic;
    classicH := g.DefaultRowHeight;
    c.Density := tdModern;
    modernH := g.DefaultRowHeight;
    AssertTrue('未设 DefaultRowHeight 时,现代应高于经典', modernH > classicH + 4);
    g.DefaultRowHeight := 20;
    AssertEquals('显式 DefaultRowHeight 钉住,不跟密度', 20, g.DefaultRowHeight);
  finally
    g.Free;
    c.Free;
  end;
end;

{ TTyExPanel.HeaderHeight had the same constructor-cached gap: it read
  --expander-header-height once at construction (classic 26), so a modern-density
  panel kept a 26px header and cramped its title. Now the getter resolves it live. }
procedure TMetricTest.TestExPanelHeaderHeightFollowsDensity;
var
  c: TTyStyleController;
  p: TTyExPanel;
  classicH, modernH: Integer;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  p := TTyExPanel.Create(nil);
  try
    c.ThemeName := 'default';
    p.Controller := c;
    c.Density := tdClassic;
    classicH := p.HeaderHeight;
    c.Density := tdModern;
    modernH := p.HeaderHeight;
    AssertTrue('未设 HeaderHeight 时,现代 header 应高于经典', modernH > classicH + 4);
    p.HeaderHeight := 22;
    AssertEquals('显式 HeaderHeight 钉住,不跟密度', 22, p.HeaderHeight);
  finally
    p.Free;
    c.Free;
  end;
end;

procedure TMetricTest.TestDensityModernEnlargesTokens;
var c: TTyStyleController;
begin
  c := TTyStyleController.Create(nil);
  try
    TyRegisterBuiltinThemes;
    c.ThemeName := 'default';
    c.Density := tdModern;
    AssertEquals('现代 checkbox 20', 20, c.Metric('--checkbox-size', 99));
    AssertEquals('现代 row-height 32', 32, c.Metric('--row-height', 99));
    AssertEquals('现代 font-size-base 14', 14, c.Metric('--font-size-base', 99));
  finally
    c.Free;
  end;
end;

{ **换主题冲掉密度包**那个坑:先开现代、再换皮肤,现代令牌必须还在。
  SetThemeName 走 LoadFromCss(REPLACE),会把追加的密度包冲掉 ——
  不在换主题后重叠的话,这里就退回经典。 }
procedure TMetricTest.TestDensitySurvivesThemeSwitch;
var c: TTyStyleController;
begin
  c := TTyStyleController.Create(nil);
  try
    TyRegisterBuiltinThemes;
    c.ThemeName := 'default';
    c.Density := tdModern;
    AssertEquals('换主题前是现代', 20, c.Metric('--checkbox-size', 99));
    c.ThemeName := 'office';       { 换个皮肤 }
    AssertEquals('换主题后仍是现代(密度包被重叠)', 20, c.Metric('--checkbox-size', 99));
    c.ThemeName := 'default';
    AssertEquals('再换回来仍是现代', 20, c.Metric('--checkbox-size', 99));
  finally
    c.Free;
  end;
end;

{ 切回经典:追加层没法卸载,靠重装底层冲掉 —— 令牌要回到经典值。 }
procedure TMetricTest.TestDensityTogglesBackToClassic;
var c: TTyStyleController;
begin
  c := TTyStyleController.Create(nil);
  try
    TyRegisterBuiltinThemes;
    c.ThemeName := 'default';
    c.Density := tdModern;
    AssertEquals('现代 20', 20, c.Metric('--checkbox-size', 99));
    c.Density := tdClassic;
    AssertEquals('切回经典 16', 16, c.Metric('--checkbox-size', 99));
  finally
    c.Free;
  end;
end;

initialization
  RegisterTest(TMetricTest);
end.
