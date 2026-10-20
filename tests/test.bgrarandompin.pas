unit test.bgrarandompin;
{$mode objfpc}{$H+}
{ [R2-H] THE CONTROLS THAT DRAW STRAIGHT ON A BITMAP'S Canvas2D pin BGRA's
  generator as the painter does (spec 211).

  BGRA's one-pass polygon filler sorts a polygon's edges with a quicksort
  whose pivot is the global Random; on a long path (more than ten points) the
  antialiased coverage of a row or two then depends on whatever the
  application's generator holds -- the same chart painted twice differs. The
  painter pins it around its own fill, stroke and clip; the twenty-odd
  controls that called their Canvas2D's fill / stroke / clip themselves did
  not. They go through TyCtxFill / TyCtxStroke / TyCtxClip now.

  Each test paints under eight global seeds and wants the same pixels: the
  wrappers on a bare bitmap, and a line chart of 300 points (its data the one
  of six streams tried that differed most unpinned: 3019 pixels over the seven
  repaints).

  [r2v] The bare paint's own fill and clip are a closed zigzag and two
  loops: shapes whose edges never tie on a row, so a fill or a clip left
  unpinned painted the same under every seed. A stroke's outline is where the
  ties are (its joins overlap): the fill and the clip of the bare paint's two
  stroke outlines are tested on their own, each with a control that the same
  paint unpinned does differ. }
interface
uses Classes, SysUtils, Graphics, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes, BGRACanvas2D, BGRAPen,
     tyControls.Painter, tyControls.Chart;
type
  TBgraRandomPinTest = class(TTestCase)
  published
    procedure TestTheCanvas2DWrappersPaintTheSameWhateverTheGlobalRandomHolds;
    procedure TestALongChartLinePaintsTheSameWhateverTheGlobalRandomHolds;
    procedure TestAFillOfAStrokesOutlinePaintsTheSameWhateverTheGlobalRandomHolds;
    procedure TestAClipToAStrokesOutlinePaintsTheSameWhateverTheGlobalRandomHolds;
  end;

implementation

type
  { RenderTo is protected: the headless render the tests use elsewhere }
  TChartOpen = class(TTyChart);

const
  cSeeds: array[0..7] of LongWord = (1, 2, 3, 99, 12345, $DEADBEEF, 7, 31337);

