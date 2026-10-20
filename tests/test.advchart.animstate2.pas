unit test.advchart.animstate2;
{$mode objfpc}{$H+}
{ THE STATE TRANSITIONS OF THE F2 SERIES, HELD TO UPSTREAM AGAINST THE CLOCK
  [F3a].

  tools/advchart-oracle/anim-state2.js drives the real ECharts 6.1 build with
  states-misc.js' harness -- an option set at T0 and settled (or, for a LIVE
  case, set at T1 so its enter is running), then pointer moves and clicks
  through zr.handler and dispatchAction at T1 + t, one frame per sample --
  over
    a gauge's pointer and arc and a radar's rings hovered while they enter
      (the state on the element the enter animates: saveTo, the way back),
    a graph's nodes (a Symbol's absolute scale), edges and adjacency, and
      while its symbols pop in,
    a tree's nodes, edges and descendant focus, and while it enters,
    a treemap's rects and its descendant focus,
    a sankey's nodes and bands, its adjacency, and its selectchanged.
  The replay is states-misc's (the same comparisons: the events, the
  selection, and per mapped element its state list, visibility, paint order
  and -- on the proxy its states run on -- every key upstream tracks bit for
  bit, its state animators and its stateTransition), with the enter's own
  keys a state may take over (rotation, an arc's angles, a ring's points)
  compared where upstream moves them. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Measure,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Style, tyControls.AdvanceChart.Scale,
     tyControls.AdvanceChart.JsMath,
     tyControls.AdvanceChart.Anim, tyControls.AdvanceChart.AnimView,
     tyControls.AdvanceChart.States, tyControls.AdvanceChart.Events, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TAs2Probe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    procedure ClickAt(AX, AY: Integer);
    function List: TTyPaintList;
    function Frame: TTyPaintList;
    function Primary: TTyChartColor;
    procedure Update;
  end;

  TAs2Logger = class
  public
    Log: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Handle(Sender: TObject; const AEvent: TTyChartEvent);
  end;

  TAdvChartAnimState2OracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAs2Probe;
    FLogger: TAs2Logger;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FKeysCompared, FTrackedCompared, FEventsCompared,
      FMarksCompared: Integer;
    FReport: string;
    FSeen, FTally: TStringList;
    procedure Miss(const AWhere: string; const AOnce: string = '');
    procedure NewChart;
    procedure Draw;
    procedure Settle(AStart: Double);
    procedure CompareEvents(const AWhere: string; ACase: TJSONObject; AT: Double);
    procedure CompareSelection(const AWhere: string; ACase: TJSONObject; ASample: Integer);
    procedure CompareElement(const AWhere: string; AEl: TJSONObject; ASample: Integer);
    procedure CompareMarker(const AWhere: string; AEl: TJSONObject; ASample: Integer);
    procedure RunCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheTransitionsAsUpstream;
  end;

implementation

const
  cW = 400;
  cH = 300;
  cPrimary = '#3c3c41';
  cEventTypes: array[0..7] of string = ('select', 'unselect', 'selectchanged',
    'mouseover', 'mouseout', 'click', 'highlight', 'downplay');

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
        + 'advchart-anim-state2.json');
      GFix := GetJSON(sl.Text);
    finally
      sl.Free;
    end;
  end;
  Result := TJSONObject(GFix);
end;

{ every case on a clock of its own upstream; only the times relative to
  its start matter }
function T0: Double;
begin
  Result := 1700000000000.0;
end;

function T1: Double;
begin
  Result := T0 + Fix.Objects['clock'].Floats['T1Offset'];
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

function IsHex16(AData: TJSONData): Boolean;
var s: string; i: Integer;
begin
  Result := False;
  if (AData = nil) or (AData.JSONType <> jtString) then Exit;
  s := AData.AsString;
  if Length(s) <> 16 then Exit;
  for i := 1 to 16 do
    if not (s[i] in ['0'..'9', 'a'..'f']) then Exit;
  Result := True;
end;

function ColourOf(const AText: string; out AC: TTyChartColor): Boolean;
begin
  AC := 0;
  if (AText = 'null') or (AText = 'none') or (AText = '') then Exit(False);
  Result := TyTryParseChartColor(AText, AC);
end;

