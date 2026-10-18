unit test.advchart.progressive;
{$mode objfpc}{$H+}
{ Progressive rendering and appendData -- held to upstream to the bit
  [Batch 119, C9].

  tools/advchart-oracle/progressive.js runs the real ECharts 6.1 build with
  its painter typed 'canvas' (progressive rendering needs one) and steps
  zrender's frames by hand, an iteration of _onframe costing the case's ms;
  it records after the setOption and after every frame, appendData, pointer
  step and snapshot: the `rendered` / `finished` and mouse events, whether
  the scheduler is unfinished, every series' pipeline (progressiveRender,
  large, modDataCount, step), the rows its datum elements stand for, its
  large batches (points or their FNV, indices, startIndex, bounding rect),
  the element and the row under the pointer and the tooltip, and -- at a
  snapshot -- the positions of the datum elements.

  The port is driven the same way: SetOption, ProgressTick at the case's
  ProgressiveStepCostMs, AppendData, MouseMove / MouseLeave, a headless render
  after each, and compared through SeriesProgress, the paint list's shown
  elements (ProgHidden, ProgRow), HitTestAt, the events and the tooltip.
  Cases the oracle marks replay: false are upstream's own breakage after
  appendData that the port does not copy (see the spec, section 154). }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Shape, tyControls.AdvChart.Large,
     tyControls.AdvChart.Progressive, tyControls.AdvChart.Events,
     tyControls.AdvChart.Data, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Builder,
     tyControls.AdvanceChart;
