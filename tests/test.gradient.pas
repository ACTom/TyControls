unit test.gradient;
{ Theme-system v3 · Phase B1: multi-stop linear gradients. linear-gradient() grows from
  exactly two colours to N colour stops with optional CSS positions (normalised: first->0,
  last->1, interior interpolated, non-decreasing), and the painter renders >2 stops via a
  BGRA multi-gradient scanner. Two stops at 0 and 1 take the cheaper two-colour scanner, and
  every path blends in plain sRGB as CSS does, which the TestTwoColours* tests guard. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.StyleModel, tyControls.Painter, tyControls.Base;
type
  TGradientTest = class(TTestCase)
  private
    function GradFill(const ACss: string): TTyFill;
    function Background(const AFill: TTyFill; AW, AH: Integer): TBGRABitmap;
    function PathFill(const AFill: TTyFill; AW, AH: Integer): TBGRABitmap;
    procedure CheckPlainMidpoint(const AWhat: string; ABmp: TBGRABitmap; AFrom, ATo: TTyColor);
  published
    procedure TestTwoStopStillFromTo;
    procedure TestThreeStopsEvenPositions;
    procedure TestExplicitPositions;
    procedure TestMissingInteriorPositionInterpolated;
    procedure TestFunctionColorWithPosition;
    procedure TestNonDecreasingClamp;
    procedure TestTooFewColoursRaises;
    procedure TestPainterRendersMiddleStop;
    procedure TestTwoStopsKeepTheirPositions;
    procedure TestTheCentreColourHonoursTwoStopPositions;
    procedure TestTwoColoursBlendInPlainSRGBOnTheBackground;
    procedure TestTwoColoursBlendInPlainSRGBOnAPath;
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

{ #49. Two stops at 20% and 80%: CSS keeps the first fifth pure stop-0 colour and the last fifth
  pure stop-1 colour, and blends only between. The two-colour scanner blended over the whole
  sweep, so the 10% row was already a mix. Sampled along the gradient axis (90deg runs down
  the rows here, as in TestPainterRendersMiddleStop). }
procedure TGradientTest.TestTwoStopsKeepTheirPositions;
var
  fill: TTyFill;
  host: TBitmap;
  p: TTyPainter;
  a, b, mid: TBGRAPixel;
begin
  fill := GradFill('linear-gradient(90deg, #FF0000 20%, #0000FF 80%)');
  AssertEquals('parsed: stop 0 at 20%', 0.2, fill.GradStops[0].Pos, 0.001);
  AssertEquals('parsed: stop 1 at 80%', 0.8, fill.GradStops[1].Pos, 0.001);
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(20, 100);
    p.BeginPaint(host.Canvas, Rect(0, 0, 20, 100), 96);
    p.FillBackground(Rect(0, 0, 20, 100), fill, 0);
    a := p.Bitmap.GetPixel(10, 10);
    b := p.Bitmap.GetPixel(10, 90);
    mid := p.Bitmap.GetPixel(10, 50);
    p.EndPaint;
    AssertTrue(Format('the 10%% row is pure red (got %d,%d,%d)', [a.red, a.green, a.blue]),
      (a.red = 255) and (a.blue = 0));
    AssertTrue(Format('the 90%% row is pure blue (got %d,%d,%d)', [b.red, b.green, b.blue]),
      (b.red = 0) and (b.blue = 255));
    AssertTrue('the middle row is between the two',
      (mid.red > 40) and (mid.red < 215) and (mid.blue > 40) and (mid.blue < 215));
  finally
    p.Free;
    host.Free;
  end;
end;

{ The parent-background samplers (TyFillCentreColor and the slice behind a child) build their
  own scanner; they must place two stops by position as the painter does. Stops at 0% and
  40%: by position the centre is already pure blue; spread over the whole sweep it would be
  a mix. }
procedure TGradientTest.TestTheCentreColourHonoursTwoStopPositions;
var
  fill: TTyFill;
  c: TTyColor;
begin
  fill := GradFill('linear-gradient(90deg, #FF0000 0%, #0000FF 40%)');
  c := TyFillCentreColor(fill, Rect(0, 0, 20, 100));
  AssertTrue(Format('the centre is past the last stop: pure blue (got %d,%d,%d)',
    [TyRedOf(c), TyGreenOf(c), TyBlueOf(c)]), (TyRedOf(c) = 0) and (TyBlueOf(c) = 255));
end;

{ ---- one interpolation for every themed gradient ----

  BGRA's two-colour scanner blends with gamma correction unless told otherwise (exponent 1.7,
  a midpoint well above the average), while its multi-gradient was built without it. So the
  same two colours used to meet in a different middle depending on whether a theme wrote them
  as a plain pair or as stops, and neither path agreed with CSS on the pair. These pin the
  CSS answer: a 1001px horizontal ramp, sampled at its middle column, is the per-channel
  average of the ends (within the rounding of a byte), on the background and on a path. }

