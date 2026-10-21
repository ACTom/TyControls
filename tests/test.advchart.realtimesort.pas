unit test.advchart.realtimesort;
{$mode objfpc}{$H+}
{ realtimeSort, THE BAR RACE, ON THE REAL CONTROL, held to upstream.
  [Batch 135, D4]

  tools/advchart-oracle/realtime-sort.js drives the real ECharts 6.1 build
  under the hand-driven clock, a frame every 20 ms whose stage is the
  zrender flush -- so `rendered`, where BarView looks at its bars, follows
  every stepped frame. A case sets its option at T0 (the init sort is
  dispatched after that setOption's own flush), then per frame its inputs
  (a merge setOption, which flushes; a dispatchAction) and the frame.
  Recorded per frame: the clips, each category axis model's
  categorySortInfo, every bar (shape, ignore, its label's text, its
  animators), every leaf of every cartesian axis group by anid, and every
  changeaxisorder event with the frame it came in.

  The replay drives the control the same way -- Option at T0, SetOption,
  DispatchAction, AnimTick unless a setOption flushed, a render per frame --
  in camAlways with the injected clock, and compares every frame: the clip
  count; the sort info; every bar's shape against its proxy (the layout
  where it has none) BIT FOR BIT, its ignore, its animators, its label's
  words; every axis leaf against the axis proxy of its anid once the control
  has axis proxies (present exactly where upstream's is, x / y / rotation
  of a label and the four ends of a line bit for bit, the animators), and
  -- with none -- that upstream's leaf does not move; and the events, in
  order, at their frames, payload for payload. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Scale, tyControls.AdvanceChart.Data,
     tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Measure,
     tyControls.AdvanceChart.Anim, tyControls.AdvanceChart.AnimView,
     tyControls.AdvanceChart.AnimAxis,
     tyControls.AdvanceChart, tyControls.AdvanceChart.Events,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TRsProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartRealtimeSortTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TRsProbe;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FBarCompared, FAxisCompared, FFrames: Integer;
    FReport: string;
    FSeen, FTally: TStringList;
    FEvAt: array of Double;
    FEvPayload: array of string;
    FT0: Double;
    procedure OnEv(Sender: TObject; const AEvent: TTyChartEvent);
    procedure Miss(const AWhere: string; const AOnce: string = '');
    procedure NewChart;
    procedure Draw;
    procedure RunCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRacesAsUpstream;
    procedure TestSortInfoMapsTicksAndOrdinals;
    procedure TestADispatchedOrderTakesOnlyCategoryAxes;
    procedure TestNoRaceOnAValueBaseAxis;
    procedure TestTheClippedBarIsKeptIgnored;
  end;

implementation

const
  cW = 400;
  cH = 300;

var
  GFix: TJSONData = nil;

function Fix: TJSONObject;
var sl: TStringList;
begin
  if GFix = nil then
  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
        + 'advchart-realtime-sort.json');
      GFix := GetJSON(sl.Text);
    finally
      sl.Free;
    end;
  end;
  Result := TJSONObject(GFix);
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Hex(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

{ the element's value of AKey at frame AFrame: its track's, else its final
  one; nil where it has none }
function ValueAt(AEl: TJSONObject; const AKey: string; AFrame: Integer): TJSONData;
var tr: TJSONData;
begin
  Result := nil;
  tr := AEl.Find('track');
  if (tr is TJSONObject) and (TJSONObject(tr).Find(AKey) <> nil) then
    Result := TJSONObject(tr).Arrays[AKey].Items[AFrame]
  else if TJSONObject(AEl.Find('final')).Find(AKey) <> nil then
    Result := TJSONObject(AEl.Find('final')).Find(AKey);
  if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
end;

function PresentAt(AEl: TJSONObject; AFrame: Integer): Boolean;
var pr: TJSONData; i: Integer;
begin
  pr := AEl.Find('present');
  if not (pr is TJSONArray) then Exit(True);
  for i := 0 to pr.Count - 1 do
    if pr.Items[i].AsInteger = AFrame then Exit(True);
  Result := False;
end;

function FindListEl(AList: TTyPaintList; ARole: TTyChartAnimRole;
  ASeries, AIndex: Integer; out AEl: TTyChartElement): Boolean;
var i: Integer;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
    if (AList.Element(i).Anim.Role = ARole) and (AList.Element(i).Anim.Series = ASeries)
      and (AList.Element(i).Anim.Index = AIndex) then
    begin
      AEl := AList.Element(i);
      Exit(True);
    end;
end;

{ a JSON text normalised: parsed and written again }
function NormJson(const AText: string): string;
var d: TJSONData;
begin
  d := GetJSON(AText);
  try
    Result := d.AsJSON;
  finally
    d.Free;
  end;
end;

{ ==================== the probe ==================== }

function TRsProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TRsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TRsProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

{ ==================== plumbing ==================== }

procedure TAdvChartRealtimeSortTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := nil;
  FSeen := TStringList.Create;
  FTally := TStringList.Create;
  FBad := 0;
  FBarCompared := 0;
  FAxisCompared := 0;
  FFrames := 0;
  FReport := '';
  FT0 := Fix.Objects['clock'].Floats['T0'];
end;

procedure TAdvChartRealtimeSortTest.TearDown;
begin
  FreeAndNil(FSeen);
  FreeAndNil(FTally);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartRealtimeSortTest.OnEv(Sender: TObject; const AEvent: TTyChartEvent);
begin
  if AEvent.EventType <> 'changeaxisorder' then Exit;
  SetLength(FEvAt, Length(FEvAt) + 1);
  FEvAt[High(FEvAt)] := FChart.AnimNow - FT0;
  SetLength(FEvPayload, Length(FEvPayload) + 1);
  FEvPayload[High(FEvPayload)] := AEvent.Payload;
end;

procedure TAdvChartRealtimeSortTest.Miss(const AWhere: string; const AOnce: string);
var c: string; i, n: Integer;
begin
  Inc(FBad);
  c := Copy(AWhere, 1, Pos(' ', AWhere) - 1);
  if (c <> '') and (c[Length(c)] = ':') then Delete(c, Length(c), 1);
  i := FTally.IndexOfName(c);
  if i < 0 then
  begin
    FTally.Add(c + '=1');
    n := 1;
  end
  else
  begin
    n := StrToInt(FTally.ValueFromIndex[i]) + 1;
    FTally.ValueFromIndex[i] := IntToStr(n);
  end;
  if AOnce <> '' then
  begin
    if FSeen.IndexOf(AOnce) >= 0 then Exit;
    FSeen.Add(AOnce);
  end;
  if n <= 12 then
    FReport := FReport + LineEnding + '  ' + AWhere;
end;

procedure TAdvChartRealtimeSortTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TRsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := FT0;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.OnChartEvent := @OnEv;
  FEvAt := nil;
  FEvPayload := nil;
end;

procedure TAdvChartRealtimeSortTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

{ ==================== the replay ==================== }

procedure TAdvChartRealtimeSortTest.RunCase(ACase: TJSONObject);
const
  BarKeys: array[0..3] of string = ('shape.x', 'shape.y', 'shape.width', 'shape.height');
  LabelKeys: array[0..2] of string = ('x', 'y', 'rotation');
  LineKeys: array[0..3] of string = ('shape.x1', 'shape.y1', 'shape.x2', 'shape.y2');
var
  name, s, eid, axisKey, anid, got, want: string;
  frames, inputs, els, clips, sorts, evs: TJSONArray;
  fi, ii, k, j, slash, series, row, upAnim: Integer;
  t: Double;
  inp, el, so: TJSONObject;
  flushed, upPresent: Boolean;
  p, lp: TTyChartAnimProxy;
  le, ll: TTyChartElement;
  v: TJSONData;
  gotN, wantN: Double;
  bar: Boolean;
begin
  name := ACase.Strings['id'];
  frames := ACase.Arrays['framesMs'];
  inputs := ACase.Arrays['inputs'];
  els := ACase.Arrays['elements'];
  clips := ACase.Arrays['clips'];
  sorts := ACase.Arrays['sorts'];
  evs := ACase.Arrays['events'];
  NewChart;
  for fi := 0 to frames.Count - 1 do
  begin
    t := frames.Floats[fi];
    FChart.AnimNow := FT0 + t;
    flushed := False;
    { the option at T0, then the inputs of the frame }
    if fi = 0 then
    begin
      FChart.Option := ACase.Objects['option'].AsJSON;
      AssertEquals(name + ': the option parses', '', FChart.OptionError);
      Draw;
      flushed := True;
    end;
    for ii := 0 to inputs.Count - 1 do
    begin
      inp := inputs.Objects[ii];
      if inp.Floats['at'] <> t then Continue;
      s := inp.Strings['type'];
      { lazyUpdate: merged now, rendered by the next frame or by an action
        before it [milestone D1-D4] }
      if (s = 'setOption') and (inp.Find('lazy') <> nil) and inp.Booleans['lazy'] then
        AssertTrue(name + ': the lazy merge is taken: ' + FChart.OptionError,
          FChart.SetOption(inp.Objects['option'].AsJSON, '{"lazyUpdate":true}'))
      else if s = 'setOption' then
      begin
        AssertTrue(name + ': the merge is taken: ' + FChart.OptionError,
          FChart.SetOption(inp.Objects['option'].AsJSON, ''));
        Draw;
        flushed := True;
      end
      else if s = 'action' then
        FChart.DispatchAction(inp.Objects['payload'].AsJSON)
      else
        Fail('unknown input ' + s);
    end;
    { a frame is the tick; the paint changes nothing a frame compares, so
      only every fifth one is drawn }
    if not flushed then
    begin
      FChart.AnimTick(FT0 + t);
      if Round(t) mod 100 = 0 then Draw;
    end;
    Inc(FFrames);
    { THE CLIPS }
    if FChart.AnimClipCount <> clips.Integers[fi] then
      Miss(Format('%s t=%s: %d clips here, %d upstream', [name, Fmt(t),
        FChart.AnimClipCount, clips.Integers[fi]]), name + 'clips');
    { THE SORT the axis models hold }
    so := sorts.Objects[fi];
    for k := 0 to so.Count - 1 do
    begin
      axisKey := so.Names[k];
      want := NormJson(so.Items[k].AsJSON);
      got := NormJson(FChart.CategorySortInfoText(Copy(axisKey, 1, 5),
        StrToInt(Copy(axisKey, 6, MaxInt))));
      if got <> want then
        Miss(Format('%s t=%s: %s sorted %s here, %s upstream', [name, Fmt(t), axisKey,
          got, want]), name + 'sort' + axisKey);
    end;
    { ---- the elements ---- }
    for j := 0 to els.Count - 1 do
    begin
      el := els.Objects[j];
      eid := el.Strings['id'];
      upPresent := PresentAt(el, fi);
      slash := Pos('/', eid);
      bar := el.Strings['kind'] = 'bar';
      if bar then
      begin
        series := StrToInt(Copy(eid, 7, slash - 7));
        row := StrToInt(Copy(eid, slash + 1, MaxInt));
        if FindListEl(FChart.List, carBar, series, row, le) <> upPresent then
        begin
          Miss(Format('%s t=%s %s: a bar here %s, upstream %s', [name, Fmt(t), eid,
            BoolToStr(not upPresent, True), BoolToStr(upPresent, True)]), name + eid + 'pres');
          Continue;
        end;
        if not upPresent then Continue;
        Inc(FBarCompared);
        p := FChart.AnimFindProxy(series, row, 'bar');
        for k := 0 to 3 do
        begin
          v := ValueAt(el, BarKeys[k], fi);
          if v = nil then Continue;
          wantN := FromHex(v.AsString);
          if p <> nil then gotN := p.Num(BarKeys[k]) else gotN := le.Anim.G[k];
          if Hex(gotN) <> Hex(wantN) then
            Miss(Format('%s t=%s %s: %s %s here, %s upstream', [name, Fmt(t), eid,
              BarKeys[k], Fmt(gotN), Fmt(wantN)]), name + eid + BarKeys[k]);
        end;
        v := ValueAt(el, 'ignore', fi);
        if (v <> nil) and (v.AsBoolean <> le.Ignore) then
          Miss(Format('%s t=%s %s: ignore %s here, %s upstream', [name, Fmt(t), eid,
            BoolToStr(le.Ignore, True), BoolToStr(v.AsBoolean, True)]), name + eid + 'ign');
        v := ValueAt(el, 'animators', fi);
        if v <> nil then
        begin
          upAnim := Round(FromHex(v.AsString));
          k := 0;
          if p <> nil then k := p.AnimatorCount;
          if k <> upAnim then
            Miss(Format('%s t=%s %s: %d animators here, %d upstream', [name, Fmt(t), eid,
              k, upAnim]), name + eid + 'anim');
        end;
        v := ValueAt(el, 'text', fi);
        if v <> nil then
        begin
          lp := FChart.AnimFindProxy(series, row, 'label');
          if (lp <> nil) and lp.HasText then got := lp.Text
          else if FindListEl(FChart.List, carLabel, series, row, ll) then got := ll.Caption.Text
          else got := '<none>';
          if got <> v.AsString then
            Miss(Format('%s t=%s %s: the label says %s here, %s upstream', [name, Fmt(t),
              eid, got, v.AsString]), name + eid + 'text');
        end;
        Continue;
      end;
      { an axis leaf }
      axisKey := Copy(eid, 1, slash - 1);
      anid := Copy(eid, slash + 1, MaxInt);
      v := ValueAt(el, 'animators', fi);
      if v <> nil then upAnim := Round(FromHex(v.AsString)) else upAnim := 0;
      if FChart.AnimAxisProxyCount = 0 then
      begin
        { NO PROXIES: the axis is drawn as laid out -- upstream's must stand }
        if upPresent and (upAnim > 0) then
          Miss(Format('%s t=%s %s: moves upstream, no axis proxy here', [name, Fmt(t), eid]),
            name + eid + 'noproxy');
        Continue;
      end;
      p := FChart.AnimAxisProxy(axisKey, anid);
      if (p <> nil) <> upPresent then
      begin
        Miss(Format('%s t=%s %s: a leaf here %s, upstream %s', [name, Fmt(t), eid,
          BoolToStr(p <> nil, True), BoolToStr(upPresent, True)]), name + eid + 'lpres');
        Continue;
      end;
      if p = nil then Continue;
      Inc(FAxisCompared);
      if el.Strings['kind'] = 'axisLabel' then
      begin
        for k := 0 to 2 do
        begin
          v := ValueAt(el, LabelKeys[k], fi);
          if v = nil then Continue;
          wantN := FromHex(v.AsString);
          gotN := p.Num(LabelKeys[k]);
          if Hex(gotN) <> Hex(wantN) then
            Miss(Format('%s t=%s %s: %s %s here, %s upstream', [name, Fmt(t), eid,
              LabelKeys[k], Fmt(gotN), Fmt(wantN)]), name + eid + LabelKeys[k]);
        end;
      end
      else
        for k := 0 to 3 do
        begin
          v := ValueAt(el, LineKeys[k], fi);
          if v = nil then Continue;
          wantN := FromHex(v.AsString);
          gotN := p.Num(LineKeys[k]);
          if Hex(gotN) <> Hex(wantN) then
            Miss(Format('%s t=%s %s: %s %s here, %s upstream', [name, Fmt(t), eid,
              LineKeys[k], Fmt(gotN), Fmt(wantN)]), name + eid + LineKeys[k]);
        end;
      if p.AnimatorCount <> upAnim then
        Miss(Format('%s t=%s %s: %d animators here, %d upstream', [name, Fmt(t), eid,
          p.AnimatorCount, upAnim]), name + eid + 'aanim');
    end;
  end;
  { THE EVENTS, in order, at their frames }
  if Length(FEvAt) <> evs.Count then
    Miss(Format('%s: %d changeaxisorder events here, %d upstream', [name, Length(FEvAt),
      evs.Count]));
  for k := 0 to Math.Min(Length(FEvAt), evs.Count) - 1 do
  begin
    want := NormJson(evs.Objects[k].Objects['payload'].AsJSON);
    got := NormJson(FEvPayload[k]);
    if (FEvAt[k] <> evs.Objects[k].Floats['at']) or (got <> want) then
      Miss(Format('%s: event %d at %s here %s, at %s upstream %s', [name, k, Fmt(FEvAt[k]),
        got, Fmt(evs.Objects[k].Floats['at']), want]));
  end;
end;

procedure TAdvChartRealtimeSortTest.TestRacesAsUpstream;
var
  cases: TJSONArray;
  i: Integer;
begin
  cases := Fix.Arrays['cases'];
  AssertTrue('the fixture has its cases', cases.Count >= 10);
  for i := 0 to cases.Count - 1 do
    RunCase(cases.Objects[i]);
  if GetEnvironmentVariable('TY_REALTIMESORT_COUNTS') = '1' then
    WriteLn(Format('realtimesort: %d frames, %d bar and %d axis leaf comparisons',
      [FFrames, FBarCompared, FAxisCompared]));
  AssertTrue('frames compared', FFrames > 500);
  AssertTrue('bars compared', FBarCompared > 2000);
  AssertTrue('axis leaves compared', FAxisCompared > 1000);
  if FBad > 0 then
    Fail(Format('%d differences from upstream (%s):%s', [FBad,
      StringReplace(FTally.CommaText, '"', '', [rfReplaceAll]), FReport]));
end;

{ setSortInfo, the example in Ordinal.ts: six categories, a sort of four --
  the two categories it leaves out come after it in ascending order }
procedure TAdvChartRealtimeSortTest.TestSortInfoMapsTicksAndOrdinals;
var
  sc: TTyOrdinalScale;
  meta: TTyOrdinalMeta;
  ords: TTyIntegerArray;
  i: Integer;
const
  ByTick: array[0..5] of Integer = (2, 5, 3, 4, 0, 1);
  ByOrd: array[0..5] of Integer = (4, 5, 0, 2, 3, 1);
begin
  meta := TTyOrdinalMeta.Create;
  sc := TTyOrdinalScale.Create;
  try
    meta.SetCategories(['a', 'b', 'c', 'd', 'e', 'f']);
    sc.SetMeta(meta);
    SetLength(ords, 4);
    ords[0] := 2;
    ords[1] := 5;
    ords[2] := 3;
    ords[3] := 4;
    sc.SetSortInfo(ords, True);
    for i := 0 to 5 do
    begin
      AssertEquals('tick ' + IntToStr(i), ByTick[i], Round(sc.TickToOrdinal(i)));
      AssertEquals('ordinal ' + IntToStr(i), ByOrd[i], Round(sc.OrdinalToTick(i)));
    end;
    AssertEquals('a label is its tick''s category', 'f', sc.GetLabel(1));
    { outside the maps the number is itself }
    AssertEquals('past the ticks', 7, Round(sc.TickToOrdinal(7)));
    AssertEquals('below the ordinals', -1, Round(sc.OrdinalToTick(-1)));
    { normalize goes through the tick: ordinal 2 (c) is on tick 0 }
    AssertEquals('c on the first tick', 0, sc.Normalize(2), 0);
    sc.SetSortInfo(nil, False);
    AssertFalse('dropped', sc.Sorted);
    AssertEquals('no sort: the identity', 3, Round(sc.TickToOrdinal(3)));
  finally
    sc.Free;
    meta.Free;
  end;
end;

{ the action writes categorySortInfo on every axis of componentType that is
  a category axis -- axisId is no query key -- and publishes the payload as
  the event }
procedure TAdvChartRealtimeSortTest.TestADispatchedOrderTakesOnlyCategoryAxes;
begin
  NewChart;
  FChart.Option := '{"xAxis":[{"type":"category","data":["A","B","C"]},'
    + '{"type":"category","data":["P","Q","R"]}],"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar","data":[1,2,3]},{"type":"bar","xAxisIndex":1,"data":[3,2,1]}]}';
  Draw;
  FChart.DispatchAction('{"type":"changeAxisOrder","componentType":"xAxis","axisId":0,'
    + '"sortInfo":{"ordinalNumbers":[2,0,1]}}');
  AssertEquals('the first x axis', NormJson('[2,0,1]'), NormJson(FChart.CategorySortInfoText('xAxis', 0)));
  AssertEquals('and the second: axisId queries nothing', NormJson('[2,0,1]'),
    NormJson(FChart.CategorySortInfoText('xAxis', 1)));
  FChart.DispatchAction('{"type":"changeAxisOrder","componentType":"yAxis","axisId":0,'
    + '"sortInfo":{"ordinalNumbers":[1,0]}}');
  AssertEquals('a value axis takes none', 'null', FChart.CategorySortInfoText('yAxis', 0));
  FChart.DispatchAction('{"type":"changeAxisOrder","componentType":"xAxis","xAxisIndex":1,'
    + '"sortInfo":{"ordinalNumbers":[1,2,0]}}');
  AssertEquals('xAxisIndex queries', NormJson('[2,0,1]'), NormJson(FChart.CategorySortInfoText('xAxis', 0)));
  AssertEquals('the one queried', NormJson('[1,2,0]'), NormJson(FChart.CategorySortInfoText('xAxis', 1)));
  AssertEquals('three events', 3, Length(FEvPayload));
  AssertEquals('the payload, its type the event''s',
    NormJson('{"type":"changeaxisorder","componentType":"xAxis","axisId":0,'
    + '"sortInfo":{"ordinalNumbers":[2,0,1]}}'), NormJson(FEvPayload[0]));
end;

{ shouldRealtimeSort: a value base axis races nothing }
procedure TAdvChartRealtimeSortTest.TestNoRaceOnAValueBaseAxis;
var t: Integer;
begin
  NewChart;
  FChart.Option := '{"xAxis":{"type":"value"},"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar","realtimeSort":true,"data":[[1,5],[2,9],[3,1]]}]}';
  Draw;
  for t := 1 to 60 do
  begin
    FChart.AnimNow := FT0 + t * 20;
    FChart.AnimTick(FT0 + t * 20);
  end;
  AssertEquals('no event', 0, Length(FEvPayload));
  AssertEquals('no sort', 'null', FChart.CategorySortInfoText('xAxis', 0));
end;

{ a racing bar clipped past the extent stays in the list, ignored, at the
  plot's edge; a bar that does not race is dropped }
procedure TAdvChartRealtimeSortTest.TestTheClippedBarIsKeptIgnored;
var
  el: TTyChartElement;
  n, i: Integer;
begin
  NewChart;
  FChart.AnimationMode := camOff;
  FChart.Option := '{"xAxis":{"type":"value"},"yAxis":{"type":"category",'
    + '"data":["A","B","C","D"],"max":1},'
    + '"series":[{"type":"bar","realtimeSort":true,"data":[4,9,2,7],'
    + '"label":{"show":true}}]}';
  Draw;
  Draw;
  n := 0;
  for i := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(i);
    if el.Anim.Role <> carBar then Continue;
    Inc(n);
    { the init sort: B and D shown, A and C past the extent }
    AssertEquals('row ' + IntToStr(el.Anim.Index) + ' ignored',
      (el.Anim.Index = 0) or (el.Anim.Index = 2), el.Ignore);
  end;
  AssertEquals('all four kept', 4, n);
  AssertTrue('a hidden bar''s label is hidden',
    FindListEl(FChart.List, carLabel, 0, 0, el) and el.Ignore);
  AssertEquals('the sort', NormJson('[1,3,0,2]'), NormJson(FChart.CategorySortInfoText('yAxis', 0)));
  FChart.Option := '{"xAxis":{"type":"value"},"yAxis":{"type":"category",'
    + '"data":["A","B","C","D"],"max":1},'
    + '"series":[{"type":"bar","data":[4,9,2,7]}]}';
  Draw;
  n := 0;
  for i := 0 to FChart.List.Count - 1 do
    if FChart.List.Element(i).Anim.Role = carBar then Inc(n);
  AssertEquals('no race: the clipped ones dropped', 2, n);
end;

initialization
  RegisterTest(TAdvChartRealtimeSortTest);
finalization
  FreeAndNil(GFix);
end.