type
  TPgProbe = class(TTyAdvanceChart)
  public
    Events: TStringList;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    procedure Leave;
    function List: TTyPaintList;
    procedure OnEv(Sender: TObject; const AEvent: TTyChartEvent);
  end;

  TAdvChartProgressiveOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TPgProbe;
    FRoot: TJSONData;
    FBad, FCompared, FSnaps: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure SameHex(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameInt(const AWhat: string; AGot, AWant: Integer);
    procedure NewChart;
    procedure RenderNow;
    procedure CheckSnap(ASnap: TJSONObject);
    procedure CheckSeries(ASr: TJSONObject; ACountToo: Boolean);
    procedure CheckGeom(AGeom: TJSONArray);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryFrameAndEveryHitAsUpstream;
  end;

  { What the oracle does not reach. }
  TAdvChartProgressiveTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TPgProbe;
    procedure Show(const AOption: string; AW: Integer = 600; AH: Integer = 400);
    procedure RenderNow(AW: Integer = 600; AH: Integer = 400);
    function ShownRows(ASeries: Integer): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheModWalkIsUpstreams;
    procedure TestTheSpecReadsJavaScriptValues;
    procedure TestAppendDataRefusesWhatUpstreamCannotTake;
    procedure TestTheAxesStayUntilAFullUpdate;
    procedure TestASetOptionStartsAgain;
    procedure TestTheTimerFrameRendersOnce;
    procedure TestAHiddenChunkIsNeitherDrawnNorFound;
    procedure TestAHundredThousandPointsComeInChunks;
  end;

implementation

{ ==================== helpers ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-progressive.json';
end;

function HexNum(AData: TJSONData): Double;
var q: QWord;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  q := StrToQWord('$' + AData.AsString);
  Result := 0;
  System.Move(q, Result, SizeOf(Result));
end;

function HexOf(A: Double): string;
var q: QWord;
begin
  if IsNan(A) then Exit('7ff8000000000000');
  System.Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

{ FNV-1a 32 over the hex strings, as the oracle folds a long points array }
function FnvOf(const APts: TTyDoubleArray; ACount: Integer): QWord;
var i, k: Integer; s: string; h: QWord;
begin
  h := $811c9dc5;
  for i := 0 to ACount - 1 do
  begin
    s := HexOf(APts[i]);
    for k := 1 to Length(s) do
    begin
      h := h xor Ord(s[k]);
      h := (h * $01000193) and $FFFFFFFF;
    end;
  end;
  Result := h;
end;

function Fmt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if IsNan(A) then Exit('NaN');
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

{ sorted unique rows as the oracle's inclusive ranges }
function RangesText(const ARows: TTyIntegerArray): string;
var
  s: array of Integer;
  i, j, t, a: Integer;
begin
  s := Copy(ARows);
  for i := 1 to High(s) do
  begin
    t := s[i];
    j := i - 1;
    while (j >= 0) and (s[j] > t) do
    begin
      s[j + 1] := s[j];
      Dec(j);
    end;
    s[j + 1] := t;
  end;
  Result := '';
  i := 0;
  while i <= High(s) do
  begin
    a := s[i];
    j := i;
    while (j < High(s)) and ((s[j + 1] = s[j]) or (s[j + 1] = s[j] + 1)) do Inc(j);
    if Result <> '' then Result := Result + ',';
    Result := Result + Format('[%d,%d]', [a, s[j]]);
    i := j + 1;
  end;
end;

function JsonRangesText(AArr: TJSONArray): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to AArr.Count - 1 do
  begin
    if Result <> '' then Result := Result + ',';
    Result := Result + Format('[%d,%d]', [TJSONArray(AArr.Items[i]).Integers[0],
      TJSONArray(AArr.Items[i]).Integers[1]]);
  end;
end;

{ the rows a series' datum elements stand for, as drawn now }
function ShownRowsOf(AList: TTyPaintList; AChart: TTyAdvanceChart;
  ASeries: Integer): TTyIntegerArray;
var
  k, slotRow: Integer;
  el: TTyChartElement;
  run: TTyProgRun;
begin
  Result := nil;
  if AList = nil then Exit;
  run := AChart.SeriesProgress(ASeries);
  for k := 0 to AList.Count - 1 do
  begin
    el := AList.Element(k);
    if el.Ignore or el.ProgHidden or (el.Shape.Kind = cskLarge) then Continue;
    slotRow := -1;
    if (el.Datum.Kind = ctkSeries) and (el.Datum.SeriesIndex = ASeries)
      and (el.Datum.DataIndex >= 0) and not el.Datum.IsEdge then
      slotRow := el.Datum.DataIndex
    else if (el.ProgChunk > 0) and (el.Datum.SeriesIndex < 0)
      and (run.Series = ASeries) and (el.ProgSlot >= 0) then
      { an incremental candle: no datum, its row kept }
      slotRow := el.ProgRow;
    if slotRow < 0 then Continue;
    if el.Silent and (el.Shape.Kind <> cskLarge) and (el.Caption.Text <> '') then Continue;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := slotRow;
  end;
end;

{ ==================== the probe ==================== }

constructor TPgProbe.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Events := TStringList.Create;
end;

destructor TPgProbe.Destroy;
begin
  Events.Free;
  inherited Destroy;
end;

procedure TPgProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TPgProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TPgProbe.Leave;
begin
  MouseLeave;
end;

function TPgProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TPgProbe.OnEv(Sender: TObject; const AEvent: TTyChartEvent);
begin
  if (AEvent.EventType = 'rendered') or (AEvent.EventType = 'finished') then
    Events.Add(AEvent.EventType)
  else
    Events.Add(Format('%s %d:%d/%d', [AEvent.EventType, AEvent.Params.SeriesIndex,
      AEvent.Params.RawDataIndex, AEvent.Params.DataIndex]));
end;

{ ==================== the oracle test ==================== }

procedure TAdvChartProgressiveOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
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
  FSnaps := 0;
  FReport := '';
end;

procedure TAdvChartProgressiveOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartProgressiveOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 80 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartProgressiveOracleTest.SameHex(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double; ok: Boolean;
begin
  Inc(FCompared);
  want := HexNum(AWant);
  if IsNan(want) or IsNan(AGot) then ok := IsNan(want) and IsNan(AGot)
  else ok := AGot = want;
  if not ok then
    Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(want), Fmt(AGot)]));
end;

procedure TAdvChartProgressiveOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

procedure TAdvChartProgressiveOracleTest.SameInt(const AWhat: string; AGot, AWant: Integer);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is %d upstream, %d here', [AWhat, AWant, AGot]));
end;

procedure TAdvChartProgressiveOracleTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TPgProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, FRoot.FindPath('W').AsInteger, FRoot.FindPath('H').AsInteger);
  FChart.AnimationMode := camOff;
  { a clock that stands still: no timer, every frame is ProgressTick }
  FChart.AnimNow := 0;
  FChart.ChartOn('mouseover', @FChart.OnEv);
  FChart.ChartOn('mousemove', @FChart.OnEv);
  FChart.ChartOn('mouseout', @FChart.OnEv);
  FChart.ChartOn('rendered', @FChart.OnEv);
  FChart.ChartOn('finished', @FChart.OnEv);
end;

procedure TAdvChartProgressiveOracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FRoot.FindPath('W').AsInteger, FRoot.FindPath('H').AsInteger,
    BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartProgressiveOracleTest.CheckSeries(ASr: TJSONObject;
  ACountToo: Boolean);
var
  si, k, j, e, n, rows: Integer;
  pr: TTyProgRun;
  what, kind, gotKind: string;
  st: TTyDataStore;
  list: TTyPaintList;
  got: TTyIntegerArray;
  el: TTyChartElement;
  g: TTyLargeGeom;
  els, want: TJSONArray;
  er: TJSONObject;
begin
  si := ASr.Integers['seriesIndex'];
  what := Format('series %d', [si]);
  pr := FChart.SeriesProgress(si);
  SameStr(what + ' progressive', BoolToStr(pr.On, True), BoolToStr(ASr.Booleans['prog'], True));
  SameStr(what + ' large', BoolToStr(pr.Large, True), BoolToStr(ASr.Booleans['large'], True));
  if ASr.Find('mod').JSONType = jtNull then SameInt(what + ' modDataCount', pr.ModCount, -1)
  else SameInt(what + ' modDataCount', pr.ModCount, ASr.Integers['mod']);
  if ASr.Find('step').JSONType = jtNull then
    SameStr(what + ' progressive enabled', BoolToStr(pr.Spec.Enabled, True), 'False')
  else
  begin
    SameStr(what + ' progressive enabled', BoolToStr(pr.Spec.Enabled, True), 'True');
    SameInt(what + ' step', pr.Spec.Step, ASr.Integers['step']);
  end;
  if ACountToo then
  begin
    st := FChart.SeriesStore(si);
    if st <> nil then SameInt(what + ' count', st.Count, ASr.Integers['count'])
    else Miss(what + ': no store');
  end;
  list := FChart.List;
  { the datum elements drawn }
  got := ShownRowsOf(list, FChart, si);
  SameStr(what + ' rows', RangesText(got), JsonRangesText(ASr.Arrays['rows']));
  { the large batches drawn, in the order they were added }
  got := nil;
  if list <> nil then
    for k := 0 to list.Count - 1 do
    begin
      el := list.Element(k);
      if (el.Shape.Kind = cskLarge) and (el.Datum.SeriesIndex = si) and not el.ProgHidden then
      begin
        SetLength(got, Length(got) + 1);
        got[High(got)] := k;
      end;
    end;
  els := ASr.Arrays['els'];
  SameInt(what + ' large batches', Length(got), els.Count);
  if Length(got) <> els.Count then Exit;
  for e := 0 to els.Count - 1 do
  begin
    er := els.Objects[e];
    el := list.Element(got[e]);
    g := el.Shape.Large;
    kind := er.Strings['kind'];
    case g.Kind of
      lgkBar: if el.Silent then gotKind := 'barBg' else gotKind := 'bar';
      lgkSymbol: gotKind := 'symbol';
      lgkCandle: gotKind := 'candle';
    else
      gotKind := '?';
    end;
    what := Format('series %d %s %d', [si, kind, e]);
    SameStr(what + ' kind', gotKind, kind);
    if gotKind <> kind then Continue;
    rows := TyLargeRows(g);
    case g.Kind of
      lgkBar: n := rows * 3;
      lgkSymbol: n := rows * 2;
    else
      n := rows * 4;
    end;
    SameInt(what + ' numbers', n, er.Integers['n']);
    if n <> er.Integers['n'] then Continue;
    if er.Find('pts') <> nil then
    begin
      want := er.Arrays['pts'];
      j := 0;
      for k := 0 to want.Count - 1 do
        if HexOf(g.Pts[k]) <> want.Strings[k] then
        begin
          Inc(j);
          if j <= 3 then
            Miss(Format('%s point %d is %s upstream, %s here', [what, k,
              Fmt(HexNum(want.Items[k])), Fmt(g.Pts[k])]));
        end;
      Inc(FCompared, want.Count);
      if j > 3 then Miss(Format('%s: %d points differ', [what, j]));
    end
    else
    begin
      Inc(FCompared);
      if FnvOf(g.Pts, n) <> QWord(er.Int64s['fnv']) then
        Miss(Format('%s: the %d numbers fold to %d upstream, %d here', [what, n,
          er.Int64s['fnv'], FnvOf(g.Pts, n)]));
    end;
    want := er.Arrays['bbox'];
    SameHex(what + ' bbox x', g.Box.X, want.Items[0]);
    SameHex(what + ' bbox y', g.Box.Y, want.Items[1]);
    SameHex(what + ' bbox w', g.Box.W, want.Items[2]);
    SameHex(what + ' bbox h', g.Box.H, want.Items[3]);
    if er.Find('si').JSONType <> jtNull then
      SameInt(what + ' startIndex', g.Start, er.Integers['si']);
    if (kind = 'bar') or (kind = 'barBg') then
    begin
      SameHex(what + ' bar width', g.BarW, er.Find('bw'));
      SameInt(what + ' base dim', g.BaseDim, er.Integers['bd']);
      want := er.Arrays['idx'];
      SameInt(what + ' indices', Length(g.Idx), want.Count);
      if Length(g.Idx) = want.Count then
        for k := 0 to want.Count - 1 do
          if g.Idx[k] <> want.Integers[k] then
          begin
            Miss(Format('%s index %d is %d upstream, %d here', [what, k,
              want.Integers[k], g.Idx[k]]));
            Break;
          end;
    end
    else if kind = 'symbol' then
    begin
      SameHex(what + ' width', g.SymW, er.Arrays['size'].Items[0]);
      SameHex(what + ' height', g.SymH, er.Arrays['size'].Items[1]);
    end
    else
      SameInt(what + ' sign', g.Sign, er.Integers['sign']);
  end;
end;

procedure TAdvChartProgressiveOracleTest.CheckGeom(AGeom: TJSONArray);
var
  s, k, j: Integer;
  items: TJSONArray;
  it: TJSONObject;
  list: TTyPaintList;
  el: TTyChartElement;
  found: Boolean;
  what: string;
  x0, y0, x1, y1: Double;
begin
  list := FChart.List;
  for s := 0 to AGeom.Count - 1 do
  begin
    items := TJSONArray(AGeom.Items[s]);
    for j := 0 to items.Count - 1 do
    begin
      it := items.Objects[j];
      what := Format('series %d row %d', [s, it.Integers['d']]);
      found := False;
      for k := 0 to list.Count - 1 do
      begin
        el := list.Element(k);
        if el.ProgHidden or el.Ignore or (el.Datum.SeriesIndex <> s)
          or (el.Datum.DataIndex <> it.Integers['d']) or (el.Caption.Text <> '') then Continue;
        found := True;
        if it.Find('rect') <> nil then
        begin
          { zrender's rect may run backwards; the port's bounds do not }
          x0 := HexNum(it.Arrays['rect'].Items[0]);
          y0 := HexNum(it.Arrays['rect'].Items[1]);
          x1 := x0 + HexNum(it.Arrays['rect'].Items[2]);
          y1 := y0 + HexNum(it.Arrays['rect'].Items[3]);
          Inc(FCompared, 4);
          if (el.Shape.Bounds.Left <> Min(x0, x1)) or (el.Shape.Bounds.Right <> Max(x0, x1))
            or (el.Shape.Bounds.Top <> Min(y0, y1)) or (el.Shape.Bounds.Bottom <> Max(y0, y1)) then
            Miss(Format('%s is [%s %s %s %s] upstream, [%s %s %s %s] here', [what,
              Fmt(Min(x0, x1)), Fmt(Min(y0, y1)), Fmt(Max(x0, x1)), Fmt(Max(y0, y1)),
              Fmt(el.Shape.Bounds.Left), Fmt(el.Shape.Bounds.Top),
              Fmt(el.Shape.Bounds.Right), Fmt(el.Shape.Bounds.Bottom)]));
        end
        else
        begin
          SameHex(what + ' x', el.Shape.CX, it.Find('x'));
          SameHex(what + ' y', el.Shape.CY, it.Find('y'));
        end;
        Break;
      end;
      if not found then Miss(what + ': not drawn here');
    end;
  end;
end;

procedure TAdvChartProgressiveOracleTest.CheckSnap(ASnap: TJSONObject);
var
  ev, series: TJSONArray;
  er, hv, tip: TJSONObject;
  j, el: Integer;
  t, want, kind, gotKind, which: string;
  d: TTyChartDatumRef;
  e: TTyChartElement;
begin
  Inc(FSnaps);
  t := ASnap.Strings['t'];
  { [F4b] A POINTER STEP'S FLUSH: the oracle runs _onframe without the
    frame's _flush there (no rendered can be recorded), the port's paint
    after a hover says rendered when it marked something -- not compared
    at pointer steps (the spec records it) }
  if (t = 'move') or (t = 'leave') then
    for j := FChart.Events.Count - 1 downto 0 do
      if (FChart.Events[j] = 'rendered') or (FChart.Events[j] = 'finished') then
        FChart.Events.Delete(j);
  { the events, in order }
  ev := ASnap.Arrays['events'];
  SameInt('events', FChart.Events.Count, ev.Count);
  for j := 0 to Min(ev.Count, FChart.Events.Count) - 1 do
  begin
    er := ev.Objects[j];
    if (er.Strings['type'] = 'rendered') or (er.Strings['type'] = 'finished') then
      want := er.Strings['type']
    else
      want := Format('%s %d:%d/%d', [er.Strings['type'], er.Integers['seriesIndex'],
        er.Integers['dataIndex'], er.Integers['dataIndexInside']]);
    SameStr(Format('event %d', [j]), FChart.Events[j], want);
  end;
  if FChart.Events.Count <> ev.Count then
    for j := 0 to FChart.Events.Count - 1 do Miss('  here: ' + FChart.Events[j]);
  SameStr('unfinished', BoolToStr(FChart.ProgressiveUnfinished, True),
    BoolToStr(ASnap.Booleans['unfinished'], True));
  series := ASnap.Arrays['series'];
  for j := 0 to series.Count - 1 do
    CheckSeries(series.Objects[j], t <> 'append');
  { the element and the row under the pointer }
  if (t = 'move') then
  begin
    d := FChart.HitTestAt(ASnap.Integers['x'], ASnap.Integers['y'], el);
    gotKind := 'none';
    if el >= 0 then
    begin
      e := FChart.List.Element(el);
      if e.Shape.Kind = cskLarge then
        case e.Shape.Large.Kind of
          lgkBar: gotKind := 'bar';
          lgkSymbol: gotKind := 'symbol';
          lgkCandle: gotKind := 'candle';
        else
          gotKind := '?';
        end
      else if TyChartDatumValid(d) then gotKind := 'item'
      else gotKind := 'other';
    end;
    if ASnap.Find('hover').JSONType = jtNull then kind := 'none'
    else
    begin
      hv := ASnap.Objects['hover'];
      kind := hv.Strings['kind'];
    end;
    SameStr('the hovered element', gotKind, kind);
    if (gotKind = kind) and (kind <> 'other') and (kind <> 'none') then
    begin
      SameInt('its series', e.Datum.SeriesIndex, hv.Integers['seriesIndex']);
      if hv.Find('dataIndex').JSONType = jtNull then
        SameStr('its row', BoolToStr(TyChartDatumValid(d), True), 'False')
      else
        SameInt('its row', d.DataIndex, hv.Integers['dataIndex']);
    end;
  end;
  { the tooltip }
  tip := ASnap.Objects['tooltip'];
  SameStr('the tooltip shown', BoolToStr(FChart.TooltipShown, True),
    BoolToStr(tip.Booleans['shown'], True));
  if tip.Booleans['shown'] and FChart.TooltipShown then
  begin
    which := tip.Strings['which'];
    d := FChart.TooltipShownDatum;
    SameStr('the tooltip', Format('item:%d:%d', [d.SeriesIndex, d.RawDataIndex]), which);
    SameInt('the tooltip row', d.DataIndex, tip.Integers['inner']);
  end;
  if (t = 'snap') and (ASnap.Find('geom') is TJSONArray) then
    CheckGeom(ASnap.Arrays['geom']);
end;

procedure TAdvChartProgressiveOracleTest.TestEveryFrameAndEveryHitAsUpstream;
var
  cases, snaps: TJSONArray;
  c, sn, opt: TJSONObject;
  ci, si, played: Integer;
  t: string;
  nowMs: Double;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  played := 0;
  for ci := 0 to cases.Count - 1 do
  begin
    c := TJSONObject(cases.Items[ci]);
    if not c.Booleans['replay'] then Continue;
    Inc(played);
    opt := c.Objects['option'];
    FName := c.Strings['id'] + ' init';
    NewChart;
    FChart.TooltipNow := 0;
    FChart.ProgressiveStepCostMs := c.Floats['cost'];
    FChart.Events.Clear;
    FChart.SetOption(opt.AsJSON, True);
    RenderNow;
    snaps := c.Arrays['snaps'];
    CheckSnap(snaps.Objects[0]);
    nowMs := 0;
    for si := 1 to snaps.Count - 1 do
    begin
      sn := snaps.Objects[si];
      t := sn.Strings['t'];
      FName := c.Strings['id'] + '/' + IntToStr(sn.Integers['at']) + ' ' + t;
      FChart.Events.Clear;
      if t = 'frame' then
        FChart.ProgressTick
      else if t = 'cost' then
        FChart.ProgressiveStepCostMs := sn.Floats['cost']
      else if t = 'append' then
      begin
        if not FChart.AppendData(sn.Integers['seriesIndex'], sn.Arrays['data'].AsJSON) then
          Miss('appendData refused');
      end
      else if (t = 'move') or (t = 'leave') then
      begin
        nowMs := nowMs + 1000;
        FChart.TooltipNow := nowMs;
        if t = 'move' then FChart.Move(sn.Integers['x'], sn.Integers['y'])
        else FChart.Leave;
        FChart.TooltipTick(nowMs + 500);
        FChart.TooltipNow := nowMs + 500;
      end;
      RenderNow;
      CheckSnap(sn);
    end;
    FreeAndNil(FChart);
  end;
  WriteLn(Format('  progressive oracle: %d comparisons, %d cases, %d snapshots',
    [FCompared, played, FSnaps]));
  if FBad > 0 then
    Fail(Format('%d of %d comparisons over %d cases and %d snapshots differ:%s',
      [FBad, FCompared, played, FSnaps, FReport]));
  AssertTrue('the oracle was compared', FCompared > 2000);
end;

{ ==================== hand-written ==================== }

procedure TAdvChartProgressiveTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
end;

procedure TAdvChartProgressiveTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartProgressiveTest.Show(const AOption: string; AW, AH: Integer);
begin
  FreeAndNil(FChart);
  FChart := TPgProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, AW, AH);
  FChart.AnimationMode := camOff;
  FChart.AnimNow := 0;
  FChart.ProgressiveStepCostMs := 1;
  FChart.ChartOn('rendered', @FChart.OnEv);
  FChart.ChartOn('finished', @FChart.OnEv);
  FChart.SetOption(AOption, True);
  RenderNow(AW, AH);
