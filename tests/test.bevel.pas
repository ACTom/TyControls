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
