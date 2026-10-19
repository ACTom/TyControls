unit test.terminal.view.devicescale;
{$mode objfpc}{$H+}

{ #83, plan B Task 9: the terminal at the device scale.

  The view keeps two sets of metrics. The layout one -- the cell in the window's units -- is
  what the grid, the hit test, the selection and the cursor are laid out by, as before. The
  raster one is what the surface is drawn with: the cell exactly S times the layout cell, the
  glyph box inside it measured with the font at the raster PPI. Exactly S times, not measured
  on its own: a cell measured at twice the PPI is often a pixel off twice the layout cell, and
  the rows would drift from where the hit test puts them. }

interface

uses
  Classes, SysUtils, Types, Graphics, Controls, Forms, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Painter, tyControls.Terminal.Render, tyControls.Terminal,
  test.terminal.view, test.devicescale.support;

type
  TTerminalViewDeviceScaleTest = class(TDeviceScaleCase)
  private
    FTheme: TTyStyleController;
    FSavedFallback: string;
    function BuildTerminal(AParent: TWinControl; APPI: Integer): TControl;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRasterCellIsExactlySTimesTheLayoutCell;
    procedure TestTerminalAtTheDeviceScale;
    procedure TestScrollAtTheDeviceScaleEqualsARepaint;
    procedure TestTerminalForgetsTheScale;
    { the composition (macOS IME) is drawn on the surface too: its underline at S = 2 is the
      S = 1 one doubled -- four times the pixels, from twice the row }
    procedure TestPreeditAtTheDeviceScale;
    { Review: on a Retina window's canvas (device px) the S-times surface is stretched into the
      device-px rect; the picture must be the S = 1 one. }
    procedure TestTerminalOnALayoutCanvas;
    { Review: the surface only grows, so a drag resize does not make it again every frame;
      but back on a one-times screen it was left S^2 the size it needs. A change of scale
      makes it again; a resize at one scale still keeps it. }
    procedure TestTheSurfaceShrinksBackWithTheScale;
  end;

implementation

const
  { colours, bold, underline, box drawing and a shade, the cursor hidden (it blinks) }
  CScreen =
    #27'[?25l' +
    #27'[1;31mBold red'#27'[0m plain '#27'[4;32munderlined green'#27'[0m'#13#10 +
    #27'[44;37m on blue '#27'[0m '#27'[7m inverse '#27'[0m'#13#10 +
    #$E2#$94#$8C#$E2#$94#$80#$E2#$94#$80#$E2#$94#$90' '#$E2#$96#$88#$E2#$96#$92#$E2#$96#$91#13#10 +
    #$E2#$94#$82'ab'#$E2#$94#$82' wxyz 0123456789'#13#10 +
    #$E2#$94#$94#$E2#$94#$80#$E2#$94#$80#$E2#$94#$98' '#27'[38;5;208morange'#27'[0m';

{ The view painted at the device scale AScale, as on a raster canvas: a bitmap AScale times its
  size, starting magenta. }
function SnapAt(F: TTyTermViewFixture; AScale: Integer): TBGRABitmap;
var
  bmp: TBitmap;
  w, h: Integer;
begin
  w := F.View.ClientWidth;
  h := F.View.ClientHeight;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(w * AScale, h * AScale);
    bmp.Canvas.Brush.Color := RGBToColor(255, 0, 255);
    bmp.Canvas.FillRect(0, 0, bmp.Width, bmp.Height);
    if AScale > 1 then TyForceDeviceScaleForTest(AScale, True, False);
    try
      F.View.Render(bmp.Canvas, Rect(0, 0, w, h), F.View.Font.PixelsPerInch);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

function DiffCount(A, B: TBGRABitmap; out AFirst: string): Integer;
var
  x, y: Integer;
  pa, pb: TBGRAPixel;
begin
  AFirst := '';
  if (A.Width <> B.Width) or (A.Height <> B.Height) then
  begin
    AFirst := Format('sizes %dx%d and %dx%d', [A.Width, A.Height, B.Width, B.Height]);
    Exit(A.Width * A.Height);
  end;
  Result := 0;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
    begin
      pa := A.GetPixel(x, y);
      pb := B.GetPixel(x, y);
      if (pa.red <> pb.red) or (pa.green <> pb.green) or (pa.blue <> pb.blue) then
      begin
        if Result = 0 then
          AFirst := Format('first at (%d,%d): (%d,%d,%d) against (%d,%d,%d)',
            [x, y, pa.red, pa.green, pa.blue, pb.red, pb.green, pb.blue]);
        Inc(Result);
      end;
    end;
end;

procedure TTerminalViewDeviceScaleTest.SetUp;
begin
  inherited SetUp;
  FSavedFallback := TyFallbackFontName;
  TyFallbackFontName := 'Segoe UI';
end;

procedure TTerminalViewDeviceScaleTest.TearDown;
begin
  FreeAndNil(FTheme);
  TyFallbackFontName := FSavedFallback;
  inherited TearDown;
end;

