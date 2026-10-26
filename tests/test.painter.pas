unit test.painter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Graphics, LCLType, LCLIntf, LazUTF8, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.CanvasText, tyControls.Grid,
  test.designregistry;

type
  TPainterTest = class(TTestCase)
  private
    FHost: TBitmap;
    FPainter: TTyPainter;
    function MakePainter(AWidth, AHeight, APPI: Integer): TRect;
    procedure FreePainter;
    function PixelAt(X, Y: Integer): TBGRAPixel;
    function WriteTempNineSlice: string;
    { Vertical extent of the ink currently on the painter's bitmap: the first and last row
      carrying any glyph pixel, and how many rows do. -1/-1/0 when nothing was drawn.
      Rows rather than a centroid because what these tests are about is how FAR DOWN the
      text reaches — the bug being guarded is a line that never gets drawn at all. }
    procedure InkRows(out ATop, ABottom, ARows: Integer);
  protected
    procedure TearDown; override;
  published
    procedure TestColorToBGRAChannels;
    procedure TestColorToBGRATransparent;
    procedure TestSolidFillCenter;
    procedure TestSolidFillCornerTransparent;
    procedure TestLinearGradientVertical;
    procedure TestBorderPixelColor;
    procedure TestDropShadowAlpha;
    procedure TestDrawTextRastersPixels;
    procedure TestTextIsInkedAsWindowsInksIt;
    procedure TestTextOnAnOpaqueSurfaceIsWhatWindowsDrawsThere;
    procedure TestTheClearTypeAnswerIsKeptASecond;
    procedure TestTheCanvasRendererDrawsInTheInksPolarity;
    procedure TestMacTextGoesThroughTheCanvasRenderer;
    procedure TestDrawnTextEndsWhereItWasMeasured;
    procedure TestDrawGlyphAllKinds;
    procedure TestChevronLeftIsTheApexMirrorOfChevronRight;
    procedure TestNineSliceCenterRegion;
    procedure TestEraseRectMakesTransparent;
    procedure TestFillCornerGapsPreservesAlpha;
    procedure TestPerCornerTopRoundBottomSquare;
    procedure TestFallbackFontNameApplied;
    procedure TestMeasureTextAndUnscale;
    procedure TestZeroFontSizeFallsBack;
    procedure TestClampRadiusPx;
    procedure TestLargeRadiusRendersPillNotLens;
    procedure TestEllipsisCutsWholeCharactersNotBytes;
    procedure TestSplitTextLinesHonoursAuthoredBreaks;
    procedure TestMultiLineDrawsTheSecondLine;
    procedure TestMultiLineFlagLeavesASingleLineByteIdentical;
    procedure TestLineHeightTokenSetsTheDrawnLineBox;
    procedure TestMeasureTextBlockCountsAuthoredLines;
    procedure TestMeasureTextBlockLineHeightIsDerivedNotFloored;
    procedure TestMeasureTextBlockWrapsToAWidth;
    procedure TestTheGdiRendererKeepsOneBitmap;
    procedure TestTheKeptMeasuringDcAnswersAsBgraDoes;
    procedure TestATurnedRunOnTheKeptDibIsBgrasOwn;
    procedure TestAKeptRunPaintsAsAFreshOne;
    procedure TestBgrasOwnPathsTouchNoKeptSurface;
    procedure TestATurnedRunOnAHalfPixelIsBgrasOwn;
    procedure TestAPrefixedOrRightToLeftRunIsMeasuredForItself;
    procedure TestTheKeptSurfacesAnswerAsBgraAtAnotherScreenPpi;
    procedure TestKeptRunsAreDroppedPastTheirCap;
    procedure TestARegisteredFontIsMeasuredAfresh;
    procedure TestTheKeptBitmapGrowsForATallerRun;
    procedure TestATallRunAfterAWideOneKeepsTheWidth;
    procedure TestARunTooBigForTheKeptBitmapGetsItsOwn;
    procedure TestTheKeptBitmapIsClearedBetweenRuns;
    procedure TestTheCoverageIsReadOffTheDib;
    procedure TestAShadowIsRenderedOncePerLook;
    procedure TestANineSliceImageIsReadOnce;
    procedure TestAnImageFillIsServedWithoutTheDisk;
  end;

implementation

function TPainterTest.MakePainter(AWidth, AHeight, APPI: Integer): TRect;
begin
  FHost := TBitmap.Create;
  FHost.SetSize(AWidth, AHeight);
  Result := Rect(0, 0, AWidth, AHeight);
  FPainter := TTyPainter.Create;
  FPainter.BeginPaint(FHost.Canvas, Result, APPI);
end;

procedure TPainterTest.FreePainter;
begin
  if Assigned(FPainter) then
  begin
    FPainter.EndPaint;
    FreeAndNil(FPainter);
  end;
  FreeAndNil(FHost);
end;

function TPainterTest.PixelAt(X, Y: Integer): TBGRAPixel;
begin
  Result := FPainter.Bitmap.GetPixel(X, Y);
end;

procedure TPainterTest.InkRows(out ATop, ABottom, ARows: Integer);
var
  x, y: Integer;
  inked: Boolean;
begin
  ATop := -1;
  ABottom := -1;
  ARows := 0;
  for y := 0 to FPainter.Bitmap.Height - 1 do
  begin
    inked := False;
    for x := 0 to FPainter.Bitmap.Width - 1 do
      if FPainter.Bitmap.GetPixel(x, y).alpha > 100 then
      begin
        inked := True;
        Break;
      end;
    if inked then
    begin
      if ATop < 0 then ATop := y;
      ABottom := y;
      Inc(ARows);
    end;
  end;
end;

procedure TPainterTest.TearDown;
begin
  FreePainter;
  inherited TearDown;
end;

procedure TPainterTest.TestColorToBGRAChannels;
var
  px: TBGRAPixel;
begin
  px := TyColorToBGRA(TyRGBA(10, 20, 30, 200));
  AssertEquals('red', 10, px.red);
  AssertEquals('green', 20, px.green);
  AssertEquals('blue', 30, px.blue);
  AssertEquals('alpha', 200, px.alpha);
end;

procedure TPainterTest.TestColorToBGRATransparent;
var
  px: TBGRAPixel;
begin
  px := TyColorToBGRA(tyTransparent);
  AssertEquals('alpha zero', 0, px.alpha);
end;

procedure TPainterTest.TestSolidFillCenter;
var
  fill: TTyFill;
  px: TBGRAPixel;
begin
  MakePainter(40, 40, 96);
  FillChar(fill, SizeOf(fill), 0);
  fill.Kind := tfkSolid;
  fill.Color := TyRGBA(255, 0, 0, 255);
  FPainter.FillBackground(Rect(0, 0, 40, 40), fill, 10);
  px := PixelAt(20, 20);
  AssertEquals('center red', 255, px.red);
  AssertEquals('center green', 0, px.green);
  AssertEquals('center blue', 0, px.blue);
  AssertEquals('center alpha', 255, px.alpha);
end;

procedure TPainterTest.TestSolidFillCornerTransparent;
var
  fill: TTyFill;
  px: TBGRAPixel;
begin
  MakePainter(40, 40, 96);
  FillChar(fill, SizeOf(fill), 0);
  fill.Kind := tfkSolid;
  fill.Color := TyRGBA(255, 0, 0, 255);
  FPainter.FillBackground(Rect(0, 0, 40, 40), fill, 16);
  px := PixelAt(0, 0);
  AssertEquals('corner alpha transparent', 0, px.alpha);
end;

procedure TPainterTest.TestLinearGradientVertical;
var
  fill: TTyFill;
  top, bottom: TBGRAPixel;
begin
  MakePainter(20, 40, 96);
  FillChar(fill, SizeOf(fill), 0);
  fill.Kind := tfkLinearGradient;
  fill.GradFrom := TyRGBA(0, 0, 0, 255);
  fill.GradTo := TyRGBA(255, 255, 255, 255);
  fill.GradAngleDeg := 90;
  FPainter.FillBackground(Rect(0, 0, 20, 40), fill, 0);
  top := PixelAt(10, 1);
  bottom := PixelAt(10, 38);
  AssertTrue('top dark', top.red < 60);
  AssertTrue('bottom light', bottom.red > 195);
  AssertEquals('top opaque', 255, top.alpha);
end;

procedure TPainterTest.TestBorderPixelColor;
var
  fill: TTyFill;
  px: TBGRAPixel;
begin
  MakePainter(40, 40, 96);
  FillChar(fill, SizeOf(fill), 0);
  fill.Kind := tfkSolid;
  fill.Color := TyRGBA(0, 255, 0, 255);
  FPainter.FillBackground(Rect(0, 0, 40, 40), fill, 0);
  FPainter.StrokeBorder(Rect(0, 0, 40, 40), 0, 4, TyRGBA(0, 0, 255, 255));
  px := PixelAt(20, 1);
  AssertTrue('border blue dominant', px.blue > 200);
  AssertTrue('border green low', px.green < 80);
  AssertEquals('border opaque', 255, px.alpha);
end;

procedure TPainterTest.TestDropShadowAlpha;
var
  px: TBGRAPixel;
begin
  MakePainter(60, 60, 96);
  FPainter.DropShadow(Rect(10, 10, 40, 40), 4, TyRGBA(0, 0, 0, 200), 6, Point(4, 4));
  px := PixelAt(44, 44);
  AssertTrue('shadow alpha present', px.alpha > 0);
  AssertTrue('shadow alpha partial', px.alpha < 200);
end;

procedure TPainterTest.TestDrawTextRastersPixels;
var
  x, y, hits: Integer;
  px: TBGRAPixel;
