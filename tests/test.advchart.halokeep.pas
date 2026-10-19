unit test.advchart.halokeep;
{$mode objfpc}{$H+}
{ [R2-P] A label's halo, kept.

  F4c's true-outline halo draws a label's glyphs on a mask, traces their
  outline with marching squares and strokes it; that made text-heavy charts
  two to four times slower to a first frame and every hover frame repaid it.
  Three things changed, and none of them may change a pixel:

  - the trace walks only the box round the ink, reading the alpha once
    (TestTheTraceIsTheWholeMaskWalk holds it to the old whole-mask walk,
    written out here, on text, noise, ink on every border and the empty and
    full masks);
  - the traced outline is kept by everything that shapes the mask
    (TestTheKeyHoldsWhatShapesTheMask: each input moved alone is a new trace,
    a whole-pixel move is not; TestAFontChangeDropsTheOutlines: the painter's
    text generation moving drops them);
  - the stroke's fill is kept as the brush calls it made, and replayed
    through the stroke's own brush (TestAKeptStrokeIsTheStrokeItReplays: on
    translucent ink, under an element alpha, in another colour, the global
    Random left as a fill leaves it, and a clip that the replay does not
    model stroking afresh).

  TestAKeptHaloPaintsAsAFreshOne draws captions and rich pieces of every
  kind with everything kept and with nothing kept, at 1x and at the 2x
  device scale (#83), and TestARepaintTracesAndFillsNothing is the guard
  that does not read a clock: a chart's first frame traces each haloed
  label once, and a repaint traces none and fills none. }
interface

uses Classes, SysUtils, Math, Types, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Painter, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Render, tyControls.AdvanceChart;

type
  THkChart = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartHaloKeepTest = class(TTestCase)
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheTraceIsTheWholeMaskWalk;
    procedure TestAKeptHaloPaintsAsAFreshOne;
    procedure TestTheKeyHoldsWhatShapesTheMask;
    procedure TestAFontChangeDropsTheOutlines;
    procedure TestAKeptStrokeIsTheStrokeItReplays;
    procedure TestARepaintTracesAndFillsNothing;
  end;

implementation

const
  cW = 360;
  cH = 240;

procedure THkChart.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function THkChart.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TAdvChartHaloKeepTest.SetUp;
begin
  inherited SetUp;
  TyAdvChartHaloCacheForTest(True);
  TyPainterKeptStrokesForTest(True);
end;

procedure TAdvChartHaloKeepTest.TearDown;
begin
  TyAdvChartHaloCacheForTest(True);
  TyPainterKeptStrokesForTest(True);
  inherited TearDown;
end;

{ ---------------------------------------------------------------- helpers }

var
  GLcg: LongWord;

function Lcg(AMax: Integer): Integer;
begin
  {$push}{$R-}{$Q-}
  GLcg := GLcg * 1664525 + 1013904223;
  {$pop}
  Result := Integer((GLcg shr 8) mod LongWord(AMax));
end;

{ a ground the halo's blending shows on: no two neighbours alike }
procedure Ground(B: TBGRABitmap);
var
  x, y: Integer;
  p: PBGRAPixel;
begin
  for y := 0 to B.Height - 1 do
  begin
    p := B.ScanLine[y];
    for x := 0 to B.Width - 1 do
    begin
      p^ := BGRA((x * 7 + y) and 255, (y * 5 + 40) and 255, ((x + y) * 3) and 255, 255);
      Inc(p);
    end;
  end;
  B.InvalidateBitmap;
end;

function DiffPixels(A, B: TBGRABitmap): Integer;
var
  i: Integer;
  pa, pb: PLongWord;
begin
  if (A.Width <> B.Width) or (A.Height <> B.Height) then Exit(MaxInt);
  Result := 0;
  pa := PLongWord(A.Data);
  pb := PLongWord(B.Data);
  for i := 0 to A.NbPixels - 1 do
  begin
    if pa^ <> pb^ then Inc(Result);
    Inc(pa);
    Inc(pb);
  end;
end;

function SameBits(const A, B: TTyDoubleArray): Boolean;
begin
  Result := (Length(A) = Length(B))
    and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A) * SizeOf(Double)));
end;

{ THE OLD TRACE, as F4c wrote it (7c52fa54): marching squares over the whole
  mask, a GetPixel per corner; the contours out as TyTraceMaskOutlineForTest
  gives them (per contour its point count, then x, y), the origin at 0 }
function RefTrace(AMask: TBGRABitmap; AScale: Integer): TTyDoubleArray;
const
  cT = 127.5;