end;

procedure TAdvChartProgressiveTest.RenderNow(AW, AH: Integer);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, AW, AH), 96);
  finally
    bmp.Free;
  end;
end;

function TAdvChartProgressiveTest.ShownRows(ASeries: Integer): Integer;
begin
  Result := Length(ShownRowsOf(FChart.List, FChart, ASeries));
end;

function PointsJson(N, AFrom: Integer): string;
var i: Integer;
begin
  Result := '[';
  for i := 0 to N - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + Format('[%d,%d]', [AFrom + i, (AFrom + i) * 7 mod 13]);
  end;
  Result := Result + ']';
end;

procedure TAdvChartProgressiveTest.TestTheModWalkIsUpstreams;
var rows, all: TTyIntegerArray; k, j: Integer; seen: array[0..9] of Integer;
begin
  { task.ts modNext, 10 rows by 4: modBy 3, winCount 4 }
  AssertEquals('modBy', 3, Trunc(TyProgModBy(10, 4)));
  all := nil;
  for k := 0 to 2 do
  begin
    rows := TyProgChunkRows(k * 4, Min(k * 4 + 4, 10), 3, 10);
    for j := 0 to High(rows) do
    begin
      SetLength(all, Length(all) + 1);
      all[High(all)] := rows[j];
    end;
  end;
  AssertEquals('ten positions', 10, Length(all));
  AssertEquals('position 1 is row 4', 4, all[1]);
  AssertEquals('position 3 runs past the count and stays', 3, all[3]);
  FillChar(seen, SizeOf(seen), 0);
  for j := 0 to High(all) do Inc(seen[all[j]]);
  AssertEquals('row 7 twice', 2, seen[7]);
  AssertEquals('row 9 never', 0, seen[9]);
  { sequential, and an infinite modBy (a task that is not incremental) }
  rows := TyProgChunkRows(4, 8, 1, 10);
  AssertEquals('sequential', 4, rows[0]);
  rows := TyProgChunkRows(0, 3, Infinity, 3);
  AssertEquals('Infinity walks the positions', 2, rows[2]);
  AssertEquals('a null count is no walk', 1, Trunc(TyProgModBy(-1, 4)));
  AssertTrue('a null step on a count is Infinity', IsInfinite(TyProgModBy(10, NaN)));
  AssertEquals('a null step on no rows normalizes to 1', 1, Trunc(TyProgModBy(0, NaN)));
  { Math.ceil(0 / 4) is 0, a number: only the `!(val >= 1)` half of
    normalizeModBy lifts it [milestone C6-C13] }
  AssertEquals('no rows with a step: ceil gives 0, normalized to 1', 1,
    Trunc(TyProgModBy(0, 4)));
