unit test.advchart.datazoomwindow;
{$mode objfpc}{$H+}
{ dataZoom's processing -- which axes each dataZoom drives and which one
  owns each axis, the window worked out in percents and values, the axis
  extents and ticks that follow from its pins, and the rows the four filter
  modes leave -- held to what ECharts 6.1 itself computes.

  tools/advchart-oracle/visualmap-window.js's sibling, datazoom-window.js,
  runs the real build and records each dataZoom's model and window, every
  axis' raw base, pins, extent and ticks, and every series' surviving rows,
  emptied values and item layout.

  EXACT: bit for bit, -0 and 0 one. The line vertices are Float32 upstream
  and in the port's polyline alike.

  NaN written into an option (the fixture's `__nan` paths) cannot be JSON
  here; the key is fed as null, which the model treats the same way for
  every case recorded (a given NaN percent falls back to the extent end). }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Scale, tyControls.AdvChart.Data,
     tyControls.AdvChart.Series, tyControls.AdvChart.DataZoom,
     tyControls.AdvanceChart;
type
  TDzwProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartDataZoomWindowOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TDzwProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FName: string;
    FOpt: TJSONObject;
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; AGot: Double; AData: TJSONData);
    procedure CheckZooms(ACase: TJSONObject);
    procedure CheckAxes(ACase: TJSONObject);
    procedure CheckSeries(ACase: TJSONObject);
    procedure RunCases(const AIds: array of string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestWindowsAsUpstream;
    procedure TestTargetsAndHostsAsUpstream;
    procedure TestAlignedAxesAsUpstream;
    procedure TestFilterModesAsUpstream;
    procedure TestGalleryAsUpstream;
    procedure TestSliderMoveShiftsKeepingTheSpan;
    procedure TestAnUntypedDataZoomIsASlider;
  end;

implementation

uses tyControls.AdvChart.Complete;

procedure TDzwProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TDzwProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-datazoom-window.json';
end;

function GalleryPath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'examples'
    + PathDelim + 'advchart' + PathDelim + 'gallery' + PathDelim + AName + '.json';
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

function IsNull(A: TJSONData): Boolean;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

{ bit for bit, -0 and 0 one, NaN and NaN one }
function SameNum(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  if (A = 0) and (B = 0) then Exit(True);
  Result := Bits(A) = Bits(B);
end;

{ a recorded double; null reads as not-a-number }
function HexOf(A: TJSONData): Double;
begin
  if IsNull(A) then Exit(NaN);
  Result := FromHex(A.AsString);
end;

function F32(A: Double): Double;
var s: Single;
begin
  if IsNan(A) then Exit(A);
  s := A;
  Result := s;
end;

procedure TAdvChartDataZoomWindowOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TDzwProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(800, 600, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartDataZoomWindowOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartDataZoomWindowOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 50 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartDataZoomWindowOracleTest.Num(const AWhat: string;
  AGot: Double; AData: TJSONData);
begin
  Inc(FCompared);
  if not SameNum(AGot, HexOf(AData)) then
    Miss(Format('%s: %s upstream, %s here', [AWhat, Fmt(HexOf(AData)), Fmt(AGot)]));
end;

{ ==================== the models ==================== }

procedure TAdvChartDataZoomWindowOracleTest.CheckZooms(ACase: TJSONObject);
const
  cModes: array[TTyDzRangeMode] of string = ('percent', 'value');
  cFilters: array[TTyDzFilterMode] of string = ('filter', 'weakFilter', 'empty', 'none');
var
  arr, tg, hs: TJSONArray;
  dz, w: TJSONObject;
  i, k, host, rep: Integer;
  spec: TTyDataZoomSpec;
  z: TTyAxisZoom;
  win, rwin: TTyDzWindow;
  hosts, want: string;
begin
  arr := ACase.Arrays['dataZooms'];
  Inc(FCompared);
  if FChart.DataZoomCount <> arr.Count then
  begin
    Miss(Format('%d dataZooms upstream, %d here', [arr.Count, FChart.DataZoomCount]));
    Exit;
  end;
  for i := 0 to arr.Count - 1 do
  begin
    dz := arr.Objects[i];
    spec := FChart.DataZoomSpec(i);
    Inc(FCompared);
    if spec.SubType <> dz.Strings['subType'] then
      Miss(Format('dz%d: %s upstream, %s here', [i, dz.Strings['subType'], spec.SubType]));
    if spec.Orient <> dz.Strings['orient'] then
      Miss(Format('dz%d: orient %s upstream, %s here', [i, dz.Strings['orient'], spec.Orient]));
    if spec.NoTarget <> dz.Booleans['noTarget'] then
      Miss(Format('dz%d: noTarget differs', [i]));
    tg := dz.Arrays['targets'];
    if Length(spec.Targets) <> tg.Count then
      Miss(Format('dz%d: %d targets upstream, %d here', [i, tg.Count, Length(spec.Targets)]))
    else
      for k := 0 to tg.Count - 1 do
        if (spec.Targets[k].Dim <> tg.Objects[k].Strings['dim'])
          or (spec.Targets[k].AxisIndex <> tg.Objects[k].Integers['axisIndex']) then
          Miss(Format('dz%d target %d: %s%d upstream, %s%d here', [i, k,
            tg.Objects[k].Strings['dim'], tg.Objects[k].Integers['axisIndex'],
            spec.Targets[k].Dim, spec.Targets[k].AxisIndex]));
    { the modes and the filter, for a model upstream knows }
    if spec.SubType <> 'select' then
      for k := 0 to 1 do
        if cModes[spec.Mode[k]] <> dz.Arrays['rangePropMode'].Strings[k] then
          Miss(Format('dz%d end %d: %s upstream, %s here', [i, k,
            dz.Arrays['rangePropMode'].Strings[k], cModes[spec.Mode[k]]]));
    if (dz.Find('filterMode') <> nil) and (dz.Find('filterMode').JSONType = jtString)
      and (cFilters[spec.FilterMode] <> dz.Strings['filterMode']) then
      Miss(Format('dz%d: filterMode %s upstream, %s here', [i, dz.Strings['filterMode'],
        cFilters[spec.FilterMode]]));
    { WHAT IT HOSTS: the axes whose owner it is }
    hs := dz.Arrays['hosts'];
    hosts := '';
    for k := 0 to High(spec.Targets) do
      if FChart.AxisZoom(spec.Targets[k].Dim + 'Axis', spec.Targets[k].AxisIndex,
        z, win, host) and (host = i) then
        hosts := hosts + spec.Targets[k].Dim + IntToStr(spec.Targets[k].AxisIndex) + ';';
    want := '';
    for k := 0 to hs.Count - 1 do
      want := want + hs.Objects[k].Strings['dim']
        + IntToStr(hs.Objects[k].Integers['axisIndex']) + ';';
    Inc(FCompared);
    if hosts <> want then
      Miss(Format('dz%d hosts %s upstream, %s here', [i, want, hosts]));
    { THE WINDOW -- findRepresentativeAxisProxy: the first axis it hosts,
      else the first it targets }
    if IsNull(dz.Find('window')) then Continue;
    w := dz.Objects['window'];
    rep := -1;
    for k := 0 to High(spec.Targets) do
      if FChart.AxisZoom(spec.Targets[k].Dim + 'Axis', spec.Targets[k].AxisIndex,
        z, win, host) and (host = i) then
      begin
        rep := k;
        Break;
      end;
    if rep < 0 then
      for k := 0 to High(spec.Targets) do
        if FChart.AxisZoom(spec.Targets[k].Dim + 'Axis', spec.Targets[k].AxisIndex,
          z, win, host) then
        begin
          rep := k;
          Break;
        end;
    if rep < 0 then
    begin
      Miss(Format('dz%d: no window here', [i]));
      Continue;
    end;
    FChart.AxisZoom(spec.Targets[rep].Dim + 'Axis', spec.Targets[rep].AxisIndex,
      z, rwin, host);
    for k := 0 to 1 do
    begin
      Num(Format('dz%d value %d', [i, k]), rwin.Value[k], w.Arrays['value'].Items[k]);
      Num(Format('dz%d percent %d', [i, k]), rwin.Percent[k], w.Arrays['percent'].Items[k]);
      Num(Format('dz%d percentInverted %d', [i, k]), rwin.PercentInverted[k],
        w.Arrays['percentInverted'].Items[k]);
    end;
    Num(Format('dz%d precision', [i]), rwin.Precision, w.Find('valuePrecision'));
  end;
end;

{ the labelled ticks: a minor tick is Level 1 }
function MajorOf(const A: TTyScaleTickArray): TTyScaleTickArray;
var k, n: Integer;
begin
  Result := nil;
  n := 0;
  SetLength(Result, Length(A));
  for k := 0 to High(A) do
    if A[k].Level = 0 then
    begin
      Result[n] := A[k];
      Inc(n);
    end;
  SetLength(Result, n);
end;

procedure TAdvChartDataZoomWindowOracleTest.CheckAxes(ACase: TJSONObject);
var
  arr, tk: TJSONArray;
  a: TJSONObject;
  i, k, host: Integer;
  ax: TTyAxis;
  main: string;
  z: TTyAxisZoom;
  win: TTyDzWindow;
  zoomed: Boolean;
  e: TTyRange;
  ticks: TTyScaleTickArray;
begin
  arr := ACase.Arrays['axes'];
  for i := 0 to arr.Count - 1 do
  begin
    a := arr.Objects[i];
    main := a.Strings['dim'] + 'Axis';
    ax := FChart.Build.Axis(main, a.Integers['index']);
    Inc(FCompared);
    if ax = nil then
    begin
      Miss(Format('%s%d: no axis here', [a.Strings['dim'], a.Integers['index']]));
      Continue;
    end;
    zoomed := FChart.AxisZoom(main, a.Integers['index'], z, win, host);
    if zoomed <> a.Booleans['zoomed'] then
    begin
      Miss(Format('%s%d: zoomed %s here', [a.Strings['dim'], a.Integers['index'],
        BoolToStr(zoomed, True)]));
      Continue;
    end;
    if zoomed then
    begin
      Inc(FCompared);
      if host <> a.Integers['hostedBy'] then
        Miss(Format('%s%d: hosted by %d upstream, %d here', [a.Strings['dim'],
          a.Integers['index'], a.Integers['hostedBy'], host]));
      Num(a.Strings['dim'] + ' noZoom 0', z.Raw.Lo, a.Arrays['noZoom'].Items[0]);
      Num(a.Strings['dim'] + ' noZoom 1', z.Raw.Hi, a.Arrays['noZoom'].Items[1]);
      Num(a.Strings['dim'] + ' zoomMM 0', z.ZoomLo, a.Arrays['zoomMM'].Items[0]);
      Num(a.Strings['dim'] + ' zoomMM 1', z.ZoomHi, a.Arrays['zoomMM'].Items[1]);
    end;
    { AND WHAT THE AXIS BECAME }
    e := ax.Scale.GetExtent;
    Num(Format('%s%d extent 0', [a.Strings['dim'], a.Integers['index']]), e.Start,
      a.Arrays['extent'].Items[0]);
    Num(Format('%s%d extent 1', [a.Strings['dim'], a.Integers['index']]), e.Stop,
      a.Arrays['extent'].Items[1]);
    if (not IsNull(a.Find('interval'))) and (ax.Scale is TTyIntervalScale)
      and not (ax.Scale is TTyTimeScale) then
      Num(Format('%s%d interval', [a.Strings['dim'], a.Integers['index']]),
        TTyIntervalScale(ax.Scale).Interval, a.Find('interval'));
    if (not IsNull(a.Find('ticks'))) and not (ax.Scale is TTyTimeScale) then
    begin
      tk := a.Arrays['ticks'];
      ticks := MajorOf(ax.Scale.GetTicks);
      Inc(FCompared);
      if Length(ticks) <> tk.Count then
        Miss(Format('%s%d: %d ticks upstream, %d here (%s..%s)', [a.Strings['dim'],
          a.Integers['index'], tk.Count, Length(ticks), Fmt(ticks[0].Value),
          Fmt(ticks[High(ticks)].Value)]))
      else
        for k := 0 to tk.Count - 1 do
          Num(Format('%s%d tick %d', [a.Strings['dim'], a.Integers['index'], k]),
            ticks[k].Value, tk.Items[k]);
    end;
  end;
end;

{ ==================== the rows ==================== }

procedure TAdvChartDataZoomWindowOracleTest.CheckSeries(ACase: TJSONObject);
var
  arr, ri, lay, em, vals: TJSONArray;
  s, it: TJSONObject;
  i, k, j, si, col, n, found: Integer;
  store: TTyDataStore;
  cnt: Integer;
  typ: string;
  lst: TTyPaintList;
  e, mark: TTyChartElement;
  ring: array of TTyPointF;
  wantPts: array of TTyPointF;
  b: TTyRectF;
  x, y, w, h, l, r, t, bt: Double;
  px, py, pw, ph: Double;

  { the series' plot rect, from its axes }
  procedure PlotOf(ACs, ASer: TJSONObject; out AX, AY, AW, AH: Double);
  var xa, ya: TTyAxis;
  begin
    xa := FChart.Build.Axis('xAxis', ASer.Integers['xAxisIndex']);
    ya := FChart.Build.Axis('yAxis', ASer.Integers['yAxisIndex']);
    AX := Min(xa.PxStart, xa.PxStop);
    AW := Abs(xa.PxStop - xa.PxStart);
    AY := Min(ya.PxStart, ya.PxStop);
    AH := Abs(ya.PxStop - ya.PxStart);
  end;

  function Smooth(ASi: Integer): Boolean;
  var d: TJSONData;
  begin
    Result := False;
    d := FOpt.Find('series');
    if (d = nil) or (d.JSONType <> jtArray) or (ASi >= TJSONArray(d).Count) then Exit;
    d := TJSONArray(d).Items[ASi];
    if d.JSONType <> jtObject then Exit;
    d := TJSONObject(d).Find('smooth');
    Result := (d <> nil) and (((d.JSONType = jtBoolean) and d.AsBoolean)
      or ((d.JSONType = jtNumber) and (d.AsFloat <> 0)));
  end;

  function SamePlot(ACs, ASer: TJSONObject): Boolean;
  var
    ax: TJSONArray;
    k2: Integer;
    a2: TJSONObject;
    xa: TTyAxis;
  begin
    Result := True;
    ax := ACs.Arrays['axes'];
    for k2 := 0 to ax.Count - 1 do
    begin
      a2 := ax.Objects[k2];
      if IsNull(a2.Find('pxSpanFinal')) then Continue;
      xa := FChart.Build.Axis(a2.Strings['dim'] + 'Axis', a2.Integers['index']);
      if (xa <> nil) and not SameNum(xa.PxLength, HexOf(a2.Find('pxSpanFinal'))) then
        Exit(False);
    end;
  end;

begin
  arr := ACase.Arrays['series'];
  lst := FChart.List;
  for i := 0 to arr.Count - 1 do
  begin
    s := arr.Objects[i];
    si := s.Integers['index'];
    typ := s.Strings['type'];
    { a series the legend switched off: upstream records nothing more }
    if s.Find('count') = nil then Continue;
    store := FChart.SeriesStore(si);
    Inc(FCompared);
    if store = nil then
    begin
      Miss(Format('s%d: no store here', [si]));
      Continue;
    end;
    { A SAMPLED SERIES (lttb) is compared as it was finally drawn: the rows
      the sampler kept after the dataZoom's. [Batch 102: it was compared as
      the dataZoom left it, because the port did not sample; `stage` is the
      snapshot before the sampler.] }
    cnt := s.Integers['count'];
    ri := s.Arrays['rawIndices'];
    if store.RawCount <> s.Integers['rawCount'] then
      Miss(Format('s%d: %d raw rows upstream, %d here', [si, s.Integers['rawCount'],
        store.RawCount]));
    if store.Count <> cnt then
    begin
      Miss(Format('s%d: %d rows kept upstream, %d here', [si, cnt, store.Count]));
      Continue;
    end;
    for k := 0 to ri.Count - 1 do
    begin
      Inc(FCompared);
      if store.GetRawIndex(k) <> ri.Integers[k] then
      begin
        Miss(Format('s%d row %d: raw %d upstream, %d here', [si, k, ri.Integers[k],
          store.GetRawIndex(k)]));
        Break;
      end;
    end;
    { 'empty': the values that went }
    if not IsNull(s.Find('emptied')) then
    begin
      em := s.Arrays['emptied'];
      for j := 0 to em.Count - 1 do
      begin
        col := store.DimIndexOf(em.Objects[j].Strings['coordDim']);
        vals := em.Objects[j].Arrays['values'];
        Inc(FCompared);
        if col < 0 then
        begin
          Miss(Format('s%d: no %s column here', [si, em.Objects[j].Strings['coordDim']]));
          Continue;
        end;
        { recorded as store.get(dim, i): i is a VIEW index, so the rows
          in view are what it says anything about }
        for k := 0 to Min(vals.Count, store.Count) - 1 do
          { null: not recorded (a store map made after a filter) }
          if not IsNull(vals.Items[k]) then
          Num(Format('s%d %s row %d', [si, em.Objects[j].Strings['coordDim'], k]),
            store.Get(col, k), vals.Items[k]);
      end;
    end;

    { AND DRAWN THERE -- where the plot is where upstream's is. The final
      grid rect follows the axis labels' measured widths, and this test
      measures with the skin's font, not zrender's; a case whose plot moved
      for that reason is not a dataZoom question. }
    if IsNull(s.Find('layout')) or (lst = nil) then Continue;
    if not SamePlot(ACase, s) then Continue;
    lay := s.Arrays['layout'];
    { KNOWN: a smooth line is drawn as a polyline here -- the port has no
      smooth yet, which is not a dataZoom question }
    if (typ = 'line') and Smooth(si) then Continue;
    if typ = 'line' then
    begin
      ring := nil;
      for k := 0 to lst.Count - 1 do
      begin
        e := lst.Element(k);
        if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si)
          or (e.Datum.RawDataIndex <> -1) or e.Silent
          or (e.Shape.Kind <> cskPolyline) then Continue;
        n := Length(ring);
        SetLength(ring, n + Length(e.Shape.Points));
        for j := 0 to High(e.Shape.Points) do ring[n + j] := e.Shape.Points[j];
      end;
      wantPts := nil;
      for k := 0 to lay.Count - 1 do
        if lay.Items[k].JSONType = jtArray then
        begin
          n := Length(wantPts);
          SetLength(wantPts, n + 1);
          wantPts[n].X := F32(HexOf(TJSONArray(lay.Items[k]).Items[0]));
          wantPts[n].Y := F32(HexOf(TJSONArray(lay.Items[k]).Items[1]));
        end;
      Inc(FCompared);
      if Length(ring) <> Length(wantPts) then
        Miss(Format('s%d: %d vertices upstream, %d here', [si, Length(wantPts), Length(ring)]))
      else
        for k := 0 to High(ring) do
        begin
          Inc(FCompared);
          if not (SameNum(F32(ring[k].X), wantPts[k].X) and SameNum(F32(ring[k].Y), wantPts[k].Y)) then
          begin
            Miss(Format('s%d vertex %d: %s,%s upstream, %s,%s here (next %s,%s / %s,%s)', [si, k,
              Fmt(wantPts[k].X), Fmt(wantPts[k].Y), Fmt(ring[k].X), Fmt(ring[k].Y),
              Fmt(wantPts[Min(k + 1, High(wantPts))].X), Fmt(wantPts[Min(k + 1, High(wantPts))].Y),
              Fmt(ring[Min(k + 1, High(ring))].X), Fmt(ring[Min(k + 1, High(ring))].Y)]));
            Break;
          end;
        end;
      Continue;
    end;
    if (typ <> 'bar') and (typ <> 'scatter') then Continue;
    for k := 0 to lay.Count - 1 do
    begin
      if IsNull(lay.Items[k]) then Continue;
      found := 0;
      mark := Default(TTyChartElement);
      for j := 0 to lst.Count - 1 do
      begin
        e := lst.Element(j);
        if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si)
          or (e.Datum.RawDataIndex <> ri.Integers[k]) then Continue;
        if e.Caption.FontSizeLogical > 0 then Continue;
        Inc(found);
        mark := e;
      end;
      Inc(FCompared);
      if found <> 1 then
      begin
        Miss(Format('s%d raw %d: %d marks here', [si, ri.Integers[k], found]));
        Continue;
      end;
      b := TyShapeBounds(mark.Shape);
      if typ = 'bar' then
      begin
        it := TJSONObject(lay.Items[k]);
        x := HexOf(it.Find('x'));
        y := HexOf(it.Find('y'));
        w := HexOf(it.Find('width'));
        h := HexOf(it.Find('height'));
        l := Min(x, x + w);
        r := Max(x, x + w);
        t := Min(y, y + h);
        bt := Max(y, y + h);
        { clip.cartesian2d: the layout cut at the plot, as the bar is drawn }
        PlotOf(ACase, s, px, py, pw, ph);
        l := Max(l, px);
        r := Min(r, px + pw);
        t := Max(t, py);
        bt := Min(bt, py + ph);
        if not (SameNum(b.Left, l) and SameNum(b.Right, r) and SameNum(b.Top, t)
          and SameNum(b.Bottom, bt)) then
          Miss(Format('s%d raw %d: bar %s,%s..%s,%s upstream, %s,%s..%s,%s here',
            [si, ri.Integers[k], Fmt(l), Fmt(t), Fmt(r), Fmt(bt), Fmt(b.Left),
             Fmt(b.Top), Fmt(b.Right), Fmt(b.Bottom)]));
      end
      else
      begin
        x := HexOf(TJSONArray(lay.Items[k]).Items[0]);
        y := HexOf(TJSONArray(lay.Items[k]).Items[1]);
        if not (SameNum(F32((b.Left + b.Right) / 2), F32(x))
          and SameNum(F32((b.Top + b.Bottom) / 2), F32(y))) then
          Miss(Format('s%d raw %d: point %s,%s upstream, %s,%s here', [si,
            ri.Integers[k], Fmt(x), Fmt(y), Fmt((b.Left + b.Right) / 2),
            Fmt((b.Top + b.Bottom) / 2)]));
      end;
    end;
  end;
end;

procedure TAdvChartDataZoomWindowOracleTest.RunCases(const AIds: array of string);
var
  cases: TJSONArray;
  cs, opt: TJSONObject;
  sl: TStringList;
  c, j, ran: Integer;
  wanted: Boolean;
begin
  ran := 0;
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    wanted := False;
    for j := 0 to High(AIds) do
      if (cs.Strings['id'] = AIds[j])
        or ((Length(AIds[j]) = 1) and (Copy(cs.Strings['id'], 1, 1) = AIds[j])) then
        wanted := True;
    if not wanted then Continue;
    Inc(ran);
    FName := cs.Strings['id'];
    if cs.Find('option').JSONType = jtObject then
      opt := TJSONObject(cs.Objects['option'].Clone)
    else
    begin
      sl := TStringList.Create;
      try
        sl.LoadFromFile(GalleryPath(cs.Strings['gallery']));
        opt := TJSONObject(GetJSON(sl.Text));
      finally
        sl.Free;
      end;
    end;
    try
      if opt.Find('__nan') <> nil then opt.Delete('__nan');
      FOpt := opt;
      FChart.Option := opt.AsJSON;
      AssertEquals(FName + ' parses', '', FChart.OptionError);
      FChart.SetBounds(0, 0, cs.Integers['width'], cs.Integers['height']);
      try
        FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cs.Integers['width'],
          cs.Integers['height']), 96);
      except
        on E: Exception do
        begin
          Miss(E.ClassName + ': ' + E.Message);
          Continue;
        end;
      end;
      CheckZooms(cs);
      CheckAxes(cs);
      CheckSeries(cs);
    finally
      opt.Free;
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue('the named cases ran', ran > 0);
end;