var
  w, h, gw, gh, nKeys, cx, cy, i, k, cur, seg, startKey, key, nSeg, n, j: Integer;
  ex, ey: array of Double;
  segA, segB: array of Integer;
  adj: array of Integer;
  used: array of Boolean;
  v0, v1, v2, v3, centre: Double;
  b0, b1, b2, b3: Boolean;
  kTop, kRight, kBottom, kLeft: Integer;
  px, py: array of Double;
  np: Integer;

  function A(AX, AY: Integer): Double;
  begin
    if (AX < 0) or (AY < 0) or (AX >= w) or (AY >= h) then Exit(0);
    Result := AMask.GetPixel(AX, AY).alpha;
  end;

  function KeyH(AX, AY: Integer): Integer;
  begin
    Result := ((AY + 1) * gw + (AX + 1)) * 2;
  end;

  function KeyV(AX, AY: Integer): Integer;
  begin
    Result := ((AY + 1) * gw + (AX + 1)) * 2 + 1;
  end;

  procedure Cross(AKey: Integer; AX0, AY0, AV0, AX1, AY1, AV1: Double);
  var t: Double;
  begin
    if AV1 = AV0 then t := 0.5 else t := (cT - AV0) / (AV1 - AV0);
    ex[AKey] := AX0 + (AX1 - AX0) * t + 0.5;
    ey[AKey] := AY0 + (AY1 - AY0) * t + 0.5;
  end;

  procedure Seg2(AK0, AK1: Integer);
  begin
    if nSeg > High(segA) then
    begin
      SetLength(segA, Length(segA) * 2 + 16);
      SetLength(segB, Length(segA));
    end;
    segA[nSeg] := AK0;
    segB[nSeg] := AK1;
    if adj[AK0 * 2] < 0 then adj[AK0 * 2] := nSeg else adj[AK0 * 2 + 1] := nSeg;
    if adj[AK1 * 2] < 0 then adj[AK1 * 2] := nSeg else adj[AK1 * 2 + 1] := nSeg;
    Inc(nSeg);
  end;

begin
  Result := nil;
  w := AMask.Width;
  h := AMask.Height;
  gw := w + 2;
  gh := h + 2;
  nKeys := gw * gh * 2;
  SetLength(ex, nKeys);
  SetLength(ey, nKeys);
  SetLength(adj, nKeys * 2);
  for i := 0 to High(adj) do adj[i] := -1;
  nSeg := 0;
  for cy := -1 to h - 1 do
    for cx := -1 to w - 1 do
    begin
      v0 := A(cx, cy);
      v1 := A(cx + 1, cy);
      v2 := A(cx + 1, cy + 1);
      v3 := A(cx, cy + 1);
      b0 := v0 >= cT;
      b1 := v1 >= cT;
      b2 := v2 >= cT;
      b3 := v3 >= cT;
      if (b0 = b1) and (b1 = b2) and (b2 = b3) then Continue;
      kTop := KeyH(cx, cy);
      kBottom := KeyH(cx, cy + 1);
      kLeft := KeyV(cx, cy);
      kRight := KeyV(cx + 1, cy);
      if b0 <> b1 then Cross(kTop, cx, cy, v0, cx + 1, cy, v1);
      if b1 <> b2 then Cross(kRight, cx + 1, cy, v1, cx + 1, cy + 1, v2);
      if b3 <> b2 then Cross(kBottom, cx, cy + 1, v3, cx + 1, cy + 1, v2);
      if b0 <> b3 then Cross(kLeft, cx, cy, v0, cx, cy + 1, v3);
      if (b0 = b2) and (b1 = b3) and (b0 <> b1) then
      begin
        centre := (v0 + v1 + v2 + v3) / 4;
        if (centre >= cT) = b0 then
        begin
          Seg2(kTop, kRight);
          Seg2(kBottom, kLeft);
        end
        else
        begin
          Seg2(kLeft, kTop);
          Seg2(kRight, kBottom);
        end;
        Continue;
      end;
      k := -1;
      cur := -1;
      if b0 <> b1 then begin if k < 0 then k := kTop else cur := kTop; end;
      if b1 <> b2 then begin if k < 0 then k := kRight else cur := kRight; end;
      if b3 <> b2 then begin if k < 0 then k := kBottom else cur := kBottom; end;
      if b0 <> b3 then begin if k < 0 then k := kLeft else cur := kLeft; end;
      if (k >= 0) and (cur >= 0) then Seg2(k, cur);
    end;
  if nSeg = 0 then Exit;
  SetLength(used, nSeg);
  for i := 0 to nSeg - 1 do used[i] := False;
  n := 0;
  for i := 0 to nSeg - 1 do
  begin
    if used[i] then Continue;
    used[i] := True;
    startKey := segA[i];
    np := 1;
    SetLength(px, 16);
    SetLength(py, 16);
    px[0] := ex[startKey] / AScale + 0;
    py[0] := ey[startKey] / AScale + 0;
    key := segB[i];
    while key <> startKey do
    begin
      if np > High(px) then
      begin
        SetLength(px, Length(px) * 2);
        SetLength(py, Length(px));
      end;
      px[np] := ex[key] / AScale + 0;
      py[np] := ey[key] / AScale + 0;
      Inc(np);
      seg := adj[key * 2];
      if (seg < 0) or used[seg] then seg := adj[key * 2 + 1];
      if (seg < 0) or used[seg] then Break;
      used[seg] := True;
      if segA[seg] = key then key := segB[seg] else key := segA[seg];
    end;
    SetLength(Result, n + 1 + 2 * np);
    Result[n] := np;
    Inc(n);
    for j := 0 to np - 1 do
    begin
      Result[n] := px[j];
      Result[n + 1] := py[j];
      Inc(n, 2);
    end;
  end;
