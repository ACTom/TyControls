unit test.advchart.sampling;
{$mode objfpc}{$H+}
{ series.sampling -- lttb, minmax, average, sum, max, min and nearest on a
  cartesian2d line or bar -- held to what ECharts 6.1 does, bit for bit.
  [Batch 102, roadmap B10]

  tools/advchart-oracle/sampling.js runs the real dist and records, per
  series, the data as the sampler received it (the view after the dataZoom
  filter, the value column by raw row, the base axis' size before the
  layout, the rate), which method ran with which argument, and what came out:
  the rows kept, the values written back, the line's layout points, an area's
  stacked-on points, the bars, the symbols and their labels, the axis extents
  and the rows the axis tooltip picks at three pointer positions.

  Two layers, reported apart:
    - THE RULES: TySamplingRate / TySamplingApplies / TySampleView fed the
      recorded input directly;
    - THE WIRING: the control renders the option and its store, paint list,
      axes and pointer hits are compared.
  Text is measured with zrender's SSR width table (as gridbounds and
  tooltipfinish do), so the category label interval -- which decides the
  symbols showAllSymbol 'auto' keeps -- and the outerBounds shrink are
  upstream's. A plot that still differs is compared on the rows, values and
  extents only.

  A LAYOUT POINT upstream keeps the coordinate it could map beside the NaN
  (dataToPoint([x, NaN]) is [x, NaN]); the port writes both NaN. Either is an
  illegal point, which is all anything reads off it, so an illegal point is
  compared as illegal. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Scale, tyControls.AdvChart.Data,
     tyControls.AdvChart.Sampling, tyControls.AdvChart.Measure, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TSmpProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function Pointers(AX, AY: Integer): TTyAxisHitArray;
  end;

  TAdvChartSamplingOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TSmpProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    { what the wiring test reached: plots that moved, labels, symbols, bars,
      point runs and pointer rows compared }
    FMoved, FLabels, FSymbols, FBars, FRuns, FTipRows: Integer;
    FMovedIds: string;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; AGot: Double; const AHex: string);
    function Cases: TJSONArray;
    function CaseById(const AId: string): TJSONObject;
    procedure Show(ACase: TJSONObject);
    procedure CheckSeries(ACase, ASer: TJSONObject; ASamePlot: Boolean);
    procedure CheckTips(ACase: TJSONObject);
    function SamePlot(ACase: TJSONObject): Boolean;
    procedure Finish(AMin: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheRulesAsUpstream;
    procedure TestTheChartSamplesAsUpstream;
    procedure TestTheOverflowingLttbStopsAtItsSlots;
    procedure TestTheSamplingOptionReadsAsUpstream;
    procedure TestTheRateAndTheGate;
    procedure TestTheParsedValueSurvivesTheSampler;
    procedure TestAResizeSamplesAgain;
    procedure TestTheMaskedArithmeticLeavesTheHostTrapsAlone;
    procedure TestASampledValueIsSeenByTheExtent;
  end;

implementation

function TSmpProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TSmpProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TSmpProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TSmpProbe.Pointers(AX, AY: Integer): TTyAxisHitArray;
begin
  Result := ResolveAxisPointers(AX, AY);
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-sampling.json';
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Bits(A: Double): QWord;
begin
  Move(A, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function SameNum(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  if (A = 0) and (B = 0) then Exit(True);
  Result := Bits(A) = Bits(B);
end;

function IsNull(D: TJSONData): Boolean;
begin
  Result := (D = nil) or (D.JSONType = jtNull);
end;

function IntsOf(A: TJSONArray): TTyIntegerArray;
var i: Integer;
begin
  SetLength(Result, A.Count);
  for i := 0 to A.Count - 1 do Result[i] := A.Integers[i];
end;

function HexesOf(A: TJSONArray): TTyDoubleArray;
var i: Integer;
begin
  SetLength(Result, A.Count);
  for i := 0 to A.Count - 1 do Result[i] := FromHex(A.Strings[i]);
end;

{ ---------------- the test case ---------------- }

procedure TAdvChartSamplingOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartSamplingOracleTest.Num(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not SameNum(AGot, FromHex(AHex)) then
    Miss(Format('%s: %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

function TAdvChartSamplingOracleTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

function TAdvChartSamplingOracleTest.CaseById(const AId: string): TJSONObject;
var c: Integer;
begin
  for c := 0 to Cases.Count - 1 do
    if Cases.Objects[c].Strings['id'] = AId then Exit(Cases.Objects[c]);
  Result := nil;
  Fail('no case ' + AId);
end;

procedure TAdvChartSamplingOracleTest.Show(ACase: TJSONObject);
begin
  FChart.Option := '{}';
  FChart.Option := ACase.Objects['option'].AsJSON;
  FChart.SetBounds(0, 0, ACase.Integers['width'], ACase.Integers['height']);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, ACase.Integers['width'],
    ACase.Integers['height']), 96);
end;

procedure TAdvChartSamplingOracleTest.Finish(AMin: Integer);
begin
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > AMin);
end;

{ THE RULES: the recorded input straight into the samplers }
procedure TAdvChartSamplingOracleTest.TestTheRulesAsUpstream;
var
  c, s, k: Integer;
  cs, se, st, ran: TJSONObject;
  view, want: TTyIntegerArray;
  col, vals: TTyDoubleArray;
  rate, arg: Double;
  mode: TTySamplingMode;
  res: TTySampleResult;
  applies: Boolean;
  sampled: Integer;
begin
  sampled := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    for s := 0 to cs.Arrays['series'].Count - 1 do
    begin
      se := cs.Arrays['series'].Objects[s];
      FName := Format('%s s%d', [cs.Strings['id'], se.Integers['index']]);
      if IsNull(se.Find('stage')) then Continue;
      st := se.Objects['stage'];
      mode := TySamplingModeOf(se.Find('samplingOption'));
      rate := TySamplingRate(st.Integers['count'], FromHex(st.Strings['size']));
      Num('rate', rate, st.Strings['rate']);
      applies := (mode <> tsmNone) and TySamplingApplies(st.Integers['count'], rate);
      Inc(FCompared);
      if applies <> not IsNull(se.Find('ran')) then
      begin
        Miss(Format('sampled %s upstream', [BoolToStr(not IsNull(se.Find('ran')), True)]));
        Continue;
      end;
      if not applies then Continue;
      Inc(sampled);
      ran := se.Objects['ran'];
      arg := 1 / rate;
      Num('the rate handed over', arg, ran.Strings['rateArg']);
      Inc(FCompared);
      if (ran.Strings['method'] = 'lttb') <> (mode = tsmLttb)
        or ((ran.Strings['method'] = 'minmax') <> (mode = tsmMinmax)) then
        Miss('method ' + ran.Strings['method'] + ' upstream, '
          + TySamplingModeName(mode) + ' here');
      view := IntsOf(st.Arrays['rawIndices']);
      col := HexesOf(st.Arrays['column']);
      res := TySampleView(mode, view, col, arg);
      if not IsNull(se.Find('sampledStore')) then
        want := IntsOf(se.Objects['sampledStore'].Arrays['indices'])
      else
        want := IntsOf(se.Arrays['rawIndices']);
      Inc(FCompared);
      if Length(res.Indices) <> Length(want) then
      begin
        Miss(Format('%d rows kept upstream, %d here', [Length(want), Length(res.Indices)]));
        Continue;
      end;
      for k := 0 to High(want) do
      begin
        Inc(FCompared);
        if res.Indices[k] <> want[k] then
        begin
          Miss(Format('row %d: raw %d upstream, %d here', [k, want[k], res.Indices[k]]));
          Break;
        end;
      end;
      if IsNull(se.Find('values')) then Continue;
      vals := HexesOf(se.Arrays['values']);
      for k := 0 to High(vals) do
      begin
        Inc(FCompared);
        if not SameNum(res.Column[res.Indices[k]], vals[k]) then
        begin
          Miss(Format('row %d (raw %d): value %s upstream, %s here', [k, want[k],
            Fmt(vals[k]), Fmt(res.Column[res.Indices[k]])]));
          Break;
        end;
      end;
    end;
  end;
  AssertTrue(Format('sampled series replayed (%d)', [sampled]), sampled > 60);
  Finish(5000);
end;

function TAdvChartSamplingOracleTest.SamePlot(ACase: TJSONObject): Boolean;
var
  ax: TJSONArray;
  k: Integer;
  a: TJSONObject;
  axis: TTyAxis;
begin
  Result := True;
  ax := ACase.Arrays['axes'];
  for k := 0 to ax.Count - 1 do
  begin
    a := ax.Objects[k];
    axis := FChart.Build.Axis(a.Strings['dim'] + 'Axis', a.Integers['index']);
    if (axis = nil) or not SameNum(axis.PxLength, FromHex(a.Strings['pxSpanFinal'])) then
      Exit(False);
  end;
end;

procedure TAdvChartSamplingOracleTest.CheckSeries(ACase, ASer: TJSONObject;
  ASamePlot: Boolean);
var
  si, k, j, n, row, col: Integer;
  store: TTyDataStore;
  ri, vals, arr, it: TJSONArray;
  lst: TTyPaintList;
  e: TTyChartElement;
  pts, base: TTyDoubleArray;
  found: Boolean;
  b: TTyRectF;
  bar: TJSONObject;
  x, y, w, h, l, r, t, bt: Double;
  xa, ya: TTyAxis;
  got: string;

  function Legal(APair: TJSONArray): Boolean;
  begin
    Result := not (IsNan(FromHex(APair.Strings[0])) or IsNan(FromHex(APair.Strings[1])));
  end;

  function FindRun(out APts, ABase: TTyDoubleArray): Boolean;
  var q: Integer;
  begin
    Result := False;
    APts := nil;
    ABase := nil;
    for q := 0 to lst.Count - 1 do
    begin
      e := lst.Element(q);
      if (e.Anim.Series <> si) or not (e.Anim.Role in [carLineRun, carLineArea]) then Continue;
      APts := e.Anim.Pts;
      ABase := e.Anim.Base;
      Exit(True);
    end;
  end;

begin
  si := ASer.Integers['index'];
  FName := Format('%s s%d', [ACase.Strings['id'], si]);
  store := FChart.SeriesStore(si);
  Inc(FCompared);
  if store = nil then
  begin
    Miss('no store here');
    Exit;
  end;
  ri := ASer.Arrays['rawIndices'];
  Inc(FCompared);
  if store.Count <> ASer.Integers['count'] then
  begin
    Miss(Format('%d rows upstream, %d here', [ASer.Integers['count'], store.Count]));
    Exit;
  end;
  for k := 0 to ri.Count - 1 do
  begin
    Inc(FCompared);
    if store.GetRawIndex(k) <> ri.Integers[k] then
    begin
      Miss(Format('row %d: raw %d upstream, %d here', [k, ri.Integers[k], store.GetRawIndex(k)]));
      Exit;
    end;
  end;
  { the value column, as the sampler left it }
  if not IsNull(ASer.Find('values')) and not IsNull(ASer.Find('valueDim')) then
  begin
    col := store.DimIndexOf(ASer.Strings['valueDim']);
    vals := ASer.Arrays['values'];
    for k := 0 to vals.Count - 1 do
    begin
      Inc(FCompared);
      if not SameNum(store.Get(col, k), FromHex(vals.Strings[k])) then
      begin
        Miss(Format('row %d: value %s upstream, %s here', [k,
          Fmt(FromHex(vals.Strings[k])), Fmt(store.Get(col, k))]));
        Break;
      end;
    end;
  end;
  if not ASamePlot then Exit;
  lst := FChart.List;

  { THE LINE'S LAYOUT: every row's point, NaN where illegal -- what the runs
    and an update's diff are cut from }
  if not IsNull(ASer.Find('points')) then
  begin
    arr := ASer.Arrays['points'];
    if not FindRun(pts, base) then
    begin
      { NO SEGMENT TO DRAW: upstream has no two legal points in a row either
        (a run of one point is a bare move upstream and no element here) }
      found := False;
      for k := 1 to arr.Count - 1 do
        if Legal(TJSONArray(arr.Items[k - 1])) and Legal(TJSONArray(arr.Items[k])) then
          found := True;
      Inc(FCompared);
      if found then Miss('no line drawn here');
    end
    else
    begin
      Inc(FCompared);
      Inc(FRuns);
      if Length(pts) <> arr.Count * 2 then
        Miss(Format('%d points upstream, %d here', [arr.Count, Length(pts) div 2]))
      else
        for k := 0 to arr.Count - 1 do
        begin
          Inc(FCompared);
          it := TJSONArray(arr.Items[k]);
          if IsNan(FromHex(it.Strings[0])) or IsNan(FromHex(it.Strings[1])) then
          begin
            if not (IsNan(pts[k * 2]) or IsNan(pts[k * 2 + 1])) then
            begin
              Miss(Format('point %d: illegal upstream, %s,%s here', [k,
                Fmt(pts[k * 2]), Fmt(pts[k * 2 + 1])]));
              Break;
            end;
            Continue;
          end;
          if not (SameNum(pts[k * 2], FromHex(it.Strings[0]))
            and SameNum(pts[k * 2 + 1], FromHex(it.Strings[1]))) then
          begin
            Miss(Format('point %d: %s,%s upstream, %s,%s here', [k,
              Fmt(FromHex(it.Strings[0])), Fmt(FromHex(it.Strings[1])),
              Fmt(pts[k * 2]), Fmt(pts[k * 2 + 1])]));
            Break;
          end;
        end;
      { an area's stacked-on points }
      if not IsNull(ASer.Find('stackedOn')) then
      begin
        arr := ASer.Arrays['stackedOn'];
        Inc(FCompared);
        if Length(base) <> arr.Count * 2 then
          Miss(Format('%d stacked-on points upstream, %d here', [arr.Count, Length(base) div 2]))
        else
          for k := 0 to arr.Count - 1 do
          begin
            Inc(FCompared);
            it := TJSONArray(arr.Items[k]);
            if IsNan(FromHex(it.Strings[0])) or IsNan(FromHex(it.Strings[1])) then
            begin
              if not (IsNan(base[k * 2]) or IsNan(base[k * 2 + 1])) then
              begin
                Miss(Format('stacked-on %d: illegal upstream, legal here', [k]));
                Break;
              end;
              Continue;
            end;
            if not (SameNum(base[k * 2], FromHex(it.Strings[0]))
              and SameNum(base[k * 2 + 1], FromHex(it.Strings[1]))) then
            begin
              Miss(Format('stacked-on %d: %s,%s upstream, %s,%s here', [k,
                Fmt(FromHex(it.Strings[0])), Fmt(FromHex(it.Strings[1])),
                Fmt(base[k * 2]), Fmt(base[k * 2 + 1])]));
              Break;
            end;
          end;
      end;
    end;
  end;

  { THE SYMBOLS: which rows have one, and where }
  if not IsNull(ASer.Find('symbols')) then
  begin
    arr := ASer.Arrays['symbols'];
    n := 0;
    for j := 0 to lst.Count - 1 do
    begin
      e := lst.Element(j);
      if (e.Anim.Role = carLineSymbol) and (e.Anim.Series = si) then Inc(n);
    end;
    Inc(FCompared);
    if n <> arr.Count then
      Miss(Format('%d symbols upstream, %d here', [arr.Count, n]));
    for k := 0 to arr.Count - 1 do
    begin
      it := TJSONArray(arr.Items[k]);
      row := it.Integers[0];
      found := False;
      for j := 0 to lst.Count - 1 do
      begin
        e := lst.Element(j);
        if (e.Anim.Role <> carLineSymbol) or (e.Anim.Series <> si)
          or (e.Anim.Index <> row) then Continue;
        found := True;
        Inc(FCompared);
        Inc(FSymbols);
        if not (SameNum(e.Anim.G[0], FromHex(it.Strings[1]))
          and SameNum(e.Anim.G[1], FromHex(it.Strings[2]))) then
          Miss(Format('symbol of row %d: %s,%s upstream, %s,%s here', [row,
            Fmt(FromHex(it.Strings[1])), Fmt(FromHex(it.Strings[2])),
            Fmt(e.Anim.G[0]), Fmt(e.Anim.G[1])]));
        Break;
      end;
      Inc(FCompared);
      if not found then
      begin
        Miss(Format('row %d: a symbol upstream, none here', [row]));
        Break;
      end;
    end;
  end;

  { THE LABELS: the raw item's words, at the sampled point }
  if not IsNull(ASer.Find('labels')) then
  begin
    arr := ASer.Arrays['labels'];
    for k := 0 to arr.Count - 1 do
    begin
      it := TJSONArray(arr.Items[k]);
      row := it.Integers[0];
      found := False;
      for j := 0 to lst.Count - 1 do
      begin
        e := lst.Element(j);
        if (e.Datum.SeriesIndex <> si) or (e.Datum.DataIndex <> row)
          or (e.Caption.FontSizeLogical <= 0) or (e.Caption.Text = '') then Continue;
        found := True;
        Inc(FCompared);
        Inc(FLabels);
        if e.Caption.Text <> it.Strings[1] then
          Miss(Format('label of row %d: "%s" upstream, "%s" here', [row,
            it.Strings[1], e.Caption.Text]))
        else if not (SameNum(e.Caption.X, FromHex(it.Strings[2]))
          and SameNum(e.Caption.Y, FromHex(it.Strings[3]))) then
          Miss(Format('label of row %d at %s,%s upstream, %s,%s here', [row,
            Fmt(FromHex(it.Strings[2])), Fmt(FromHex(it.Strings[3])),
            Fmt(e.Caption.X), Fmt(e.Caption.Y)]));
        case e.Caption.AnchorH of
          tahLeft: got := 'left';
          tahRight: got := 'right';
        else
          got := 'center';
        end;
        case e.Caption.AnchorV of
          tavTop: got := got + '/top';
          tavBottom: got := got + '/bottom';
        else
          got := got + '/middle';
        end;
        Inc(FCompared);
        if got <> it.Strings[4] + '/' + it.Strings[5] then
          Miss(Format('label of row %d: %s/%s upstream, %s here', [row,
            it.Strings[4], it.Strings[5], got]));
        Break;
      end;
      Inc(FCompared);
      if not found then
      begin
        Miss(Format('row %d: a label upstream, none here', [row]));
        Break;
      end;
    end;
  end;

  { THE BARS: one per kept row, cut at the plot as drawn }
  if not IsNull(ASer.Find('bars')) then
  begin
    arr := ASer.Arrays['bars'];
    for k := 0 to arr.Count - 1 do
    begin
      if IsNull(arr.Items[k]) then Continue;
      bar := TJSONObject(arr.Items[k]);
      found := False;
      for j := 0 to lst.Count - 1 do
      begin
        e := lst.Element(j);
        if (e.Datum.SeriesIndex <> si) or (e.Datum.DataIndex <> k)
          or (e.Caption.FontSizeLogical > 0) or (e.Anim.Role <> carBar) then Continue;
        found := True;
        Inc(FBars);
        b := TyShapeBounds(e.Shape);
        x := FromHex(bar.Strings['x']);
        y := FromHex(bar.Strings['y']);
        w := FromHex(bar.Strings['width']);
        h := FromHex(bar.Strings['height']);
        { the layout cut at the plot, as the bar is drawn (clip: true) }
        xa := FChart.Build.Axis('xAxis', 0);
        ya := FChart.Build.Axis('yAxis', 0);
        l := Max(Min(x, x + w), Min(xa.PxStart, xa.PxStop));
        r := Min(Max(x, x + w), Max(xa.PxStart, xa.PxStop));
        t := Max(Min(y, y + h), Min(ya.PxStart, ya.PxStop));
        bt := Min(Max(y, y + h), Max(ya.PxStart, ya.PxStop));
        Inc(FCompared);
        if not (SameNum(b.Left, l) and SameNum(b.Right, r)
          and SameNum(b.Top, t) and SameNum(b.Bottom, bt)) then
        begin
          Miss(Format('bar of row %d: %s,%s..%s,%s upstream, %s,%s..%s,%s here', [k,
            Fmt(l), Fmt(t), Fmt(r), Fmt(bt),
            Fmt(b.Left), Fmt(b.Top), Fmt(b.Right), Fmt(b.Bottom)]));
          Exit;
        end;
        Break;
      end;
      Inc(FCompared);
      if not found then
      begin
        Miss(Format('row %d: a bar upstream, none here', [k]));
        Exit;
      end;
    end;
  end;
end;

procedure TAdvChartSamplingOracleTest.CheckTips(ACase: TJSONObject);
var
  tips, shown, rows: TJSONArray;
  t, a, k, q, total, slot, row: Integer;
  tip, ax: TJSONObject;
  hits: TTyAxisHitArray;
  hit: TTyAxisHit;
  got, want: string;
  store: TTyDataStore;
  have: Boolean;
begin
  tips := ACase.Arrays['tips'];
  for t := 0 to tips.Count - 1 do
  begin
    tip := tips.Objects[t];
    FName := Format('%s tip %d,%d', [ACase.Strings['id'], tip.Integers['x'], tip.Integers['y']]);
    hits := FChart.Pointers(tip.Integers['x'], tip.Integers['y']);
    if IsNull(tip.Find('shown')) then
    begin
      total := 0;
      for k := 0 to High(hits) do
        if not hits[k].Cross then Inc(total, Length(hits[k].Rows));
      Inc(FCompared);
      if total > 0 then Miss(Format('no rows upstream, %d here', [total]));
      Continue;
    end;
    shown := tip.Arrays['shown'];
    for a := 0 to shown.Count - 1 do
    begin
      ax := shown.Objects[a];
      have := False;
      hit := Default(TTyAxisHit);
      for k := 0 to High(hits) do
        if (not hits[k].Cross) and (hits[k].Axis <> nil)
          and (hits[k].Axis.Dim = ax.Strings['dim'])
          and (hits[k].Axis.ComponentIndex = ax.Integers['index']) then
        begin
          hit := hits[k];
          have := True;
        end;
      Inc(FCompared);
      if not have then
      begin
        Miss(Format('%s%d: no pointer here', [ax.Strings['dim'], ax.Integers['index']]));
        Continue;
      end;
      Num(ax.Strings['dim'] + ' value', hit.SnapValue, ax.Strings['value']);
      rows := ax.Arrays['rows'];
      want := '';
      for q := 0 to rows.Count - 1 do
        want := want + Format('[%d,%d,%d]', [TJSONArray(rows.Items[q]).Integers[0],
          TJSONArray(rows.Items[q]).Integers[1], TJSONArray(rows.Items[q]).Integers[2]]);
      got := '';
      for q := 0 to High(hit.Slots) do
      begin
        slot := hit.Slots[q];
        row := hit.Rows[q];
        store := FChart.SeriesStore(slot);
        if store <> nil then
          got := got + Format('[%d,%d,%d]', [slot, row, store.GetRawIndex(row)])
        else
          got := got + Format('[%d,%d,?]', [slot, row]);
      end;
      Inc(FCompared);
      Inc(FTipRows, rows.Count);
      if got <> want then
        Miss(Format('rows %s upstream, %s here', [want, got]));
    end;
  end;
end;

procedure TAdvChartSamplingOracleTest.TestTheChartSamplesAsUpstream;
var
  c, s, k: Integer;
  cs, a: TJSONObject;
  same: Boolean;
  ax: TTyAxis;
  e: TTyRange;
begin
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if not IsNull(cs.Find('throws')) then Continue;
    FName := cs.Strings['id'];
    try
      Show(cs);
    except
      on E: Exception do
      begin
        Miss(E.ClassName + ': ' + E.Message);
        Continue;
      end;
    end;
    { THE AXES, sized from the sampled rows }
    for k := 0 to cs.Arrays['axes'].Count - 1 do
    begin
      a := cs.Arrays['axes'].Objects[k];
      FName := Format('%s %s%d', [cs.Strings['id'], a.Strings['dim'], a.Integers['index']]);
      ax := FChart.Build.Axis(a.Strings['dim'] + 'Axis', a.Integers['index']);
      Inc(FCompared);
      if ax = nil then
      begin
        Miss('no axis here');
        Continue;
      end;
      e := ax.Scale.GetExtent;
      Num('extent 0', e.Start, a.Arrays['extent'].Strings[0]);
      Num('extent 1', e.Stop, a.Arrays['extent'].Strings[1]);
    end;
    same := SamePlot(cs);
    if not same then
    begin
      Inc(FMoved);
      FMovedIds := FMovedIds + ' ' + cs.Strings['id'];
    end;
    for s := 0 to cs.Arrays['series'].Count - 1 do
      CheckSeries(cs, cs.Arrays['series'].Objects[s], same);
    if same then CheckTips(cs);
  end;
  Finish(20000);
  { NOT A SILENT PASS: the plot is upstream's everywhere (the measure table
    makes even the outerBounds case agree), and every kind of thing was
    reached }
  AssertEquals('plots that moved:' + FMovedIds, 0, FMoved);
  AssertTrue(Format('labels compared (%d)', [FLabels]), FLabels >= 90);
  AssertTrue(Format('symbols compared (%d)', [FSymbols]), FSymbols >= 200);
  AssertTrue(Format('bars compared (%d)', [FBars]), FBars >= 250);
  AssertTrue(Format('lines compared (%d)', [FRuns]), FRuns >= 60);
  AssertTrue(Format('pointer rows compared (%d)', [FTipRows]), FTipRows >= 150);
end;

{ UPSTREAM THROWS here; the port keeps what upstream's index array holds }
procedure TAdvChartSamplingOracleTest.TestTheOverflowingLttbStopsAtItsSlots;
var
  cs, se: TJSONObject;
  store: TTyDataStore;
  want: TTyIntegerArray;
  k: Integer;
begin
  cs := CaseById('throws-alt-nan');
  AssertFalse('upstream threw', IsNull(cs.Find('throws')));
  Show(cs);
  se := cs.Arrays['series'].Objects[0];
  want := IntsOf(se.Objects['sampledStore'].Arrays['indices']);
  AssertEquals('upstream counted one more than it holds', Length(want) + 1,
    se.Objects['sampledStore'].Integers['count']);
  store := FChart.SeriesStore(0);
  AssertEquals('the rows the slots hold', Length(want), store.Count);
  for k := 0 to High(want) do
    AssertEquals(Format('row %d', [k]), want[k], store.GetRawIndex(k));
end;

procedure TAdvChartSamplingOracleTest.TestTheSamplingOptionReadsAsUpstream;

  function M(const AText: string): TTySamplingMode;
  var d: TJSONData;
  begin
    d := GetJSON(AText);
    try
      Result := TySamplingModeOf(d);
    finally
      d.Free;
    end;
  end;

begin
  AssertTrue('lttb', M('"lttb"') = tsmLttb);
  AssertTrue('minmax', M('"minmax"') = tsmMinmax);
  AssertTrue('average', M('"average"') = tsmAverage);
  AssertTrue('sum', M('"sum"') = tsmSum);
  AssertTrue('max', M('"max"') = tsmMax);
  AssertTrue('min', M('"min"') = tsmMin);
  AssertTrue('nearest', M('"nearest"') = tsmNearest);
  AssertTrue('case matters', M('"LTTB"') = tsmNone);
  AssertTrue('none', M('"none"') = tsmNone);
  AssertTrue('an unknown name', M('"median"') = tsmNone);
  AssertTrue('a prototype name is not a sampler here', M('"toString"') = tsmNone);
  AssertTrue('true', M('true') = tsmNone);
  AssertTrue('a number', M('3') = tsmNone);
  AssertTrue('null', M('null') = tsmNone);
  AssertTrue('absent', TySamplingModeOf(nil) = tsmNone);
end;

procedure TAdvChartSamplingOracleTest.TestTheRateAndTheGate;
var
  r: TTySampleResult;
  v: TTyIntegerArray;
  col: TTyDoubleArray;
  k: Integer;
begin
  AssertEquals('1.5 rounds up', 2, TySamplingRate(300, 200), 0);
  AssertEquals('1.495 rounds down', 1, TySamplingRate(299, 200), 0);
  AssertEquals('2.5 rounds up', 3, TySamplingRate(250, 100), 0);
  AssertTrue('a zero size is an infinite rate', IsInfinite(TySamplingRate(300, 0)));
  AssertTrue('a NaN size is a NaN rate', IsNan(TySamplingRate(300, NaN)));
  AssertFalse('rate 1', TySamplingApplies(300, 1));
  AssertTrue('rate 2', TySamplingApplies(300, 2));
  AssertFalse('ten rows', TySamplingApplies(10, 5));
  AssertTrue('eleven rows', TySamplingApplies(11, 6));
  AssertFalse('an infinite rate', TySamplingApplies(300, Infinity));
  AssertFalse('a NaN rate', TySamplingApplies(300, NaN));
  { a frame wider than the view is one frame }
  SetLength(v, 20);
  SetLength(col, 20);
  for k := 0 to 19 do
  begin
    v[k] := k;
    col[k] := k mod 7;
  end;
  r := TySampleView(tsmMinmax, v, col, 1e-12);
  AssertEquals('one frame, two rows', 2, Length(r.Indices));
  AssertEquals('the min first (row 0)', 0, r.Indices[0]);
  AssertEquals('then the max (row 6)', 6, r.Indices[1]);
  { a frame below one row samples nothing }
  r := TySampleView(tsmAverage, v, col, 2);
  AssertEquals('the view as it was', 20, Length(r.Indices));
  AssertFalse('nothing written', r.Wrote);
end;

{ THE PARSED VALUE SURVIVES: a slider's data shadow reads getRawData() }
procedure TAdvChartSamplingOracleTest.TestTheParsedValueSurvivesTheSampler;
var
  cs: TJSONObject;
  store: TTyDataStore;
  col, raw, k, changed: Integer;
  opt: TJSONArray;
  parsed: Double;
begin
  cs := CaseById('mode-average');
  Show(cs);
  store := FChart.SeriesStore(0);
  col := store.DimIndexOf('y');
  opt := TJSONArray(cs.Objects['option'].Arrays['series'].Objects[0].Arrays['data']);
  changed := 0;
  for k := 0 to store.Count - 1 do
  begin
    raw := store.GetRawIndex(k);
    parsed := opt.Floats[raw];
    AssertEquals(Format('row %d: the original', [k]), parsed, store.GetOriginalByRaw(col, raw), 0);
    if store.Get(col, k) <> parsed then Inc(changed);
  end;
  AssertTrue(Format('the view holds the averages (%d changed)', [changed]), changed > 50);
end;

{ THE SIZE IS READ EVERY BUILD: a narrower chart samples harder }
procedure TAdvChartSamplingOracleTest.TestAResizeSamplesAgain;
var
  n1, n2: Integer;
begin
  FChart.Option := '{"animation": false, "grid": {"left": 80, "right": 80,'
    + ' "outerBoundsMode": "none"}, "xAxis": {"type": "category"},'
    + ' "yAxis": {}, "series": [{"type": "line", "sampling": "average",'
    + ' "data": [' + StringReplace(StringOfChar('1', 1200), '1', '1,', [rfReplaceAll]) + '1]}]}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  n1 := FChart.SeriesStore(0).Count;
  FChart.SetBounds(0, 0, 400, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 400, 600), 96);
  n2 := FChart.SeriesStore(0).Count;
  { 1201 rows on 640 px: rate 2; on 240 px: rate 5 }
  AssertEquals('on 640 px', 601, n1);
  AssertEquals('on 240 px', 241, n2);
end;

{ THE MASK IS GIVEN BACK CLEAN: Infinity and NaN went through masked
  arithmetic, and the host's own division by zero still says so }
procedure TAdvChartSamplingOracleTest.TestTheMaskedArithmeticLeavesTheHostTrapsAlone;
var
  v: TTyIntegerArray;
  col: TTyDoubleArray;
  k: Integer;
  r: TTySampleResult;
  a, b: Double;
  raised: string;
begin
  SetLength(v, 30);
  SetLength(col, 30);
  for k := 0 to 29 do
  begin
    v[k] := k;
    if k mod 4 = 0 then col[k] := Infinity
    else if k mod 4 = 1 then col[k] := NaN
    else col[k] := k;
  end;
  r := TySampleView(tsmLttb, v, col, 1 / 3);
  AssertTrue('sampled', Length(r.Indices) > 2);
  r := TySampleView(tsmMax, v, col, 1 / 3);
  AssertTrue('an infinite max is NaN', IsNan(r.Column[r.Indices[0]]));
  a := 1;
  b := 0;
  raised := '';
  try
    a := a / b;
  except
    on E: Exception do raised := E.ClassName;
  end;
  AssertEquals('the host''s division by zero', 'EZeroDivide', raised);
end;

{ A WRITE IS SEEN BY THE NEXT EXTENT, whatever comes after it: the cache and
  the unfiltered fast path both go stale, not only when a view change happens
  to follow (the control always sets the view after the writes, which is what
  let a missing invalidation survive the first mutation round) }
procedure TAdvChartSamplingOracleTest.TestASampledValueIsSeenByTheExtent;
var
  st: TTyDataStore;
  d, k: Integer;
  lo, hi: Double;
begin
  st := TTyDataStore.Create;
  try
    d := st.AddDimension('y', ddtFloat);
    for k := 0 to 9 do st.AppendRow([TyDataNum(k)]);
    { unfiltered: the append-time fast path }
    AssertTrue(st.DataExtent(d, lo, hi));
    AssertEquals('before', 9, hi, 0);
    st.SetSampledValue(d, 3, 50);
    AssertTrue(st.DataExtent(d, lo, hi));
    AssertEquals('the write, unfiltered', 50, hi, 0);
    AssertEquals('the parsed value kept', 3, st.GetOriginalByRaw(d, 3), 0);
    { a view, its extent cached, then a write into it }
    st.SetSampledView([1, 3, 5], 3);
    AssertTrue(st.DataExtent(d, lo, hi));
    AssertEquals('the view', 50, hi, 0);
    st.SetSampledValue(d, 3, -7);
    AssertTrue(st.DataExtent(d, lo, hi));
    AssertEquals('the write, in a view: min', -7, lo, 0);
    AssertEquals('the write, in a view: max', 5, hi, 0);
    { a view as long as the input is still a view }
    st.SetSampledView([0, 0, 2, 2, 4, 4, 6, 6, 8, 8], 10);
    AssertTrue('as long as the input, still a view', st.IsFiltered);
    AssertEquals('row 1 is raw 0 again', 0, st.GetRawIndex(1));
  finally
    st.Free;
  end;
end;

procedure TAdvChartSamplingOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TSmpProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(800, 600, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FBad := 0;
  FCompared := 0;
  FReport := '';
  FMoved := 0;
  FMovedIds := '';
  FLabels := 0;
  FSymbols := 0;
  FBars := 0;
  FRuns := 0;
  FTipRows := 0;
end;

procedure TAdvChartSamplingOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

initialization
  RegisterTest(TAdvChartSamplingOracleTest);
end.