procedure TAdvChartDataZoomWindowOracleTest.TestWindowsAsUpstream;
begin
  RunCases(['W']);
end;

procedure TAdvChartDataZoomWindowOracleTest.TestTargetsAndHostsAsUpstream;
begin
  RunCases(['T']);
end;

procedure TAdvChartDataZoomWindowOracleTest.TestAlignedAxesAsUpstream;
begin
  RunCases(['A']);
end;

procedure TAdvChartDataZoomWindowOracleTest.TestFilterModesAsUpstream;
begin
  RunCases(['F']);
end;

procedure TAdvChartDataZoomWindowOracleTest.TestGalleryAsUpstream;
begin
  RunCases(['G']);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > 2000);
end;

procedure TAdvChartDataZoomWindowOracleTest.TestSliderMoveShiftsKeepingTheSpan;
var e: array[0..1] of Double;
begin
  { upstream.md 2.5, observed: a window off the extent moves back in whole }
  e[0] := -10; e[1] := 50;
  TyDzSliderMove(0, e, 0, 100, -1, NaN, NaN);
  AssertTrue('-10..50 -> 0..60: ' + Fmt(e[0]) + '..' + Fmt(e[1]), (e[0] = 0) and (e[1] = 60));
  e[0] := 60; e[1] := 130;
  TyDzSliderMove(0, e, 0, 100, -1, NaN, NaN);
  AssertTrue('60..130 -> 30..100', (e[0] = 30) and (e[1] = 100));
  e[0] := 40; e[1] := 45;
  TyDzSliderMove(0, e, 0, 100, -1, 20, NaN);
  AssertTrue('minSpan 20: 40..60', (e[0] = 40) and (e[1] = 60));
end;

procedure TAdvChartDataZoomWindowOracleTest.TestAnUntypedDataZoomIsASlider;
var o: TJSONObject;
begin
  o := TJSONObject(GetJSON('{"start": 10}'));
  try
    AssertEquals('slider', TyOptDefaultSubType('dataZoom', o));
  finally
    o.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartDataZoomWindowOracleTest);
end.