end;

procedure TAdvChartProgressiveTest.TestTheSpecReadsJavaScriptValues;
  function Spec(const AType, AJson: string): TTyProgSpec;
  var d: TJSONData;
  begin
    d := GetJSON(AJson);
    try
      Result := TyProgSpecOf(AType, TJSONObject(d));
    finally
      d.Free;
    end;
  end;
var s: TTyProgSpec;
begin
  s := Spec('scatter', '{}');
  AssertTrue('scatter on', s.Enabled);
  AssertEquals('scatter 400', 400, s.Step);
  AssertEquals('scatter 3000', 3000, Trunc(s.Threshold));
  AssertFalse('scatter sequential', s.ModMode);
  s := Spec('scatter', '{"large": true}');
  AssertEquals('large scatter 5000', 5000, s.Step);
  AssertEquals('large scatter 1e4', 10000, Trunc(s.Threshold));
  s := Spec('scatter', '{"large": true, "progressive": null, "progressiveThreshold": 7}');
  AssertEquals('a null progressive is the default branch', 5000, s.Step);
  AssertEquals('a written threshold', 7, Trunc(s.Threshold));
  s := Spec('bar', '{"progressive": 50}');
  AssertFalse('a bar without large', s.Enabled);
  s := Spec('bar', '{"large": 1}');
  AssertTrue('a bar with large', s.Enabled);
  AssertEquals('bar 3000', 3000, s.Step);
  AssertTrue('bar mod', s.ModMode);
  s := Spec('candlestick', '{}');
  AssertEquals('candle 3000', 3000, s.Step);
  AssertEquals('candle 1e4', 10000, Trunc(s.Threshold));
  AssertTrue('candle mod', s.ModMode);
  s := Spec('candlestick', '{"progressiveChunkMode": "sequential"}');
  AssertFalse('candle sequential', s.ModMode);
  s := Spec('line', '{}');
  AssertFalse('line 0', s.Enabled);
  s := Spec('heatmap', '{"progressive": "50.5"}');
  AssertEquals('a string rounds', 51, s.Step);
  s := Spec('heatmap', '{"progressive": null}');
  AssertFalse('a null is off', s.Enabled);
  s := Spec('heatmap', '{"progressive": -3}');
  AssertFalse('a step that never ends a chunk is left off', s.Enabled);
  s := Spec('heatmap', '{"progressiveThreshold": null}');
  AssertTrue('a null threshold is 0', TyProgRenderOn(s, 'heatmap', 0));
  s := Spec('heatmap', '{"progressiveThreshold": "x"}');
  AssertFalse('a threshold that is no number never passes', TyProgRenderOn(s, 'heatmap', 99999));
  AssertFalse('a line view is not incremental', TyProgRenderOn(Spec('line', '{"progressive": 5, "progressiveThreshold": 1}'), 'line', 10));