end;

{ ------------------------------------------------------------------ trace }

procedure TAdvChartHaloKeepTest.TestTheTraceIsTheWholeMaskWalk;
var
  mask: TBGRABitmap;
  p: TTyPainter;
  sc: TTyCanvasScale;
  bad, cases, contours, i, x, y, s: Integer;
  report: string;
  levels: array[0..6] of Byte = (0, 60, 127, 128, 129, 200, 255);

  procedure Check(const AName: string; AScale: Integer);
  var a, b: TTyDoubleArray;
  begin
    a := TyTraceMaskOutlineForTest(mask, AScale);
    b := RefTrace(mask, AScale);
    Inc(cases);
    if Length(b) > 0 then Inc(contours);
    if not SameBits(a, b) then
    begin
      Inc(bad);
      report := report + LineEnding + Format('  %s: %d numbers here, %d by the whole walk',
        [AName, Length(a), Length(b)]);
    end;
  end;

  procedure TextMask(const AText: string; ASize, AWeight: Integer; ARot: Double;
    AX, AY: Double; AScale: Integer);
  begin
    mask := TBGRABitmap.Create(160 * AScale, 120 * AScale, BGRAPixelTransparent);
    try
      p := TTyPainter.Create;
      try
        sc.Scale := AScale;
        sc.DeviceUnits := False;
        p.BeginPaintOnScaled(nil, Rect(0, 0, 160, 120), 96, mask, sc);
        if ARot = 0 then
          p.DrawText(Rect(Round(AX), Round(AY), Round(AX) + 120, Round(AY) + 40), AText, '',
            ASize, AWeight, TTyColor($FFFFFFFF), taLeftJustify, tlTop, False)
        else
          p.DrawTextRotated(AText, '', ASize, AWeight, TTyColor($FFFFFFFF), AX, AY, ARot,
            taCenter, tlCenter);
        p.EndPaint;
      finally
        p.Free;
      end;
      Check(Format('"%s" %d/%d at %g rad, %gx', [AText, ASize, AWeight, ARot, AScale * 1.0]),
        AScale);
    finally
      FreeAndNil(mask);
    end;
  end;

begin
  bad := 0;
  cases := 0;
  contours := 0;
  report := '';
  { glyphs, as a halo's mask holds them }
  TextMask('Halo 8g', 14, 400, 0, 10, 10, 1);
  TextMask('W@ %&', 22, 700, 0, 3.5, 70.25, 1);
  TextMask('flare.analytics', 12, 400, 0.6, 80.3, 60.7, 1);
  TextMask('ROTATED', 18, 700, -1.3, 79.5, 59.5, 1);
  TextMask('upside 9', 16, 400, 3.0, 81.25, 58.75, 1);
  TextMask('Halo 8g', 14, 400, 0, 10, 10, 2);
  TextMask('turned', 15, 400, 0.9, 80.4, 60.6, 2);
  { noise round half coverage: saddles everywhere }
  for s := 1 to 6 do
  begin
    GLcg := LongWord(s * 7919);
    mask := TBGRABitmap.Create(23 + s * 5, 17 + s * 3, BGRAPixelTransparent);
    try
      for y := 0 to mask.Height - 1 do
        for x := 0 to mask.Width - 1 do
          if Lcg(3) > 0 then
            mask.SetPixel(x, y, BGRA(255, 255, 255, levels[Lcg(7)]));
      Check('noise ' + IntToStr(s), 1 + s mod 2);
    finally
      FreeAndNil(mask);
    end;
  end;
  { ink on every border, in the corners, everywhere, nowhere }
  mask := TBGRABitmap.Create(30, 20, BGRAPixelTransparent);
  try
    for i := 0 to 29 do
    begin
      mask.SetPixel(i, 0, BGRA(255, 255, 255, 255));
      mask.SetPixel(i, 19, BGRA(255, 255, 255, 200));
    end;
    for i := 0 to 19 do
    begin
      mask.SetPixel(0, i, BGRA(255, 255, 255, 255));
      mask.SetPixel(29, i, BGRA(255, 255, 255, 140));
    end;
    Check('the border', 1);
    mask.FillTransparent;
    mask.SetPixel(0, 0, BGRA(255, 255, 255, 255));
    mask.SetPixel(29, 19, BGRA(255, 255, 255, 128));
    mask.SetPixel(29, 0, BGRA(255, 255, 255, 129));
    Check('the corners', 1);
    mask.FillTransparent;
    mask.SetPixel(13, 9, BGRA(255, 255, 255, 127));
    Check('just under half', 1);
    Check('nothing', 1);
    mask.Fill(BGRA(255, 255, 255, 255));
    Check('everything', 1);
  finally
    FreeAndNil(mask);
  end;
  AssertTrue(Format('enough was traced (%d cases, %d with contours)', [cases, contours]),
    (cases >= 18) and (contours >= 15));
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(cases) + ' differ:' + report, 0, bad);
end;