function TTerminalViewDeviceScaleTest.BuildTerminal(AParent: TWinControl; APPI: Integer): TControl;
var
  v: TTyTerminalViewProbe;
begin
  if FTheme = nil then
  begin
    FTheme := TTyStyleController.Create(nil);
    FTheme.Mode := 'light';
    FTheme.ThemeName := 'default';
    { the fixture's colours, and a frame: a border drawn at the wrong scale shows }
    FTheme.StyleOverride := TyTermFixtureCss + #10 +
      'TyTerminal { border-width: 2px; border-color: #e0a000; border-radius: 6px; padding: 4px; }';
  end;
  v := TTyTerminalViewProbe.Create(AParent);
  v.RasterBudgetMs := 0;   { the whole frame: no glyph left for the next one }
  v.Controller := FTheme;
  v.Parent := AParent;
  v.Font.PixelsPerInch := APPI;
  v.WriteSync(CScreen);
  Result := v;
end;

procedure TTerminalViewDeviceScaleTest.TestRasterCellIsExactlySTimesTheLayoutCell;
var
  F: TTyTermViewFixture;
  b: TBGRABitmap;
  size: Integer;
  lay, ras: TTyTermCellMetrics;
begin
  for size := 8 to 16 do
  begin
    F := TTyTermViewFixture.Create;
    try
      F.View.Font.Size := size;
      F.View.RasterBudgetMs := 0;
      F.SizeTo(20, 6);
      F.View.WriteSync('abc');
      b := SnapAt(F, 2);
      b.Free;
      lay := F.View.CellMetrics;
      ras := F.View.RasterMetrics;
      AssertEquals(Format('%dpt: the raster cell is twice the layout cell across', [size]),
        2 * lay.CellW, ras.CellW);
      AssertEquals(Format('%dpt: and down', [size]), 2 * lay.CellH, ras.CellH);
      { the glyph box is the font's at the raster PPI and may be a pixel wider than the cell
        (hinting: 11pt Consolas is 17 px at 192 PPI, 8 at 96) -- the rasterizer squeezes a
        glyph wider than its cells; the baseline must still fall inside the cell }
      AssertTrue(Format('%dpt: the baseline is inside the raster cell (baseline %d, cell %dx%d)',
        [size, ras.Baseline, ras.CellW, ras.CellH]), (ras.Baseline > 0) and (ras.Baseline < ras.CellH));
    finally
      F.Free;
    end;
  end;
end;

procedure TTerminalViewDeviceScaleTest.TestTerminalAtTheDeviceScale;
begin
  CheckScale('TTyTerminalView-content', @BuildTerminal, 360, 120);
end;

procedure TTerminalViewDeviceScaleTest.TestScrollAtTheDeviceScaleEqualsARepaint;
var
  F: TTyTermViewFixture;
  moved, fresh: TBGRABitmap;
  i, n: Integer;
  first: string;
begin
  F := TTyTermViewFixture.Create;
  moved := nil;
  fresh := nil;
  try
    F.View.RasterBudgetMs := 0;
    F.SizeTo(24, 8);
    F.View.WriteSync(#27'[?25l');
    for i := 0 to 7 do
      F.View.WriteSync(#13#10 + #27'[3' + IntToStr(1 + i mod 6) + 'mline ' + IntToStr(i)
        + #27'[0m '#$E2#$94#$80#$E2#$94#$90);   { no shade: a shade keeps a row from moving by a cell that is not its period }
    SnapAt(F, 2).Free;
    F.View.WriteSync(#13#10'one more line');
    moved := SnapAt(F, 2);
    AssertTrue(Format('precondition: the scroll moved rows (%d moved)', [F.View.MovedLast]),
      F.View.MovedLast >= F.View.Rows - 3);
    F.View.Forget;
    fresh := SnapAt(F, 2);
    AssertEquals('precondition: the second frame painted every row', F.View.Rows, F.View.PaintedLast);
    n := DiffCount(moved, fresh, first);
    AssertEquals('S = 2: a scrolled frame is the frame painted afresh (' + first + ')', 0, n);
  finally
    fresh.Free;
    moved.Free;
    F.Free;
  end;
end;

procedure TTerminalViewDeviceScaleTest.TestTerminalForgetsTheScale;
var
  F1, F2: TTyTermViewFixture;
  after, plain: TBGRABitmap;
  n: Integer;
  first: string;
begin
  F1 := TTyTermViewFixture.Create;
  F2 := TTyTermViewFixture.Create;
  after := nil;
  plain := nil;
  try
    F1.View.RasterBudgetMs := 0;
    F2.View.RasterBudgetMs := 0;
    F1.SizeTo(30, 6);
    F2.SizeTo(30, 6);
    F1.View.WriteSync(CScreen);
    F2.View.WriteSync(CScreen);
    SnapAt(F1, 2).Free;
    after := SnapAt(F1, 1);
    plain := SnapAt(F2, 1);
    n := DiffCount(after, plain, first);
    AssertEquals('S = 1 after S = 2 is S = 1 from the start (' + first + ')', 0, n);
  finally
    plain.Free;
    after.Free;
    F2.Free;
    F1.Free;
  end;
end;

procedure TTerminalViewDeviceScaleTest.TestPreeditAtTheDeviceScale;
var
  F: TTyTermViewFixture;
  b: TBGRABitmap;
  mark: Cardinal;
  n1, n2, top1, top2, left1, left2: Integer;

  procedure Marks(B: TBGRABitmap; out ACount, ATop, ALeft: Integer);
  var
    x, y: Integer;
    p: TBGRAPixel;
  begin
    ACount := 0;
    ATop := -1;
    ALeft := MaxInt;
    for y := 0 to B.Height - 1 do
      for x := 0 to B.Width - 1 do
      begin
        p := B.GetPixel(x, y);
        if ((Cardinal(p.red) shl 16) or (Cardinal(p.green) shl 8) or p.blue) = mark then
        begin
          Inc(ACount);
          if ATop < 0 then ATop := y;
          if x < ALeft then ALeft := x;
        end;
      end;
  end;

begin
  F := TTyTermViewFixture.Create;
  try
    F.View.RasterBudgetMs := 0;
    F.SizeTo(20, 4);
    { the cursor on the second row, third column: the composition's place is a row and two
      cells in, in raster cells at S = 2 }
    F.View.WriteSync(#27'[?25lab'#13#10'cd');
    mark := F.Ctl.Model.ResolveStyle('TyTerminalPreedit', '', []).BorderColor and $FFFFFF;
    F.View.ImeBegin;
    F.View.ImeReplaceText(0, 0, 'zh');
    b := SnapAt(F, 1);
    try
      Marks(b, n1, top1, left1);
    finally
      b.Free;
    end;
    b := SnapAt(F, 2);
    try
      Marks(b, n2, top2, left2);
    finally
      b.Free;
    end;
    AssertTrue('precondition: the composition is underlined at S = 1', n1 > 0);
    AssertEquals('S = 2: the underline is four times the pixels', 4 * n1, n2);
    AssertEquals('S = 2: from twice the row', 2 * top1, top2);
    AssertEquals('S = 2: from twice the column', 2 * left1, left2);
    F.View.ImeEnd;
  finally
    F.Free;
  end;
end;

procedure TTerminalViewDeviceScaleTest.TestTerminalOnALayoutCanvas;
var
  F1, F2: TTyTermViewFixture;
  bmp: TBitmap;
  onLayout, plain: TBGRABitmap;
  ink, blocks: Integer;
begin
  F1 := TTyTermViewFixture.Create;
  F2 := TTyTermViewFixture.Create;
  bmp := TBitmap.Create;
  onLayout := nil;
  plain := nil;
  try
    F1.View.RasterBudgetMs := 0;
    F2.View.RasterBudgetMs := 0;
    F1.SizeTo(30, 6);
    F2.SizeTo(30, 6);
    F1.View.WriteSync(CScreen);
    F2.View.WriteSync(CScreen);
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(F1.View.ClientWidth, F1.View.ClientHeight);
    bmp.Canvas.Brush.Color := RGBToColor(255, 0, 255);
    bmp.Canvas.FillRect(0, 0, bmp.Width, bmp.Height);
    TyForceDeviceScaleForTest(2, False, False);
    try
      F1.View.Render(bmp.Canvas, Rect(0, 0, F1.View.ClientWidth, F1.View.ClientHeight),
        F1.View.Font.PixelsPerInch);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    onLayout := TBGRABitmap.Create(bmp);
    plain := SnapAt(F2, 1);
    ink := TyInkMismatch(onLayout, plain);
    blocks := TyBlockMismatch(onLayout, plain);
    AssertTrue(Format('a Retina window''s canvas shows the S = 1 picture (score %d > %d: ink %d, blocks %d)',
      [ink + blocks, CMaxMismatch, ink, blocks]), ink + blocks <= CMaxMismatch);
  finally
    plain.Free;
    onLayout.Free;
    bmp.Free;
    F2.Free;
    F1.Free;
  end;
end;

procedure TTerminalViewDeviceScaleTest.TestTheSurfaceShrinksBackWithTheScale;
var
  F: TTyTermViewFixture;
  w1, h1: Integer;
begin
  F := TTyTermViewFixture.Create;
  try
    F.View.RasterBudgetMs := 0;
    F.SizeTo(30, 6);
    F.View.WriteSync(CScreen);
    SnapAt(F, 1).Free;
    w1 := F.View.Surface.Width;
    h1 := F.View.Surface.Height;
    SnapAt(F, 2).Free;
    AssertTrue(Format('precondition: at S = 2 the surface is twice as wide (%d against %d)',
      [F.View.Surface.Width, w1]), F.View.Surface.Width >= 2 * F.View.ClientWidth);
    SnapAt(F, 1).Free;
    AssertEquals('back at S = 1: as wide as a surface that was never at S = 2', w1,
      F.View.Surface.Width);
    AssertEquals('and as high', h1, F.View.Surface.Height);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TTerminalViewDeviceScaleTest);

end.
