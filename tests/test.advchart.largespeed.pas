unit test.advchart.largespeed;
{$mode objfpc}{$H+}
{ [R2-L] Large data, drawn faster and the same.

  The gallery's large examples (half a million bars, a million points, two
  hundred thousand candles, a heatmap of forty thousand cells) took ten to
  thirty seconds to a picture. What changed, none of it a pixel:

  - per-row bookkeeping only where a row has something: a large batch's
    rows keep no state records (TestALargeSeriesKeepsNoRowRecords);
  - a large batch's rects without BGRA's scanline objects
    (TyFillRectAntialiasExact, held to BGRA's own FillRectAntialias on
    every kind of rect, clip and ground: TestARectFillIsBgrasOwn), the
    brush's work on a pixel kept per pixel value and coverage
    (TestTheRectMemoIsTheBrush);
  - a progress frame paints the static layer only where the chunk landed
    (TestAProgressFrameIsTheFullPaint: every frame of two progressive runs,
    with a hover between, the same pixels with the fast path on and off);
  - a visual map's indicator rebuilds the list's components alone
    (TestTheIndicatorRebuildsTheTail: a hover sweep over a heatmap, the
    same frames whole-list or tail);
  - the visual map reads one row's value for a hover, and a value's text
    only where a piece or a category reads it (TestOneRowValueIsTheSeries-
    Value, TestTheTextIsReadWhereItIsRead);
  - an axis' label places only for the labels built
    (TestOnlyTheBuiltLabelsArePlaced);
  - a short decimal read without strings (TestAShortDecimalIsTheLongWay),
    a colour text parsed once (TestAColourParseIsKept);
  - the painter's kept strokes keep the pen's polygon too, stroke under a
    clip mask, and leave an ink that draws nothing undrawn
    (TestAKeptPenIsThePen). }
interface

uses Classes, SysUtils, Math, Types, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Painter, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Data,
     tyControls.AdvChart.Scale, tyControls.AdvChart.Color, tyControls.AdvChart.Layout,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Coord, tyControls.AdvChart.Option,
     tyControls.AdvChart.VisualMap, tyControls.AdvChart.Render, tyControls.AdvanceChart;

type
  TLsChart = class(TTyAdvanceChart)
  public
    procedure Cached(ACanvas: TCanvas; const ARect: TRect);
    procedure Move(AX, AY: Integer);
    procedure Leave;
  end;

  TAdvChartLargeSpeedTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    function NewChart(AW, AH: Integer; const AOption: string): TLsChart;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestARectFillIsBgrasOwn;
    procedure TestTheRectMemoIsTheBrush;
    procedure TestALargeSeriesKeepsNoRowRecords;
    procedure TestAProgressFrameIsTheFullPaint;
    procedure TestTheIndicatorRebuildsTheTail;
    procedure TestOneRowValueIsTheSeriesValue;
    procedure TestTheTextIsReadWhereItIsRead;
    procedure TestOnlyTheBuiltLabelsArePlaced;
    procedure TestAShortDecimalIsTheLongWay;
    procedure TestAColourParseIsKept;
    procedure TestAKeptPenIsThePen;
  end;

implementation

{ ---------------------------------------------------------------- helpers }

procedure TLsChart.Cached(ACanvas: TCanvas; const ARect: TRect);
begin
  RenderCached(ACanvas, ARect, 96);
end;

procedure TLsChart.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TLsChart.Leave;
begin
  MouseLeave;
end;

var
  GLcg: LongWord;

function Lcg(AMax: Integer): Integer;
begin
  {$push}{$R-}{$Q-}
  GLcg := GLcg * 1664525 + 1013904223;
  {$pop}
  Result := Integer((GLcg shr 8) mod LongWord(AMax));
end;

function LcgF: Double;
begin
  Result := Lcg(1000000) / 1000000;
end;

procedure Ground(B: TBGRABitmap; ASeed: LongWord);
var
  x, y: Integer;
  p: PBGRAPixel;
  s: LongWord;
begin
  s := ASeed;
  for y := 0 to B.Height - 1 do
  begin
    p := B.ScanLine[y];
    for x := 0 to B.Width - 1 do
    begin
      {$push}{$R-}{$Q-}
      s := s * 1103515245 + 12345;
      {$pop}
      { a third of the ground transparent, a third opaque, the rest between }
      case (s shr 20) mod 3 of
        0: p^ := BGRAPixelTransparent;
        1: p^ := BGRA((s shr 8) and 255, (s shr 13) and 255, (s shr 18) and 255, 255);
      else
        p^ := BGRA((s shr 8) and 255, (s shr 13) and 255, (s shr 18) and 255, 1 + (s shr 3) mod 254);
      end;
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