{ ----------------------------------------------------------- the elements }

function Caption(const AText: string; AX, AY, ARot: Double; ASize, AWeight: Integer;
  AHalo: TTyChartColor; AWidth: Double; const ADash: string): TTyChartElement;
begin
  Result := TyChartElement(TyShapeRect(TyRectF(AX - 50, AY - 12, AX + 50, AY + 12)));
  Result.Caption.Text := AText;
  Result.Caption.FontName := '';
  Result.Caption.FontSizeLogical := ASize;
  Result.Caption.FontWeight := AWeight;
  Result.Caption.Colour := TTyChartColor($FF202020);
  Result.Caption.X := AX;
  Result.Caption.Y := AY;
  Result.Caption.AnchorH := tahCentre;
  Result.Caption.AnchorV := tavMiddle;
  Result.Caption.RotationRad := ARot;
  Result.Caption.StrokeColour := AHalo;
  Result.Caption.StrokeWidthLogical := AWidth;
  Result.Caption.StrokeType := ADash;
end;

type
  TElArray = array of TTyChartElement;

{ every kind of halo there is: turned runs, the shape's rect (one line and
  broken lines, truncated), a box off the anchor, dashes, translucent ink, an
  element alpha }
function Elements(AHalo: TTyChartColor): TElArray;
var
  e: TTyChartElement;
  sh: TTyChartShape;
