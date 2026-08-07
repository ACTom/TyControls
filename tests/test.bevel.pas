unit test.bevel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Bevel;

type
  TTyBevelTest = class(TTestCase)
  published
    // Pure geometry (no window handle)
    procedure TestEdgesBox;
    procedure TestEdgesFrame;
    procedure TestEdgesSingleLines;
    procedure TestEdgesSpacerEmpty;
    // Pure colour math
    procedure TestLightenTowardWhite;
    procedure TestDarkenTowardBlack;
    procedure TestLightenDarkenPreserveAlpha;
    procedure TestLightenClampsAmount;
    procedure TestLumaMatchesRec601;
    procedure TestLightSurfaceRailsAreUnchanged;
    procedure TestDarkSurfaceSwapsTheFractions;
    procedure TestDarkSurfaceHighlightStopsGlowing;
    procedure TestRailsAlwaysStraddleTheBase;
    // Headless behaviour
    procedure TestTypeKey;
    procedure TestDefaultProps;
    procedure TestSpacerPaintsNothing;
    procedure TestBoxPaintsEdges;
    procedure TestRaisedLoweredSwapTopEdge;
    procedure TestTopLineOnlyPaintsTop;
  end;

implementation

type
  { Access subclass: expose the protected RenderTo so tests can drive the paint
    path with NO window handle, exactly like test.listbox's TListBoxAccess. }
  TBevelAccess = class(TTyBevel)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

function TBevelAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TBevelAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

{ Render a bevel of the given shape/style into a fresh W x H bitmap on a black
  ground, driven by a stylesheet that fixes the TyPanel border colour. Returns the
  re-read BGRA bitmap (caller frees). }
function RenderBevel(AShape: TTyBevelShape; AStyle: TTyBevelStyle;
  const ACss: string; W, H: Integer): TBGRABitmap;
var
  Ctl: TTyStyleController;
  F: TForm;
  B: TBevelAccess;
  Bmp: TBitmap;
begin
  Ctl := TTyStyleController.Create(nil);
  F := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(ACss);
    B := TBevelAccess.Create(F);
    B.Parent := F;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Shape := AShape;
    B.Style := AStyle;
    B.SetBounds(0, 0, W, H);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(W, H);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, W, H);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, W, H), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
    F.Free;
    Ctl.Free;
  end;
end;

{ ---- pure geometry ---- }

procedure TTyBevelTest.TestEdgesBox;
begin
  AssertTrue('box occupies all four edges',
    TyBevelEdges(tbsBox) = [tbeTop, tbeBottom, tbeLeft, tbeRight]);
end;

procedure TTyBevelTest.TestEdgesFrame;
begin
  AssertTrue('frame occupies all four edges',
    TyBevelEdges(tbsFrame) = [tbeTop, tbeBottom, tbeLeft, tbeRight]);
end;

procedure TTyBevelTest.TestEdgesSingleLines;
begin
  AssertTrue('top line',    TyBevelEdges(tbsTopLine)    = [tbeTop]);
  AssertTrue('bottom line', TyBevelEdges(tbsBottomLine) = [tbeBottom]);
  AssertTrue('left line',   TyBevelEdges(tbsLeftLine)   = [tbeLeft]);
  AssertTrue('right line',  TyBevelEdges(tbsRightLine)  = [tbeRight]);
end;

procedure TTyBevelTest.TestEdgesSpacerEmpty;
begin
  AssertTrue('spacer occupies no edge', TyBevelEdges(tbsSpacer) = []);
end;

{ ---- pure colour math ---- }

procedure TTyBevelTest.TestLightenTowardWhite;
var
  c: TTyColor;
begin
  // Mid grey (128) lightened 50% -> ~191; lightened 100% -> white.
  c := TyBevelLighten(TyRGB(128, 128, 128), 0.5);
  AssertTrue('lighten 50% raises the channel above the base',
    (TyRedOf(c) > 128) and (TyRedOf(c) < 255));
  c := TyBevelLighten(TyRGB(0, 0, 0), 1.0);
  AssertEquals('lighten 100% -> white R', 255, TyRedOf(c));
  AssertEquals('lighten 100% -> white G', 255, TyGreenOf(c));
  AssertEquals('lighten 100% -> white B', 255, TyBlueOf(c));
  c := TyBevelLighten(TyRGB(70, 90, 110), 0.0);
  AssertEquals('lighten 0% is identity R', 70, TyRedOf(c));
  AssertEquals('lighten 0% is identity B', 110, TyBlueOf(c));