{ the bytes of a 24-bit bitmap }
function Frame(B: TBitmap): RawByteString;
var
  y, n: Integer;
begin
  n := B.Width * 3;
  SetLength(Result, n * B.Height);
  for y := 0 to B.Height - 1 do
    Move(B.ScanLine[y]^, Result[1 + y * n], n);
end;

{ where two frames differ: the box and how many pixels }
function FrameDiff(const A, B: RawByteString; AW: Integer): string;
var
  i, x, y, n, x0, y0, x1, y1: Integer;
begin
  Result := '';
  if A = B then Exit;
  if Length(A) <> Length(B) then Exit(' (sizes differ)');
  n := 0; x0 := MaxInt; y0 := MaxInt; x1 := -1; y1 := -1;
  i := 1;
  while i <= Length(A) do
  begin
    if (A[i] <> B[i]) or (A[i + 1] <> B[i + 1]) or (A[i + 2] <> B[i + 2]) then
    begin
      Inc(n);
      x := ((i - 1) div 3) mod AW;
      y := ((i - 1) div 3) div AW;
      x0 := Min(x0, x); y0 := Min(y0, y); x1 := Max(x1, x); y1 := Max(y1, y);
    end;
    Inc(i, 3);
  end;
  Result := Format(' (%d pixels in %d,%d..%d,%d)', [n, x0, y0, x1, y1]);
end;

function TAdvChartLargeSpeedTest.NewChart(AW, AH: Integer; const AOption: string): TLsChart;
begin
  Result := TLsChart.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.AnimationMode := camOff;
  Result.AnimNow := 0;
  Result.ProgressiveStepCostMs := 1;
  Result.SetBounds(0, 0, AW, AH);
  Result.Option := AOption;
end;

procedure TAdvChartLargeSpeedTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  TyAdvChartProgFastForTest(True);
  TyAdvChartListTailForTest(True);
  TyPainterKeptStrokesForTest(True);
end;

procedure TAdvChartLargeSpeedTest.TearDown;
begin
  TyAdvChartProgFastForTest(True);
  TyAdvChartListTailForTest(True);
  TyPainterKeptStrokesForTest(True);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

{ ------------------------------------------------------- the rect fill }

{ a coordinate that lands on the rows' own scan lines now and then:
  yb + 1/256, yb + 255/256, the sub-scans' (2c + 1) / 32, less the half
  pixel the fill adds }
function EdgyCoord(AMax: Integer): Single;
begin
  case Lcg(7) of
    0: Result := Lcg(AMax) + 1 / 256 - 0.5;
    1: Result := Lcg(AMax) + 255 / 256 - 0.5;
    2: Result := Lcg(AMax) + (Lcg(16) * 2 + 1) / 32 - 0.5;
    3: Result := Lcg(AMax);
    4: Result := Lcg(AMax) + 0.5;
  else
    Result := Lcg(AMax * 100) / 100 - 0.5;
  end;
end;

procedure TAdvChartLargeSpeedTest.TestARectFillIsBgrasOwn;
var
  ref, got: TBGRABitmap;
  t, k, w, h, bad: Integer;
  x, y, x2, y2: Single;
  c: TBGRAPixel;
  clip: TRect;
  memo: TObject;
