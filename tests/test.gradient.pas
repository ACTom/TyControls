unit test.gradient;
{ Theme-system v3 · Phase B1: multi-stop linear gradients. linear-gradient() grows from
  exactly two colours to N colour stops with optional CSS positions (normalised: first->0,
  last->1, interior interpolated, non-decreasing), and the painter renders >2 stops via a
  BGRA multi-gradient scanner. Two-stop gradients keep the exact old GradFrom/GradTo path
  (byte-identical golden), which the last test guards. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.StyleModel, tyControls.Painter;
type
  TGradientTest = class(TTestCase)
  private
    function GradFill(const ACss: string): TTyFill;
  published
    procedure TestTwoStopStillFromTo;
    procedure TestThreeStopsEvenPositions;
    procedure TestExplicitPositions;
    procedure TestMissingInteriorPositionInterpolated;
    procedure TestFunctionColorWithPosition;
    procedure TestNonDecreasingClamp;
    procedure TestTooFewColoursRaises;
    procedure TestPainterRendersMiddleStop;
  end;

implementation

function TGradientTest.GradFill(const ACss: string): TTyFill;
var m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TyButton { background: ' + ACss + '; }');
    Result := m.ResolveStyle('TyButton', '', []).Background;   // managed copy survives m.Free
  finally
    m.Free;
  end;
end;

procedure TGradientTest.TestTwoStopStillFromTo;
var f: TTyFill;
begin
  f := GradFill('linear-gradient(45deg, #FFFFFF, #000000)');
  AssertEquals('kind is linear gradient', Ord(tfkLinearGradient), Ord(f.Kind));
  AssertEquals('angle', 45, Round(f.GradAngleDeg));
  AssertEquals('two stops', 2, Length(f.GradStops));
  AssertEquals('GradFrom mirrors stop 0', Integer(TyRGB($FF, $FF, $FF)), Integer(f.GradFrom));
  AssertEquals('GradTo mirrors last stop', Integer(TyRGB(0, 0, 0)), Integer(f.GradTo));
  AssertEquals('stop0 pos', 0.0, f.GradStops[0].Pos, 0.001);
  AssertEquals('stop1 pos', 1.0, f.GradStops[1].Pos, 0.001);
end;

procedure TGradientTest.TestThreeStopsEvenPositions;
var f: TTyFill;
begin
  f := GradFill('linear-gradient(90deg, #FF0000, #00FF00, #0000FF)');
  AssertEquals('three stops', 3, Length(f.GradStops));
  AssertEquals('mid colour is green', Integer(TyRGB(0, $FF, 0)), Integer(f.GradStops[1].Color));
  AssertEquals('pos0', 0.0, f.GradStops[0].Pos, 0.001);
  AssertEquals('pos1 even = 0.5', 0.5, f.GradStops[1].Pos, 0.001);
  AssertEquals('pos2', 1.0, f.GradStops[2].Pos, 0.001);
end;

procedure TGradientTest.TestExplicitPositions;
var f: TTyFill;
begin
  f := GradFill('linear-gradient(0deg, #FFFFFF 0%, #EEEEEE 40%, #999999 100%)');
  AssertEquals('three stops', 3, Length(f.GradStops));
  AssertEquals('explicit interior pos = 0.4', 0.4, f.GradStops[1].Pos, 0.001);
end;

procedure TGradientTest.TestMissingInteriorPositionInterpolated;
var f: TTyFill;
begin
  // c0 (no pos -> 0), c1 (no pos -> interpolated), c2 @80% -> c1 = 0 + (0.8-0)*1/2 = 0.4
  f := GradFill('linear-gradient(0deg, #FFFFFF, #CCCCCC, #333333 80%)');
  AssertEquals('interior interpolated to 0.4', 0.4, f.GradStops[1].Pos, 0.001);
  AssertEquals('last honoured 0.8', 0.8, f.GradStops[2].Pos, 0.001);
end;

procedure TGradientTest.TestFunctionColorWithPosition;
var f: TTyFill;
begin
  // a function colour with an inner comma must not be mis-split, and its trailing position
  // must still be parsed (the paren-depth-0 split).
  f := GradFill('linear-gradient(0deg, lighten(#3366CC, 20%) 0%, #3366CC 50%, darken(#3366CC, 20%) 100%)');
  AssertEquals('three stops', 3, Length(f.GradStops));
  AssertEquals('middle honoured 0.5', 0.5, f.GradStops[1].Pos, 0.001);
  AssertEquals('middle colour is the base', Integer(TyRGB($33, $66, $CC)), Integer(f.GradStops[1].Color));
end;

procedure TGradientTest.TestNonDecreasingClamp;
var f: TTyFill;
begin
  // a position lower than its predecessor is clamped up.
  f := GradFill('linear-gradient(0deg, #FFFFFF 60%, #000000 30%)');
  AssertTrue('second pos clamped >= first', f.GradStops[1].Pos >= f.GradStops[0].Pos - 0.0001);
end;

procedure TGradientTest.TestTooFewColoursRaises;
var m: TTyStyleModel; raised: Boolean;
begin
  m := TTyStyleModel.Create;
  try
    raised := False;
    try
      m.LoadFromCss('TyButton { background: linear-gradient(90deg, #FFFFFF); }');
      m.ResolveStyle('TyButton', '', []);
    except
      raised := True;
    end;
    AssertTrue('a single-colour gradient raises', raised);
  finally
    m.Free;
  end;
end;

procedure TGradientTest.TestPainterRendersMiddleStop;
var
  fill: TTyFill;
  host: TBitmap;
  p: TTyPainter;
  mid: TBGRAPixel;
begin
  // A 3-stop red -> green -> blue vertical gradient: the MIDDLE row must be green-dominant.
  // A 2-stop (red -> blue) scanner could never produce green there, so this proves the
  // multi-stop path actually renders the interior stops.
  fill := Default(TTyFill);
  fill.Kind := tfkLinearGradient;
  fill.GradAngleDeg := 90;
  SetLength(fill.GradStops, 3);
  fill.GradStops[0].Color := TyRGB($FF, 0, 0); fill.GradStops[0].Pos := 0;
  fill.GradStops[1].Color := TyRGB(0, $FF, 0); fill.GradStops[1].Pos := 0.5;
  fill.GradStops[2].Color := TyRGB(0, 0, $FF); fill.GradStops[2].Pos := 1;
  fill.GradFrom := fill.GradStops[0].Color;
  fill.GradTo := fill.GradStops[2].Color;
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(20, 40);
    p.BeginPaint(host.Canvas, Rect(0, 0, 20, 40), 96);
    p.FillBackground(Rect(0, 0, 20, 40), fill, 0);
    mid := p.Bitmap.GetPixel(10, 20);   // middle row
    p.EndPaint;
    AssertTrue('middle row is green-dominant (multi-stop rendered)',
      (mid.green > mid.red) and (mid.green > mid.blue));
  finally
    p.Free;
    host.Free;
  end;
end;

initialization
  RegisterTest(TGradientTest);
end.