end;

procedure TAdvChartProgressiveTest.TestAppendDataRefusesWhatUpstreamCannotTake;
var deep: string; i: Integer; d: TJSONData;
begin
  Show('{"animation": false, "xAxis": {}, "yAxis": {}, "dataset": {"source": [[1, 2], [2, 3]]},' +
    '"series": [{"type": "scatter", "data": [[1, 2]]}, {"type": "scatter"}]}');
  AssertFalse('no such series', FChart.AppendData(5, '[[1, 2]]'));
  AssertFalse('a dataset series', FChart.AppendData(1, '[[1, 2]]'));
  AssertFalse('not an array', FChart.AppendData(0, '{"a": 1}'));
  AssertFalse('not JSON', FChart.AppendData(0, '[[1, 2'));
  deep := '';
  for i := 1 to 400 do deep := deep + '[';
  for i := 1 to 400 do deep := deep + ']';
  AssertFalse('too deep', FChart.AppendData(0, deep));
  AssertFalse('nothing pending after a refusal', FChart.ProgressiveUnfinished);
  AssertTrue('taken', FChart.AppendData(0, '[[3, 4], [5, 6]]'));
  AssertTrue('pending until a frame', FChart.ProgressiveUnfinished);
  AssertEquals('nothing drawn yet', 1, ShownRows(0));
  FChart.ProgressTick;
  RenderNow;
  AssertFalse('the frame took them in', FChart.ProgressiveUnfinished);
  AssertEquals('the store holds them', 3, FChart.SeriesStore(0).Count);
  d := GetJSON(FChart.GetOptionJson);
  try
    AssertEquals('the option holds them', 3, TJSONArray(d.FindPath('series[0].data')).Count);
  finally
    d.Free;
  end;