begin
  GLcg := 2026;
  memo := TyRectFillMemoNew;
  ref := TBGRABitmap.Create(61, 47);
  got := TBGRABitmap.Create(61, 47);
  try
    bad := 0;
    for t := 0 to 299 do
    begin
      Ground(ref, t);
      Ground(got, t);
      { the draw mode, and a clip now and then }
      ref.LinearAntialiasing := Odd(t div 50);
      got.LinearAntialiasing := ref.LinearAntialiasing;
      if t mod 3 = 0 then
        clip := Rect(Lcg(20), Lcg(15), 30 + Lcg(31), 25 + Lcg(22))
      else
        clip := Rect(0, 0, 61, 47);
      ref.ClipRect := clip;
      got.ClipRect := clip;
      for k := 0 to 39 do
      begin
        c := BGRA(Lcg(256), Lcg(256), Lcg(256), Lcg(256));
        if Lcg(3) = 0 then c.alpha := 255;
        x := EdgyCoord(70) - 5;
        y := EdgyCoord(55) - 4;
        case Lcg(6) of
          0: begin w := 0; h := 0; end;             // a thin bar: under a pixel wide
          1: begin w := Lcg(3); h := Lcg(40); end;
          2: begin w := Lcg(20); h := 0; end;       // a row's sliver
        else
          begin w := Lcg(30); h := Lcg(30); end;
        end;
        x2 := x + w + Lcg(100) / 100;
        y2 := y + h + Lcg(100) / 100;
        { now and then the corners the other way round, or a huge one }
        if Lcg(8) = 0 then begin x := x2 + 3; end;
        if Lcg(9) = 0 then begin y := y2 + 2.25; end;
        if Lcg(25) = 0 then begin x := -1e5; x2 := 1e5; end;
        ref.FillRectAntialias(x, y, x2, y2, c);
        if Odd(k) then TyFillRectAntialiasExact(got, x, y, x2, y2, c)
        else TyFillRectAntialiasExact(got, x, y, x2, y2, c, memo);
      end;
      if DiffPixels(ref, got) <> 0 then
      begin
        Inc(bad);
        if bad = 1 then
          Fail(Format('trial %d: %d pixels differ', [t, DiffPixels(ref, got)]));
      end;
    end;
    AssertEquals('every trial is BGRA''s own fill', 0, bad);
  finally
    ref.Free;
    got.Free;
    memo.Free;
  end;
end;

procedure TAdvChartLargeSpeedTest.TestTheRectMemoIsTheBrush;
var
  ref, got: TBGRABitmap;
  i: Integer;
  memo: TObject;
  c1, c2: TBGRAPixel;
  y0: Single;
begin
  { thin bars, one colour then another and back: the memo forgets a colour's
    pixels when the colour changes, and one stale entry would show }
  GLcg := 7;
  memo := TyRectFillMemoNew;
  ref := TBGRABitmap.Create(40, 60, BGRAPixelTransparent);
  got := TBGRABitmap.Create(40, 60, BGRAPixelTransparent);
  try
    c1 := BGRA(30, 120, 220, 255);
    c2 := BGRA(30, 120, 221, 255);
    for i := 0 to 599 do
    begin
      if (i div 50) mod 2 = 0 then
      begin
        y0 := 5 + Lcg(20) / 7;
        ref.FillRectAntialias(i * 0.0617, y0, i * 0.0617 + 0.86, 55, c1);
        TyFillRectAntialiasExact(got, i * 0.0617, y0, i * 0.0617 + 0.86, 55, c1, memo);
      end
      else
      begin
        ref.FillRectAntialias(i * 0.0617, 3, i * 0.0617 + 0.86, 50 - i mod 7, c2);
        TyFillRectAntialiasExact(got, i * 0.0617, 3, i * 0.0617 + 0.86, 50 - i mod 7, c2, memo);
      end;
    end;
    AssertEquals('six hundred thin bars of two colours', 0, DiffPixels(ref, got));
  finally
    ref.Free;
    got.Free;
    memo.Free;
  end;
end;

{ --------------------------------------------------- per-row bookkeeping }

procedure TAdvChartLargeSpeedTest.TestALargeSeriesKeepsNoRowRecords;
var
  chart: TLsChart;
  bmp: TBitmap;
  sb: TStringBuilder;
  i: Integer;
  data: string;
begin
  sb := TStringBuilder.Create;
  try
    for i := 0 to 59 do
    begin
      if i > 0 then sb.Append(',');
      sb.Append(IntToStr(10 + (i * 37) mod 50));
    end;
    data := sb.ToString;
  finally
    sb.Free;
  end;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(400, 300);
    chart := NewChart(400, 300, '{"animation": false, "xAxis": {"type": "category"},'
      + ' "yAxis": {}, "series": [{"type": "bar", "large": true, "largeThreshold": 10,'
      + ' "data": [' + data + ']}, {"type": "bar", "data": [' + data + ']}]}');
    chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
    AssertEquals('a large batch hosts no row: no records', 0, chart.StRowRecordsForTest(0));
    AssertEquals('a bar per row: a record per row', 60, chart.StRowRecordsForTest(1));
    { a select on the large series: still none, and drawn as before }
    chart.DispatchAction('{"type": "select", "seriesIndex": 0, "dataIndex": 3}');
    chart.Cached(bmp.Canvas, Rect(0, 0, 400, 300));
    AssertEquals('none after a select', 0, chart.StRowRecordsForTest(0));
  finally
    bmp.Free;
  end;
end;