begin
  MakePainter(120, 40, 96);
  FPainter.DrawText(Rect(0, 0, 120, 40), 'Ty', 'DejaVu Sans', 14, 700,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
  hits := 0;
  for y := 0 to 39 do
    for x := 0 to 119 do
    begin
      px := PixelAt(x, y);
      if px.alpha > 100 then
        Inc(hits);
    end;
  AssertTrue('glyph pixels rendered', hits > 0);
end;

{ TEXT IS INKED AS WINDOWS INKS IT.
  Three renderings were shipped or tried and each looked wrong next to the text Windows
  draws in the same window: six-times-and-shrink (soft and light), GDI grayscale at the real
  size (crisp, but both axes hinted: Microsoft YaHei's strokes snapped sideways and turned
  blocky), BGRA's ClearType (coloured, and lighter). What the eye compares is how much ink a
  line lays down and how much of it is solid -- so that is what is compared, against GDI's
  own ClearType drawing the same string in the same font, black on white and white on black.
  Each of the three rejected renderings misses one of the two by far more than the margin.
  The reference is GDI under THIS machine's ClearType settings, on purpose: away from the
  default contrast Windows inks light-on-dark heavier than dark-on-light (12% for Segoe UI
  at 1200), so a light-ink case going red where it was green is the renderer drifting from
  what Windows draws on that desktop -- light ink drawn from dark-on-light coverage did
  exactly that -- not an environment to be waved through. }
{$IFDEF LCLWin32}
type
  TTestCanvasAccess = class(TCanvas);

function TestSystemParametersInfo(uiAction, uiParam: LongWord; pvParam: Pointer;
  fWinIni: LongWord): LongBool; stdcall; external 'user32' name 'SystemParametersInfoW';

{ The desktop's own answer, asked here rather than of the renderer: ClearType is in effect. }
function DesktopUsesClearType: Boolean;
const
  SPI_GETFONTSMOOTHING = $004A;
  SPI_GETFONTSMOOTHINGTYPE = $200A;
  FE_FONTSMOOTHINGCLEARTYPE = 2;
var
  smooth: LongBool;
  kind: LongWord;
begin
  smooth := False;
  kind := 0;
  Result := TestSystemParametersInfo(SPI_GETFONTSMOOTHING, 0, @smooth, 0) and smooth
    and TestSystemParametersInfo(SPI_GETFONTSMOOTHINGTYPE, 0, @kind, 0)
    and (kind = FE_FONTSMOOTHINGCLEARTYPE);
end;
{$ENDIF}

{ ON AN OPAQUE SURFACE, WHAT WINDOWS DRAWS THERE (#90). Text averaged to grey keeps
  ClearType's weight but not its sharpness: a stem ClearType lays on two subpixels comes out
  as two grey pixels, and next to the system's own text in the same window it reads soft.
  Where the surface under the run is opaque, the colour the text lands on is known, so the
  three coverages go down channel by channel, as GDI lays them down itself. Compared pixel
  by pixel with GDI drawing the same run with the same call on the same surface: black on
  white and white on black, where GDI's blend and ours are the same arithmetic. First the
  grey of the two is compared, so a run in the wrong place cannot pass for the wrong colour.
  A desktop with ClearType off gets grey from both. }
{ #107. Text on an opaque surface asks whether the desktop draws in ClearType; the answer
  is kept a second, not asked of the system per run: three runs in a row ask once, a run a
  second later asks again, a run after TyForgetDesktopClearType asks at once. }
procedure TPainterTest.TestTheClearTypeAnswerIsKeptASecond;
{$IFDEF LCLWin32}
var
  bmp: TBGRABitmap;
  n: Integer;
begin
  bmp := TBGRABitmap.Create(200, 30, BGRAWhite);
  try
    TyConfigureTextFont(bmp, 'Segoe UI', 9, 400, 96);
    TyDesktopClearTypeClockShiftForTest(0);
    TyForgetDesktopClearType;
    n := TyDesktopClearTypeAsksForTest;
    bmp.TextOut(4, 4, 'one', BGRABlack);
    bmp.TextOut(4, 4, 'two', BGRABlack);
    bmp.TextOut(4, 4, 'three', BGRABlack);
    AssertEquals('three runs within a second ask the system once', n + 1,
      TyDesktopClearTypeAsksForTest);
    TyDesktopClearTypeClockShiftForTest(1000);
    bmp.TextOut(4, 4, 'four', BGRABlack);
    AssertEquals('a second later the system is asked again', n + 2,
      TyDesktopClearTypeAsksForTest);
    bmp.TextOut(4, 4, 'five', BGRABlack);
    AssertEquals('and that answer is kept', n + 2, TyDesktopClearTypeAsksForTest);
    TyForgetDesktopClearType;
    bmp.TextOut(4, 4, 'six', BGRABlack);
    AssertEquals('a forgotten answer is asked for at once', n + 3,
      TyDesktopClearTypeAsksForTest);
  finally
    TyDesktopClearTypeClockShiftForTest(0);
    TyForgetDesktopClearType;
    bmp.Free;
  end;
end;
{$ELSE}
begin
  AssertEquals('only Win32 asks the system', 0, TyDesktopClearTypeAsksForTest);
end;
{$ENDIF}

procedure TPainterTest.TestTextOnAnOpaqueSurfaceIsWhatWindowsDrawsThere;
{$IFDEF LCLWin32}
  procedure Compare(const AFont: string; ALightInk: Boolean);
  const
    CText = '节点 0 (L0) Illuminate Tabs 富输入 · TyControls';
    W = 560;
    H = 32;
  var
    ours, theirs: TBGRABitmap;
    b: TBitmap;
    r: TRect;
    bg, ink, po, pt: TBGRAPixel;
    x, y, greyWorst, worst, inked, chroma: Integer;
    ourR, ourG, ourB, winR, winG, winB: Integer;
    what: string;
  begin
    if ALightInk then
    begin
      bg := BGRABlack;
      ink := BGRAWhite;
    end
    else
    begin
      bg := BGRAWhite;
      ink := BGRABlack;
    end;
    ours := TBGRABitmap.Create(W, H, bg);
    theirs := nil;
    b := TBitmap.Create;
    try
      TyConfigureTextFont(ours, AFont, 9, 400, 96);
      ours.TextOut(4, 4, CText, ink);
      b.PixelFormat := pf24bit;
      b.SetSize(W, H);
      b.Canvas.Brush.Color := BGRAToColor(bg);
      b.Canvas.FillRect(0, 0, W, H);
      b.Canvas.Font.Name := AFont;
      b.Canvas.Font.Height := -TyFontHeightPx(9, 96);
      b.Canvas.Font.Quality := fqCleartypeNatural;
      TTestCanvasAccess(b.Canvas).RequiredState([csHandleValid, csFontValid]);
      SetBkMode(b.Canvas.Handle, TRANSPARENT);
      SetTextColor(b.Canvas.Handle, BGRAToColor(ink));
      r := Rect(4, 4, W, H);
      b.Canvas.Changing;
      LCLIntf.DrawText(b.Canvas.Handle, PChar(CText), Length(CText), r,
        DT_SINGLELINE or DT_NOCLIP or DT_NOPREFIX);
      b.Canvas.Changed;
      theirs := TBGRABitmap.Create(b);
      greyWorst := 0;
      worst := 0;
      inked := 0;
      chroma := 0;
      for y := 0 to H - 1 do
        for x := 0 to W - 1 do
        begin
          po := ours.GetPixel(x, y);
          pt := theirs.GetPixel(x, y);
          ourR := po.red;
          ourG := po.green;
          ourB := po.blue;
          winR := pt.red;
          winG := pt.green;
          winB := pt.blue;
          if (winR <> bg.red) or (winG <> bg.green) or (winB <> bg.blue) then Inc(inked);
          greyWorst := Max(greyWorst, Abs((ourR + ourG + ourB) div 3 - (winR + winG + winB) div 3));
          worst := Max(worst, Max(Abs(ourR - winR), Max(Abs(ourG - winG), Abs(ourB - winB))));
          chroma := Max(chroma, Max(ourR, Max(ourG, ourB)) - Min(ourR, Min(ourG, ourB)));
        end;
      what := Format('%s, %s ink: worst grey difference %d, worst channel difference %d,'
        + ' ours most coloured %d, %d pixels inked by Windows', [AFont,
        BoolToStr(ALightInk, 'light', 'dark'), greyWorst, worst, chroma, inked]);
      AssertTrue('precondition: Windows drew the run -- ' + what, inked > 200);
      AssertTrue('the run lies where Windows lays it, as heavy -- ' + what, greyWorst <= 2);
      if DesktopUsesClearType then
        AssertTrue('channel by channel what Windows draws there -- ' + what, worst <= 2)
      else
        AssertEquals('ClearType is off: grey, as Windows draws it -- ' + what, 0, chroma);
    finally
      theirs.Free;
      b.Free;
      ours.Free;
    end;
  end;

begin
  Compare('Microsoft YaHei UI', False);
  Compare('Segoe UI', False);
  Compare('Microsoft YaHei UI', True);
  Compare('Segoe UI', True);
end;
{$ELSE}
begin
  Ignore('Win32 only: the other widgetsets draw text through BGRA');
end;
{$ENDIF}

{ IN THE INK'S POLARITY (#91). BGRABitmap rasterises every run white on black on an LCL
  bitmap and uses that as the mask, whatever the colour of the ink. macOS font smoothing
  thickens light-on-dark far more than dark-on-light (one line of PingFang SC 13 px, white
  on black and inverted: 25% more ink than black on white), so dark text drawn from that
  mask came out heavy -- 26% more ink than LCL's own text on a transparent surface. The
  canvas renderer draws the run on the same kind of bitmap, with the same canvas call, in the
  ink's polarity. That property is the canvas's, not the Mac's, so it is checked here on
  whatever canvas this is: the coverage laid down on a transparent surface is, pixel for
  pixel, the run the canvas itself draws dark on light for dark ink and light on dark for
  light ink. A mask of the other polarity differs pixel by pixel on any canvas that smooths
  or hints by polarity -- ClearType does, at every contrast. }
procedure TPainterTest.TestTheCanvasRendererDrawsInTheInksPolarity;

  procedure Compare(const AFont: string; ALightInk: Boolean);
  const
    CText = 'Illuminate Tabs 节点 0 (L0) 富输入 · TyControls';
    W = 520;
    H = 34;
    CHeight = 15;
  var
    ours: TBGRABitmap;
    b: TBitmap;
    theirs: TBGRABitmap;
    ink: TBGRAPixel;
    x, y, worst, inked, o, c: Integer;
    p: TBGRAPixel;
    what: string;
  begin
    if ALightInk then ink := BGRAWhite else ink := BGRABlack;
    ours := TBGRABitmap.Create(W, H, BGRAPixelTransparent);
    b := TBitmap.Create;
    theirs := nil;
    try
      ours.FontRenderer := TTyCanvasTextRenderer.Create;
      ours.FontName := AFont;
      ours.FontHeight := CHeight;
      ours.FontQuality := fqSystemClearType;
      ours.TextOut(4, 4, CText, ink);
      { theirs: the canvas, the run in the ink's own polarity, at the same place }
      b.SetSize(W, H);
      if ALightInk then b.Canvas.Brush.Color := clBlack else b.Canvas.Brush.Color := clWhite;
      b.Canvas.FillRect(0, 0, W, H);
      b.Canvas.Font.Name := AFont;
      b.Canvas.Font.Height := -CHeight;
      b.Canvas.Font.Quality := fqCleartype;
      if ALightInk then b.Canvas.Font.Color := clWhite else b.Canvas.Font.Color := clBlack;
      b.Canvas.Brush.Style := bsClear;
      b.Canvas.TextOut(4, 4, CText);
      theirs := TBGRABitmap.Create(b);
      worst := 0;
      inked := 0;
      for y := 0 to H - 1 do
        for x := 0 to W - 1 do
        begin
          p := theirs.GetPixel(x, y);
          c := (p.red + p.green + p.blue) div 3;
          if not ALightInk then c := 255 - c;
          if c > 0 then Inc(inked);
          o := ours.GetPixel(x, y).alpha;
          worst := Max(worst, Abs(o - c));
        end;
      what := Format('%s, %s ink: worst coverage difference %d, %d pixels inked by the canvas',
        [AFont, BoolToStr(ALightInk, 'light', 'dark'), worst, inked]);
      AssertTrue('precondition: the canvas drew the run -- ' + what, inked > 200);
      AssertTrue('pixel for pixel the canvas''s own run in the ink''s polarity -- ' + what,
        worst <= 2);
    finally
      theirs.Free;
      b.Free;
      ours.Free;
    end;
  end;

begin
  Compare('Segoe UI', False);
  Compare('Segoe UI', True);
  Compare('Microsoft YaHei UI', False);
  Compare('Microsoft YaHei UI', True);
end;

{ #91: what the test above checks is only worth something if Cocoa text goes through that
  renderer. Nothing here runs Cocoa, so the wiring is read off the source: the procedure
  every font configuration ends in installs it under LCLCocoa. }
procedure TPainterTest.TestMacTextGoesThroughTheCanvasRenderer;
var
  sl: TStringList;
  i, e: Integer;
  body: string;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(RepoRoot + 'source' + PathDelim + 'tyControls.Painter.pas');
    i := Pos('procedure TyUseTextRenderer(ABmp: TBGRABitmap);' + LineEnding + 'begin', sl.Text);
    AssertTrue('TyUseTextRenderer found', i > 0);
    e := Pos(LineEnding + 'end;', Copy(sl.Text, i, MaxInt));
    body := Copy(sl.Text, i, e);
    AssertTrue('Cocoa installs the canvas renderer -- ' + body,
      Pos('{$IFDEF LCLCocoa}' + LineEnding + '  if not (ABmp.FontRenderer is TTyCanvasTextRenderer) then'
        + LineEnding + '    ABmp.FontRenderer := TTyCanvasTextRenderer.Create;', body) > 0);
  finally
    sl.Free;
  end;
end;

procedure TPainterTest.TestTextIsInkedAsWindowsInksIt;

  { Coverage of every pixel: 0 = paper, 1 = ink. }
  procedure Measure(const ACov: array of Single; out AMass, ASolid: Double);
  var
    i, ink, solid: Integer;
  begin
    AMass := 0;
    ink := 0;
    solid := 0;
    for i := 0 to High(ACov) do
      if ACov[i] > 0.05 then
      begin
        AMass := AMass + ACov[i];
        Inc(ink);
        if ACov[i] > 0.75 then Inc(solid);
      end;
    if ink > 0 then ASolid := solid / ink else ASolid := 0;
  end;

  procedure Compare(const AFont: string; APPI: Integer; ALightInk: Boolean);
  const
    CText = 'Illuminate Tabs TStrings 按住 Alt 显示助记下划线 跳到对应标签';
  var
    w, h, x, y, n: Integer;
    ours, theirs: array of Single;
    b: TBitmap;
    shot: TBGRABitmap;
    p: TBGRAPixel;
    m1, s1, m2, s2: Double;
    ink: TTyColor;
    what: string;
  begin
    w := MulDiv(700, APPI, 96);
    h := MulDiv(28, APPI, 96);
    SetLength(ours, w * h);
    SetLength(theirs, w * h);
    if ALightInk then ink := TyRGBA(255, 255, 255, 255) else ink := TyRGBA(0, 0, 0, 255);
    { Ours: the painter, on its own transparent surface -- alpha IS coverage. }
    MakePainter(w, h, APPI);
    try
      FPainter.DrawText(Rect(0, 0, w, h), CText, AFont, 9, 400, ink, taLeftJustify, tlCenter,
        False);
      for y := 0 to h - 1 do
        for x := 0 to w - 1 do
          ours[y * w + x] := PixelAt(x, y).alpha / 255;
    finally
      FreePainter;
    end;
    { Theirs: GDI's ClearType, in the same font at the same pixel height. }
    b := TBitmap.Create;
    try
      b.PixelFormat := pf24bit;
      b.SetSize(w, h);
      if ALightInk then b.Canvas.Brush.Color := clBlack else b.Canvas.Brush.Color := clWhite;
      b.Canvas.FillRect(0, 0, w, h);
      b.Canvas.Font.Name := AFont;
      b.Canvas.Font.Height := -TyFontHeightPx(9, APPI);
      b.Canvas.Font.Quality := fqCleartypeNatural;
      if ALightInk then b.Canvas.Font.Color := clWhite else b.Canvas.Font.Color := clBlack;
      b.Canvas.Brush.Style := bsClear;
      b.Canvas.TextOut(0, 2, CText);
      shot := TBGRABitmap.Create(b);
      try
        for y := 0 to h - 1 do
          for x := 0 to w - 1 do
          begin
            p := shot.GetPixel(x, y);
            n := (p.red + p.green + p.blue) div 3;
            if ALightInk then theirs[y * w + x] := n / 255
            else theirs[y * w + x] := 1 - n / 255;
          end;
      finally
        shot.Free;
      end;
    finally
      b.Free;
    end;
    Measure(ours, m1, s1);
    Measure(theirs, m2, s2);
    what := Format('%s, %d PPI, %s ink: ours lays down %.0f of ink, %.2f of it solid;'
      + ' Windows %.0f, %.2f', [AFont, APPI, BoolToStr(ALightInk, 'light', 'dark'),
      m1, s1, m2, s2]);
    AssertTrue('precondition: Windows drew the text -- ' + what, m2 > 100);
    AssertTrue('as much ink as Windows lays down -- ' + what, Abs(m1 - m2) <= 0.08 * m2);
    AssertTrue('as much of it solid -- ' + what, Abs(s1 - s2) <= 0.06);
  end;

begin
  {$IFDEF LCLWin32}
  Compare('Microsoft YaHei UI', 96, False);
  Compare('Microsoft YaHei UI', 168, False);
  Compare('Segoe UI', 96, False);
  Compare('Segoe UI', 168, False);
  Compare('Microsoft YaHei UI', 168, True);
  Compare('Segoe UI', 96, True);
  {$ELSE}
  Ignore('the renderer is chosen per widgetset; this compares the Win32 one with GDI');
  {$ENDIF}
end;

{ DRAWN TEXT ENDS WHERE IT WAS MEASURED.
  Carets, ellipses and AutoSize widths are all laid out from MeasureText, so the glyphs have
  to land on it. On Windows the measuring side asks GDI's DrawText, and a renderer can draw
  the run with a call that lays it out differently: TextOut does not kern the pairs DrawText
  kerns (a line of AV/To/Ty in Segoe UI: 145 px measured, 159 drawn), and TCanvas.TextRect
  renames an unnamed font 'default', which is another face. So the line is kerned, and it is
  drawn in a named font and in an unnamed one -- the test runner's own font. }
procedure TPainterTest.TestDrawnTextEndsWhereItWasMeasured;

  procedure Check(const AFont: string; APPI: Integer);
  const
    CText = 'AVAVAVAVAV To Ty Wa Yo LT';
  var
    sz: TSize;
    w, h, x, y, right: Integer;
  begin
    w := MulDiv(400, APPI, 96);
    h := MulDiv(30, APPI, 96);
    MakePainter(w, h, APPI);
    try
      sz := FPainter.MeasureText(CText, AFont, 9, 400);
      FPainter.DrawText(Rect(0, 0, w, h), CText, AFont, 9, 400, TyRGBA(0, 0, 0, 255),
        taLeftJustify, tlCenter, False);
      right := 0;
      for y := 0 to h - 1 do
        for x := 0 to w - 1 do
          if (PixelAt(x, y).alpha > 60) and (x + 1 > right) then right := x + 1;
    finally
      FreePainter;
    end;
    AssertTrue(Format('precondition: "%s" at %d PPI measured inside the surface (%d of %d)',
      [AFont, APPI, sz.cx, w]), (sz.cx > 0) and (sz.cx < w - 20));
    AssertTrue(Format('"%s" at %d PPI: the ink ends at %d, the measured line at %d',
      [AFont, APPI, right, sz.cx]), Abs(right - sz.cx) <= 2);
  end;

var
  saved: string;
begin
  {$IFDEF LCLWin32}
  saved := TyFallbackFontName;
  TyFallbackFontName := '';
  try
    Check('Segoe UI', 96);
    Check('Segoe UI', 168);
    Check('', 96);
    Check('', 168);
  finally
    TyFallbackFontName := saved;
  end;
  {$ELSE}
  Ignore('the renderer is chosen per widgetset; this checks the Win32 one against GDI''s measure');
  if saved = '' then ;
  {$ENDIF}
end;

procedure TPainterTest.TestDrawGlyphAllKinds;
var
  g: TTyGlyphKind;
  x, y, hits: Integer;
  px: TBGRAPixel;
begin
  for g := Low(TTyGlyphKind) to High(TTyGlyphKind) do
  begin
    MakePainter(24, 24, 96);
    FPainter.DrawGlyph(Rect(0, 0, 24, 24), g, TyRGBA(0, 0, 0, 255), 2);
    hits := 0;
    for y := 0 to 23 do
      for x := 0 to 23 do
      begin
        px := PixelAt(x, y);
        if px.alpha > 100 then
          Inc(hits);
      end;
    AssertTrue('glyph ' + IntToStr(Ord(g)) + ' painted', hits > 0);
    FreePainter;
  end;
end;

{ The mirror partner, asked where the two shapes actually differ.

  A '<' and a '>' fill the same box with the same amount of ink and their arms are each
  other's reflection, so total ink, bounding box and centre of mass are all identical for the
  two -- a probe aimed anywhere near the middle of the glyph cannot tell them apart, and
  would go on passing if tgChevronLeft were a copy of tgChevronRight. Only the APEX moves, so
  only the apex is asserted: the vertical centre band, which each chevron touches with
  nothing but its point, must be empty on the side the point came from.

  Pad 1 rather than the default 4, because that is what every slot-sized caller passes and
  what the arithmetic below assumes about where the glyph box sits inside the rect. }
procedure TPainterTest.TestChevronLeftIsTheApexMirrorOfChevronRight;
const
  BOX = 24;
var
  inkLeft, inkRight: Integer;

  { Ink in the glyph's vertical centre band, split at the box's own centre line. }
  procedure BandInk(AGlyph: TTyGlyphKind; out ALeft, ARight: Integer);
  var
    x, y: Integer;
  begin
    ALeft := 0;
    ARight := 0;
    MakePainter(BOX, BOX, 96);
    FPainter.DrawGlyph(Rect(0, 0, BOX, BOX), AGlyph, TyRGBA(0, 0, 0, 255), 1, 1);
    for y := BOX div 2 - 1 to BOX div 2 + 1 do
      for x := 0 to BOX - 1 do
        if PixelAt(x, y).alpha > 100 then
          if x < BOX div 2 then Inc(ALeft) else Inc(ARight);
    FreePainter;
  end;

begin
  BandInk(tgChevronRight, inkLeft, inkRight);
  AssertTrue('a right chevron puts its point in the right half', inkRight > 0);
  AssertEquals('and nothing of it reaches the half its arms open towards', 0, inkLeft);
  BandInk(tgChevronLeft, inkLeft, inkRight);
  AssertTrue('a left chevron puts its point in the left half', inkLeft > 0);
  AssertEquals('and nothing of it reaches the half its arms open towards', 0, inkRight);
end;

function TPainterTest.WriteTempNineSlice: string;
var
  bmp: TBGRABitmap;
begin
  Result := GetTempDir(False) + 'tyninetest.png';
  bmp := TBGRABitmap.Create(9, 9, BGRA(0, 0, 255, 255));
  try
    bmp.FillRect(3, 3, 6, 6, BGRA(255, 0, 0, 255), dmSet);
    bmp.SaveToFile(Result);
  finally
    bmp.Free;
  end;
end;

procedure TPainterTest.TestNineSliceCenterRegion;
var
  fn: string;
  px: TBGRAPixel;
begin
  fn := WriteTempNineSlice;
  try
    MakePainter(60, 60, 96);
    FPainter.NineSlice(Rect(0, 0, 60, 60), fn, Rect(3, 3, 3, 3));
    px := PixelAt(30, 30);
    AssertTrue('center red', px.red > 200);
    AssertTrue('center blue low', px.blue < 80);
  finally
    DeleteFile(fn);
  end;
end;

procedure TPainterTest.TestEraseRectMakesTransparent;
{ Fill the entire bitmap solid red, then EraseRect a sub-region.
  Assert the erased sub-region pixel is fully transparent (alpha=0)
  and a pixel outside the erased rect still has alpha=255. }
var
  fill: TTyFill;
  pxInside, pxOutside: TBGRAPixel;
begin
  MakePainter(40, 40, 96);
  FillChar(fill, SizeOf(fill), 0);
  fill.Kind := tfkSolid;
  fill.Color := TyRGBA(255, 0, 0, 255);
  FPainter.FillBackground(Rect(0, 0, 40, 40), fill, 0);
  // Erase a 10x10 sub-rect in the top-left
  FPainter.EraseRect(Rect(5, 5, 15, 15));
  pxInside := PixelAt(10, 10);
  pxOutside := PixelAt(30, 30);
  AssertEquals('erased pixel alpha = 0', 0, pxInside.alpha);
  AssertEquals('outside pixel alpha = 255 (unchanged)', 255, pxOutside.alpha);
  AssertEquals('outside pixel red = 255 (unchanged)', 255, pxOutside.red);
end;

procedure TPainterTest.TestFillCornerGapsPreservesAlpha;
{ Closes a recorded-but-WRONG suspicion from the aero black-corner investigation
  (plans/2026-08-04-parity-remaining-programs.md): that FillCornerGaps treats an alpha
  colour like the #00000014 shadow as opaque #000000. It does not — the patch is built
  from TyColorToBGRA (alpha kept) and composited with dmDrawWithTransparency — and this
  pins that: a 20/255-alpha black over a white base must leave the corner NEAR-WHITE
  (255 * 235/255 = ~235), not black. The aero notches came from the colour HANDED to
  FillCornerGaps (an unresolved clDefault), which test.formgradientbg guards.

  The probe is the CORNER pixel, never the centre — and the centre must stay untouched:
  FillCornerGaps' whole contract is to repaint only the gaps outside the rounded shape. }
var
  fill: TTyFill;
  corner, centre: TBGRAPixel;
begin
  MakePainter(40, 40, 96);
  FillChar(fill, SizeOf(fill), 0);
  fill.Kind := tfkSolid;
  fill.Color := TyRGBA(255, 255, 255, 255);
  FPainter.FillBackground(Rect(0, 0, 40, 40), fill, 0);   // opaque white base everywhere
  FPainter.FillCornerGaps(Rect(0, 0, 40, 40), TyUniformCorners(8), TyRGBA(0, 0, 0, 20));
  corner := PixelAt(0, 0);
  centre := PixelAt(20, 20);
  AssertTrue(Format('corner blends the 20/255 alpha instead of going opaque black ' +
    '(got #%.2x%.2x%.2x)', [corner.red, corner.green, corner.blue]),
    (corner.red >= 225) and (corner.red <= 245) and
    (corner.green >= 225) and (corner.green <= 245) and
    (corner.blue >= 225) and (corner.blue <= 245));
  AssertEquals('corner stays opaque (composited over the opaque base)', 255, corner.alpha);
  AssertEquals('the centre inside the rounded shape is untouched (red)', 255, centre.red);
  AssertEquals('the centre inside the rounded shape is untouched (alpha)', 255, centre.alpha);
end;

procedure TPainterTest.TestPerCornerTopRoundBottomSquare;
{ border-radius 6 6 0 0: top corners rounded away (transparent in BGRA bitmap),
  bottom corners square (green fill reaches the corner). Read directly from the
  internal BGRA bitmap before EndPaint, consistent with all other painter tests.
  Discriminate on alpha/red:
    top-left   alpha = 0   (rounded corner cut away, transparent)
    bottom-left alpha = 255, red = $20 (square corner, fully-opaque green fill) }
var
  fill: TTyFill;
  r: TRect;
  pxTL, pxBL: TBGRAPixel;
begin
  MakePainter(40, 40, 96);
  r := Rect(0, 0, 40, 40);
  fill := Default(TTyFill);
  fill.Kind := tfkSolid;
  fill.Color := TyRGB($20, $C0, $40);       // green, red channel = $20
  FPainter.FillBackground(r, fill, TyCorners(6, 6, 0, 0));
  pxTL := FPainter.Bitmap.GetPixel(0, 0);   // top-left: rounded -> transparent
  pxBL := FPainter.Bitmap.GetPixel(1, 38);  // bottom-left: (1,38) is outside the r=6 arc centered at (6,33) (distance ~7.07 > 6), so it is filled green only when the corner is truly square
  AssertEquals('top-left rounded (transparent): alpha = 0', 0, pxTL.alpha);
  AssertEquals('bottom-left square: alpha opaque', 255, pxBL.alpha);
  AssertEquals('bottom-left green fill: red = $20', $20, pxBL.red);
end;

procedure TPainterTest.TestFallbackFontNameApplied;
{ Mechanism guard for the empty-FontName fix (no real GUI needed):
  - With TyFallbackFontName set, an empty AFontName is replaced by it.
  - A non-empty AFontName always passes through unchanged.
  - With no fallback, the empty name is preserved (original behavior). }
var
  bmp: TBGRABitmap;
  saved: string;
begin
  saved := TyFallbackFontName;
  bmp := TBGRABitmap.Create(4, 4);
  try
    TyFallbackFontName := 'Arial';
    TyConfigureTextFont(bmp, '', 9, 400, 96);
    AssertEquals('empty name uses fallback', 'Arial', bmp.FontName);
    TyConfigureTextFont(bmp, 'Verdana', 9, 400, 96);
    AssertEquals('explicit name preserved', 'Verdana', bmp.FontName);
    TyFallbackFontName := '';
    TyConfigureTextFont(bmp, '', 9, 400, 96);
    AssertEquals('no fallback => empty preserved', '', bmp.FontName);
  finally
    bmp.Free;
    TyFallbackFontName := saved;
  end;
end;

procedure TPainterTest.TestMeasureTextAndUnscale;
var sz: TSize;
begin
  MakePainter(60, 30, 96);   // FreePainter runs in TearDown
  sz := FPainter.MeasureText('99+', '', 9, 400);
  AssertTrue('measured width > 0', sz.cx > 0);
  AssertTrue('measured height > 0', sz.cy > 0);
  AssertEquals('unscale identity at 96ppi', 12, FPainter.Unscale(FPainter.Scale(12)));
end;

procedure TPainterTest.TestZeroFontSizeFallsBack;
var szZero, szFallback: TSize;
begin
  MakePainter(60, 30, 96);
  // A theme rule with no font-size resolves to 0; text must still be visible — the painter
  // falls back to TyFallbackFontSize instead of rendering/measuring a size-0 (invisible) glyph.
  szZero     := FPainter.MeasureText('Ag', '', 0, 400);
  szFallback := FPainter.MeasureText('Ag', '', TyFallbackFontSize, 400);
  AssertTrue('zero font-size measures non-empty', (szZero.cx > 0) and (szZero.cy > 0));
  AssertEquals('zero width == fallback width', szFallback.cx, szZero.cx);
  AssertEquals('zero height == fallback height', szFallback.cy, szZero.cy);
end;

procedure TPainterTest.TestClampRadiusPx;
{ A radius is clamped to half the SHORTER side (pill), never larger. }
begin
  AssertEquals('pill radius on a short track clamps to half-height', 9, TyClampRadiusPx(100, 420, 18));
  AssertEquals('small radius passes through', 6, TyClampRadiusPx(6, 116, 34));
  AssertEquals('clamps to half the shorter side (width here)', 10, TyClampRadiusPx(50, 20, 200));
  AssertEquals('negative radius floors at 0', 0, TyClampRadiusPx(-3, 40, 40));
end;

procedure TPainterTest.TestLargeRadiusRendersPillNotLens;
{ A wide, short rect with a huge "pill" radius (100 >> half-height 10) must render as a rounded
  PILL, not a pointed lens. A near-end pixel (5,3) lies inside the pill's left semicircle
  (centre (10,10) r=10) → filled; without the clamp the corner is cut into a point → transparent. }
var
  fill: TTyFill;
  px: TBGRAPixel;
begin
  MakePainter(200, 20, 96);
  fill := Default(TTyFill);
  fill.Kind := tfkSolid;
  fill.Color := TyRGB(255, 0, 0);
  FPainter.FillBackground(Rect(0, 0, 200, 20), fill, 100);
  px := FPainter.Bitmap.GetPixel(5, 3);
  AssertEquals('near-end pixel filled (pill), not cut to a point (lens)', 255, px.alpha);
end;

{ Ellipsising used to shorten the string one BYTE at a time (Delete(s, Length(s), 1)).
  Every CJK character is three bytes in UTF-8, so that left a half-cut sequence: the real GUI
  drew a replacement glyph, which is what the maintainer saw in title bars, buttons, list
  rows and tab headers -- they all funnel through this one DrawText.

  A pixel comparison cannot guard it. The headless BGRA path silently swallows the stray
  trailing byte, so the broken and the correct render come out IDENTICAL here (verified: with
  the byte-wise cut restored, a bitmap-equality test still passed). So assert the STRING
  invariant instead, on the function DrawText actually calls: every prefix the fitter can
  produce is a whole number of characters. }
procedure TPainterTest.TestEllipsisCutsWholeCharactersNotBytes;
const
  CJK = '积压任务徽标挂在按钮上不是按钮内置的';
var
  i, n: Integer;
  prefix: string;
begin
  n := UTF8Length(CJK);
  AssertTrue('the sample really is multi-byte', Length(CJK) = n * 3);

  for i := 0 to n do
  begin
    prefix := TyEllipsisPrefix(CJK, i);
    AssertEquals(Format('prefix of %d chars holds %d characters', [i, i]),
      i, UTF8Length(prefix));
    { The load-bearing one: a byte count that is not a multiple of three here means a
      character was cut through the middle. }
    AssertEquals(Format('prefix of %d chars ends on a character boundary', [i]),
      i * 3, Length(prefix));
  end;

  AssertEquals('a negative count yields nothing', '', TyEllipsisPrefix(CJK, -1));
end;

{ ---- multi-line text, and the line box it is laid out on ---------------------------- }

const
  { Two lines of the SAME text: the width can then never explain a difference, only the
    layout can. 'Ay' carries both an ascender and a descender, so the ink of one line is a
    full line box worth. }
  cTwoLines = 'Ay' + LineEnding + 'Ay';
  cMeasureFont = 'Tahoma';

type
  TPixBuf = array of TBGRAPixel;

function SnapshotOf(ABmp: TBGRABitmap): TPixBuf;
var
  x, y, i: Integer;
begin
  SetLength(Result, ABmp.Width * ABmp.Height);
  i := 0;
  for y := 0 to ABmp.Height - 1 do
    for x := 0 to ABmp.Width - 1 do
    begin
      Result[i] := ABmp.GetPixel(x, y);
      Inc(i);
    end;
end;

function CountDifferingPixels(const A, B: TPixBuf): Integer;
var
  i: Integer;
begin
  Result := 0;
  if Length(A) <> Length(B) then
    Exit(MaxInt);
  for i := 0 to High(A) do
    if (A[i].red <> B[i].red) or (A[i].green <> B[i].green)
       or (A[i].blue <> B[i].blue) or (A[i].alpha <> B[i].alpha) then
      Inc(Result);
end;

procedure TPainterTest.TestSplitTextLinesHonoursAuthoredBreaks;
{ The split is what both the drawing path and the measuring path ask "how many lines is
  this?", so its edge cases are the edge cases of every size floor derived from it. }
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    TySplitTextLines('plain', L);
    AssertEquals('no break at all is one line', 1, L.Count);
    AssertEquals('and it is the text', 'plain', L[0]);

    TySplitTextLines('a'#13#10'b', L);
    AssertEquals('CRLF breaks', 2, L.Count);
    TySplitTextLines('a'#10'b', L);
    AssertEquals('a bare LF breaks', 2, L.Count);
    TySplitTextLines('a'#13'b', L);
    AssertEquals('a bare CR breaks', 2, L.Count);

    TySplitTextLines('one' + LineEnding + LineEnding + 'two', L);
    AssertEquals('a blank line between paragraphs is content', 3, L.Count);
    AssertEquals('and it is the empty one', '', L[1]);

    { Load-bearing: an empty caption must still be ONE line. Zero lines here would let a
      height floor of "lines x line height" collapse a control to its padding. }
    TySplitTextLines('', L);
    AssertEquals('an empty caption is one empty line', 1, L.Count);
    AssertEquals('', L[0]);
  finally
    L.Free;
  end;
end;

procedure TPainterTest.TestMultiLineDrawsTheSecondLine;
{ THE BUG. style.SingleLine was hard-coded, so a caption with an authored break drew as one
  run — the second line simply did not exist. Both draws below get the same rect, the same
  text and the same centring; only the opt-in flag differs, so any difference in how far the
  ink reaches is the second line appearing. }
var
  t1, b1, r1, t2, b2, r2: Integer;
begin
  MakePainter(200, 140, 96);
  FPainter.DrawText(Rect(0, 0, 200, 140), cTwoLines, cMeasureFont, 12, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
  InkRows(t1, b1, r1);
  FreePainter;

  MakePainter(200, 140, 96);
  FPainter.DrawText(Rect(0, 0, 200, 140), cTwoLines, cMeasureFont, 12, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False, 0, False, True);
  InkRows(t2, b2, r2);

  AssertTrue('the single-line path inked something to compare against', r1 > 0);
  AssertTrue(Format('two lines reach lower than one (%d vs %d)', [b2, b1]), b2 > b1);
  AssertTrue(Format('and start higher — the block is centred as a whole (%d vs %d)',
    [t2, t1]), t2 < t1);
  AssertTrue(Format('so the block grew by most of a line (%d vs %d)',
    [b2 - t2, b1 - t1]), (b2 - t2) > (b1 - t1) + 8);
end;

procedure TPainterTest.TestMultiLineFlagLeavesASingleLineByteIdentical;
{ The flag defaults to off so no existing caller changes; this pins the other half of that
  promise — a caption with NO break in it is drawn by the same code either way, mnemonic
  underline included, and a themed line box does not sneak into it. }
var
  flagOff, flagOn: TPixBuf;
begin
  MakePainter(200, 60, 96);
  FPainter.DrawText(Rect(0, 0, 200, 60), 'Single', cMeasureFont, 12, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False, 3);
  flagOff := SnapshotOf(FPainter.Bitmap);
  FreePainter;

  MakePainter(200, 60, 96);
  FPainter.DrawText(Rect(0, 0, 200, 60), 'Single', cMeasureFont, 12, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False, 3, False, True, 40);
  flagOn := SnapshotOf(FPainter.Bitmap);

  AssertEquals('multi-line mode changes nothing when there is no break',
    0, CountDifferingPixels(flagOff, flagOn));
end;

procedure TPainterTest.TestLineHeightTokenSetsTheDrawnLineBox;
{ The extra leading is a VISUAL value, so it comes from the theme — and it has to work in
  BOTH directions: a bigger line box spreads the block, a smaller one pulls it in. A floor
  hard-coded at the font's line box would pass the first half and fail the second. }
var
  tNat, bNat, rNat, tBig, bBig, rBig, tSmall, bSmall, rSmall: Integer;
begin
  MakePainter(200, 200, 96);
  FPainter.DrawText(Rect(0, 0, 200, 200), cTwoLines, cMeasureFont, 12, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False, 0, False, True, 0);
  InkRows(tNat, bNat, rNat);
  FreePainter;

  MakePainter(200, 200, 96);
  FPainter.DrawText(Rect(0, 0, 200, 200), cTwoLines, cMeasureFont, 12, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False, 0, False, True, 40);
  InkRows(tBig, bBig, rBig);
  FreePainter;

  MakePainter(200, 200, 96);
  FPainter.DrawText(Rect(0, 0, 200, 200), cTwoLines, cMeasureFont, 12, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False, 0, False, True, 6);
  InkRows(tSmall, bSmall, rSmall);

  AssertTrue('the natural line box inked two lines', rNat > 0);
  AssertTrue(Format('a 40px line box spreads the block (%d vs %d)',
    [bBig - tBig, bNat - tNat]), (bBig - tBig) > (bNat - tNat) + 8);
  AssertTrue(Format('a 6px line box pulls it in (%d vs %d)',
    [bSmall - tSmall, bNat - tNat]), (bSmall - tSmall) < (bNat - tNat));
end;

procedure TPainterTest.TestMeasureTextBlockCountsAuthoredLines;
{ The measurement a size floor is built from. Two identical lines make the arithmetic exact:
  the width cannot move at all and the height must exactly double. }
var
  w1, h1, w2, h2, wEmpty, hEmpty: Integer;
begin
  TyMeasureTextBlock('one', cMeasureFont, 12, 400, 96, 0, 0, w1, h1);
  AssertTrue('one line has width', w1 > 0);
  AssertTrue('one line has height', h1 > 0);

  TyMeasureTextBlock('one' + LineEnding + 'one', cMeasureFont, 12, 400, 96, 0, 0, w2, h2);
  AssertEquals('the widest line is the width, not the sum', w1, w2);
  AssertEquals('two lines are exactly twice as tall', h1 * 2, h2);

  { An empty caption still occupies a line — otherwise a control sized from this could be
    allowed to collapse to its padding the moment its caption is cleared. }
  TyMeasureTextBlock('', cMeasureFont, 12, 400, 96, 0, 0, wEmpty, hEmpty);
  AssertEquals('an empty caption measures no width', 0, wEmpty);
  AssertEquals('but still one line of height', h1, hEmpty);
end;

procedure TPainterTest.TestMeasureTextBlockLineHeightIsDerivedNotFloored;
{ "Override the CSS if you want it smaller" is only an honest answer while the height a
  theme asks for is really the height it gets — in both directions — and while a logical-px
  token still means logical px at 192 PPI. }
var
  w, hNat, h40, h6, h40Hi: Integer;
begin
  TyMeasureTextBlock(cTwoLines, cMeasureFont, 12, 400, 96, 0, 0, w, hNat);
  TyMeasureTextBlock(cTwoLines, cMeasureFont, 12, 400, 96, 0, 40, w, h40);
  TyMeasureTextBlock(cTwoLines, cMeasureFont, 12, 400, 96, 0, 6, w, h6);
  TyMeasureTextBlock(cTwoLines, cMeasureFont, 12, 400, 192, 0, 40, w, h40Hi);

  AssertEquals('two lines on a 40px line box', 80, h40);
  AssertTrue(Format('which is taller than the font own box (%d vs %d)', [h40, hNat]),
    h40 > hNat);
  AssertEquals('two lines on a 6px line box', 12, h6);
  AssertTrue(Format('which LOWERS the block (%d vs %d)', [h6, hNat]), h6 < hNat);
  AssertEquals('the token is logical px: it doubles at 192 PPI', 160, h40Hi);
end;

procedure TPainterTest.TestMeasureTextBlockWrapsToAWidth;
{ The wrap the measurement does is the same CJK-aware wrap the label draws with — a Chinese
  run has no spaces, so a width-unaware measurer would report one very wide line and the
  control would be sized for a line it never draws. }
const
  cCJK = '积压任务徽标挂在按钮上不是按钮内置的';
var
  wFull, hFull, wNarrow, hNarrow: Integer;
begin
  TyMeasureTextBlock(cCJK, cMeasureFont, 12, 400, 96, 0, 0, wFull, hFull);
  AssertTrue('unconstrained is one wide line', wFull > 0);

  TyMeasureTextBlock(cCJK, cMeasureFont, 12, 400, 96, wFull div 4, 0, wNarrow, hNarrow);
  AssertTrue(Format('wrapping to a quarter of the width folds it (%d vs %d)',
    [wNarrow, wFull]), wNarrow <= wFull div 4);
  AssertTrue(Format('and makes it at least three lines tall (%d vs %d)',
    [hNarrow, hFull]), hNarrow >= 3 * hFull);
end;

{ The Win32 text renderer draws every run on ONE kept GDI bitmap (it grows when a run
  needs more room) instead of a fresh TBitmap and a whole-bitmap conversion per run.
  From a fresh start (no kept bitmap): the first run makes it, 200 runs no wider than it
  keep the very same one, none gets a bitmap of its own, none is converted. The pixels
  are held by TestTheCoverageIsReadOffTheDib and tools/painter-regress. }
procedure TPainterTest.TestTheGdiRendererKeepsOneBitmap;
var
  made, own, conv, k, w, h: Integer;
  kept: THandle;
begin
  {$IFNDEF LCLWin32}
  Ignore('Win32 only: the other widgetsets draw text through BGRA');
  {$ENDIF}
  TyGdiTextResetForTest;
  made := TyGdiTextBitmapsMade;
  own := TyGdiTextOneOffBitmapsForTest;
  conv := TyGdiTextConversionsForTest;
  MakePainter(300, 60, 96);
  FPainter.DrawText(Rect(0, 0, 300, 60), 'Run 200 文字 text', 'Segoe UI', 10, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
  kept := TyGdiTextKeptBitmapForTest(w, h);
  AssertTrue('the first run made the kept bitmap', kept <> 0);
  AssertEquals('one made', 1, TyGdiTextBitmapsMade - made);
  for k := 1 to 200 do
    FPainter.DrawText(Rect(0, 0, 300, 60), 'Run ' + IntToStr(k) + ' 文字 text', 'Segoe UI', 10, 400,
      TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
  AssertTrue('200 runs on the same bitmap', kept = TyGdiTextKeptBitmapForTest(w, h));
  AssertEquals('none made or grown', 1, TyGdiTextBitmapsMade - made);
  AssertEquals('none drawn on a bitmap of its own', 0, TyGdiTextOneOffBitmapsForTest - own);
  AssertEquals('none converted: the coverage read off the DIB', 0, TyGdiTextConversionsForTest - conv);
end;

{ Every measurement used to make, select into and free a TBitmap of its own (BGRA's
  scratch: about a millisecond a call here). The renderer measures on one kept DC; the
  answer must be BGRA's own for every kind of run -- prefixes, tabs, right-to-left,
  wrapping to a width, CJK, a bold and a big font -- and a hundred measurements make one
  DC, not a hundred. }
procedure TPainterTest.TestTheKeptMeasuringDcAnswersAsBgraDoes;
const
  cRuns: array[0..9] of string = ('Axis label 12.5', '&Prefixed && run', 'tab'#9'bed',
    'مرحبا بالعالم', '中文标签 混排 text', 'Wwwwwiiiiil', '', ' ', 'a very long label that wraps when it is given a width',
    'emoji ☃ ✓');
  cFonts: array[0..2] of string = ('Segoe UI', 'Microsoft YaHei', 'Consolas');
var
  bmp: TBGRABitmap;
  i, j, k, made: Integer;
  a, b: TSize;
begin
  {$IFNDEF LCLWin32}
  Ignore('Win32 only: the other widgetsets measure through BGRA');
  {$ENDIF}
  TyGdiTextResetForTest;
  made := TyGdiTextKeptSurfacesMadeForTest;
  bmp := TBGRABitmap.Create(10, 10);
  try
    for j := 0 to High(cFonts) do
      for k := 0 to 2 do
      begin
        TyConfigureTextFont(bmp, cFonts[j], 9 + k * 7, 400 + (k mod 2) * 300, 96 + k * 48);
        for i := 0 to High(cRuns) do
        begin
          TyGdiTextBgraPathsForTest(True);
          try
            a := bmp.TextSize(cRuns[i]);
            b := bmp.TextSize(cRuns[i], 120, k = 1);
          finally
            TyGdiTextBgraPathsForTest(False);
          end;
          AssertEquals(Format('%s %d: "%s" wide', [cFonts[j], k, cRuns[i]]), a.cx, bmp.TextSize(cRuns[i]).cx);
          AssertEquals(Format('%s %d: "%s" high', [cFonts[j], k, cRuns[i]]), a.cy, bmp.TextSize(cRuns[i]).cy);
          AssertEquals(Format('%s %d: "%s" wrapped wide', [cFonts[j], k, cRuns[i]]), b.cx,
            bmp.TextSize(cRuns[i], 120, k = 1).cx);
          AssertEquals(Format('%s %d: "%s" wrapped high', [cFonts[j], k, cRuns[i]]), b.cy,
            bmp.TextSize(cRuns[i], 120, k = 1).cy);
        end;
      end;
  finally
    bmp.Free;
  end;
  AssertEquals('one kept DC for all of them', 1, TyGdiTextKeptSurfacesMadeForTest - made);
end;

{ A turned run went through BGRATextOutAngle, which makes a TBitmap to measure on and a
  BGRA bitmap with a DIB and a canvas to draw on, per run. The renderer does the same
  steps on two kept surfaces: the pixels must be BGRA's, exactly, at every angle, every
  alignment, fractional positions (the half-up rounding), translucent and light ink, and
  a run that wants a bigger surface than the last. }
procedure TPainterTest.TestATurnedRunOnTheKeptDibIsBgrasOwn;
const
  cRuns: array[0..3] of string = ('Rotated label', '中文 标签', 'ij', 'a much longer turned label, 42%');
var
  a, b: TBGRABitmap;
  i, ang, al, made, x, y, n: Integer;
  ink: TBGRAPixel;
  xf, yf: Single;

  procedure DrawOn(ABmp: TBGRABitmap; ABgra: Boolean);
  begin
    ABmp.Fill(BGRA(250, 250, 250, 255));
    TyConfigureTextFont(ABmp, 'Segoe UI', 10 + i * 3, 400 + (al mod 2) * 300, 96);
    TyGdiTextBgraPathsForTest(ABgra);
    try
      ABmp.TextOutAngle(xf, yf, ang, cRuns[i], ink, TAlignment(al), False);
    finally
      TyGdiTextBgraPathsForTest(False);
    end;
  end;

begin
  {$IFNDEF LCLWin32}
  Ignore('Win32 only: the other widgetsets draw turned text through BGRA');
  {$ENDIF}
  TyGdiTextResetForTest;
  made := TyGdiTextKeptSurfacesMadeForTest;
  a := TBGRABitmap.Create(400, 400);
  b := TBGRABitmap.Create(400, 400);
  try
    n := 0;
    for i := 0 to High(cRuns) do
      for al := 0 to 2 do
      begin
        ang := -3150 + i * 1170 + al * 450;
        xf := 200.3 + al * 0.25;
        yf := 199.6 - i * 0.375;
        case (i + al) mod 3 of
          0: ink := BGRA(20, 30, 40, 255);
          1: ink := BGRA(200, 20, 20, 140);
        else
          ink := BGRA(255, 255, 255, 255);
        end;
        DrawOn(a, False);
        DrawOn(b, True);
        for y := 0 to 399 do
          for x := 0 to 399 do
            if a.GetPixel(x, y) <> b.GetPixel(x, y) then
              Fail(Format('"%s" at %d tenths, align %d: pixel %d,%d differs', [cRuns[i], ang, al, x, y]));
        for y := 0 to 399 do
          for x := 0 to 399 do
            if a.GetPixel(x, y) <> BGRA(250, 250, 250, 255) then Inc(n);
      end;
    AssertTrue(Format('and something was drawn (%d pixels)', [n]), n > 1000);
    AssertTrue('on the kept surfaces', TyGdiTextKeptSurfacesMadeForTest - made >= 2);
    { the last, longest run grew the kept surfaces; drawing the first again makes none }
    made := TyGdiTextKeptSurfacesMadeForTest;
    i := 0; al := 0; ang := 450; xf := 200; yf := 200; ink := BGRA(0, 0, 0, 255);
    DrawOn(a, False);
    AssertEquals('no surface made for a smaller run', 0, TyGdiTextKeptSurfacesMadeForTest - made);
  finally
    a.Free;
    b.Free;
  end;
end;

{ A chart repaints the same labels on every hover frame, so the renderer keeps what each
  run came to -- its measurement, its coverage, a turned run's mask -- by everything that
  decides it. A frame drawn from what was kept must be the frame drawn afresh: the same
  strings in two sizes, dark and light ink (the coverage is taken in the ink's polarity),
  translucent ink, straight and turned at several angles and sub-pixel positions, drawn
  twice, against the same with the keeping off. }
procedure TPainterTest.TestAKeptRunPaintsAsAFreshOne;
const
  cRuns: array[0..2] of string = ('Label 12.5', '中文 标签', 'Wij');
var
  ref: TBGRABitmap;
  x, y, kept: Integer;

  procedure Paint;
  var
    i, k, pass: Integer;
    ink: TTyColor;
  begin
    FPainter.Bitmap.Fill(BGRA(120, 120, 120, 255));
    for pass := 0 to 1 do
      for i := 0 to High(cRuns) do
        for k := 0 to 3 do
        begin
          case (i + k + pass) mod 3 of
            0: ink := TyRGBA(10, 20, 30, 255);
            1: ink := TyRGBA(250, 250, 240, 255);
          else
            ink := TyRGBA(200, 30, 30, 120);
          end;
          FPainter.DrawText(Rect(10 + pass * 150, 10 + (i * 4 + k) * 22, 300 + pass * 150, 32 + (i * 4 + k) * 22),
            cRuns[i], 'Segoe UI', 9 + (k mod 2) * 5, 400 + (k div 2) * 300, ink,
            taLeftJustify, tlCenter, False);
          FPainter.DrawTextRotated(cRuns[i], 'Segoe UI', 9 + (k mod 2) * 5, 400, ink,
            320.3 + pass * 0.25 + k * 0.125, 60.6 + i * 110 + k * 0.375, (k + 1) * 0.6,
            TAlignment(k mod 3), tlCenter);
        end;
  end;

begin
  {$IFNDEF LCLWin32}
  Ignore('Win32 only: the other widgetsets draw text through BGRA');
  {$ENDIF}
  TyGdiTextResetForTest;
  TyGdiTextRunCacheForTest(False);
  try
    MakePainter(460, 300, 96);
    Paint;
    ref := FPainter.Bitmap.Duplicate as TBGRABitmap;
    FreePainter;
  finally
    TyGdiTextRunCacheForTest(True);
  end;
  try
    AssertEquals('nothing kept with the keeping off', 0, TyGdiTextRunsKeptForTest);
    MakePainter(460, 300, 96);
    Paint;
    kept := TyGdiTextRunsKeptForTest;
    AssertTrue(Format('runs were kept (%d)', [kept]), kept > 10);
    for y := 0 to 299 do
      for x := 0 to 459 do
        if FPainter.Bitmap.GetPixel(x, y) <> ref.GetPixel(x, y) then
          Fail(Format('pixel %d,%d differs from drawing every run afresh', [x, y]));
    Paint;
    AssertEquals('a second frame keeps nothing new', kept, TyGdiTextRunsKeptForTest);
  finally
    ref.Free;
  end;
end;

{ The comparisons above hold the kept surfaces to BGRA's own path, switched on by
  TyGdiTextBgraPathsForTest. If the switch stopped reaching the measuring branch or the
  turned branch, both sides of those comparisons would be the kept surfaces and every one
  of them would pass for nothing. So: after a reset, BGRA's own measuring and turned
  drawing make no kept surface; the same calls with the switch off make the two. }
procedure TPainterTest.TestBgrasOwnPathsTouchNoKeptSurface;
var
  bmp: TBGRABitmap;
  made: Integer;
begin
  {$IFNDEF LCLWin32}
  Ignore('Win32 only: the other widgetsets measure through BGRA');
  {$ENDIF}
  bmp := TBGRABitmap.Create(200, 200);
  try
    TyConfigureTextFont(bmp, 'Segoe UI', 12, 400, 96);
    TyGdiTextResetForTest;
    made := TyGdiTextKeptSurfacesMadeForTest;
    TyGdiTextBgraPathsForTest(True);
    try
      AssertTrue('measured', bmp.TextSize('Axis label 12.5').cx > 0);
      bmp.TextOutAngle(100, 100, 450, 'Turned label', BGRA(0, 0, 0, 255), taLeftJustify, False);
    finally
      TyGdiTextBgraPathsForTest(False);
    end;
    AssertEquals('BGRA''s own paths made no kept surface', 0,
      TyGdiTextKeptSurfacesMadeForTest - made);
    bmp.TextSize('Axis label 12.5');
    AssertEquals('the kept DC, with the switch off', 1, TyGdiTextKeptSurfacesMadeForTest - made);
    bmp.TextOutAngle(100, 100, 450, 'Turned label', BGRA(0, 0, 0, 255), taLeftJustify, False);
    AssertEquals('and the kept DIB', 2, TyGdiTextKeptSurfacesMadeForTest - made);
  finally
    bmp.Free;
  end;
end;

{ BGRA places a turned run's sub-pixel offset with HalfUp, and widens the box by a column
  when there is one. The test above draws at positions whose fractions are never exactly
  a half, so Round would have passed for HalfUp. Here the fraction IS a half (a quarter
  and three quarters turn and a half turn, whose sines and cosines leave x + 0.5 exactly),
  and a slightly turned italic run whose last letter leans past its advance reaches the
  column the offset added. }
procedure TPainterTest.TestATurnedRunOnAHalfPixelIsBgrasOwn;
const
  cAngles: array[0..4] of Integer = (1800, 900, 2700, 10, 3590);
var
  a, b: TBGRABitmap;
  k, x, y, n: Integer;

  procedure DrawOn(ABmp: TBGRABitmap; ABgra: Boolean);
  begin
    ABmp.Fill(BGRA(250, 250, 250, 255));
    TyConfigureTextFont(ABmp, 'Segoe UI', 40, 400, 96);
    ABmp.FontStyle := [fsItalic];
    TyGdiTextBgraPathsForTest(ABgra);
    try
      ABmp.TextOutAngle(200.5, 200.5, cAngles[k], 'Wff', BGRA(0, 0, 0, 255), taLeftJustify, False);
    finally
      TyGdiTextBgraPathsForTest(False);
    end;
  end;

begin
  {$IFNDEF LCLWin32}
  Ignore('Win32 only: the other widgetsets draw turned text through BGRA');
  {$ENDIF}
  TyGdiTextResetForTest;
  a := TBGRABitmap.Create(400, 400);
  b := TBGRABitmap.Create(400, 400);
  try
    for k := 0 to High(cAngles) do
    begin
      DrawOn(a, False);
      DrawOn(b, True);
      n := 0;
      for y := 0 to 399 do
        for x := 0 to 399 do
        begin
          if a.GetPixel(x, y) <> b.GetPixel(x, y) then
            Fail(Format('at %d tenths: pixel %d,%d differs', [cAngles[k], x, y]));
          if a.GetPixel(x, y) <> BGRA(250, 250, 250, 255) then Inc(n);
        end;
      AssertTrue(Format('at %d tenths something was drawn (%d)', [cAngles[k], n]), n > 200);
    end;
  finally
    a.Free;
    b.Free;
  end;
end;

{ A run drawn with its prefixes shown, or right to left, is measured with its own flags:
  the measurement kept for '&Prefixed && run' drawn plainly is not the one for the same
  text with its prefixes shown (the ampersands are gone), so a right-aligned run lands
  where BGRA lands it. Every combination, after the others, against BGRA's own path. }
procedure TPainterTest.TestAPrefixedOrRightToLeftRunIsMeasuredForItself;
const
  cRuns: array[0..2] of string = ('&Prefixed && run', 'AV, To. (1.5%) Wa', 'مرحبا (1) abc.');
var
  a, b: TBGRABitmap;
  x, y: Integer;

  procedure DrawOn(ABmp: TBGRABitmap; ABgra: Boolean);
  var
    i, k: Integer;
    st: TTextStyle;
  begin
    ABmp.Fill(BGRA(250, 250, 250, 255));
    TyConfigureTextFont(ABmp, 'Segoe UI', 14, 400, 96);
    TyGdiTextBgraPathsForTest(ABgra);
    try
      for i := 0 to High(cRuns) do
        for k := 0 to 3 do
        begin
          FillChar(st, SizeOf(st), 0);
          st.SingleLine := True;
          st.Alignment := taRightJustify;
          st.Layout := tlTop;
          st.ShowPrefix := (k and 1) <> 0;
          st.RightToLeft := (k and 2) <> 0;
          ABmp.TextRect(Rect(0, (i * 4 + k) * 24, 380, (i * 4 + k) * 24 + 24), 0, 0,
            cRuns[i], st, BGRA(0, 0, 0, 255));
        end;
    finally
      TyGdiTextBgraPathsForTest(False);
    end;
  end;

begin
  {$IFNDEF LCLWin32}
  Ignore('Win32 only: the other widgetsets measure through BGRA');
  {$ENDIF}
  TyGdiTextResetForTest;
  a := TBGRABitmap.Create(400, 300);
  b := TBGRABitmap.Create(400, 300);
  try
    DrawOn(a, False);
    DrawOn(b, True);
    for y := 0 to 299 do
      for x := 0 to 399 do
        if a.GetPixel(x, y) <> b.GetPixel(x, y) then
          Fail(Format('row %d: pixel %d,%d differs', [y div 24, x, y]));
  finally
    a.Free;
    b.Free;
  end;
end;

{ The kept surfaces copy BGRA's steps for the font: the canvas font back to the screen's
  PPI, Assign, then the pixel height set outright. The last step is the one that matters
  when the font being copied was born at another PPI than the screen's now -- Assign then
  carries the point size across, not the pixel height. With the renderer's font made at
  one screen PPI and the measuring and turning done at another, the kept surfaces must
  still answer as BGRA's fresh ones do. The kept runs are off: they would answer from
  before the change. }
procedure TPainterTest.TestTheKeptSurfacesAnswerAsBgraAtAnotherScreenPpi;
var
  a, b: TBGRABitmap;
  sx, sy, x, y: Integer;
  ka, kb: TSize;
begin
  {$IFNDEF LCLWin32}
  Ignore('Win32 only: the other widgetsets measure through BGRA');
  {$ENDIF}
  TyGdiTextResetForTest;
  TyGdiTextRunCacheForTest(False);
  sx := ScreenInfo.PixelsPerInchX;
  sy := ScreenInfo.PixelsPerInchY;
  a := TBGRABitmap.Create(300, 300);
  b := TBGRABitmap.Create(300, 300);
  try
    TyConfigureTextFont(a, 'Segoe UI', 13, 400, 96);
    TyConfigureTextFont(b, 'Segoe UI', 13, 400, 96);
    a.TextSize('x');
    b.TextSize('x');
    ScreenInfo.PixelsPerInchX := sx * 3 div 2;
    ScreenInfo.PixelsPerInchY := sy * 3 div 2;
    try
      a.Fill(BGRA(250, 250, 250, 255));
      b.Fill(BGRA(250, 250, 250, 255));
      TyGdiTextBgraPathsForTest(True);
      try
        kb := b.TextSize('Axis label 12.5');
        b.TextOutAngle(150.3, 150.6, 450, 'Turned label', BGRA(0, 0, 0, 255), taLeftJustify, False);
      finally
        TyGdiTextBgraPathsForTest(False);
      end;
      ka := a.TextSize('Axis label 12.5');
      a.TextOutAngle(150.3, 150.6, 450, 'Turned label', BGRA(0, 0, 0, 255), taLeftJustify, False);
    finally
      ScreenInfo.PixelsPerInchX := sx;
      ScreenInfo.PixelsPerInchY := sy;
    end;
    AssertEquals('as wide as BGRA measures it', kb.cx, ka.cx);
    AssertEquals('as high', kb.cy, ka.cy);
    for y := 0 to 299 do
      for x := 0 to 299 do
        if a.GetPixel(x, y) <> b.GetPixel(x, y) then
          Fail(Format('turned: pixel %d,%d differs', [x, y]));
  finally
    a.Free;
    b.Free;
    TyGdiTextRunCacheForTest(True);
    TyGdiTextResetForTest;
  end;
end;

{ What the runs keep is capped: past the byte cap everything kept is dropped (the memo's
  clear-not-evict), so a stream of big distinct runs never holds more than the cap. }
procedure TPainterTest.TestKeptRunsAreDroppedPastTheirCap;
var
  bmp: TBGRABitmap;
  i, n: Integer;
begin
  {$IFNDEF LCLWin32}
  Ignore('Win32 only: the other widgetsets draw text through BGRA');
  {$ENDIF}
  TyGdiTextResetForTest;
  bmp := TBGRABitmap.Create(100, 100);
  try
    TyConfigureTextFont(bmp, 'Segoe UI', 200, 400, 96);
    for i := 0 to 19 do
      bmp.TextOut(0, 0, StringOfChar('W', 30) + IntToStr(i), BGRA(0, 0, 0, 255));
    n := TyGdiTextRunsKeptForTest;
    AssertTrue(Format('some kept, and fewer than the 20 drawn (%d)', [n]), (n > 0) and (n < 20));
  finally
    bmp.Free;
    TyGdiTextResetForTest;
  end;
end;

{$IFDEF WINDOWS}
function AddFontMemResourceExForTest(pbFont: Pointer; cbFont: LongWord; pdv: Pointer;
  pcFonts: PLongWord): THandle; stdcall; external 'gdi32' name 'AddFontMemResourceEx';
function RemoveFontMemResourceExForTest(h: THandle): LongBool; stdcall;
  external 'gdi32' name 'RemoveFontMemResourceEx';
{$ENDIF}

{ Registering a font changes what its name measures, and TyInvalidateTextMeasureCache is
  how the library is told so: it must drop the kept measurements with everything else.
  The face is the bundled Lucide font under a name no other test registers (its name
  table rewritten in memory), so the name falls back to a default face before and is the
  icon font after. }
procedure TPainterTest.TestARegisteredFontIsMeasuredAfresh;
const
  cFace = 'tyq197';
var
  bmp: TBGRABitmap;
  ms: TMemoryStream;
  p: PByte;
  i, j, hits: Integer;
  h: THandle;
  count: LongWord;
  before, after, ref: TSize;
  s: string;
  wide: UnicodeString;
begin
  {$IFNDEF LCLWin32}
  Ignore('Win32 only: the other widgetsets measure through BGRA');
  {$ELSE}
  ms := TMemoryStream.Create;
  bmp := TBGRABitmap.Create(10, 10);
  try
    ms.LoadFromFile(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'assets' + PathDelim
      + 'lucide' + PathDelim + 'lucide.ttf');
    { the family name, in its one-byte and its UTF-16BE spellings }
    p := ms.Memory;
    hits := 0;
    wide := UnicodeString(cFace);
    for i := 0 to ms.Size - 12 do
    begin
      if CompareMem(p + i, PChar('lucide'), 6) then
      begin
        Move(PChar(cFace)^, (p + i)^, 6);
        Inc(hits);
      end
      else if (p[i] = 0) and (p[i + 1] = Ord('l')) and (p[i + 3] = Ord('u'))
        and (p[i + 5] = Ord('c')) and (p[i + 7] = Ord('i')) and (p[i + 9] = Ord('d'))
        and (p[i + 11] = Ord('e')) then
      begin
        for j := 0 to 5 do p[i + 1 + j * 2] := Ord(wide[j + 1]);
        Inc(hits);
      end;
    end;
    AssertTrue('the family name was found to rename', hits >= 2);
    TyGdiTextResetForTest;
    TyConfigureTextFont(bmp, cFace, 20, 400, 96);
    s := 'abc ' + #$EE#$96#$85;
    before := bmp.TextSize(s);
    count := 0;
    h := AddFontMemResourceExForTest(ms.Memory, ms.Size, nil, @count);
    AssertTrue('the face registered', h <> 0);
    try
      TyInvalidateTextMeasureCache;
      after := bmp.TextSize(s);
      TyGdiTextBgraPathsForTest(True);
      try
        ref := bmp.TextSize(s);
      finally
        TyGdiTextBgraPathsForTest(False);
      end;
      AssertTrue(Format('registering the face changed what it measures (%d -> %d)',
        [before.cx, ref.cx]), before.cx <> ref.cx);
      AssertEquals('measured afresh, as BGRA measures it', ref.cx, after.cx);
    finally
      RemoveFontMemResourceExForTest(h);
      TyInvalidateTextMeasureCache;
    end;
  finally
    bmp.Free;
    ms.Free;
  end;
  {$ENDIF}
end;

{ The kept bitmap grows in each direction on its own: a wide run of small text first
  (wide enough for what follows, not tall enough), then one very tall letter -- all of it
  drawn, not cut at the height the wide run left (nor read past the bitmap's end). }
procedure TPainterTest.TestTheKeptBitmapGrowsForATallerRun;
var
  top, bottom, rows, w, h: Integer;
begin
  {$IFNDEF LCLWin32}
  Ignore('Win32 only: the other widgetsets draw text through BGRA');
  {$ENDIF}
  TyGdiTextResetForTest;
  MakePainter(1400, 40, 96);
  FPainter.DrawText(Rect(0, 0, 1400, 40), StringOfChar('m', 150), 'Segoe UI', 8, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
  FreePainter;
  TyGdiTextKeptBitmapForTest(w, h);
  AssertTrue(Format('the wide run left a short bitmap (%d rows)', [h]), h < 250);
  MakePainter(1000, 900, 96);
  FPainter.DrawText(Rect(0, 0, 1000, 900), 'W', 'Segoe UI', 300, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
  InkRows(top, bottom, rows);
  AssertTrue(Format('the whole letter: %d rows of ink (%d..%d)', [rows, top, bottom]), rows >= 250);
end;

{ ...and only in the direction that is short: a tall letter after a wide run leaves the
  width as the wide run made it (it used to widen by half on every growth of the height,
  so a long line followed by a few big titles kept a bitmap of tens of megabytes). }
procedure TPainterTest.TestATallRunAfterAWideOneKeepsTheWidth;
var
  w0, h0, w1, h1: Integer;
begin
  {$IFNDEF LCLWin32}
  Ignore('Win32 only: the other widgetsets draw text through BGRA');
  {$ENDIF}
  TyGdiTextResetForTest;
  MakePainter(1400, 40, 96);
  FPainter.DrawText(Rect(0, 0, 1400, 40), StringOfChar('m', 150), 'Segoe UI', 8, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
  TyGdiTextKeptBitmapForTest(w0, h0);
  FPainter.DrawText(Rect(0, 0, 1400, 40), 'W', 'Segoe UI', 72, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
  TyGdiTextKeptBitmapForTest(w1, h1);
  AssertTrue(Format('taller (%d -> %d)', [h0, h1]), h1 > h0);
  AssertEquals('as wide as the wide run made it', w0, w1);
  FPainter.DrawText(Rect(0, 0, 1400, 40), 'W', 'Segoe UI', 200, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
  TyGdiTextKeptBitmapForTest(w1, h1);
  AssertEquals('still as wide after a second growth', w0, w1);
end;

{ A run too big to keep a bitmap for (wider than 8192 pixels here) is drawn on a bitmap
  of its own: the kept one stays as it was, and the run is still drawn. }
procedure TPainterTest.TestARunTooBigForTheKeptBitmapGetsItsOwn;
var
  own, w0, h0, w1, h1, top, bottom, rows: Integer;
  kept: THandle;
begin
  {$IFNDEF LCLWin32}
  Ignore('Win32 only: the other widgetsets draw text through BGRA');
  {$ENDIF}
  TyGdiTextResetForTest;
  MakePainter(400, 300, 96);
  FPainter.DrawText(Rect(0, 0, 400, 300), 'small', 'Segoe UI', 10, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlTop, False);
  kept := TyGdiTextKeptBitmapForTest(w0, h0);
  own := TyGdiTextOneOffBitmapsForTest;
  FreePainter;
  MakePainter(400, 300, 96);
  FPainter.DrawText(Rect(0, 0, 400, 300), StringOfChar('W', 60), 'Segoe UI', 120, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlTop, False);
  AssertEquals('drawn on a bitmap of its own', 1, TyGdiTextOneOffBitmapsForTest - own);
  AssertTrue('the kept bitmap is the same', kept = TyGdiTextKeptBitmapForTest(w1, h1));
  AssertEquals('same width', w0, w1);
  AssertEquals('same height', h0, h1);
  InkRows(top, bottom, rows);
  AssertTrue(Format('and the run was drawn (%d rows of ink)', [rows]), rows > 50);
end;

{ The kept bitmap holds the last run's ink: a long run of solid blocks, then a short run,
  must come out as the short one does on a fresh bitmap. }
procedure TPainterTest.TestTheKeptBitmapIsClearedBetweenRuns;
var
  a: TBGRABitmap;
  x, y, diff: Integer;
  p, q: TBGRAPixel;
  Blocks: string;
begin
  Blocks := '';
  for x := 1 to 40 do
    Blocks := Blocks + '█';
  {$IFNDEF LCLWin32}
  Ignore('Win32 only: the other widgetsets draw text through BGRA');
  {$ENDIF}
  TyGdiTextResetForTest;
  { drawn afresh every time: a kept run would never touch the kept bitmap }
  TyGdiTextRunCacheForTest(False);
  MakePainter(200, 60, 96);
  FPainter.DrawText(Rect(0, 0, 200, 60), 'ab 字', 'Segoe UI', 12, 400,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
  a := FPainter.Bitmap.Duplicate as TBGRABitmap;
  try
    { text, not a box: a bitmap never cleared is black, and black reads as full ink }
    diff := 0;
    for y := 0 to 59 do
      for x := 0 to 199 do
        if a.GetPixel(x, y).alpha > 0 then Inc(diff);
    AssertTrue(Format('the short run is drawn as text (%d inked pixels)', [diff]), (diff > 20) and (diff < 800));
    FreePainter;
    { solid ink where the small run's own part of the bitmap lies (the same size puts
      both runs' margins in the same place) }
    MakePainter(900, 60, 96);
    FPainter.DrawText(Rect(0, 0, 900, 60), Blocks, 'Segoe UI', 12, 700,
      TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
    FreePainter;
    MakePainter(200, 60, 96);
    FPainter.DrawText(Rect(0, 0, 200, 60), 'ab 字', 'Segoe UI', 12, 400,
      TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
    diff := 0;
    for y := 0 to 59 do
      for x := 0 to 199 do
      begin
        p := a.GetPixel(x, y);
        q := FPainter.Bitmap.GetPixel(x, y);
        if (p.red <> q.red) or (p.green <> q.green) or (p.blue <> q.blue) or (p.alpha <> q.alpha) then
          Inc(diff);
      end;
    AssertEquals('pixels left over from the big run', 0, diff);
  finally
    a.Free;
    TyGdiTextRunCacheForTest(True);
  end;
end;

{ The coverage read straight off the DIB is the coverage the whole conversion to BGRA
  gives (the old path, still the one for a bitmap that is not a DIB): every channel in
  the average, the rows in the DIB's order, the DIB's own row length. Several sizes and
  runs (CJK, a mnemonic ampersand, ligatures), byte for byte. }
procedure TPainterTest.TestTheCoverageIsReadOffTheDib;
const
  Runs: array[0..3] of string = ('Hamburgefonstiv 0123', '中文与 English 混排', 'W&M ag', 'ffi fl é');
  Sizes: array[0..2] of Integer = (8, 11, 23);
var
  a: TBGRABitmap;
  r, s, x, y, diff, conv, inked: Integer;
  p, q: TBGRAPixel;
begin
  {$IFNDEF LCLWin32}
  Ignore('Win32 only: the other widgetsets draw text through BGRA');
  {$ENDIF}
  for r := 0 to High(Runs) do
    for s := 0 to High(Sizes) do
    begin
      MakePainter(400, 80, 96);
      conv := TyGdiTextConversionsForTest;
      FPainter.DrawText(Rect(3, 0, 400, 80), Runs[r], 'Segoe UI', Sizes[s], 400,
        TyRGBA(20, 40, 60, 255), taLeftJustify, tlCenter, False);
      AssertEquals('read off the DIB', 0, TyGdiTextConversionsForTest - conv);
      a := FPainter.Bitmap.Duplicate as TBGRABitmap;
      try
        FreePainter;
        MakePainter(400, 80, 96);
        TyGdiTextForceConversionForTest(True);
        try
          FPainter.DrawText(Rect(3, 0, 400, 80), Runs[r], 'Segoe UI', Sizes[s], 400,
            TyRGBA(20, 40, 60, 255), taLeftJustify, tlCenter, False);
        finally
          TyGdiTextForceConversionForTest(False);
        end;
        AssertTrue('the other went through the conversion', TyGdiTextConversionsForTest - conv >= 1);
        diff := 0;
        inked := 0;
        for y := 0 to 79 do
          for x := 0 to 399 do
          begin
            p := a.GetPixel(x, y);
            q := FPainter.Bitmap.GetPixel(x, y);
            if p.alpha > 0 then Inc(inked);
            if (p.red <> q.red) or (p.green <> q.green) or (p.blue <> q.blue) or (p.alpha <> q.alpha) then
              Inc(diff);
          end;
        AssertTrue(Format('"%s" at %d pt: drawn at all', [Runs[r], Sizes[s]]), inked > 20);
        AssertEquals(Format('"%s" at %d pt: pixels that differ', [Runs[r], Sizes[s]]), 0, diff);
      finally
        a.Free;
        FreePainter;
      end;
    end;
end;

{ Every pixel, alpha included, of A and B. }
procedure AssertSamePixels(const AMsg: string; A, B: TBGRABitmap);
var
  x, y, diff: Integer;
  pa, pb: TBGRAPixel;
begin
  TAssert.AssertEquals(AMsg + ': width', B.Width, A.Width);
  TAssert.AssertEquals(AMsg + ': height', B.Height, A.Height);
  diff := 0;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
    begin
      pa := A.GetPixel(x, y);
      pb := B.GetPixel(x, y);
      if (pa.red <> pb.red) or (pa.green <> pb.green) or (pa.blue <> pb.blue)
         or (pa.alpha <> pb.alpha) then
        Inc(diff);
    end;
  TAssert.AssertEquals(AMsg + ': pixels that differ', 0, diff);
end;

{ A SHADOW IS RENDERED ONCE PER LOOK (TTyPainter.DropShadow).
  Each look is drawn with the cache off -- the reference, rendered the way every shadow
  always was -- and then with it on, and the two must be the same bytes. The looks are drawn
  in an order that makes the key matter: the first is kept, and every one after it differs
  from it in ONE thing the shadow depends on (the bitmap's size, the outline, the radius, the
  blur, the colour), so a key that left that thing out would hand back the first shadow.
  The offset is not in the key -- it is applied when the shadow is laid down -- so the look
  moved by an offset must come from the cache and still land where the reference does. One
  outline runs off the bitmap's edge, where the blur is cut off. }
procedure TPainterTest.TestAShadowIsRenderedOncePerLook;
type
  TLook = record
    W, H: Integer;
    R: TRect;
    Rad, Blur: Integer;
    C: TTyColor;
    Ofs: TPoint;
  end;

  function Look(AW, AH: Integer; const AR: TRect; ARad, ABlur: Integer; AC: TTyColor;
    const AOfs: TPoint): TLook;
  begin
    Result.W := AW; Result.H := AH; Result.R := AR; Result.Rad := ARad; Result.Blur := ABlur;
    Result.C := AC; Result.Ofs := AOfs;
  end;

  function Draw(const L: TLook; ACache: Boolean): TBGRABitmap;
  var
    saved: Boolean;
  begin
    saved := TyShadowCacheEnabled;
    TyShadowCacheEnabled := ACache;
    try
      MakePainter(L.W, L.H, 96);
      try
        FPainter.DropShadow(L.R, L.Rad, L.C, L.Blur, L.Ofs);
        Result := FPainter.Bitmap.Duplicate as TBGRABitmap;
      finally
        FreePainter;
      end;
    finally
      TyShadowCacheEnabled := saved;
    end;
  end;

  procedure Check(const AMsg: string; const L: TLook; AExpectRender: Boolean);
  var
    want, got: TBGRABitmap;
    before: Integer;
  begin
    want := Draw(L, False);
    before := TyShadowsRendered;
    got := Draw(L, True);
    try
      AssertSamePixels(AMsg, got, want);
      if AExpectRender then
        AssertEquals(AMsg + ': rendered, not taken from the cache', before + 1, TyShadowsRendered)
      else
        AssertEquals(AMsg + ': taken from the cache', before, TyShadowsRendered);
    finally
      want.Free;
      got.Free;
    end;
  end;

var
  base: TLook;
  shade: TTyColor;
begin
  TyClearShadowCache;
  shade := TyRGBA(0, 0, 0, 90);
  base := Look(160, 110, Rect(16, 14, 140, 92), 8, 10, shade, Point(0, 4));
  Check('the first look', base, True);
  Check('the same look again', base, False);
  Check('the same look at another offset', Look(160, 110, Rect(16, 14, 140, 92), 8, 10, shade,
    Point(3, -2)), False);
  Check('a bitmap of another size', Look(170, 110, Rect(16, 14, 140, 92), 8, 10, shade,
    Point(0, 4)), True);
  Check('another outline', Look(160, 110, Rect(20, 14, 140, 92), 8, 10, shade, Point(0, 4)), True);
  Check('another radius', Look(160, 110, Rect(16, 14, 140, 92), 3, 10, shade, Point(0, 4)), True);
  Check('another blur', Look(160, 110, Rect(16, 14, 140, 92), 8, 4, shade, Point(0, 4)), True);
  Check('another colour', Look(160, 110, Rect(16, 14, 140, 92), 8, 10, TyRGBA(200, 0, 0, 90),
    Point(0, 4)), True);
  Check('an outline off the edge', Look(160, 110, Rect(-6, 14, 150, 104), 8, 10, shade,
    Point(0, 4)), True);
  Check('no blur, and square', Look(160, 110, Rect(16, 14, 140, 92), 0, 0, shade, Point(0, 4)), True);
  Check('no blur, and square, again', Look(160, 110, Rect(16, 14, 140, 92), 0, 0, shade,
    Point(0, 4)), False);
end;

{ Writes a small picture with a different colour in each of its nine cells. }
function WriteNineCellPng(const APath: string): Boolean;
var
  b: TBGRABitmap;
  x, y: Integer;
begin
  b := TBGRABitmap.Create(9, 9);
  try
    for y := 0 to 8 do
      for x := 0 to 8 do
        b.SetPixel(x, y, BGRA(40 + 70 * (x div 3), 40 + 70 * (y div 3), 200, 255));
    b.SaveToFile(APath);
  finally
    b.Free;
  end;
  Result := FileExists(APath);
end;

{ A NINE-SLICE IMAGE IS READ ONCE. NineSlice read its file from disk on every paint; it now
  shares DrawImageFill's image cache. Drawn once, the file removed, drawn again: the second
  picture is the first. }
procedure TPainterTest.TestANineSliceImageIsReadOnce;
var
  path: string;
  first, second: TBGRABitmap;
begin
  path := GetTempDir(False) + 'ty_nineslice_' + IntToStr(GetProcessID) + '_'
    + IntToStr(GetTickCount64) + '.png';
  AssertTrue('precondition: the picture was written', WriteNineCellPng(path));
  MakePainter(60, 40, 96);
  try
    FPainter.NineSlice(Rect(0, 0, 60, 40), path, Rect(3, 3, 3, 3), False);
    first := FPainter.Bitmap.Duplicate as TBGRABitmap;
  finally
    FreePainter;
  end;
  try
    AssertTrue('precondition: the slices were drawn', first.GetPixel(30, 20).alpha = 255);
    AssertTrue('precondition: the file is gone', DeleteFile(path));
    MakePainter(60, 40, 96);
    try
      FPainter.NineSlice(Rect(0, 0, 60, 40), path, Rect(3, 3, 3, 3), False);
      second := FPainter.Bitmap.Duplicate as TBGRABitmap;
    finally
      FreePainter;
    end;
    try
      AssertSamePixels('the second paint, without the file', second, first);
    finally
      second.Free;
    end;
  finally
    first.Free;
  end;
end;

{ AN IMAGE FILL IS SERVED WITHOUT THE DISK. The image cache asked the file system whether the
  file existed before it looked in the cache, on every paint; it now looks first. Drawn once,
  the file removed, drawn again: the cached picture is still drawn. }
procedure TPainterTest.TestAnImageFillIsServedWithoutTheDisk;
var
  path: string;
  fill: TTyFill;
  first, second: TBGRABitmap;
begin
  path := GetTempDir(False) + 'ty_imagefill_' + IntToStr(GetProcessID) + '_'
    + IntToStr(GetTickCount64) + '.png';
  AssertTrue('precondition: the picture was written', WriteNineCellPng(path));
  FillChar(fill, SizeOf(fill), 0);
  fill.Kind := tfkImage;
  fill.ImagePath := path;
  fill.ImageMode := timStretch;
  MakePainter(45, 45, 96);
  try
    FPainter.FillBackground(Rect(0, 0, 45, 45), fill, 0);
    first := FPainter.Bitmap.Duplicate as TBGRABitmap;
  finally
    FreePainter;
  end;
  try
    AssertTrue('precondition: the picture was drawn', first.GetPixel(22, 22).alpha = 255);
    AssertTrue('precondition: the file is gone', DeleteFile(path));
    MakePainter(45, 45, 96);
    try
      FPainter.FillBackground(Rect(0, 0, 45, 45), fill, 0);
      second := FPainter.Bitmap.Duplicate as TBGRABitmap;
    finally
      FreePainter;
    end;
    try
      AssertSamePixels('the second paint, without the file', second, first);
    finally
      second.Free;
    end;
  finally
    first.Free;
  end;
end;

{ ---- the ellipsis fit DrawText and the grid share (#18) ---- }

type
  TEllipsisFitTest = class(TTestCase)
  published
    procedure TestTheFitIsTheOneAtATimeCut;
    procedure TestAMultiLineTextShowsItsFirstLine;
    procedure TestAHugeTextIsDrawnQuickly;
  end;

{ The cut as it was made before #18: one codepoint at a time, re-measuring the rest each time.
  Quadratic, but its answers are the reference -- the bounded search must give the same ones. }
function OneAtATimeFit(ABmp: TBGRABitmap; const AText: string; AW: Integer): string;
var
  n: Integer;
  sz: TSize;
begin
  Result := AText;
  if AText = '' then Exit;
  n := UTF8Length(Result);
  sz := ABmp.TextSize(Result);
  while (n > 1) and (sz.cx > AW) do
  begin
    Dec(n);
    Result := TyEllipsisPrefix(AText, n);
    sz := ABmp.TextSize(Result + '...');
  end;
  if Result <> AText then Result := Result + '...';
end;

procedure TEllipsisFitTest.TestTheFitIsTheOneAtATimeCut;
const
  TEXTS: array[0..8] of string = ('Hello', 'Try it in the preview', 'Show hidden files',
    '中文标题测试一下', 'Mixed 中英 text here', 'a', 'ab',
    'WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW', 'iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii');
  FONTS: array[0..1] of string = ('Arial', 'Microsoft YaHei UI');
  { Too narrow for anything, a few glyphs, and the widths where these captions get cut. }
  WIDTHS: array[0..13] of Integer = (0, 1, 5, 10, 20, 30, 45, 60, 80, 100, 130, 160, 200, 240);
var
  bmp: TBGRABitmap;
  f, i, k: Integer;
  want, got: string;
begin
  bmp := TBGRABitmap.Create(1, 1);
  try
    for f := Low(FONTS) to High(FONTS) do
    begin
      TyConfigureTextFont(bmp, FONTS[f], 9, 400, 96);
      for i := Low(TEXTS) to High(TEXTS) do
      begin
        for k := Low(WIDTHS) to High(WIDTHS) do
        begin
          want := OneAtATimeFit(bmp, TEXTS[i], WIDTHS[k]);
          got := TyEllipsisFit(bmp, TEXTS[i], WIDTHS[k]);
          AssertEquals(Format('%s, "%s" in %d px', [FONTS[f], TEXTS[i], WIDTHS[k]]), want, got);
        end;
      end;
    end;
  finally
    bmp.Free;
  end;
end;

{ BGRA strips CR/LF before it measures or draws, so a multi-line text drawn on one line used to
  come out with its lines glued together. One line now shows its first line, and says there is
  more. }
procedure TEllipsisFitTest.TestAMultiLineTextShowsItsFirstLine;
var
  bmp: TBGRABitmap;
  s: string;
begin
  AssertEquals('the shown line of a multi-line text', 'First...',
    TySingleLineText('First' + #13#10 + 'Second'));
  AssertEquals('a text without a break is itself', 'First', TySingleLineText('First'));
  bmp := TBGRABitmap.Create(1, 1);
  try
    TyConfigureTextFont(bmp, 'Arial', 9, 400, 96);
    AssertEquals('room for it all: the first line and the ellipsis', 'First...',
      TyEllipsisFit(bmp, 'First' + #13#10 + 'Second', 400));
    AssertEquals('a bare LF counts too', 'First...', TyEllipsisFit(bmp, 'First' + #10 + 'Second', 400));
    AssertEquals('a text that starts with a break shows the ellipsis alone', '...',
      TyEllipsisFit(bmp, #10 + 'Second', 400));
    s := TyEllipsisFit(bmp, 'A first line long enough to need cutting' + #10 + 'x', 60);
    AssertTrue('narrow: a shorter prefix of the first line, with the ellipsis: ' + s,
      (Pos('...', s) = Length(s) - 2) and (Pos('A first', s) = 1) and (Pos('x', s) = 0));
  finally
    bmp.Free;
  end;
end;

{ A 300-line script in a tree cell froze the tree: the old cut re-measured the whole remaining
  text once per codepoint. Both shapes now cost about a dozen measurements of strings no longer
  than the cell can show. The bound is generous on purpose; the old cut took far longer. }
procedure TEllipsisFitTest.TestAHugeTextIsDrawnQuickly;
var
  host: TBitmap;
  p: TTyPainter;
  lines, one: string;
  i: Integer;
  t0, took: QWord;
begin
  lines := '';
  one := '';
  for i := 1 to 300 do
  begin
    lines := lines + Format('line %d: if value > limit then report(value, ''too high'');', [i]);
    one := one + Format('part %d of a very long single line of text ', [i]);
    if i < 300 then lines := lines + #13#10;
  end;
  AssertTrue('precondition: about 12k characters each', (Length(lines) > 10000) and (Length(one) > 10000));
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(220, 40);
    p.BeginPaint(host.Canvas, Rect(0, 0, 220, 40), 96);
    t0 := GetTickCount64;
    p.DrawText(Rect(0, 0, 200, 20), lines, 'Arial', 9, 400, TyRGB(0, 0, 0), taLeftJustify,
      tlCenter, True);
    p.DrawText(Rect(0, 20, 200, 40), one, 'Arial', 9, 400, TyRGB(0, 0, 0), taLeftJustify,
      tlCenter, True);
    { The grid's cell fit is the same function; ask it too, so a grid that went back to its own
      loop would show here. }
    TyGridEllipsisFit(p.Bitmap, one, 200);
    TyGridEllipsisFit(p.Bitmap, lines, 200);
    took := GetTickCount64 - t0;
    p.EndPaint;
    AssertTrue(Format('the 12k-character texts ellipsised in %d ms', [took]), took < 1000);
  finally
    p.Free;
    host.Free;
  end;
end;

initialization
  RegisterTest(TEllipsisFitTest);
  RegisterTest(TPainterTest);

end.