end;

procedure TAdvChartProgressiveTest.TestTheAxesStayUntilAFullUpdate;
var lo, hi: Double;
begin
  Show('{"animation": false, "xAxis": {"type": "value"}, "yAxis": {"type": "value"},' +
    '"series": [{"type": "scatter", "data": [[0, 1], [10, 5]]}]}');
  lo := FChart.Build.Grid(0).XAxis(0).Scale.GetExtent.Start;
  hi := FChart.Build.Grid(0).XAxis(0).Scale.GetExtent.Stop;
  AssertTrue(FChart.AppendData(0, '[[500, 3]]'));
  FChart.ProgressTick;
  RenderNow;
  AssertEquals('the frozen min', lo, FChart.Build.Grid(0).XAxis(0).Scale.GetExtent.Start);
  AssertEquals('the frozen max', hi, FChart.Build.Grid(0).XAxis(0).Scale.GetExtent.Stop);
  AssertEquals('the point past it is not drawn', 2, ShownRows(0));
  AssertTrue('a second append', FChart.AppendData(0, '[[700, 3]]'));
  FChart.ProgressTick;
  RenderNow;
  AssertEquals('still frozen', hi, FChart.Build.Grid(0).XAxis(0).Scale.GetExtent.Stop);
  { a merge is an update: the axes measure every row again }
  FChart.MergeOption('{}');
  RenderNow;
  AssertTrue('the update took the rows in', FChart.Build.Grid(0).XAxis(0).Scale.GetExtent.Stop >= 700);
  AssertEquals('every row drawn', 4, ShownRows(0));