{ ------------------------------------------------------ progress frames }

function ProgressOption(ASeed: LongWord): string;
var
  sb: TStringBuilder;
  i: Integer;
begin
  GLcg := ASeed;
  sb := TStringBuilder.Create;
  try
    { two progressive runs, overlapping, and what lies over them: a line
      across the plot, the slider and the title }
    sb.Append('{"animation": false, "title": {"text": "Progress", "left": "center", "top": 40},');
    sb.Append(' "dataZoom": [{"type": "slider"}], "legend": {},');
    sb.Append(' "xAxis": {"type": "category", "boundaryGap": false}, "yAxis": {},');
    sb.Append(' "series": [{"name": "bars", "type": "bar", "large": true, "largeThreshold": 20,');
    sb.Append(' "progressive": 40, "progressiveThreshold": 50, "data": [');
    for i := 0 to 299 do
    begin
      if i > 0 then sb.Append(',');
      sb.Append(IntToStr(20 + Lcg(80)));
    end;
    sb.Append(']}, {"name": "dots", "type": "scatter", "large": true, "largeThreshold": 20,');
    sb.Append(' "progressive": 33, "progressiveThreshold": 50, "symbolSize": 7,');
    sb.Append(' "itemStyle": {"opacity": 0.6}, "data": [');
    for i := 0 to 299 do
    begin
      if i > 0 then sb.Append(',');
      sb.Append('[').Append(IntToStr(Lcg(300))).Append(',').Append(IntToStr(10 + Lcg(95))).Append(']');
    end;
    sb.Append(']}, {"name": "line", "type": "line", "showSymbol": false, "data": [');
    for i := 0 to 299 do
    begin
      if i > 0 then sb.Append(',');
      sb.Append(IntToStr(60 + (i mod 23)));
    end;
    sb.Append(']}]}');
    Result := sb.ToString;
  finally
    sb.Free;
  end;
end;

procedure TAdvChartLargeSpeedTest.TestAProgressFrameIsTheFullPaint;
var
  frames: array[Boolean] of TStringList;
  fast: Boolean;
  chart: TLsChart;
  bmp: TBitmap;
  n, k, f0, used: Integer;
  opt: string;
begin
  opt := ProgressOption(11);
  frames[False] := TStringList.Create;
  frames[True] := TStringList.Create;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(520, 360);
    used := 0;
    for fast := False to True do
    begin
      TyAdvChartProgFastForTest(fast);
      f0 := TyAdvChartProgFastFramesForTest;
      chart := NewChart(520, 360, opt);
      try
        chart.Cached(bmp.Canvas, Rect(0, 0, 520, 360));
        frames[fast].Add(Frame(bmp));
        n := 0;
        while chart.ProgressiveUnfinished and (n < 60) do
        begin
          chart.ProgressTick;
          chart.Cached(bmp.Canvas, Rect(0, 0, 520, 360));
          frames[fast].Add(Frame(bmp));
          Inc(n);
          { a hover between two frames (a state: the full paint), and away }
          if n = 3 then
          begin
            chart.Move(150, 200);
            chart.Cached(bmp.Canvas, Rect(0, 0, 520, 360));
            frames[fast].Add(Frame(bmp));
            chart.Leave;
            chart.Cached(bmp.Canvas, Rect(0, 0, 520, 360));
            frames[fast].Add(Frame(bmp));
          end;
        end;
        AssertFalse('drawn to the end', chart.ProgressiveUnfinished);
        if fast then used := TyAdvChartProgFastFramesForTest - f0
        else AssertEquals('switched off: no frame served', 0, TyAdvChartProgFastFramesForTest - f0);
      finally
        chart.Free;
      end;
    end;
    AssertTrue('several chunks', frames[False].Count > 8);
    AssertEquals('as many frames', frames[False].Count, frames[True].Count);
    for k := 0 to frames[False].Count - 1 do
      AssertTrue(Format('frame %d the same pixels%s', [k, FrameDiff(frames[False][k], frames[True][k], 520)]),
        frames[False][k] = frames[True][k]);
    AssertTrue('most progress frames kept the static layer', used >= frames[False].Count - 6);
  finally
    bmp.Free;
    frames[False].Free;
    frames[True].Free;
    TyAdvChartProgFastForTest(True);
  end;
end;