end;

procedure TTyBevelTest.TestDarkenTowardBlack;
var
  c: TTyColor;
begin
  c := TyBevelDarken(TyRGB(200, 200, 200), 0.5);
  AssertTrue('darken 50% lowers the channel below the base',
    (TyRedOf(c) < 200) and (TyRedOf(c) > 0));
  c := TyBevelDarken(TyRGB(255, 255, 255), 1.0);
  AssertEquals('darken 100% -> black R', 0, TyRedOf(c));
  AssertEquals('darken 100% -> black G', 0, TyGreenOf(c));
  AssertEquals('darken 100% -> black B', 0, TyBlueOf(c));
end;

procedure TTyBevelTest.TestLightenDarkenPreserveAlpha;
var
  c: TTyColor;
begin
  c := TyBevelLighten(TyRGBA(100, 100, 100, 128), 0.5);
  AssertEquals('lighten preserves alpha', 128, TyAlphaOf(c));
  c := TyBevelDarken(TyRGBA(100, 100, 100, 64), 0.5);
  AssertEquals('darken preserves alpha', 64, TyAlphaOf(c));
end;

procedure TTyBevelTest.TestLightenClampsAmount;
var
  c: TTyColor;
begin
  // Out-of-range amounts clamp to [0,1] (no overflow / negative channel).
  c := TyBevelLighten(TyRGB(10, 20, 30), 5.0);
  AssertEquals('over-range lighten clamps to white', 255, TyRedOf(c));
  c := TyBevelDarken(TyRGB(10, 20, 30), 5.0);
  AssertEquals('over-range darken clamps to black', 0, TyRedOf(c));
  c := TyBevelLighten(TyRGB(10, 20, 30), -3.0);
  AssertEquals('under-range lighten is identity', 10, TyRedOf(c));
end;

{ ---- rails: the mode-aware pair ---- }

