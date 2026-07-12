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
  tyControls.Types, tyControls.StyleModel, tyControls.Controller, tyControls.CheckBox;
type
  TCheckBoxProbe = class(TTyCheckBox)   // expose the protected RenderTo for headless sampling
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
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
  end;

implementation

procedure TCheckBoxProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
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

initialization
  RegisterTest(TMetricTest);
end.