begin
  Result := nil;
  SetLength(Result, 9);
  Result[0] := Caption('flare.vis', 80.3, 60.7, 0.7, 12, 400, AHalo, 3, '');
  Result[1] := Caption('ROTATED', 200.5, 50.25, -1.2, 14, 700, AHalo, 2, 'dashed');
  Result[2] := Caption('Halo 8g', 120, 150, 0, 16, 400, AHalo, 4, '');
  Result[3] := Caption('dotted', 250, 160, 0, 13, 400, AHalo, 3, 'dotted');
  e := Caption('two' + #10 + 'lines', 60, 190, 0, 12, 400, AHalo, 2, '');
  e.Caption.MultiLine := True;
  Result[4] := e;
  e := Caption('a long caption cut short', 300, 210, 0, 12, 400, AHalo, 2, '');
  e.Shape := TyShapeRect(TyRectF(270, 200, 330, 220));
  e.Caption.Truncate := True;
  Result[5] := e;
  e := Caption('translucent', 280, 100, 0.3, 15, 700,
    (AHalo and $00FFFFFF) or $80000000, 5, '');
  Result[6] := e;
  e := Caption('faded', 150, 100, 0, 18, 400, AHalo, 4, '');
  e.Style.Alpha := 0.55;
  Result[7] := e;
  { no shape bounds: the box hung off the anchor }
  sh := Default(TTyChartShape);
  sh.Kind := cskCircle;
  sh.CX := 40;
  sh.CY := 120;
  sh.R1 := 0;
  sh.Bounds := TyRectF(NaN, NaN, NaN, NaN);
  e := Caption('anchored', 40, 120, 0, 13, 400, AHalo, 3, '');
  e.Shape := sh;
  Result[8] := e;
end;

{ rich pieces with a halo each, one dashed }
function Pieces(AHalo: TTyChartColor): TTyRtPieceArray;
var k: Integer;
begin
  Result := nil;
  SetLength(Result, 2);
  for k := 0 to 1 do
  begin
    Result[k] := Default(TTyRtPiece);
    Result[k].Kind := rpkText;
    Result[k].Text := 'rich ' + IntToStr(k);
    Result[k].FontFamily := '';
    Result[k].FontSizePx := 14 + 4 * k;
    Result[k].FontWeight := 400 + 300 * k;
    Result[k].HasFill := True;
    Result[k].Fill := TTyChartColor($FF000000);
    Result[k].HasStroke := True;
    Result[k].Stroke := AHalo;
    Result[k].LineWidth := 3;
    Result[k].Opacity := 1;
    Result[k].X := 0;
    Result[k].Y := 18 * k;
  end;
  Result[1].LineDash := 'dashed';
end;

{ the elements and the pieces on B at AScale device px per px }
procedure Paint(B: TBGRABitmap; AScale: Integer; AHalo: TTyChartColor);
var
  p: TTyPainter;
  sc: TTyCanvasScale;
  els: TElArray;
  pcs: TTyRtPieceArray;
  i: Integer;
begin
  Ground(B);
  els := Elements(AHalo);
  pcs := Pieces(AHalo);
  p := TTyPainter.Create;
  try
    sc.Scale := AScale;
    sc.DeviceUnits := False;
    p.BeginPaintOnScaled(nil, Rect(0, 0, cW, cH), 96, B, sc);
    for i := 0 to High(els) do
      TyRenderElement(p, els[i]);
    TyRenderRtPieces(p, pcs, 180.5, 20.25, 0, 1, 1, False, TTyColor(0));
    TyRenderRtPieces(p, pcs, 320.3, 60.6, 0.8, 1, 1, False, TTyColor(0));
    p.EndPaint;
  finally
    p.Free;
  end;
end;

procedure PaintOne(B: TBGRABitmap; const AEl: TTyChartElement; APPI: Integer);
var p: TTyPainter;
begin
  Ground(B);
  p := TTyPainter.Create;
  try
    p.BeginPaintOn(nil, Rect(0, 0, cW, cH), APPI, B);
    TyRenderElement(p, AEl);
    p.EndPaint;
  finally
    p.Free;
  end;
end;

procedure SetKeeping(AOn: Boolean);
begin
  TyAdvChartHaloCacheForTest(AOn);
  TyPainterKeptStrokesForTest(AOn);
end;

procedure TAdvChartHaloKeepTest.TestAKeptHaloPaintsAsAFreshOne;
const
  cRed = TTyChartColor($FFE02020);
  cBlue = TTyChartColor($FF2040E0);
var
  s, t0, f0, r0: Integer;
  refRed, refBlue, a: TBGRABitmap;
begin
  { the box hung off the anchor (no shape bounds) is nought wide: its run
    draws nothing, so its halo has no outline and strokes nothing -- the
    other twelve do }
  a := TBGRABitmap.Create(cW, cH);
  refRed := TBGRABitmap.Create(cW, cH);
  try
    SetKeeping(False);
    PaintOne(a, Elements(cRed)[8], 96);
    Ground(refRed);
    AssertEquals('the anchored box draws nothing', 0, DiffPixels(a, refRed));
  finally
    FreeAndNil(a);
    FreeAndNil(refRed);
  end;
  for s := 1 to 2 do
  begin
    refRed := TBGRABitmap.Create(cW * s, cH * s);
    refBlue := TBGRABitmap.Create(cW * s, cH * s);
    a := TBGRABitmap.Create(cW * s, cH * s);
    try
      SetKeeping(False);
      Paint(refRed, s, cRed);
      Paint(refBlue, s, cBlue);
      SetKeeping(True);
      t0 := TyAdvChartHaloTracesForTest;
      f0 := TyPainterKeptStrokeFillsForTest;
      Paint(a, s, cRed);
      AssertEquals(Format('%dx: traced and kept, the pixels are a fresh frame''s', [s]), 0,
        DiffPixels(a, refRed));
      AssertEquals(Format('%dx: every halo traced once (9 captions, 4 pieces)', [s]), 13,
        TyAdvChartHaloTracesForTest - t0);
      AssertTrue(Format('%dx: and its fill recorded', [s]), TyPainterKeptStrokeFillsForTest > f0);
      t0 := TyAdvChartHaloTracesForTest;
      f0 := TyPainterKeptStrokeFillsForTest;
      r0 := TyPainterKeptStrokeReplaysForTest;
      Paint(a, s, cRed);
      AssertEquals(Format('%dx: from what was kept, the same pixels', [s]), 0,
        DiffPixels(a, refRed));
      AssertEquals(Format('%dx: nothing traced again', [s]), 0, TyAdvChartHaloTracesForTest - t0);
      AssertEquals(Format('%dx: nothing filled again', [s]), 0, TyPainterKeptStrokeFillsForTest - f0);
      AssertEquals(Format('%dx: every stroke replayed (all but the anchored box)', [s]), 12,
        TyPainterKeptStrokeReplaysForTest - r0);
      { ANOTHER INK, the same outline and the same coverage: the kept fill
        holds no colour }
      t0 := TyAdvChartHaloTracesForTest;
      f0 := TyPainterKeptStrokeFillsForTest;
      Paint(a, s, cBlue);
      AssertEquals(Format('%dx: in blue from the red one''s keeping, a fresh blue frame', [s]), 0,
        DiffPixels(a, refBlue));
      AssertEquals(Format('%dx: blue traced nothing', [s]), 0, TyAdvChartHaloTracesForTest - t0);
      AssertEquals(Format('%dx: blue filled nothing', [s]), 0, TyPainterKeptStrokeFillsForTest - f0);
      AssertTrue('the two inks differ at all', DiffPixels(refRed, refBlue) > 500);
    finally
      refRed.Free;
      refBlue.Free;
      a.Free;
    end;
  end;
end;

procedure TAdvChartHaloKeepTest.TestTheKeyHoldsWhatShapesTheMask;
const
  cRed = TTyChartColor($FFE02020);
var
  turned, straight, e: TTyChartElement;
  ref, a: TBGRABitmap;
  bad, cases: Integer;
  report: string;

  { AVariant after ABase, both kept: AWant new traces, a fresh frame's pixels }
  procedure Variant(const AName: string; const ABase, AVariant: TTyChartElement;
    AWant: Integer; APPI: Integer = 96);
  var t0, d: Integer;
  begin
    Inc(cases);
    SetKeeping(False);
    PaintOne(ref, AVariant, APPI);
    SetKeeping(True);
    PaintOne(a, ABase, 96);
    t0 := TyAdvChartHaloTracesForTest;
    PaintOne(a, AVariant, APPI);
    d := DiffPixels(a, ref);
    if (TyAdvChartHaloTracesForTest - t0 <> AWant) or (d <> 0) then
    begin
      Inc(bad);
      report := report + LineEnding + Format('  %s: %d traced (want %d), %d px off a fresh frame',
        [AName, TyAdvChartHaloTracesForTest - t0, AWant, d]);
    end;
  end;

begin
  bad := 0;
  cases := 0;
  report := '';
  ref := TBGRABitmap.Create(cW, cH);
  a := TBGRABitmap.Create(cW, cH);
  try
    turned := Caption('Key test', 150.3, 100.6, 0.5, 14, 400, cRed, 3, '');
    straight := Caption('Key test', 150, 100, 0, 14, 400, cRed, 3, '');
    { each input to the mask, moved alone: a new outline }
    e := turned; e.Caption.Text := 'Key tesT'; Variant('the words', turned, e, 1);
    e := turned; e.Caption.FontSizeLogical := 15; Variant('the size', turned, e, 1);
    e := turned; e.Caption.FontWeight := 700; Variant('the weight', turned, e, 1);
    e := turned; e.Caption.FontName := 'Courier New'; Variant('the font', turned, e, 1);
    e := turned; e.Caption.X := 150.55; Variant('a sub-pixel across', turned, e, 1);
    e := turned; e.Caption.Y := 100.85; Variant('a sub-pixel down', turned, e, 1);
    e := turned; e.Caption.RotationRad := 0.51; Variant('the turn', turned, e, 1);
    e := turned; e.Caption.AnchorH := tahLeft; Variant('the alignment', turned, e, 1);
    e := turned; Variant('the PPI', turned, e, 1, 144);
    e := straight; e.Shape := TyShapeRect(TyRectF(100, 88, 190, 112));
    Variant('the rect', straight, e, 1);
    e := straight; e.Caption.Text := 'Key test that is long'; e.Caption.Truncate := True;
    Variant('truncation', straight, e, 1);
    e := straight; e.Caption.Text := 'Key' + #10 + 'test'; e.Caption.MultiLine := True;
    Variant('line breaking', straight, e, 1);
    e := straight; e.Caption.AnchorV := tavTop; Variant('the straight alignment', straight, e, 1);
    { what does not reach the mask: the same outline }
    e := turned; e.Caption.X := 153.3; e.Caption.Y := 98.6;
    Variant('whole pixels further', turned, e, 0);
    e := straight; e.Shape := TyShapeRect(TyRectF(103, 90, 203, 114));
    Variant('the rect moved by whole pixels', straight, e, 0);
    e := turned; e.Caption.StrokeColour := TTyChartColor($FF00A000);
    Variant('the ink', turned, e, 0);
    e := turned; e.Caption.StrokeType := 'dashed'; Variant('the dash', turned, e, 0);
    e := turned; e.Caption.StrokeWidthLogical := 2.6; Variant('the width, the same mask', turned, e, 0);
    e := turned; e.Caption.Colour := TTyChartColor($FF0000FF); Variant('the glyph ink', turned, e, 0);
    AssertEquals(IntToStr(bad) + ' of ' + IntToStr(cases) + ':' + report, 0, bad);
  finally
    ref.Free;
    a.Free;
  end;
end;

procedure TAdvChartHaloKeepTest.TestAFontChangeDropsTheOutlines;
var
  e: TTyChartElement;
  a: TBGRABitmap;
  t0: Integer;
begin
  a := TBGRABitmap.Create(cW, cH);
  try
    e := Caption('Generation', 120.4, 90.7, 0.4, 14, 400, TTyChartColor($FFE02020), 3, '');
    PaintOne(a, e, 96);
    AssertTrue('kept', TyAdvChartHaloOutlinesKeptForTest >= 1);
    t0 := TyAdvChartHaloTracesForTest;
    PaintOne(a, e, 96);
    AssertEquals('found again', t0, TyAdvChartHaloTracesForTest);
    { a font registered, a theme applied: what a name draws may have moved }
    TyInvalidateTextMeasureCache;
    PaintOne(a, e, 96);
    AssertEquals('traced afresh after the painter''s text generation moved', t0 + 1,
      TyAdvChartHaloTracesForTest);
    AssertEquals('the old outlines gone, the new one kept', 1, TyAdvChartHaloOutlinesKeptForTest);
  finally
    a.Free;
  end;
end;

{ -------------------------------------------------------- the kept stroke }

var
  GPath: array of TPointF;

procedure StrokeOn(B: TBGRABitmap; AKept: Boolean; AColour: TTyColor; AAlpha: Double;
  AClip: Boolean; AWidth: Double = 3);
var
  p: TTyPainter;
  i: Integer;
begin
  Ground(B);
  p := TTyPainter.Create;
  try
    p.BeginPaintOn(nil, Rect(0, 0, cW, cH), 96, B);
    p.SaveState;
    if AAlpha < 1 then p.SetElementAlpha(AAlpha);
    if AClip then p.ClipRect(Rect(30, 25, 220, 160));
    p.BeginPath;
    p.MoveTo(GPath[0].X, GPath[0].Y);
    for i := 1 to High(GPath) do p.LineTo(GPath[i].X, GPath[i].Y);
    p.ClosePath;
    p.MoveTo(20.5, 220.25);
    for i := 1 to 30 do p.LineTo(20.5 + i * 10.3, 220.25 - (i mod 3) * 7.7);
    if AKept then p.StrokePathKept(AColour, AWidth) else p.StrokePath(AColour, AWidth);
    p.RestoreState;
    p.EndPaint;
  finally
    p.Free;
  end;
end;

procedure TAdvChartHaloKeepTest.TestAKeptStrokeIsTheStrokeItReplays;
const
  cRed = TTyColor($FFE02020);
  cBlue = TTyColor($802040E0);
var
  ref, a: TBGRABitmap;
  i, f0, r0: Integer;
  r1, r2, r3, rNone: LongInt;
begin
  GLcg := 99;
  SetLength(GPath, 48);
  for i := 0 to High(GPath) do
    GPath[i] := PointF(40 + Lcg(28000) / 100, 30 + Lcg(15000) / 100);
  ref := TBGRABitmap.Create(cW, cH);
  a := TBGRABitmap.Create(cW, cH);
  try
    { opaque ink: recorded, then replayed }
    StrokeOn(ref, False, cRed, 1, False);
    f0 := TyPainterKeptStrokeFillsForTest;
    StrokeOn(a, True, cRed, 1, False);
    AssertEquals('recorded: a fresh stroke''s pixels', 0, DiffPixels(a, ref));
    AssertEquals('one fill recorded', f0 + 1, TyPainterKeptStrokeFillsForTest);
    r0 := TyPainterKeptStrokeReplaysForTest;
    StrokeOn(a, True, cRed, 1, False);
    AssertEquals('replayed: the same pixels', 0, DiffPixels(a, ref));
    AssertEquals('replayed, not filled', r0 + 1, TyPainterKeptStrokeReplaysForTest);
    AssertEquals('nothing more recorded', f0 + 1, TyPainterKeptStrokeFillsForTest);
    { translucent ink, then an element alpha over it: the same coverage, another brush }
    StrokeOn(ref, False, cBlue, 1, False);
    StrokeOn(a, True, cBlue, 1, False);
    AssertEquals('translucent ink from the red one''s coverage', 0, DiffPixels(a, ref));
    StrokeOn(ref, False, cBlue, 0.45, False);
    StrokeOn(a, True, cBlue, 0.45, False);
    AssertEquals('under an element alpha', 0, DiffPixels(a, ref));
    AssertEquals('one coverage served all three', f0 + 1, TyPainterKeptStrokeFillsForTest);
    { another width: another polygon }
    StrokeOn(ref, False, cRed, 1, False, 5);
    StrokeOn(a, True, cRed, 1, False, 5);
    AssertEquals('a wider pen', 0, DiffPixels(a, ref));
    AssertEquals('is a polygon of its own', f0 + 2, TyPainterKeptStrokeFillsForTest);
    { a clip the replay does not model: stroked as StrokePath strokes }
    r0 := TyPainterKeptStrokeReplaysForTest;
    StrokeOn(ref, False, cRed, 1, True);
    StrokeOn(a, True, cRed, 1, True);
    AssertEquals('clipped', 0, DiffPixels(a, ref));
    AssertEquals('not recorded', f0 + 2, TyPainterKeptStrokeFillsForTest);
    AssertEquals('not replayed', r0, TyPainterKeptStrokeReplaysForTest);
    { THE GLOBAL Random, left as the fill leaves it: the fill draws its pivots
      from the pinned generator, and unpinning reseeds the application's }
    RandSeed := 4242;
    rNone := Random(1000000000);
    RandSeed := 4242;
    StrokeOn(ref, False, cRed, 1, False);
    r1 := Random(1000000000);
    AssertTrue('the fill does draw from the generator', r1 <> rNone);
    RandSeed := 4242;
    StrokeOn(a, True, cRed, 1, False);          // replayed
    r2 := Random(1000000000);
    AssertEquals('a replay leaves the application''s stream as a fill does', r1, r2);
    TyPainterKeptStrokesForTest(True);
    RandSeed := 4242;
    StrokeOn(a, True, cRed, 1, False);          // recorded
    r3 := Random(1000000000);
    AssertEquals('and so does a recording', r1, r3);
  finally
    ref.Free;
    a.Free;
    GPath := nil;
  end;
end;

{ -------------------------------------------------------------- the guard }

const
  cTree = '{"animation": false, "series": [{"type": "tree", "layout": "radial",'
    + ' "expandAndCollapse": false, "symbolSize": 6,'
    + ' "label": {"textBorderColor": "#ffffff", "textBorderWidth": 3},'
    + ' "data": [{"name": "root", "children": ['
    + '{"name": "alpha", "children": [{"name": "alpha one"}, {"name": "alpha two"}, {"name": "alpha three"}]},'
    + '{"name": "beta", "children": [{"name": "beta one"}, {"name": "beta two"}]},'
    + '{"name": "gamma", "children": [{"name": "gamma one"}, {"name": "gamma two"}, {"name": "gamma three"}]},'
    + '{"name": "delta", "children": [{"name": "delta one"}, {"name": "delta two"}]}'
    + ']}]}]}';

procedure TAdvChartHaloKeepTest.TestARepaintTracesAndFillsNothing;
var
  form: TForm;
  ctl: TTyStyleController;
  chart: THkChart;
  bmp: TBitmap;
  lst: TTyPaintList;
  k, n, t0, f0, r0: Integer;
begin
  form := TForm.CreateNew(nil);
  ctl := TTyStyleController.Create(nil);
  bmp := TBitmap.Create;
  try
    ctl.Mode := 'light';
    ctl.ThemeName := 'default';
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(cW, cH);
    chart := THkChart.Create(form);
    chart.Parent := form;
    chart.Controller := ctl;
    chart.AnimationMode := camOff;
    chart.SetBounds(0, 0, cW, cH);
    chart.Option := cTree;
    t0 := TyAdvChartHaloTracesForTest;
    f0 := TyPainterKeptStrokeFillsForTest;
    chart.Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
    lst := chart.List;
    n := 0;
    for k := 0 to lst.Count - 1 do
      if (lst.Element(k).Caption.Text <> '') and (lst.Element(k).Caption.StrokeWidthLogical > 0)
        and ((lst.Element(k).Caption.StrokeColour shr 24) <> 0) then
        Inc(n);
    AssertEquals('every node has a haloed label', 15, n);
    AssertEquals('a first frame traces each haloed label once', n, TyAdvChartHaloTracesForTest - t0);
    AssertEquals('and fills each halo once', n, TyPainterKeptStrokeFillsForTest - f0);
    t0 := TyAdvChartHaloTracesForTest;
    f0 := TyPainterKeptStrokeFillsForTest;
    r0 := TyPainterKeptStrokeReplaysForTest;
    chart.Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
    AssertEquals('a repaint traces no mask', 0, TyAdvChartHaloTracesForTest - t0);
    AssertEquals('and fills no halo', 0, TyPainterKeptStrokeFillsForTest - f0);
    AssertEquals('it replays each', n, TyPainterKeptStrokeReplaysForTest - r0);
  finally
    bmp.Free;
    form.Free;
    ctl.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartHaloKeepTest);
end.