const
  { The shipped surface seeds, so the numbers below are the REAL ones a user sees. }
  CDarkSurface  = 30;   { #1E1E1E — dark.tycss --surface, luma 30 }
  CLightSurface = 255;  { #FFFFFF — light.tycss --surface }

procedure TTyBevelTest.TestLumaMatchesRec601;
begin
  AssertEquals('white', 255.0, TyBevelLuma(TyRGB(255, 255, 255)), 0.01);
  AssertEquals('black', 0.0,   TyBevelLuma(TyRGB(0, 0, 0)), 0.01);
  { Rec.601 is NOT a plain mean — green dominates. A helper that averaged the channels
    would return 85 for pure green; the whole rail choice would then class surfaces wrong. }
  AssertEquals('pure green is Rec.601-weighted, not averaged',
    149.685, TyBevelLuma(TyRGB(0, 255, 0)), 0.01);
  { dark.tycss --surface #1E1E1E and light.tycss --surface #FFFFFF land either side of the
    128 boundary the rail choice uses — i.e. the shipped themes are not near the cut. }
  AssertTrue('dark surface classes dark',  TyBevelLuma(TyRGB($1E, $1E, $1E)) < 128);
  AssertTrue('light surface classes light', TyBevelLuma(TyRGB(255, 255, 255)) >= 128);
end;

{ **The no-regression proof.** On a light surface the rails must be EXACTLY the two calls
  the pre-fix code made — same function, same fractions, same direction. Asserted against
  TyBevelLighten/TyBevelDarken themselves rather than against baked hex, so it stays a
  statement about the maths and not about one theme's border colour. }
procedure TTyBevelTest.TestLightSurfaceRailsAreUnchanged;
var
  base, hi, lo: TTyColor;
begin
  base := TyRGB($D1, $D5, $DB);           { light.tycss --border }
  TyBevelRails(base, TyRGB(CLightSurface, CLightSurface, CLightSurface), hi, lo);
  AssertEquals('light-surface highlight = the old lighten(base, 0.55)',
    Integer(TyBevelLighten(base, 0.55)), Integer(hi));
  AssertEquals('light-surface shadow = the old darken(base, 0.45)',
    Integer(TyBevelDarken(base, 0.45)), Integer(lo));
end;

{ On a DARK surface the two fractions swap sides. Stated against the primitives for the
  same reason as above. }
procedure TTyBevelTest.TestDarkSurfaceSwapsTheFractions;
var
  base, hi, lo: TTyColor;
begin
  base := TyRGB($3F, $3F, $46);           { dark.tycss --border }
  TyBevelRails(base, TyRGB(CDarkSurface, CDarkSurface, CDarkSurface), hi, lo);
  AssertEquals('dark-surface highlight takes the SMALL fraction',
    Integer(TyBevelLighten(base, 0.45)), Integer(hi));
  AssertEquals('dark-surface shadow takes the LARGE fraction',
    Integer(TyBevelDarken(base, 0.55)), Integer(lo));
end;

{ The user-visible symptom, in numbers: on the shipped dark theme the highlight rail used
  to be pushed 55% toward white and came out around luma 169 on a luma-30 window — the
  bright rail. It must now be strictly darker than that, while staying visible (still
  lighter than the surface it sits on, or it stops being a highlight). }
procedure TTyBevelTest.TestDarkSurfaceHighlightStopsGlowing;
var
  base, surf, hi, lo: TTyColor;
  oldHi: TTyColor;
begin
  base := TyRGB($3F, $3F, $46);
  surf := TyRGB(CDarkSurface, CDarkSurface, CDarkSurface);
  oldHi := TyBevelLighten(base, 0.55);    { what the mode-blind code produced }
  TyBevelRails(base, surf, hi, lo);
  AssertTrue(Format('dark highlight (luma %.0f) must be darker than the old mode-blind '
    + 'rail (luma %.0f)', [TyBevelLuma(hi), TyBevelLuma(oldHi)]),
    TyBevelLuma(hi) < TyBevelLuma(oldHi));
  AssertTrue('…but still lighter than the dark surface, or it is not a highlight',
    TyBevelLuma(hi) > TyBevelLuma(surf));
  AssertTrue('…and the shadow still reads against the surface too',
    TyBevelLuma(lo) < TyBevelLuma(hi));
end;

{ The invariant that makes raised/lowered mean anything, in BOTH modes: the lit rail is
  lighter than the base and the shaded rail darker. A "fix" that merely damped the
  highlight until it crossed the base would pass the symptom test above and destroy the
  control; this is the guard that stops that. }
procedure TTyBevelTest.TestRailsAlwaysStraddleTheBase;
var
  hi, lo, base: TTyColor;
  i: Integer;
const
  { A spread of bases across the whole axis, checked on both a dark and a light surface. }
  CBases: array[0..4] of Byte = (10, 63, 128, 200, 245);
begin
  for i := 0 to High(CBases) do
  begin
    base := TyRGB(CBases[i], CBases[i], CBases[i]);

    TyBevelRails(base, TyRGB(CDarkSurface, CDarkSurface, CDarkSurface), hi, lo);
    AssertTrue(Format('dark surface, base %d: highlight must be lighter than base',
      [CBases[i]]), TyBevelLuma(hi) >= TyBevelLuma(base));
    AssertTrue(Format('dark surface, base %d: shadow must be darker than base',
      [CBases[i]]), TyBevelLuma(lo) <= TyBevelLuma(base));

    TyBevelRails(base, TyRGB(CLightSurface, CLightSurface, CLightSurface), hi, lo);
    AssertTrue(Format('light surface, base %d: highlight must be lighter than base',
      [CBases[i]]), TyBevelLuma(hi) >= TyBevelLuma(base));
    AssertTrue(Format('light surface, base %d: shadow must be darker than base',
      [CBases[i]]), TyBevelLuma(lo) <= TyBevelLuma(base));
  end;
end;

{ ---- headless behaviour ---- }

procedure TTyBevelTest.TestTypeKey;
var
  F: TForm;
  B: TBevelAccess;
begin
  F := TForm.CreateNew(nil);
  try
    B := TBevelAccess.Create(F);
    B.Parent := F;
    AssertEquals('owns TyBevel', 'TyBevel', B.StyleTypeKey);
  finally
    F.Free;
  end;
end;

procedure TTyBevelTest.TestDefaultProps;
var
  F: TForm;
  B: TTyBevel;
begin
  F := TForm.CreateNew(nil);
  try
    B := TTyBevel.Create(F);
    B.Parent := F;
    AssertTrue('default shape is box', B.Shape = tbsBox);
    AssertTrue('default style is lowered', B.Style = tbsLowered);
    AssertEquals('default width', 50, B.Width);
    AssertEquals('default height', 50, B.Height);
  finally
    F.Free;
  end;
end;

const
  // A theme that pins the TyPanel border colour to a bright known value so the
  // derived highlight/shadow lines are distinguishable from the black ground.
  CBorderCss = 'TyPanel { background: #202020; border-color: #808080; ' +
               'border-width: 1px; border-radius: 0px; }';

procedure TTyBevelTest.TestSpacerPaintsNothing;
var
  R: TBGRABitmap;
  x, y: Integer;
  anyNonBlack: Boolean;
begin
  // A spacer must be fully invisible: every pixel stays the black ground.
  R := RenderBevel(tbsSpacer, tbsLowered, CBorderCss, 40, 40);
  try
    anyNonBlack := False;
    for y := 0 to R.Height - 1 do
      for x := 0 to R.Width - 1 do
        if (R.GetPixel(x, y).red > 20) or (R.GetPixel(x, y).green > 20)
           or (R.GetPixel(x, y).blue > 20) then
          anyNonBlack := True;
    AssertFalse('spacer leaves the whole area black', anyNonBlack);
  finally
    R.Free;
  end;
end;

procedure TTyBevelTest.TestBoxPaintsEdges;
var
  R: TBGRABitmap;
  pTop, pBot, pLeft, pRight, pCenter: TBGRAPixel;

  function IsLit(const px: TBGRAPixel): Boolean;
  begin
    Result := (px.red > 20) or (px.green > 20) or (px.blue > 20);
  end;

begin
  // A box outlines all four edges but leaves the interior the black ground (a
  // bevel has NO fill of its own).
  R := RenderBevel(tbsBox, tbsLowered, CBorderCss, 40, 40);
  try
    pTop    := R.GetPixel(20, 0);
    pBot    := R.GetPixel(20, 39);
    pLeft   := R.GetPixel(0, 20);
    pRight  := R.GetPixel(39, 20);
    pCenter := R.GetPixel(20, 20);
    AssertTrue('top edge is drawn',    IsLit(pTop));
    AssertTrue('bottom edge is drawn', IsLit(pBot));
    AssertTrue('left edge is drawn',   IsLit(pLeft));
    AssertTrue('right edge is drawn',  IsLit(pRight));
    AssertFalse('interior is not filled', IsLit(pCenter));
  finally
    R.Free;
  end;
end;

procedure TTyBevelTest.TestRaisedLoweredSwapTopEdge;
var
  RRaised, RLowered: TBGRABitmap;
  topRaised, topLowered: TBGRAPixel;
begin
  // The top edge carries the HIGHLIGHT when raised and the SHADOW when lowered,
  // so raised's top edge must be brighter than lowered's top edge (same base).
  RRaised  := RenderBevel(tbsBox, tbsRaised,  CBorderCss, 40, 40);
  RLowered := RenderBevel(tbsBox, tbsLowered, CBorderCss, 40, 40);
  try
    topRaised  := RRaised.GetPixel(20, 0);
    topLowered := RLowered.GetPixel(20, 0);
    AssertTrue(Format('raised top edge brighter than lowered ' +
      '(raised R=%d vs lowered R=%d)', [topRaised.red, topLowered.red]),
      topRaised.red > topLowered.red);
  finally
    RRaised.Free;
    RLowered.Free;
  end;
end;

procedure TTyBevelTest.TestTopLineOnlyPaintsTop;
var
  R: TBGRABitmap;

  function IsLit(const px: TBGRAPixel): Boolean;
  begin
    Result := (px.red > 20) or (px.green > 20) or (px.blue > 20);
  end;

begin
  // tbsTopLine draws only the top edge; the bottom edge stays black.
  R := RenderBevel(tbsTopLine, tbsLowered, CBorderCss, 40, 40);
  try
    AssertTrue('top line is drawn',        IsLit(R.GetPixel(20, 0)));
    AssertFalse('bottom edge stays black', IsLit(R.GetPixel(20, 39)));
    AssertFalse('left edge stays black',   IsLit(R.GetPixel(0, 20)));
  finally
    R.Free;
  end;
end;

initialization
  RegisterTest(TTyBevelTest);
end.