function ValText(const V: TTyAnimValue): string;
begin
  case V.Kind of
    avkNull: Result := 'null';
    avkNumber, avkBool: Result := TyJsNumberToString(V.Num);
    avkString: Result := V.Str;
  else
    Result := '[array]';
  end;
end;

function StateAnimsOf(P: TTyChartAnimProxy): string;
var
  i: Integer;
  a: TTyAnimator;
begin
  Result := '';
  if P = nil then Exit;
  for i := 0 to P.AnimatorCount - 1 do
  begin
    a := P.AnimatorAt(i);
    if a.FromStateTransition = '' then Continue;
    if Result <> '' then Result := Result + ' ';
    Result := Result + a.FromStateTransition + ':' + a.TargetName;
  end;
end;

{ ==================== the probe ==================== }

function TAs2Probe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TAs2Probe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TAs2Probe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TAs2Probe.ClickAt(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
  MouseDown(mbLeft, [ssLeft], AX, AY);
  MouseUp(mbLeft, [], AX, AY);
end;

function TAs2Probe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TAs2Probe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

function TAs2Probe.Primary: TTyChartColor;
begin
  Result := StPrimaryInk;
end;

procedure TAs2Probe.Update;
begin
  FullUpdate;
end;

{ ==================== the log ==================== }

constructor TAs2Logger.Create;
begin
  inherited Create;
  Log := TStringList.Create;
end;

destructor TAs2Logger.Destroy;
begin
  Log.Free;
  inherited Destroy;
end;

procedure TAs2Logger.Handle(Sender: TObject; const AEvent: TTyChartEvent);
var o: TJSONObject;
begin
  if AEvent.Payload <> '' then
    Log.Add(AEvent.EventType + #9 + AEvent.Payload)
  else
  begin
    o := TJSONObject.Create;
    try
      o.Add('componentType', AEvent.Params.ComponentType);
      o.Add('seriesIndex', AEvent.Params.SeriesIndex);
      o.Add('dataIndex', AEvent.Params.RawDataIndex);
      Log.Add(AEvent.EventType + #9 + o.AsJSON);
    finally
      o.Free;
    end;
  end;
end;

function JsonText(AData: TJSONData): string;
begin
  if AData = nil then Result := '(none)' else Result := AData.AsJSON;
end;

{ upstream's fields, each as the port's: a null upstream matches a field the
  port leaves out }
function SameJsonData(AWant, AGot: TJSONData): Boolean;
var
  i, k: Integer;
  wo, go: TJSONObject;
begin
  if (AWant = nil) or (AWant.JSONType = jtNull) then
    Exit((AGot = nil) or (AGot.JSONType = jtNull));
  if AGot = nil then Exit(False);
  if AWant.JSONType <> AGot.JSONType then Exit(False);
  case AWant.JSONType of
    jtBoolean: Result := AWant.AsBoolean = AGot.AsBoolean;
    jtNumber: Result := AWant.AsFloat = AGot.AsFloat;
    jtString: Result := AWant.AsString = AGot.AsString;
    jtArray:
      begin
        Result := False;
        if AWant.Count <> AGot.Count then Exit;
        for i := 0 to AWant.Count - 1 do
          if not SameJsonData(TJSONArray(AWant).Items[i], TJSONArray(AGot).Items[i]) then Exit;
        Result := True;
      end;
    jtObject:
      begin
        Result := False;
        wo := TJSONObject(AWant);
        go := TJSONObject(AGot);
        if wo.Count <> go.Count then Exit;
        for i := 0 to wo.Count - 1 do
        begin
          if go.Names[i] <> wo.Names[i] then Exit;
          k := i;
          if not SameJsonData(wo.Items[i], go.Items[k]) then Exit;
        end;
        Result := True;
      end;
  else
    Result := False;
  end;
end;

{ ==================== the replay ==================== }

procedure TAdvChartAnimState2OracleTest.SetUp;
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
  FLogger := TAs2Logger.Create;
  FSeen := TStringList.Create;
  FTally := TStringList.Create;
end;

procedure TAdvChartAnimState2OracleTest.TearDown;
begin
  FreeAndNil(FSeen);
  FreeAndNil(FTally);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  FreeAndNil(FLogger);
  inherited TearDown;
end;

procedure TAdvChartAnimState2OracleTest.Miss(const AWhere: string; const AOnce: string);
var c: string; i: Integer;
begin
  Inc(FBad);
  c := Copy(AWhere, 1, Pos(' ', AWhere) - 1);
  i := FTally.IndexOfName(c);
  if i < 0 then FTally.Add(c + '=1')
  else FTally.ValueFromIndex[i] := IntToStr(StrToInt(FTally.ValueFromIndex[i]) + 1);
  if AOnce <> '' then
  begin
    if FSeen.IndexOf(AOnce) >= 0 then Exit;
    FSeen.Add(AOnce);
  end;
  if FSeen.Count + Ord(AOnce = '') <= 80 then
    FReport := FReport + LineEnding + '  ' + AWhere;
end;

procedure TAdvChartAnimState2OracleTest.NewChart;
var i: Integer;
begin
  FreeAndNil(FChart);
  FChart := TAs2Probe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := T0;
  FChart.SetBounds(0, 0, cW, cH);
  for i := 0 to High(cEventTypes) do FChart.ChartOn(cEventTypes[i], @FLogger.Handle);
end;

procedure TAdvChartAnimState2OracleTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartAnimState2OracleTest.Settle(AStart: Double);
var t: Integer;
begin
  t := 16;
  while t <= 5000 do
  begin
    FChart.AnimNow := AStart + t;
    FChart.AnimTick(AStart + t);
    Inc(t, 250);
  end;
  Draw;
  AssertEquals('settled', FChart.AnimLoopClipCount, FChart.AnimClipCount);
end;

procedure TAdvChartAnimState2OracleTest.CompareEvents(const AWhere: string;
  ACase: TJSONObject; AT: Double);
var
  want: TJSONArray;
  i, n, p, k: Integer;
  ev, got: TJSONObject;
  line, typ, names: string;
  g: TJSONData;
begin
  want := ACase.Arrays['published'];
  n := 0;
  names := '';
  for i := 0 to want.Count - 1 do
  begin
    ev := want.Objects[i];
    if ev.Floats['at'] <> AT then Continue;
    Inc(FEventsCompared);
    if n >= FLogger.Log.Count then
    begin
      Miss(Format('%s: event %d %s missing', [AWhere, n, ev.Strings['type']]),
        AWhere + 'ev' + IntToStr(n));
      Inc(n);
      Continue;
    end;
    line := FLogger.Log[n];
    p := Pos(#9, line);
    typ := Copy(line, 1, p - 1);
    names := names + ' ' + typ;
    if typ <> ev.Strings['type'] then
    begin
      Miss(Format('%s: event %d is %s, upstream %s', [AWhere, n, typ,
        ev.Strings['type']]), AWhere + 'evt' + IntToStr(n));
      Inc(n);
      Continue;
    end;
    g := GetJSON(Copy(line, p + 1, MaxInt));
    try
      if not (g is TJSONObject) then
      begin
        Miss(AWhere + ': event payload not an object');
        Inc(n);
        Continue;
      end;
      got := TJSONObject(g);
      for k := 0 to ev.Count - 1 do
      begin
        if (ev.Names[k] = 'at') or (ev.Names[k] = 'type') then Continue;
        if not SameJsonData(ev.Items[k], got.Find(ev.Names[k])) then
          Miss(Format('%s: event %d %s.%s %s, upstream %s', [AWhere, n, typ,
            ev.Names[k], JsonText(got.Find(ev.Names[k])), ev.Items[k].AsJSON]),
            AWhere + typ + ev.Names[k] + IntToStr(n));
      end;
    finally
      g.Free;
    end;
    Inc(n);
  end;
  for i := n to FLogger.Log.Count - 1 do
    Miss(Format('%s: an extra event %s', [AWhere, Copy(FLogger.Log[i], 1,
      Pos(#9, FLogger.Log[i]) - 1)]), AWhere + 'extra' + IntToStr(i));
end;

procedure TAdvChartAnimState2OracleTest.CompareSelection(const AWhere: string;
  ACase: TJSONObject; ASample: Integer);
var
  sel, rec: TJSONArray;
  i, k: Integer;
  e: TJSONObject;
  got: TJSONData;
  txt, want: string;
  idx: TTyIntegerArray;
begin
  sel := ACase.Arrays['selection'];
  if ASample < sel.Count then rec := sel.Arrays[ASample] else rec := sel.Arrays[0];
  for i := 0 to rec.Count - 1 do
  begin
    e := rec.Objects[i];
    txt := StringReplace(FChart.SelectedMapText(e.Integers['s']), '\u0000', '<0>',
      [rfReplaceAll]);
    got := GetJSON(txt);
    try
      if not SameJsonData(e.Find('map'), got) then
        Miss(Format('%s: series %d selectedMap %s, upstream %s', [AWhere,
          e.Integers['s'], got.AsJSON, e.Find('map').AsJSON]), AWhere + 'map');
    finally
      got.Free;
    end;
    idx := FChart.SelectedDataIndices(e.Integers['s']);
    txt := '';
    for k := 0 to High(idx) do txt := txt + IntToStr(idx[k]) + ',';
    want := '';
    for k := 0 to e.Arrays['indices'].Count - 1 do
      want := want + IntToStr(e.Arrays['indices'].Integers[k]) + ',';
    if txt <> want then
      Miss(Format('%s: series %d selected %s, upstream %s', [AWhere,
        e.Integers['s'], txt, want]), AWhere + 'idx');
  end;
end;

{ the value of a key at sample ASample: the track's, else the final one }
function ValueAt(AEl: TJSONObject; const AKey: string; ASample: Integer;
  out AV: TJSONData): Boolean;
var tr: TJSONData;
begin
  AV := nil;
  tr := AEl.Find('track');
  if (tr <> nil) and (tr.JSONType = jtObject) and (TJSONObject(tr).Find(AKey) <> nil) then
    AV := TJSONObject(tr).Arrays[AKey].Items[ASample]
  else if TJSONObject(AEl.Find('final')).Find(AKey) <> nil then
    AV := TJSONObject(AEl.Find('final')).Find(AKey);
  Result := (AV <> nil) and (AV.JSONType <> jtNull);
end;

function Tracked(AEl: TJSONObject; const AKey: string): Boolean;
var tr: TJSONData;
begin
  tr := AEl.Find('track');
  Result := (tr <> nil) and (tr.JSONType = jtObject) and (TJSONObject(tr).Find(AKey) <> nil);
end;

{ the last sample at which the element holds no state: its rest values }
function RestSample(AEl: TJSONObject): Integer;
var
  i, n: Integer;
  v: TJSONData;
begin
  n := TJSONArray(Fix.Arrays['samplesMs']).Count;
  Result := -1;
  for i := n - 1 downto 0 do
    if ValueAt(AEl, 'states', i, v) and (v.AsString = '') then Exit(i);
end;

function Present(AEl: TJSONObject; ASample: Integer): Boolean;
var i: Integer;
begin
  if AEl.Find('present').JSONType = jtNull then Exit(True);
  Result := False;
  for i := 0 to AEl.Arrays['present'].Count - 1 do
    if AEl.Arrays['present'].Integers[i] = ASample then Exit(True);
end;

function NumOf(AV: TJSONData): Double;
begin
  if IsHex16(AV) then Result := FromHex(AV.AsString)
  else Result := AV.AsFloat;
end;

procedure TAdvChartAnimState2OracleTest.CompareMarker(const AWhere: string;
  AEl: TJSONObject; ASample: Integer);
var
  map: TJSONObject;
  st: TTyStElement;
  idx, rs: Integer;
  v, rv: TJSONData;
  want, rest, got, portRest: Double;
begin
  map := AEl.Objects['map'];
  if not FChart.MarkerStates(map.Integers['s'], map.Strings['part'], st, idx) then
  begin
    Miss(Format('%s %s: no marker element', [AWhere, map.Strings['part']]),
      AEl.Strings['id'] + 'none');
    Exit;
  end;
  Inc(FMarksCompared);
  if ValueAt(AEl, 'states', ASample, v) and (v.AsString <> TyStNamesText(st.States)) then
    Miss(Format('%s %s: states "%s", upstream "%s"', [AWhere, map.Strings['part'],
      TyStNamesText(st.States), v.AsString]), AWhere + map.Strings['part'] + 'st');
  { the opacity as a factor over the rest: an end symbol's rest has none }
  rs := RestSample(AEl);
  if ValueAt(AEl, 'style.opacity', ASample, v) then want := NumOf(v) else want := 1;
  rest := 1;
  if (rs >= 0) and ValueAt(AEl, 'style.opacity', rs, rv) then rest := NumOf(rv);
  portRest := st.Rest.Num[stkOpacity];
  got := FChart.List.Element(idx).Style.Alpha;
  if rest > 0 then want := want / rest * portRest;
  if Abs(got - want) > 1e-12 then
    Miss(Format('%s %s: opacity %s, upstream %s', [AWhere, map.Strings['part'],
      FloatToStr(got), FloatToStr(want)]), AWhere + map.Strings['part'] + 'op');
end;

procedure TAdvChartAnimState2OracleTest.CompareElement(const AWhere: string;
  AEl: TJSONObject; ASample: Integer);
const
  cKeys: array[0..13] of string = ('style.fill', 'style.stroke', 'style.lineWidth',
    'style.opacity', 'x', 'y', 'scaleX', 'scaleY', 'shape.r', 'shape.r0',
    'rotation', 'shape.startAngle', 'shape.endAngle', 'shape.points');
var
  map: TJSONObject;
  s, row, j, idx, rs, q: Integer;
  part, key, want, got, restF, id: string;
  p: TTyChartAnimProxy;
  v: TTyAnimValue;
  fv, rv, tr: TJSONData;
  rest: TTyAnimValue;
  restOk: Boolean;
  cf, cp, cr, crp: TTyChartColor;
  st: TTyAnimCfg;
  el: TTyChartElement;
  rec: TTyStElement;
begin
  map := AEl.Objects['map'];
  s := map.Integers['s'];
  row := map.Integers['row'];
  part := map.Strings['part'];
  id := AEl.Strings['id'];
  idx := FChart.StatePartIndex(s, row, part);
  if idx < 0 then
  begin
    { an element upstream keeps ignored and the port does not build (a
      radar's polygon no state shows, an inside label's line): not drawn }
    if ValueAt(AEl, 'ignore', ASample, fv) and fv.AsBoolean then Exit;
    Miss(Format('%s %s: no element', [AWhere, id]), id + 'none');
    Exit;
  end;
  el := FChart.List.Element(idx);
  { visible as upstream }
  if ValueAt(AEl, 'ignore', ASample, fv) and (fv.AsBoolean <> el.Ignore) then
    Miss(Format('%s %s: ignore %s, upstream %s', [AWhere, id, BoolToStr(el.Ignore, True),
      fv.AsJSON]), AWhere + id + 'ign');
  { the paint order against the rest, as the state machine holds it, and
    what the list draws }
  rs := RestSample(AEl);
  if FChart.StatePartRecord(s, row, part, rec) then
  begin
    if (rs >= 0) and ValueAt(AEl, 'z2', ASample, fv) and ValueAt(AEl, 'z2', rs, rv)
      and (rec.Cur.Num[stkZ2] - rec.Rest.Num[stkZ2] <> NumOf(fv) - NumOf(rv)) then
      Miss(Format('%s %s: z2 lifted by %s, upstream %s', [AWhere, id,
        FloatToStr(rec.Cur.Num[stkZ2] - rec.Rest.Num[stkZ2]),
        FloatToStr(NumOf(fv) - NumOf(rv))]), AWhere + id + 'z2');
    if el.Z2 <> Round(rec.Cur.Num[stkZ2]) then
      Miss(Format('%s %s: the list draws z2 %d, the state %s', [AWhere, id, el.Z2,
        FloatToStr(rec.Cur.Num[stkZ2])]), AWhere + id + 'z2l');
  end
  else
    Miss(Format('%s %s: no state record', [AWhere, id]), id + 'rec');
  p := FChart.AnimStateProxy(s, row, part);
  if p = nil then
  begin
    Miss(Format('%s %s: no state proxy', [AWhere, id]), id + 'px');
    Exit;
  end;
  Inc(FCompared);
  if ValueAt(AEl, 'states', ASample, fv) and (fv.AsString <> p.CurrentStates) then
    Miss(Format('%s %s: states "%s", upstream "%s"', [AWhere, id,
      p.CurrentStates, fv.AsString]), AWhere + id + 'states');
  tr := AEl.Find('stateAnimators');
  if tr.JSONType = jtNull then want := '' else want := TJSONArray(tr).Strings[ASample];
  got := StateAnimsOf(p);
  if want <> got then
    Miss(Format('%s %s: state animators "%s", upstream "%s"', [AWhere, id,
      got, want]), AWhere + id + 'sa');
  tr := AEl.Find('transition');
  if tr.JSONType = jtNull then want := '' else want := TJSONArray(tr).Strings[ASample];
  if p.HasStateTransition then
  begin
    st := p.StateTransition;
    got := TyJsNumberToString(st.Duration) + '/' + st.Easing + '/';
    if st.Delay <> 0 then got := got + TyJsNumberToString(st.Delay);
  end
  else
    got := '';
  if want <> got then
    Miss(Format('%s %s: stateTransition "%s", upstream "%s"', [AWhere, id, got, want]),
      id + 'tr');
  for j := 0 to High(cKeys) do
  begin
    key := cKeys[j];
    if ((key = 'x') or (key = 'y') or (key = 'scaleX') or (key = 'scaleY'))
      and not p.HasStKey(key) then Continue;
    v := p.GetAnimProp(key);
    { [F3a] THE ENTER'S KEYS (a pointer's rotation, an arc's angles, a radar
      ring's points): compared where upstream moves them -- the proxy the
      states run on must be the one the enter runs on }
    if ((key = 'rotation') or (Copy(key, 1, 6) = 'shape.')) and (key <> 'shape.r')
      and (key <> 'shape.r0') and not Tracked(AEl, key) then Continue;
    { a graph edge's label is placed from its line's percent: the enter
      test's }
    if (key = 'rotation') and (Copy(part, Length(part) - 4, 5) = 'label') then Continue;
    if key = 'shape.points' then
    begin
      if not ValueAt(AEl, key, ASample, fv) or not (fv is TJSONArray) then Continue;
      if v.Kind <> avkArray then
      begin
        Miss(Format('%s %s %s: the proxy has none', [AWhere, id, key]), id + key + 'none');
        Continue;
      end;
      Inc(FKeysCompared);
      Inc(FTrackedCompared);
      if Length(v.Arr) <> fv.Count then
      begin
        Miss(Format('%s %s %s: %d numbers, upstream %d', [AWhere, id, key, Length(v.Arr),
          fv.Count]), AWhere + id + key + 'n');
        Continue;
      end;
      for q := 0 to High(v.Arr) do
        if Hex(v.Arr[q]) <> TJSONArray(fv).Strings[q] then
        begin
          Miss(Format('%s %s %s[%d]: %s, upstream %s', [AWhere, id, key, q,
            TyJsNumberToString(v.Arr[q]), TyJsNumberToString(FromHex(TJSONArray(fv).Strings[q]))]),
            AWhere + id + key);
          Break;
        end;
      Continue;
    end;
    if not ValueAt(AEl, key, ASample, fv) then
    begin
      if Tracked(AEl, key) and (v.Kind <> avkNull) and (key = 'style.stroke') then
        Miss(Format('%s %s %s: %s, upstream none', [AWhere, id, key, ValText(v)]),
          AWhere + id + key + 'n');
      Continue;
    end;
    if (v.Kind = avkNull) and not ((fv.JSONType = jtString) and (fv.AsString = 'null')) then
    begin
      if Tracked(AEl, key) then
        Miss(Format('%s %s %s: the proxy has none, upstream %s', [AWhere, id, key,
          fv.AsJSON]), id + key + 'none');
      Continue;
    end;
    Inc(FKeysCompared);
    if Tracked(AEl, key) then Inc(FTrackedCompared);
    if IsHex16(fv) then
    begin
      if v.Kind <> avkNumber then
      begin
        Miss(Format('%s %s %s: not a number', [AWhere, id, key]), id + key + 'nan');
        Continue;
      end;
      if Hex(v.Num) <> fv.AsString then
        Miss(Format('%s %s %s: %s, upstream %s', [AWhere, id, key,
          TyJsNumberToString(v.Num), TyJsNumberToString(FromHex(fv.AsString))]),
          AWhere + id + key);
      Continue;
    end;
    if fv.JSONType <> jtString then Continue;
    restOk := p.StRestOf(key, rest) and (rest.Kind = avkString);
    rv := nil;
    if (rs < 0) or not ValueAt(AEl, key, rs, rv) then rv := nil;
    restF := '';
    if (rv <> nil) and (rv.JSONType = jtString) then restF := rv.AsString;
    if fv.AsString = 'null' then
    begin
      if (v.Kind <> avkNull) and ColourOf(ValText(v), cp) then
        Miss(Format('%s %s %s: %s, upstream null', [AWhere, id, key, ValText(v)]),
          AWhere + id + key);
      Continue;
    end;
    if not ColourOf(fv.AsString, cf) then Continue;
    if not ColourOf(ValText(v), cp) then
    begin
      Miss(Format('%s %s %s: %s, upstream %s', [AWhere, id, key, ValText(v),
        fv.AsString]), AWhere + id + key);
      Continue;
    end;
    if fv.AsString = cPrimary then cf := FChart.Primary
    else if restOk and ColourOf(restF, cr) and ColourOf(rest.Str, crp) and (cr <> crp) then
    begin
      if cf = cr then cf := crp
      else if cf = TyChartLiftColor(cr) then cf := TyChartLiftColor(crp)
      else Continue;
    end;
    if cf <> cp then
      Miss(Format('%s %s %s: %s, upstream %s', [AWhere, id, key, ValText(v),
        fv.AsString]), AWhere + id + key);
  end;
end;

procedure TAdvChartAnimState2OracleTest.RunCase(ACase: TJSONObject);
var
  name, s, where: string;
  samples, events, els: TJSONArray;
  si, ei, k: Integer;
  t: Double;
  e, el: TJSONObject;
  live, flushed: Boolean;
begin
  name := ACase.Strings['id'];
  samples := Fix.Arrays['samplesMs'];
  events := ACase.Arrays['events'];
  els := ACase.Arrays['elements'];
  NewChart;
  live := (ACase.Find('live') <> nil) and ACase.Booleans['live'];
  if not live then
  begin
    FChart.Option := ACase.Objects['option'].AsJSON;
    AssertEquals(name + ': the option parses', '', FChart.OptionError);
    Draw;
    Settle(T0);
  end;
  for si := 0 to samples.Count - 1 do
  begin
    t := samples.Floats[si];
    FChart.AnimNow := T1 + t;
    FLogger.Log.Clear;
    { A LIVE CASE's option at T1: its first render arms and flushes -- the
      sample makes no further frame }
    flushed := False;
    if live and (si = 0) then
    begin
      FChart.Option := ACase.Objects['option'].AsJSON;
      AssertEquals(name + ': the option parses', '', FChart.OptionError);
      Draw;
      flushed := True;
    end;
    for ei := 0 to events.Count - 1 do
    begin
      e := events.Objects[ei];
      if e.Floats['at'] <> t then Continue;
      s := e.Strings['type'];
      if (s = 'move') or (s = 'out') then FChart.Move(e.Integers['x'], e.Integers['y'])
      else if s = 'click' then FChart.ClickAt(e.Integers['x'], e.Integers['y'])
      else if s = 'action' then FChart.DispatchAction(e.Objects['payload'].AsJSON);
    end;
    if not flushed then FChart.AnimTick(T1 + t);
    Draw;
    where := name + ' t=' + FloatToStr(t);
    CompareEvents(where, ACase, t);
    CompareSelection(where, ACase, si);
    for k := 0 to els.Count - 1 do
    begin
      el := els.Objects[k];
      if el.Find('map').JSONType = jtNull then Continue;
      if not Present(el, si) then Continue;
      if el.Objects['map'].Integers['row'] < 0 then CompareMarker(where, el, si)
      else CompareElement(where, el, si);
    end;
  end;
end;

procedure TAdvChartAnimState2OracleTest.TestTheTransitionsAsUpstream;
var
  cases: TJSONArray;
  i: Integer;
begin
  cases := Fix.Arrays['cases'];
  AssertTrue('the fixture has its cases', cases.Count >= 15);
  for i := 0 to cases.Count - 1 do RunCase(cases.Objects[i]);
  if FBad > 0 then
    Fail(Format('%d mismatches over %d samples (%s):%s', [FBad, FCompared,
      FTally.CommaText, FReport]));
  AssertTrue(Format('keys compared: %d, tracked %d, events %d',
    [FKeysCompared, FTrackedCompared, FEventsCompared]),
    (FTrackedCompared > 500) and (FEventsCompared > 20));
end;

initialization
  RegisterTest(TAdvChartAnimState2OracleTest);
finalization
  FreeAndNil(GFix);
end.