end;

procedure TAdvChartProgressiveTest.TestASetOptionStartsAgain;
begin
  Show('{"animation": false, "xAxis": {}, "yAxis": {},' +
    '"series": [{"type": "scatter", "progressive": 3, "progressiveThreshold": 5, "data": ' + PointsJson(12, 0) + '}]}');
  AssertEquals('the first chunk', 3, ShownRows(0));
  FChart.ProgressTick;
  FChart.ProgressTick;
  RenderNow;
  AssertEquals('three chunks', 9, ShownRows(0));
  FChart.MergeOption('{"title": {"text": "x"}}');
  RenderNow;
  AssertEquals('from row 0 again', 3, ShownRows(0));
  AssertTrue('unfinished', FChart.ProgressiveUnfinished);
end;

procedure TAdvChartProgressiveTest.TestTheTimerFrameRendersOnce;
begin
  Show('{"animation": false, "xAxis": {}, "yAxis": {},' +
    '"series": [{"type": "scatter", "progressive": 3, "progressiveThreshold": 5, "data": ' + PointsJson(6, 0) + '}]}');
  AssertEquals('the update', 'rendered', FChart.Events.CommaText);
  FChart.Events.Clear;
  { the animation frame: the chunk, then one rendered and the finished }
  FChart.AnimTick(16);
  AssertEquals('one frame', 'rendered,finished', FChart.Events.CommaText);
  FChart.Events.Clear;
  FChart.AnimTick(32);
  AssertEquals('an idle frame says nothing', '', FChart.Events.CommaText);
end;