{ ------------------------------------------------- the indicator's tail }

procedure TAdvChartLargeSpeedTest.TestTheIndicatorRebuildsTheTail;
var
  frames: array[Boolean] of TStringList;
  tail: Boolean;
  chart: TLsChart;
  bmp: TBitmap;
  sb: TStringBuilder;
  i, j, k, t0, used: Integer;
  opt: string;
begin
  sb := TStringBuilder.Create;
  try
    sb.Append('{"animation": false, "tooltip": {}, "xAxis": {"type": "category"},');
    sb.Append(' "yAxis": {"type": "category"}, "dataZoom": [{"type": "slider"}],');
    sb.Append(' "visualMap": {"min": 0, "max": 1, "calculable": true, "orient": "horizontal", "left": "center", "top": 0},');
    sb.Append(' "series": [{"type": "heatmap", "progressive": 60, "data": [');
    for i := 0 to 19 do
      for j := 0 to 19 do
      begin
        if (i > 0) or (j > 0) then sb.Append(',');
        sb.Append(Format('[%d,%d,%s]', [i, j, FloatToStr(((i * 7 + j * 13) mod 20) / 20)]));
      end;
    sb.Append(']}]}');
    opt := sb.ToString;
  finally
    sb.Free;
  end;
  frames[False] := TStringList.Create;
  frames[True] := TStringList.Create;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(480, 400);
    used := 0;
    for tail := False to True do
    begin
      TyAdvChartListTailForTest(tail);
      chart := NewChart(480, 400, opt);
      try
        chart.Cached(bmp.Canvas, Rect(0, 0, 480, 400));
        while chart.ProgressiveUnfinished do
        begin
          chart.ProgressTick;
          chart.Cached(bmp.Canvas, Rect(0, 0, 480, 400));
        end;
        t0 := TyAdvChartListTailsForTest;
        { across the cells, a frame for each move, and off the chart }
        for k := 0 to 13 do
        begin
          chart.Move(90 + k * 23, 120 + (k mod 4) * 41);
          chart.Cached(bmp.Canvas, Rect(0, 0, 480, 400));
          frames[tail].Add(Frame(bmp));
        end;
        chart.Leave;
        chart.Cached(bmp.Canvas, Rect(0, 0, 480, 400));
        frames[tail].Add(Frame(bmp));
        if tail then used := TyAdvChartListTailsForTest - t0
        else AssertEquals('switched off: none', 0, TyAdvChartListTailsForTest - t0);
      finally
        chart.Free;
      end;
    end;
    AssertEquals('as many frames', frames[False].Count, frames[True].Count);
    for k := 0 to frames[False].Count - 1 do
      AssertTrue(Format('hover frame %d the same pixels', [k]), frames[False][k] = frames[True][k]);
    AssertTrue('the indicator moved by its tail', used >= 10);
  finally
    bmp.Free;
    frames[False].Free;
    frames[True].Free;
    TyAdvChartListTailForTest(True);
  end;
end;

{ ------------------------------------------------------- visual values }

function Cell(const AText: string): TTyDataValue;
begin
  Result := TyDataText(AText);
end;

procedure TAdvChartLargeSpeedTest.TestOneRowValueIsTheSeriesValue;
var
  st: TTyDataStore;
  it: TTyRawItem;
  dims: array of TTyVisualDim;
  vals: TTyDoubleArray;
  col, di, raw, d: Integer;
  v: Double;
begin
  st := TTyDataStore.Create;
  try
    st.AddDimension('x', ddtFloat);
    st.AddDimension('y', ddtFloat);
    st.SetRawDimPos(0, 0);
    st.SetRawDimPos(1, 1);
    st.RawWidth := 4;
    st.SetRawDimType(3, ddtOrdinal);
    for raw := 0 to 7 do
    begin
      st.AppendRow([TyDataNum(raw), TyDataNum(raw * 1.5)]);
      it := Default(TTyRawItem);
      it.Shape := rshArray;
      SetLength(it.Cells, 4);
      it.Cells[0] := TyDataNum(raw);
      it.Cells[1] := TyDataNum(raw * 1.5);
      case raw mod 4 of
        0: it.Cells[2] := TyDataNum(raw / 3);
        1: it.Cells[2] := Cell('12.5');
        2: it.Cells[2] := TyDataNone;
      else
        it.Cells[2] := Cell('word');
      end;
      case raw mod 3 of
        0: it.Cells[3] := Cell('7');
        1: it.Cells[3] := TyDataBool(True);
      else
        it.Cells[3] := TyDataNone;
      end;
      if raw = 5 then SetLength(it.Cells, 2);
      st.SetRawItem(raw, it);
    end;
    { the store's own columns, positions parsed from the item, an ordinal
      position, a position past the row, none, a name }
    SetLength(dims, 7);
    for d := 0 to High(dims) do dims[d] := Default(TTyVisualDim);
    dims[0].Given := True; dims[0].Num := 1;
    dims[1].Given := True; dims[1].Num := 2;
    dims[2].Given := True; dims[2].Num := 3;
    dims[3].Given := True; dims[3].Num := 9;
    dims[4].Given := False;
    dims[5].Given := True; dims[5].IsName := True; dims[5].Name := 'y';
    dims[6].Given := True; dims[6].Num := 1.5;
    for d := 0 to High(dims) do
    begin
      vals := TyVisualSeriesValues(st, dims[d], col, di);
      for raw := 0 to st.RawCount - 1 do
      begin
        v := TyVisualSeriesValueAt(st, dims[d], raw);
        AssertTrue(Format('dim %d row %d', [d, raw]),
          (IsNan(v) and IsNan(vals[raw])) or (not IsNan(v) and (v = vals[raw])));
      end;
      AssertTrue(Format('dim %d off the rows', [d]), IsNan(TyVisualSeriesValueAt(st, dims[d], -1))
        and IsNan(TyVisualSeriesValueAt(st, dims[d], st.RawCount)));
    end;
  finally
    st.Free;
  end;
end;

procedure TAdvChartLargeSpeedTest.TestTheTextIsReadWhereItIsRead;
var
  opt: TTyChartOption;
  spec: TTyVisualMapSpec;
  ramp: TTyVisualColorArray;

  function SpecOf(const AJson: string): TTyVisualMapSpec;
  begin
    opt.SetOptionText(AJson);
    Result := TyVisualMapSpecOf(opt, 0, ramp, TyVisualUndefined);
  end;

begin
  ramp := TyVisualDefaultRamp(TTyChartColor($FF5470C6));
  opt := TTyChartOption.Create;
  try
    spec := SpecOf('{"visualMap": {"min": 0, "max": 10}, "series": []}');
    AssertFalse('continuous: no text read', TyVisualSpecReadsText(spec));
    spec := SpecOf('{"visualMap": {"type": "piecewise", "pieces": [{"min": 0, "max": 5}, {"value": 7}]}, "series": []}');
    AssertFalse('number pieces: none', TyVisualSpecReadsText(spec));
    spec := SpecOf('{"visualMap": {"type": "piecewise", "pieces": [{"value": "7"}]}, "series": []}');
    AssertTrue('a piece whose value is a string', TyVisualSpecReadsText(spec));
    spec := SpecOf('{"visualMap": {"type": "piecewise", "categories": ["a", "b"]}, "series": []}');
    AssertTrue('categories', TyVisualSpecReadsText(spec));
  finally
    opt.Free;
  end;
end;

{ ----------------------------------------------------- the label places }

procedure TAdvChartLargeSpeedTest.TestOnlyTheBuiltLabelsArePlaced;
var
  chart: TLsChart;
  bmp: TBitmap;
  sb: TStringBuilder;
  spec: PTyAxisLayoutSpec;
  i, built: Integer;
begin
  sb := TStringBuilder.Create;
  try
    sb.Append('{"animation": false, "xAxis": {"type": "category", "data": [');
    for i := 0 to 1999 do
    begin
      if i > 0 then sb.Append(',');
      sb.Append('"c').Append(IntToStr(i)).Append('"');
    end;
    sb.Append(']}, "yAxis": {}, "series": [{"type": "line", "data": [1, 2, 3]}]}');
    bmp := TBitmap.Create;
    try
      bmp.PixelFormat := pf24bit;
      bmp.SetSize(600, 300);
      chart := NewChart(600, 300, sb.ToString);
      chart.Cached(bmp.Canvas, Rect(0, 0, 600, 300));
      spec := chart.Build.Grid(0).SpecFor(chart.Build.Grid(0).XAxis(0));
      AssertEquals('a place for every category', 2000, Length(spec^.Placements));
      built := 0;
      for i := 0 to High(spec^.Placements) do
      begin
        AssertEquals(Format('label %d placed iff built', [i]), spec^.Placements[i].Built,
          spec^.Placements[i].HasM);
        if spec^.Placements[i].Built then Inc(built);
      end;
      AssertTrue('a few built', (built > 3) and (built < 200));
    finally
      bmp.Free;
    end;
  finally
    sb.Free;
  end;
end;

{ ------------------------------------------------------------- numbers }

procedure TAdvChartLargeSpeedTest.TestAShortDecimalIsTheLongWay;
const
  cFixed: array[0..21] of string = ('0', '-0', '0.000', '00012.5000', '1e22',
    '1e-22', '123456789012345e7', '123456789012345e-22', '.5', '5.', '+1.5E+3',
    '-4512.34', '999999999999999', '0.000000000000001234', '7e0', '1E+0022',
    '3.14159265358979', '-.25e-3', '1234567890123456', '1e23', '12.e1', '4.5e-23');
var
  i, k, n, ex, fracLen: Integer;
  s, digits, ip, fp: string;
  neg: Boolean;
  want, got: Double;

  function Expected(const AText: string): Double;
  var
    p, e, t: Integer;
    sgn: Boolean;
    intPart, fracPart, expPart: string;
    expo: Int64;
  begin
    { the literal's own parts, worked out the long way }
    p := 1;
    sgn := False;
    if AText[p] in ['+', '-'] then
    begin
      sgn := AText[p] = '-';
      Inc(p);
    end;
    intPart := '';
    while (p <= Length(AText)) and (AText[p] in ['0'..'9']) do
    begin
      intPart := intPart + AText[p];
      Inc(p);
    end;
    fracPart := '';
    if (p <= Length(AText)) and (AText[p] = '.') then
    begin
      Inc(p);
      while (p <= Length(AText)) and (AText[p] in ['0'..'9']) do
      begin
        fracPart := fracPart + AText[p];
        Inc(p);
      end;
    end;
    expo := 0;
    if (p <= Length(AText)) and (AText[p] in ['e', 'E']) then
    begin
      e := p + 1;
      t := 1;
      if AText[e] in ['+', '-'] then
      begin
        if AText[e] = '-' then t := -1;
        Inc(e);
      end;
      expPart := Copy(AText, e, MaxInt);
      expo := t * StrToInt64(expPart);
    end;
    Result := TyJsDecimalToDouble(intPart + fracPart, expo - Length(fracPart));
    if sgn then Result := -Result;
  end;

  procedure Check(const AText: string);
  var a, b: QWord;
  begin
    want := Expected(AText);
    got := TyJsToNumber(AText);
    Move(want, a, 8);
    Move(got, b, 8);
    AssertEquals('"' + AText + '"', Int64(a), Int64(b));
  end;

begin
  for i := 0 to High(cFixed) do Check(cFixed[i]);
  GLcg := 31337;
  for n := 0 to 4999 do
  begin
    { up to 17 digits about a point, a sign and an exponent now and then }
    k := 1 + Lcg(17);
    digits := '';
    for i := 1 to k do digits := digits + Chr(Ord('0') + Lcg(10));
    fracLen := Lcg(k + 1);
    ip := Copy(digits, 1, k - fracLen);
    fp := Copy(digits, k - fracLen + 1, MaxInt);
    s := ip;
    if fp <> '' then s := s + '.' + fp;
    if s = '' then s := '0';
    neg := Lcg(3) = 0;
    if neg then s := '-' + s;
    if Lcg(3) = 0 then
    begin
      ex := Lcg(61) - 30;
      s := s + 'e' + IntToStr(ex);
    end;
    Check(s);
  end;
  AssertTrue('not a number', IsNan(TyJsToNumber('1.2.3')));
  AssertTrue('a point alone', IsNan(TyJsToNumber('.')));
  AssertTrue('an exponent with no digits is not read', TyJsParseFloat('1e') = 1);
end;

procedure TAdvChartLargeSpeedTest.TestAColourParseIsKept;
const
  cTexts: array[0..6] of string = ('#ec0000', 'rgba(1, 2, 3, 0.5)', 'red',
    'not a colour', '#00da3c', 'hsl(120, 50%, 50%)', '');
var
  i, k: Integer;
  c: TTyVisualColor;
  ok, ok2: Boolean;
  r, g, b, a: Double;
begin
  { more texts than the memo holds, over and over: each answer the parse's }
  for k := 0 to 40 do
    for i := 0 to High(cTexts) do
    begin
      ok := TyVisualTryParse(cTexts[(i * 3 + k) mod Length(cTexts)], c);
      ok2 := TyTryParseCssRgba(cTexts[(i * 3 + k) mod Length(cTexts)], r, g, b, a);
      AssertEquals('ok', ok2, ok);
      if ok then
      begin
        AssertTrue('the colour', (c.R = r) and (c.G = g) and (c.B = b) and (c.A = a) and c.Defined);
      end
      else
        AssertFalse('undefined', c.Defined);
    end;
end;

{ --------------------------------------------------------- the kept pen }

var
  GPath: array of TPointF;

procedure StrokeOn(B: TBGRABitmap; AKept: Boolean; AColour: TTyColor; AWidth: Double;
  AClip: Boolean; ADash: Boolean);
var
  p: TTyPainter;
  i: Integer;
begin
  Ground(B, 5);
  p := TTyPainter.Create;
  try
    p.BeginPaintOn(nil, Rect(0, 0, B.Width, B.Height), 96, B);
    p.SaveState;
    if AClip then p.ClipRect(Rect(20, 15, 150, 110));
    if ADash then p.SetLineDash([4, 2]);
    p.BeginPath;
    p.MoveTo(GPath[0].X, GPath[0].Y);
    for i := 1 to High(GPath) do p.LineTo(GPath[i].X, GPath[i].Y);
    if AKept then p.StrokePathKept(AColour, AWidth) else p.StrokePath(AColour, AWidth);
    p.RestoreState;
    p.EndPaint;
  finally
    p.Free;
  end;
end;

procedure TAdvChartLargeSpeedTest.TestAKeptPenIsThePen;
var
  ref, a: TBGRABitmap;
  i, c0, f0: Integer;
  r1, r2: LongInt;
begin
  GLcg := 5;
  SetLength(GPath, 40);
  for i := 0 to High(GPath) do
    GPath[i] := PointF(10 + Lcg(16000) / 100, 10 + Lcg(10000) / 100);
  ref := TBGRABitmap.Create(200, 140);
  a := TBGRABitmap.Create(200, 140);
  try
    TyPainterKeptStrokesForTest(True);
    { a pen kept, then met again: computed once }
    StrokeOn(ref, False, TTyColor($FF2060C0), 2.5, False, False);
    c0 := TyPainterKeptStrokeContoursForTest;
    StrokeOn(a, True, TTyColor($FF2060C0), 2.5, False, False);
    AssertEquals('the pen''s polygon', 0, DiffPixels(a, ref));
    AssertEquals('computed', c0 + 1, TyPainterKeptStrokeContoursForTest);
    StrokeOn(a, True, TTyColor($80C02060), 2.5, False, False);
    StrokeOn(ref, False, TTyColor($80C02060), 2.5, False, False);
    AssertEquals('kept, another ink', 0, DiffPixels(a, ref));
    AssertEquals('not computed again', c0 + 1, TyPainterKeptStrokeContoursForTest);
    { another width and a dash: other polygons }
    StrokeOn(ref, False, TTyColor($FF2060C0), 1, False, False);
    StrokeOn(a, True, TTyColor($FF2060C0), 1, False, False);
    AssertEquals('another width', 0, DiffPixels(a, ref));
    AssertEquals('is its own', c0 + 2, TyPainterKeptStrokeContoursForTest);
    StrokeOn(ref, False, TTyColor($FF2060C0), 2.5, False, True);
    StrokeOn(a, True, TTyColor($FF2060C0), 2.5, False, True);
    AssertEquals('dashed', 0, DiffPixels(a, ref));
    { under a clip mask: kept and the same pixels }
    StrokeOn(ref, False, TTyColor($FF20C060), 2.5, True, False);
    f0 := TyPainterKeptStrokeReplaysForTest;
    StrokeOn(a, True, TTyColor($FF20C060), 2.5, True, False);
    AssertEquals('under a clip mask', 0, DiffPixels(a, ref));
    AssertEquals('replayed through the mask', f0 + 1, TyPainterKeptStrokeReplaysForTest);
    { an ink that draws nothing: nothing drawn, no pen, the application's
      Random as before }
    c0 := TyPainterKeptStrokeContoursForTest;
    RandSeed := 777;
    StrokeOn(ref, False, TTyColor($00FF0000), 2.5, False, False);
    r1 := Random(1000000);
    RandSeed := 777;
    StrokeOn(a, True, TTyColor($00FF0000), 2.5, False, False);
    r2 := Random(1000000);
    AssertEquals('nothing drawn either way', 0, DiffPixels(a, ref));
    AssertEquals('the stream as a stroke leaves it', r1, r2);
    AssertEquals('no pen made for it', c0, TyPainterKeptStrokeContoursForTest);
  finally
    ref.Free;
    a.Free;
    GPath := nil;
  end;
end;

initialization
  RegisterTest(TAdvChartLargeSpeedTest);
end.