function TGradientTest.Background(const AFill: TTyFill; AW, AH: Integer): TBGRABitmap;
var
  host: TBitmap;
  p: TTyPainter;
begin
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(AW, AH);
    p.BeginPaint(host.Canvas, Rect(0, 0, AW, AH), 96);
    p.FillBackground(Rect(0, 0, AW, AH), AFill, 0);
    Result := p.Bitmap.Duplicate as TBGRABitmap;
    p.EndPaint;
  finally
    p.Free;
    host.Free;
  end;
end;

function TGradientTest.PathFill(const AFill: TTyFill; AW, AH: Integer): TBGRABitmap;
var
  host: TBitmap;
  p: TTyPainter;
begin
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(AW, AH);
    p.BeginPaint(host.Canvas, Rect(0, 0, AW, AH), 96);
    p.BeginPath;
    p.RectPath(0, 0, AW, AH);
    p.FillPathWith(AFill, Rect(0, 0, AW, AH));
    Result := p.Bitmap.Duplicate as TBGRABitmap;
    p.EndPaint;
  finally
    p.Free;
    host.Free;
  end;
end;

procedure TGradientTest.CheckPlainMidpoint(const AWhat: string; ABmp: TBGRABitmap;
  AFrom, ATo: TTyColor);
var
  m: TBGRAPixel;

  procedure Channel(const AName: string; AGot, AA, AB: Integer);
  begin
    AssertTrue(Format('%s: the midpoint %s is the sRGB average %.1f (got %d)',
      [AWhat, AName, (AA + AB) / 2, AGot]), Abs(AGot - (AA + AB) / 2) <= 1);
  end;

begin
  m := ABmp.GetPixel(ABmp.Width div 2, ABmp.Height div 2);
  Channel('red', m.red, TyRedOf(AFrom), TyRedOf(ATo));
  Channel('green', m.green, TyGreenOf(AFrom), TyGreenOf(ATo));
  Channel('blue', m.blue, TyBlueOf(AFrom), TyBlueOf(ATo));
end;

{ Count the pixels that differ by more than ATol in any channel; the first one is named. }
function Mismatch(A, B: TBGRABitmap; ATol: Integer; out AFirst: string): Integer;
var
  x, y: Integer;
  pa, pb: TBGRAPixel;
begin
  Result := 0;
  AFirst := '';
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
    begin
      pa := A.GetPixel(x, y);
      pb := B.GetPixel(x, y);
      if (Abs(pa.red - pb.red) > ATol) or (Abs(pa.green - pb.green) > ATol) or
         (Abs(pa.blue - pb.blue) > ATol) or (Abs(pa.alpha - pb.alpha) > ATol) then
      begin
        if Result = 0 then
          AFirst := Format(' first at (%d,%d): %d,%d,%d,%d vs %d,%d,%d,%d',
            [x, y, pa.red, pa.green, pa.blue, pa.alpha, pb.red, pb.green, pb.blue, pb.alpha]);
        Inc(Result);
      end;
    end;
end;

