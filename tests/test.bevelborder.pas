unit test.bevelborder;
{ Theme-system v3 · Phase B2: two-tone 3D bevel border (border-style: outset | inset).
  Parse -> BorderStyle enum; the DrawEdge painter primitive draws a light top/left + dark
  bottom/right edge (swapped for inset); and DrawFrame derives the edge colours from
  border-color (lighten TL / darken BR) and renders a raised/sunken bevel end-to-end. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, BGRABitmap, BGRABitmapTypes,
  fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.Painter, tyControls.Base;
type
  TBevelProbe = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  public
    procedure RunDrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
  end;

  TBevelBorderTest = class(TTestCase)
  private
    function BorderStyleOf(const ACss: string): TTyBorderStyle;
    procedure RenderFrame(const AStyle: TTyStyleSet; out ATL, ABR: TBGRAPixel);
  published
    procedure TestParseOutsetLonghand;
    procedure TestParseInsetShorthand;
    procedure TestParseSolidStillSolid;
    procedure TestDrawEdgePrimitiveTwoTone;
    procedure TestDrawFrameOutsetRaised;
    procedure TestDrawFrameInsetSunken;
  end;

implementation

function TBevelProbe.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';
end;

procedure TBevelProbe.RunDrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
begin
  DrawFrame(APainter, ARect, AStyle);
end;

function TBevelBorderTest.BorderStyleOf(const ACss: string): TTyBorderStyle;
var m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TyButton { ' + ACss + ' }');
    Result := m.ResolveStyle('TyButton', '', []).BorderStyle;
  finally
    m.Free;
  end;
end;

procedure TBevelBorderTest.RenderFrame(const AStyle: TTyStyleSet; out ATL, ABR: TBGRAPixel);
var
  probe: TBevelProbe;
  painter: TTyPainter;
  bmp: TBitmap;
  r: TRect;
  reread: TBGRABitmap;
begin
  bmp := TBitmap.Create;
  probe := TBevelProbe.Create(nil);
  painter := TTyPainter.Create;
  try
    bmp.SetSize(40, 40);
    r := Rect(0, 0, 40, 40);
    painter.BeginPaint(bmp.Canvas, r, 96);
    probe.RunDrawFrame(painter, r, AStyle);
    painter.EndPaint;
    reread := TBGRABitmap.Create(bmp);
    try
      ATL := reread.GetPixel(1, 1);
      ABR := reread.GetPixel(38, 38);
    finally
      reread.Free;
    end;
  finally
    painter.Free;
    probe.Free;
    bmp.Free;
  end;
end;

procedure TBevelBorderTest.TestParseOutsetLonghand;
begin
  AssertEquals('border-style: outset -> tbsOutset', Ord(tbsOutset),
    Ord(BorderStyleOf('border-width: 2px; border-style: outset; border-color: #808080;')));
end;

procedure TBevelBorderTest.TestParseInsetShorthand;
begin
  AssertEquals('border: 2px inset -> tbsInset', Ord(tbsInset),
    Ord(BorderStyleOf('border: 2px inset #808080;')));
end;

procedure TBevelBorderTest.TestParseSolidStillSolid;
begin
  AssertEquals('border: 1px solid stays tbsSolid', Ord(tbsSolid),
    Ord(BorderStyleOf('border: 1px solid #808080;')));
end;

procedure TBevelBorderTest.TestDrawEdgePrimitiveTwoTone;
var
  bmp: TBitmap;
  p: TTyPainter;
  reread: TBGRABitmap;
  tl, br: TBGRAPixel;
begin
  bmp := TBitmap.Create;
  p := TTyPainter.Create;
  try
    bmp.SetSize(30, 30);
    p.BeginPaint(bmp.Canvas, Rect(0, 0, 30, 30), 96);
    p.DrawEdge(Rect(0, 0, 30, 30), 4, TyRGB(255, 255, 255), TyRGB(0, 0, 0));  // TL white, BR black
    p.EndPaint;
    reread := TBGRABitmap.Create(bmp);
    try
      tl := reread.GetPixel(1, 1);
      br := reread.GetPixel(28, 28);
      AssertTrue('TL edge is light', tl.red > 200);
      AssertTrue('BR edge is dark', br.red < 55);
    finally
      reread.Free;
    end;
  finally
    p.Free;
    bmp.Free;
  end;
end;

procedure TBevelBorderTest.TestDrawFrameOutsetRaised;
var style: TTyStyleSet; tl, br: TBGRAPixel;
begin
  style := EmptyStyleSet;
  style.Background.Kind := tfkSolid;
  style.Background.Color := TyRGB($80, $80, $80);
  Include(style.Present, tpBackground);
  style.BorderColor := TyRGB($80, $80, $80);
  style.BorderWidth := 4;
  style.BorderStyle := tbsOutset;
  Include(style.Present, tpBorderColor);
  Include(style.Present, tpBorderWidth);
  Include(style.Present, tpBorderStyle);
  RenderFrame(style, tl, br);
  // Raised: top-left edge lightened above the base gray, bottom-right darkened below it.
  AssertTrue('raised TL lighter than base', tl.red > $80);
  AssertTrue('raised BR darker than base', br.red < $80);
  AssertTrue('raised TL lighter than BR', tl.red > br.red);
end;

procedure TBevelBorderTest.TestDrawFrameInsetSunken;
var style: TTyStyleSet; tl, br: TBGRAPixel;
begin
  style := EmptyStyleSet;
  style.Background.Kind := tfkSolid;
  style.Background.Color := TyRGB($80, $80, $80);
  Include(style.Present, tpBackground);
  style.BorderColor := TyRGB($80, $80, $80);
  style.BorderWidth := 4;
  style.BorderStyle := tbsInset;
  Include(style.Present, tpBorderColor);
  Include(style.Present, tpBorderWidth);
  Include(style.Present, tpBorderStyle);
  RenderFrame(style, tl, br);
  // Sunken: the light/dark sides are swapped vs outset.
  AssertTrue('sunken TL darker than base', tl.red < $80);
  AssertTrue('sunken BR lighter than base', br.red > $80);
  AssertTrue('sunken BR lighter than TL', br.red > tl.red);
end;

initialization
  RegisterTest(TBevelBorderTest);
end.