procedure TAdvChartProgressiveTest.TestAHiddenChunkIsNeitherDrawnNorFound;
var bmp: TBGRABitmap; px: TBGRAPixel; x, y: Integer; d: TTyChartDatumRef;
begin
  Show('{"animation": false, "grid": {"left": 0, "right": 0, "top": 0, "bottom": 0},' +
    '"xAxis": {"type": "value", "min": 0, "max": 10, "show": false}, "yAxis": {"type": "value", "min": 0, "max": 10, "show": false},' +
    '"series": [{"type": "scatter", "symbolSize": 20, "itemStyle": {"color": "#ff0000", "opacity": 1}, "progressive": 1, "progressiveThreshold": 2,' +
    '"data": [[2, 5], [8, 5]]}]}', 200, 200);
  { row 1 at (160, 100) waits for the frame }
  x := 160;
  y := 100;
  d := FChart.HitTestAt(x, y);
  AssertFalse('not found', TyChartDatumValid(d));
  bmp := TBGRABitmap.Create(200, 200, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 200, 200), 96);
    px := bmp.GetPixel(x, y);
    AssertTrue('not drawn', px.red + px.green + px.blue > 700);
    px := bmp.GetPixel(40, 100);
    AssertTrue('row 0 drawn', (px.red > 200) and (px.green < 80));
    FChart.ProgressTick;
    bmp.Fill(BGRA(255, 255, 255, 255));
    FChart.Render(bmp.Canvas, Rect(0, 0, 200, 200), 96);
    px := bmp.GetPixel(x, y);
    AssertTrue('drawn after its frame', (px.red > 200) and (px.green < 80));
  finally
    bmp.Free;
  end;
  d := FChart.HitTestAt(x, y);
  AssertEquals('found', 1, d.DataIndex);
end;

procedure TAdvChartProgressiveTest.TestAHundredThousandPointsComeInChunks;
var
  sb: TStringBuilder;
  i, frames: Integer;
  t0, tSet, tFirst, tFrames, tWorst, tf: QWord;
begin
  sb := TStringBuilder.Create;
  try
    sb.Append('{"animation": false, "xAxis": {"type": "value"}, "yAxis": {"type": "value"},');
    sb.Append('"series": [{"type": "scatter", "large": true, "symbolSize": 3, "data": [');
    for i := 0 to 99999 do
    begin
      if i > 0 then sb.Append(',');
      sb.Append('[').Append(IntToStr((i * 7919) mod 100003)).Append(',')
        .Append(IntToStr((i * 104729) mod 50021)).Append(']');
    end;
    sb.Append(']}]}');
    FreeAndNil(FChart);
    FChart := TPgProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.SetBounds(0, 0, 800, 600);
    FChart.AnimationMode := camOff;
    FChart.AnimNow := 0;
    FChart.ProgressiveStepCostMs := 1;
    t0 := GetTickCount64;
    FChart.SetOption(sb.ToString, True);
    tSet := GetTickCount64 - t0;
  finally
    sb.Free;
  end;
  t0 := GetTickCount64;
  RenderNow(800, 600);
  tFirst := GetTickCount64 - t0;
  AssertTrue('progressive at 1e4', FChart.SeriesProgress(0).On);
  AssertEquals('a chunk of 5000', 5000, FChart.SeriesProgress(0).Spec.Step);
  frames := 0;
  tWorst := 0;
  t0 := GetTickCount64;
  while FChart.ProgressiveUnfinished and (frames < 100) do
  begin
    tf := GetTickCount64;
    FChart.ProgressTick;
    RenderNow(800, 600);
    tf := GetTickCount64 - tf;
    if tf > tWorst then tWorst := tf;
    Inc(frames);
  end;
  tFrames := GetTickCount64 - t0;
  WriteLn(Format('  100k progressive points: setOption %d ms, first frame %d ms, %d frames %d ms (worst %d ms)',
    [tSet, tFirst, frames, tFrames, tWorst]));
  AssertEquals('19 frames after the first chunk', 19, frames);
  AssertFalse('done', FChart.ProgressiveUnfinished);
  { THE MACHINE'S CLOCK: a frame paints its chunk inside its 1 ms budget,
    so it ends after one -- it must not draw the rest at once }
  FChart.MergeOption('{"title": {"text": "again"}}');
  RenderNow(800, 600);
  FChart.ProgressiveStepCostMs := NaN;
  FChart.AnimNow := NaN;
  FChart.ProgressTick;
  FChart.AnimNow := 0;
  RenderNow(800, 600);
  AssertTrue('the real budget ends a frame early', FChart.ProgressiveUnfinished);
  AssertTrue('and still draws', FChart.SeriesProgress(0).Done >= 2);
  { generous: other trees' suites run beside this one }
  AssertTrue('a frame stays a frame, not the whole series again', tWorst < 30000);
end;

initialization
  RegisterTest(TAdvChartProgressiveOracleTest);
  RegisterTest(TAdvChartProgressiveTest);
end.