const
  GradPairs: array[0..1, 0..1] of TTyColor = (
    (TTyColor($FF000000), TTyColor($FFFFFFFF)),     // black to white
    (TTyColor($FFFF8000), TTyColor($FF0040FF)));    // orange to blue: every channel moves

{ The same colours three ways: a plain pair; two stops at 0 and 1, as the style model writes
  them (the two-colour path); and three stops with the first one twice, which is the same ramp
  through the multi-gradient path. }
procedure SameRampThreeWays(AFrom, ATo: TTyColor; out APair, AStops, AMulti: TTyFill);
begin
  APair := Default(TTyFill);
  APair.Kind := tfkLinearGradient;
  APair.GradAngleDeg := 0;   // left to right
  APair.GradFrom := AFrom;
  APair.GradTo := ATo;
  AStops := APair;
  SetLength(AStops.GradStops, 2);
  AStops.GradStops[0].Color := AFrom; AStops.GradStops[0].Pos := 0;
  AStops.GradStops[1].Color := ATo;   AStops.GradStops[1].Pos := 1;
  AMulti := APair;
  SetLength(AMulti.GradStops, 3);
  AMulti.GradStops[0] := AStops.GradStops[0];
  AMulti.GradStops[1] := AStops.GradStops[0];
  AMulti.GradStops[2] := AStops.GradStops[1];
end;

procedure TGradientTest.TestTwoColoursBlendInPlainSRGBOnTheBackground;
var
  k, n: Integer;
  pair, stops, multi: TTyFill;
  a, b, c: TBGRABitmap;
  first, what: string;
begin
  for k := 0 to High(GradPairs) do
  begin
    what := Format('%.8x to %.8x', [GradPairs[k, 0], GradPairs[k, 1]]);
    SameRampThreeWays(GradPairs[k, 0], GradPairs[k, 1], pair, stops, multi);
    AssertFalse('fixture: two stops at 0 and 1 are the two-colour path', TyGradientNeedsStops(stops));
    AssertTrue('fixture: the repeated stop is the multi-stop path', TyGradientNeedsStops(multi));
    a := Background(pair, 1001, 3);
    b := Background(stops, 1001, 3);
    c := Background(multi, 1001, 3);
    try
      n := Mismatch(a, b, 0, first);
      AssertEquals(what + ': two colours and two stops at 0/1 paint the same pixels' + first, 0, n);
      { Not byte-identical: the two-colour scanner rounds, the multi-gradient truncates. }
      n := Mismatch(a, c, 1, first);
      AssertEquals(what + ': and the multi-stop path paints the same ramp' + first, 0, n);
      CheckPlainMidpoint(what + ', two colours', a, pair.GradFrom, pair.GradTo);
      CheckPlainMidpoint(what + ', multi-stop', c, pair.GradFrom, pair.GradTo);
    finally
      a.Free;
      b.Free;
      c.Free;
    end;
  end;
end;

procedure TGradientTest.TestTwoColoursBlendInPlainSRGBOnAPath;
var
  k, n: Integer;
  pair, stops, multi: TTyFill;
  a, b, c: TBGRABitmap;
  first, what: string;
begin
  for k := 0 to High(GradPairs) do
  begin
    what := Format('path %.8x to %.8x', [GradPairs[k, 0], GradPairs[k, 1]]);
    SameRampThreeWays(GradPairs[k, 0], GradPairs[k, 1], pair, stops, multi);
    a := PathFill(pair, 1001, 3);
    b := PathFill(stops, 1001, 3);
    c := PathFill(multi, 1001, 3);
    try
      n := Mismatch(a, b, 0, first);
      AssertEquals(what + ': two colours and two stops at 0/1 paint the same pixels' + first, 0, n);
      n := Mismatch(a, c, 1, first);
      AssertEquals(what + ': and three stops paint the same ramp' + first, 0, n);
      CheckPlainMidpoint(what, a, pair.GradFrom, pair.GradTo);
    finally
      a.Free;
      b.Free;
      c.Free;
    end;
  end;
end;

initialization
  RegisterTest(TGradientTest);
end.