{ the test's own numbers: a linear congruential stream, not the global one }
function Lcg(var AState: LongWord): Double;
begin
  {$push}{$R-}{$Q-}
  AState := AState * 1664525 + 1013904223;
  {$pop}
  Result := (AState shr 8) / 16777216;
end;

{ 300 points across 800 px, up and down: a long path of many edges on the
  same rows }
procedure Zigzag(ACtx: TBGRACanvas2D; ASeed: LongWord; AClose: Boolean; ANew: Boolean = True);
var
  s: LongWord;
  i: Integer;
  x, y: Double;
begin
  s := ASeed;
  if ANew then ACtx.beginPath;
  for i := 0 to 299 do
  begin
    x := 10 + i * 780 / 299;
    y := 40 + Lcg(s) * 420;
    if i = 0 then ACtx.moveTo(x, y) else ACtx.lineTo(x, y);
  end;
  if AClose then ACtx.closePath;
end;

function PixelsDiffer(A, B: TBGRABitmap): Integer;
var
  i: Integer;
  pa, pb: PBGRAPixel;
begin
  Result := 0;
  if (A.Width <> B.Width) or (A.Height <> B.Height) then Exit(MaxInt);
  pa := A.Data;
  pb := B.Data;
  for i := 0 to A.NbPixels - 1 do
  begin
    if LongWord(pa^) <> LongWord(pb^) then Inc(Result);
    Inc(pa);
    Inc(pb);
  end;
end;

function TBgraRandomPinTestPaintBare(ASeed: LongWord): TBGRABitmap;
var
  ctx: TBGRACanvas2D;
begin
  Result := TBGRABitmap.Create(800, 500, BGRA(255, 255, 255, 255));
  ctx := Result.Canvas2D;
  RandSeed := ASeed;
  ctx.lineWidth := 2;
  ctx.lineJoin := 'bevel';
  ctx.strokeStyle(BGRA(84, 112, 198, 255));
  Zigzag(ctx, 1, False);
  TyCtxStroke(ctx);
  ctx.strokeStyle(BGRA(200, 60, 40, 255));
  Zigzag(ctx, 3, False);
  TyCtxStroke(ctx);
  ctx.fillStyle(BGRA(200, 60, 40, 110));
  Zigzag(ctx, 2, True);
  TyCtxFill(ctx);
  { a clip that winds twice where the two loops overlap }
  ctx.save;
  Zigzag(ctx, 9, True);
  Zigzag(ctx, 11, True, False);
  TyCtxClip(ctx);
  ctx.fillStyle(BGRA(20, 160, 60, 90));
  ctx.fillRect(0, 0, 800, 500);
  ctx.restore;
end;

{ the outline a canvas' stroke fills for the bare paint's zigzag (width 2,
  bevelled, butt): one polygon whose edges overlap at every join }
procedure StrokeOutline(ACtx: TBGRACanvas2D; ASeed: LongWord);
var
  s: LongWord;
  i: Integer;
  line, wide: ArrayOfTPointF;
  fresh: Boolean;
  stroker: TBGRAPenStroker;
begin
  s := ASeed;
  SetLength(line, 300);
  for i := 0 to 299 do
    line[i] := PointF(10 + i * 780 / 299, 40 + Lcg(s) * 420);
  stroker := TBGRAPenStroker.Create;
  try
    stroker.JoinStyle := pjsBevel;
    stroker.LineCap := pecFlat;
    wide := stroker.ComputePolylineAutocycle(line, 2);
  finally
    stroker.Free;
  end;
  ACtx.beginPath;
  fresh := True;
  for i := 0 to High(wide) do
    if isEmptyPointF(wide[i]) then fresh := True
    else if fresh then
    begin
      ACtx.moveTo(wide[i]);
      fresh := False;
    end
    else ACtx.lineTo(wide[i]);
  ACtx.closePath;
end;

{ AClip: the outline clips a translucent fill of the whole bitmap, else it
  is filled translucent itself; APinned: through the wrapper, else straight }
function PaintOutline(ASeed: LongWord; AClip, APinned: Boolean): TBGRABitmap;
var
  ctx: TBGRACanvas2D;
  k: Integer;
begin
  Result := TBGRABitmap.Create(800, 500, BGRA(255, 255, 255, 255));
  ctx := Result.Canvas2D;
  RandSeed := ASeed;
  if AClip then
  begin
    for k := 0 to 1 do
    begin
      ctx.save;
      StrokeOutline(ctx, 1 + 2 * k);
      if APinned then TyCtxClip(ctx) else ctx.clip;
      ctx.fillStyle(BGRA(20, 160, 60, 140));
      ctx.fillRect(0, 0, 800, 500);
      ctx.restore;
    end;
  end
  else
  begin
    ctx.fillStyle(BGRA(40, 40, 160, 140));
    for k := 0 to 1 do
    begin
      StrokeOutline(ctx, 1 + 2 * k);
      if APinned then TyCtxFill(ctx) else ctx.fill;
    end;
  end;
end;

{ every seed's paint against the first: the pixels that differ, summed }
function OutlineSeedsDiffer(AClip, APinned: Boolean): Integer;
var
  ref, b: TBGRABitmap;
  k: Integer;
begin
  Result := 0;
  ref := PaintOutline(cSeeds[0], AClip, APinned);
  try
    for k := 1 to High(cSeeds) do
    begin
      b := PaintOutline(cSeeds[k], AClip, APinned);
      try
        Inc(Result, PixelsDiffer(ref, b));
      finally
        b.Free;
      end;
    end;
  finally
    ref.Free;
  end;
end;

procedure TBgraRandomPinTest.TestAFillOfAStrokesOutlinePaintsTheSameWhateverTheGlobalRandomHolds;
begin
  AssertTrue('the control: unpinned, the fill differs under some seed',
    OutlineSeedsDiffer(False, False) > 0);
  AssertEquals('pinned: pixels that differ from the first seed''s', 0,
    OutlineSeedsDiffer(False, True));
end;

procedure TBgraRandomPinTest.TestAClipToAStrokesOutlinePaintsTheSameWhateverTheGlobalRandomHolds;
begin
  AssertTrue('the control: unpinned, the clip differs under some seed',
    OutlineSeedsDiffer(True, False) > 0);
  AssertEquals('pinned: pixels that differ from the first seed''s', 0,
    OutlineSeedsDiffer(True, True));
end;

procedure TBgraRandomPinTest.TestTheCanvas2DWrappersPaintTheSameWhateverTheGlobalRandomHolds;
var
  ref, b: TBGRABitmap;
  k, diff: Integer;
begin
  ref := TBgraRandomPinTestPaintBare(cSeeds[0]);
  try
    for k := 1 to High(cSeeds) do
    begin
      b := TBgraRandomPinTestPaintBare(cSeeds[k]);
      try
        diff := PixelsDiffer(ref, b);
        AssertEquals(Format('seed %d: pixels that differ from the first paint', [cSeeds[k]]), 0, diff);
      finally
        b.Free;
      end;
    end;
  finally
    ref.Free;
  end;
end;

function RenderChart(ASeed: LongWord): TBGRABitmap;
var
  ch: TTyChart;
  bmp: TBitmap;
  s: LongWord;
  i: Integer;
  vals, sep: string;
begin
  ch := TTyChart.Create(nil);
  bmp := TBitmap.Create;
  try
    ch.Font.PixelsPerInch := 96;
    ch.SetBounds(0, 0, 800, 500);
    s := 4;
    vals := '';
    sep := '';
    for i := 0 to 299 do
    begin
      vals := vals + sep + IntToStr(Round(Lcg(s) * 1000));
      sep := ',';
    end;
    with ch.Series.Add do Values := vals;
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(800, 500);
    RandSeed := ASeed;
    TChartOpen(ch).RenderTo(bmp.Canvas, Rect(0, 0, 800, 500), 96);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
    ch.Free;
  end;
end;

procedure TBgraRandomPinTest.TestALongChartLinePaintsTheSameWhateverTheGlobalRandomHolds;
var
  ref, b: TBGRABitmap;
  k: Integer;
begin
  ref := RenderChart(cSeeds[0]);
  try
    for k := 1 to High(cSeeds) do
    begin
      b := RenderChart(cSeeds[k]);
      try
        AssertEquals(Format('seed %d: pixels that differ from the first paint', [cSeeds[k]]), 0,
          PixelsDiffer(ref, b));
      finally
        b.Free;
      end;
    end;
  finally
    ref.Free;
  end;
end;

initialization
  RegisterTest(TBgraRandomPinTest);
end.
