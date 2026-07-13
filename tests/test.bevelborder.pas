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
    function RenderStyleOf(const ACss: string): TTyRenderStyle;
    procedure RenderFrame(const AStyle: TTyStyleSet; out ATL, ABR: TBGRAPixel);
  published
    procedure TestParseOutsetLonghand;
    procedure TestParseInsetShorthand;
    procedure TestParseSolidStillSolid;
    procedure TestDrawEdgePrimitiveTwoTone;
    procedure TestDrawFrameOutsetRaised;
    procedure TestDrawFrameInsetSunken;
    // v3/D render-style family preset
    procedure TestParseRenderStyleBevel3D;
    procedure TestRenderStyleBevel3DAutoRaised;
    procedure TestRenderStyleInset3DAutoSunken;
    // v3/E: the shipped classic skin file parses and uses the render-style bevels
    procedure TestClassicSkinFileValid;
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

function TBevelBorderTest.RenderStyleOf(const ACss: string): TTyRenderStyle;
var m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TyButton { ' + ACss + ' }');
    Result := m.ResolveStyle('TyButton', '', []).RenderStyle;
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

procedure TBevelBorderTest.TestParseRenderStyleBevel3D;
begin
  AssertEquals('render-style: bevel3d -> trsBevel3D', Ord(trsBevel3D),
    Ord(RenderStyleOf('render-style: bevel3d;')));
  AssertEquals('render-style: flat -> trsFlat', Ord(trsFlat),
    Ord(RenderStyleOf('render-style: flat;')));
end;

procedure TBevelBorderTest.TestRenderStyleBevel3DAutoRaised;
var style: TTyStyleSet; tl, br: TBGRAPixel;
begin
  // render-style: bevel3d + a solid grey face and NO explicit border tokens must, on its own,
  // produce a RAISED bevel (outset auto-applied, edges derived from the face).
  style := EmptyStyleSet;
  style.Background.Kind := tfkSolid;
  style.Background.Color := TyRGB($80, $80, $80);
  Include(style.Present, tpBackground);
  style.RenderStyle := trsBevel3D;
  Include(style.Present, tpRenderStyle);
  RenderFrame(style, tl, br);
  AssertTrue('preset raised: TL lighter than face', tl.red > $80);
  AssertTrue('preset raised: BR darker than face', br.red < $80);
  AssertTrue('preset raised: TL lighter than BR', tl.red > br.red);
end;

procedure TBevelBorderTest.TestRenderStyleInset3DAutoSunken;
var style: TTyStyleSet; tl, br: TBGRAPixel;
begin
  style := EmptyStyleSet;
  style.Background.Kind := tfkSolid;
  style.Background.Color := TyRGB($80, $80, $80);
  Include(style.Present, tpBackground);
  style.RenderStyle := trsInset3D;
  Include(style.Present, tpRenderStyle);
  RenderFrame(style, tl, br);
  AssertTrue('preset sunken: TL darker than face', tl.red < $80);
  AssertTrue('preset sunken: BR lighter than face', br.red > $80);
end;

procedure TBevelBorderTest.TestClassicSkinFileValid;
var m: TTyStyleModel; s: TTyStyleSet; fn: string;
begin
  // The classic skin ships in themes/ (one level up from the test exe's tests/ dir).
  fn := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim + 'classic.tycss';
  AssertTrue('classic.tycss exists', FileExists(fn));
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(fn);   // raises on any syntax/value error
    s := m.ResolveStyle('TyButton', '', []);
    AssertEquals('classic TyButton uses render-style bevel3d', Ord(trsBevel3D), Ord(s.RenderStyle));
    s := m.ResolveStyle('TyEdit', '', []);
    AssertEquals('classic TyEdit uses render-style inset3d', Ord(trsInset3D), Ord(s.RenderStyle));
  finally
    m.Free;
  end;
end;

initialization
  RegisterTest(TBevelBorderTest);
end.
