unit test.advchart.statesmisc;
{$mode objfpc}{$H+}
{ THE STATES THE SHARED MODEL DID NOT REACH YET, HELD TO UPSTREAM [F2b].

  tools/advchart-oracle/states-misc.js drives the real ECharts 6.1 build with
  the controlled clock of state-anim.js -- an option set at T0 and settled,
  then pointer moves and clicks through zr.handler and dispatchAction at
  T1 + t, one frame per sample -- over
    a gauge's pointer and progress arc (two dispatchers, z2EmphasisLift 0),
    a radar's item group (polyline, polygon, symbols),
    the markers of a series blurSeries reached,
    a click on a large bar or point (select dispatched, no state),
    a pie's and a funnel's label hidden at rest and shown by a state,
    a pictorial bar's glyphs as its hit target.
  Every element is recorded per sample with its state list, its keys, its
  state animators and its stateTransition, and `map`, the part the port keeps
  it as; every published event and every series' selection per sample.

  The replay drives the control the same way -- MouseMove, MouseDown /
  MouseUp, DispatchAction, AnimTick, a render per sample -- in camAlways with
  the injected clock and compares, sample by sample: the events (type and the
  fields upstream's carry), the selectedMap and the selected indices, and for
  every mapped element its state list, its visibility, its paint order
  against its rest, and -- on the proxy its states run on -- every key
  upstream tracks bit for bit (colours through the skin, as animstate's
  replay), its state animators and its stateTransition; a marker, which has
  no transition, by its list element's opacity. }
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
  TSmProbe = class(TTyAdvanceChart)
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

  TSmLogger = class
  public
    Log: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Handle(Sender: TObject; const AEvent: TTyChartEvent);
  end;

  TAdvChartStatesMiscOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TSmProbe;
    FLogger: TSmLogger;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FKeysCompared, FTrackedCompared, FEventsCompared,
      FMarksCompared, FPlaces, FOrders, FDashes: Integer;
    { [R2-I3] the pens' phases compared as drawn }
    FDashOffs: Integer;
    { [R2-I1] labels' opacities: a factor over a rest other than 1, as drawn }
    FFactored, FDrawnOpacities: Integer;
    { [r2v] label lines' pens as drawn against their state proxies }
    FDrawnPens: Integer;
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
    procedure CompareOrder(const AWhere: string; AEls: TJSONArray; ASample: Integer);
    procedure RunCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheStatesAsUpstream;
  end;

  { the pieces the replay does not reach on its own }
  TAdvChartStatesMiscTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TSmProbe;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    procedure NewChart(AMode: TTyChartAnimationMode);
    procedure Load(const AOption: string);
    procedure Draw;
    function FindRole(ARole: TTyChartAnimRole; ASeries, ARow: Integer;
      out AEl: TTyChartElement): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAHoveredPointerIsLiftedInTheListAndTheArcIsNot;
    procedure TestTheRoundCapsTakeTheirArcsState;
    procedure TestARadarSymbolStaysOverALiftedRing;
    procedure TestAMarkPointFadesWithinItsEnterAnimation;
    procedure TestAPictorialLabelTakesNoPointer;
    procedure TestAFullUpdateMakesTheGaugeAnew;
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
        + 'advchart-states-misc.json');
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

function TSmProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TSmProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TSmProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TSmProbe.ClickAt(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
  MouseDown(mbLeft, [ssLeft], AX, AY);
  MouseUp(mbLeft, [], AX, AY);
end;

function TSmProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TSmProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

function TSmProbe.Primary: TTyChartColor;
begin
  Result := StPrimaryInk;
end;

procedure TSmProbe.Update;
begin
  FullUpdate;
end;

{ ==================== the log ==================== }

constructor TSmLogger.Create;
begin
  inherited Create;
  Log := TStringList.Create;
end;

destructor TSmLogger.Destroy;
begin
  Log.Free;
  inherited Destroy;
end;

procedure TSmLogger.Handle(Sender: TObject; const AEvent: TTyChartEvent);
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

procedure TAdvChartStatesMiscOracleTest.SetUp;
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
  FLogger := TSmLogger.Create;
  FSeen := TStringList.Create;
  FTally := TStringList.Create;
end;

procedure TAdvChartStatesMiscOracleTest.TearDown;
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

procedure TAdvChartStatesMiscOracleTest.Miss(const AWhere: string; const AOnce: string);
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

procedure TAdvChartStatesMiscOracleTest.NewChart;
var i: Integer;
begin
  FreeAndNil(FChart);
  FChart := TSmProbe.Create(FForm);
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

procedure TAdvChartStatesMiscOracleTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartStatesMiscOracleTest.Settle(AStart: Double);
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

procedure TAdvChartStatesMiscOracleTest.CompareEvents(const AWhere: string;
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

procedure TAdvChartStatesMiscOracleTest.CompareSelection(const AWhere: string;
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

procedure TAdvChartStatesMiscOracleTest.CompareMarker(const AWhere: string;
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

procedure TAdvChartStatesMiscOracleTest.CompareElement(const AWhere: string;
  AEl: TJSONObject; ASample: Integer);
const
  cKeys: array[0..9] of string = ('style.fill', 'style.stroke', 'style.lineWidth',
    'style.opacity', 'x', 'y', 'scaleX', 'scaleY', 'shape.r', 'shape.r0');
var
  map: TJSONObject;
  s, row, j, idx, rs: Integer;
  part, key, want, got, restF, id: string;
  p: TTyChartAnimProxy;
  v: TTyAnimValue;
  fv, rv, tr: TJSONData;
  rest: TTyAnimValue;
  restOk: Boolean;
  cf, cp, cr, crp: TTyChartColor;
  st: TTyAnimCfg;
  el, fel: TTyChartElement;
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
  { [R2-B] A LABEL WHERE IT IS DRAWN (a labelPlace case): its computed
    transform's translation, the frame's caption anchor -- to 1e-9 }
  if ValueAt(AEl, 'tx', ASample, fv) and ValueAt(AEl, 'ty', ASample, rv) then
  begin
    if (FChart.Frame <> nil) and (FChart.Frame.Count = FChart.List.Count) then
      fel := FChart.Frame.Element(idx)
    else
      fel := el;
    Inc(FPlaces);
    if (Abs(fel.Caption.X - NumOf(fv)) > 1e-9) or (Abs(fel.Caption.Y - NumOf(rv)) > 1e-9) then
      Miss(Format('%s %s: drawn at (%s, %s), upstream (%s, %s)', [AWhere, id,
        FloatToStr(fel.Caption.X), FloatToStr(fel.Caption.Y), FloatToStr(NumOf(fv)),
        FloatToStr(NumOf(rv))]), AWhere + id + 'place');
  end;
  { [R2-B] A PATH'S DASH (a dash case): normalizeLineDash's lengths, as
    drawn -- [R2-I4] the frame's where there is one (a word follows the width
    a state tweens), the list's otherwise [was: the list's] }
  if ValueAt(AEl, 'dash', ASample, fv) then
  begin
    if (FChart.Frame <> nil) and (FChart.Frame.Count = FChart.List.Count) then
      fel := FChart.Frame.Element(idx)
    else
      fel := el;
    got := 'null';
    if Length(fel.Style.DashLogical) > 0 then
    begin
      got := '[';
      for j := 0 to High(fel.Style.DashLogical) do
      begin
        if j > 0 then got := got + ',';
        got := got + TyJsNumberToString(fel.Style.DashLogical[j]);
      end;
      got := got + ']';
    end;
    Inc(FDashes);
    if got <> fv.AsString then
      Miss(Format('%s %s: dash %s, upstream %s', [AWhere, id, got, fv.AsString]),
        AWhere + id + 'dash');
  end;
  { [R2-I3] THE PEN'S PHASE as drawn (a dashOff case): the frame's where a
    state's tweens it, the list's otherwise -- recorded only where a dash is }
  if ValueAt(AEl, 'dashOff', ASample, fv) and (fv.JSONType <> jtNull) then
  begin
    if (FChart.Frame <> nil) and (FChart.Frame.Count = FChart.List.Count) then
      fel := FChart.Frame.Element(idx)
    else
      fel := el;
    Inc(FDashOffs);
    if Abs(fel.Style.DashOffsetLogical - NumOf(fv)) > 1e-9 then
      Miss(Format('%s %s: dash phase %s, upstream %s', [AWhere, id,
        FloatToStr(fel.Style.DashOffsetLogical), FloatToStr(NumOf(fv))]), AWhere + id + 'doff');
  end;
  { visible as upstream }
  if ValueAt(AEl, 'ignore', ASample, fv) and (fv.AsBoolean <> el.Ignore) then
    Miss(Format('%s %s: ignore %s, upstream %s', [AWhere, id, BoolToStr(el.Ignore, True),
      fv.AsJSON]), AWhere + id + 'ign');
  { [R2-I1] A LABEL'S OPACITY AS DRAWN: the frame's (in motion or on a
    state proxy), the list's otherwise -- upstream's style.opacity, the
    host's at rest (defaultOpacity) }
  if (AEl.Strings['role'] = 'label') and not el.Ignore
    and ValueAt(AEl, 'style.opacity', ASample, fv) and IsHex16(fv) then
  begin
    if (FChart.Frame <> nil) and (FChart.Frame.Count = FChart.List.Count) then
      fel := FChart.Frame.Element(idx)
    else
      fel := el;
    Inc(FDrawnOpacities);
    if Abs(fel.Style.Alpha - FromHex(fv.AsString)) > 1e-9 then
      Miss(Format('%s %s: drawn at opacity %s, upstream %s', [AWhere, id,
        FloatToStr(fel.Style.Alpha), FloatToStr(FromHex(fv.AsString))]), AWhere + id + 'dop');
  end;
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
  { [r2v] A LABEL LINE'S PEN AS DRAWN: the frame's (or the list's) stroke and
    width are its state proxy's -- the proxy's own values are compared with
    upstream's below; while the tween still stands at the rest (the hover's
    first frame) the frame draws the list's, which must then be the rest
    too [226-09: the state's colour written to the list at once showed
    through there] }
  if (AEl.Strings['role'] = 'guide') and not el.Ignore then
  begin
    if (FChart.Frame <> nil) and (FChart.Frame.Count = FChart.List.Count) then
      fel := FChart.Frame.Element(idx)
    else
      fel := el;
    v := p.GetAnimProp('style.stroke');
    if (v.Kind <> avkNull) and ColourOf(ValText(v), cp) then
    begin
      Inc(FDrawnPens);
      if fel.Style.StrokeColor <> cp then
        Miss(Format('%s %s: drawn stroke %s, its proxy %s', [AWhere, id,
          IntToHex(fel.Style.StrokeColor, 8), ValText(v)]), AWhere + id + 'dpen');
    end;
    v := p.GetAnimProp('style.lineWidth');
    if v.Kind = avkNumber then
    begin
      Inc(FDrawnPens);
      if Abs(fel.Style.StrokeWidthLogical - v.Num) > 1e-9 then
        Miss(Format('%s %s: drawn width %s, its proxy %s', [AWhere, id,
          FloatToStr(fel.Style.StrokeWidthLogical), ValText(v)]), AWhere + id + 'dwid');
    end;
  end;
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
    { [R2-I1] A LABEL'S OPACITY ON A PROXY IT SHARES WITH ITS FADE is a
      factor over the label's own (the host's style.opacity, handed over as
      defaultOpacity): upstream's is the factor times that rest [was: the
      factor against upstream's, which held only where the rest is 1] }
    if (key = 'style.opacity') and IsHex16(fv) and (v.Kind = avkNumber)
      and not p.StAbsOpacity and (rec.Exists) and not rec.IsPath
      and (rec.Rest.Num[stkOpacity] <> 1) then
    begin
      Inc(FFactored);
      if Abs(v.Num * rec.Rest.Num[stkOpacity] - FromHex(fv.AsString)) > 1e-12 then
        Miss(Format('%s %s %s: %s x rest %s, upstream %s', [AWhere, id, key,
          TyJsNumberToString(v.Num), TyJsNumberToString(rec.Rest.Num[stkOpacity]),
          TyJsNumberToString(FromHex(fv.AsString))]), AWhere + id + key);
      Continue;
    end;
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

{ [R2-B] THE PAINT ORDER (an order case): the elements upstream records a
  display-list place for, in that order, are painted in that order here }
procedure TAdvChartStatesMiscOracleTest.CompareOrder(const AWhere: string;
  AEls: TJSONArray; ASample: Integer);
var
  k, i, n, idx: Integer;
  el, map: TJSONObject;
  v: TJSONData;
  pos: TTyIntegerArray;
  zi, at: array of Integer;
  ids: TTyStringArray;
  swapped: Boolean;
  tz, ta: Integer;
  ts: string;
begin
  n := 0;
  zi := nil;
  at := nil;
  ids := nil;
  for k := 0 to AEls.Count - 1 do
  begin
    el := AEls.Objects[k];
    if el.Find('map').JSONType = jtNull then Continue;
    if not Present(el, ASample) or not ValueAt(el, 'zi', ASample, v) then Continue;
    map := el.Objects['map'];
    idx := FChart.StatePartIndex(map.Integers['s'], map.Integers['row'], map.Strings['part']);
    if idx < 0 then Continue;
    SetLength(zi, n + 1);
    SetLength(at, n + 1);
    SetLength(ids, n + 1);
    zi[n] := Round(NumOf(v));
    at[n] := idx;
    ids[n] := el.Strings['id'];
    Inc(n);
  end;
  if n < 2 then Exit;
  SetLength(pos, FChart.List.Count);
  for i := 0 to FChart.List.Count - 1 do pos[FChart.List.PaintOrder(i)] := i;
  { by upstream's place }
  repeat
    swapped := False;
    for i := 0 to n - 2 do
      if zi[i] > zi[i + 1] then
      begin
        tz := zi[i]; zi[i] := zi[i + 1]; zi[i + 1] := tz;
        ta := at[i]; at[i] := at[i + 1]; at[i + 1] := ta;
        ts := ids[i]; ids[i] := ids[i + 1]; ids[i + 1] := ts;
        swapped := True;
      end;
  until not swapped;
  for i := 0 to n - 2 do
  begin
    Inc(FOrders);
    if pos[at[i]] > pos[at[i + 1]] then
      Miss(Format('%s: %s is painted over %s, upstream under it', [AWhere, ids[i], ids[i + 1]]),
        AWhere + ids[i] + 'ord');
  end;
end;

procedure TAdvChartStatesMiscOracleTest.RunCase(ACase: TJSONObject);
var
  name, s, where: string;
  samples, events, els: TJSONArray;
  si, ei, k: Integer;
  t: Double;
  e, el: TJSONObject;
begin
  name := ACase.Strings['id'];
  samples := Fix.Arrays['samplesMs'];
  events := ACase.Arrays['events'];
  els := ACase.Arrays['elements'];
  NewChart;
  FChart.Option := ACase.Objects['option'].AsJSON;
  AssertEquals(name + ': the option parses', '', FChart.OptionError);
  Draw;
  Settle(T0);
  for si := 0 to samples.Count - 1 do
  begin
    t := samples.Floats[si];
    FChart.AnimNow := T1 + t;
    FLogger.Log.Clear;
    for ei := 0 to events.Count - 1 do
    begin
      e := events.Objects[ei];
      if e.Floats['at'] <> t then Continue;
      s := e.Strings['type'];
      if (s = 'move') or (s = 'out') then FChart.Move(e.Integers['x'], e.Integers['y'])
      else if s = 'click' then FChart.ClickAt(e.Integers['x'], e.Integers['y'])
      else if s = 'action' then FChart.DispatchAction(e.Objects['payload'].AsJSON);
    end;
    FChart.AnimTick(T1 + t);
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
    CompareOrder(where, els, si);
  end;
end;

procedure TAdvChartStatesMiscOracleTest.TestTheStatesAsUpstream;
var
  cases: TJSONArray;
  i: Integer;
begin
  cases := Fix.Arrays['cases'];
  AssertTrue('the fixture has its cases', cases.Count >= 25);
  for i := 0 to cases.Count - 1 do RunCase(cases.Objects[i]);
  if FBad > 0 then
    Fail(Format('%d mismatches over %d samples (%s):%s', [FBad, FCompared,
      FTally.CommaText, FReport]));
  AssertTrue(Format('keys compared: %d, tracked %d, events %d, marker samples %d, '
    + 'label places %d, paint orders %d',
    [FKeysCompared, FTrackedCompared, FEventsCompared, FMarksCompared, FPlaces, FOrders])
    + Format(', dashes %d, factored label opacities %d, drawn label opacities %d',
      [FDashes, FFactored, FDrawnOpacities])
    + Format(', dash phases %d, drawn label-line pens %d', [FDashOffs, FDrawnPens]),
    (FTrackedCompared > 500) and (FEventsCompared > 40) and (FMarksCompared > 100)
    and (FPlaces > 100) and (FOrders > 100) and (FDashes > 50) and (FFactored > 200)
    and (FDashOffs > 50) and (FDrawnPens > 200)
    and (FDrawnOpacities > 1000));
end;

{ ==================== by hand ==================== }

procedure TAdvChartStatesMiscTest.SetUp;
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
end;

procedure TAdvChartStatesMiscTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartStatesMiscTest.NewChart(AMode: TTyChartAnimationMode);
begin
  FreeAndNil(FChart);
  FChart := TSmProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := AMode;
  FChart.AnimNow := T0;
  FChart.SetBounds(0, 0, cW, cH);
end;

procedure TAdvChartStatesMiscTest.Load(const AOption: string);
begin
  FChart.Option := AOption;
  AssertEquals('the option parses', '', FChart.OptionError);
  Draw;
end;

procedure TAdvChartStatesMiscTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartStatesMiscTest.FindRole(ARole: TTyChartAnimRole; ASeries,
  ARow: Integer; out AEl: TTyChartElement): Integer;
var k: Integer;
begin
  AEl := Default(TTyChartElement);
  for k := 0 to FChart.List.Count - 1 do
    if (FChart.List.Element(k).Anim.Role = ARole)
      and (FChart.List.Element(k).Anim.Series = ASeries)
      and (FChart.List.Element(k).Anim.Index = ARow) then
    begin
      AEl := FChart.List.Element(k);
      Exit(k);
    end;
  Result := -1;
end;

function PolyCentre(const AEl: TTyChartElement): TPoint;
var i: Integer; x, y: Double;
begin
  x := 0;
  y := 0;
  for i := 0 to High(AEl.Shape.Points) do
  begin
    x := x + AEl.Shape.Points[i].X;
    y := y + AEl.Shape.Points[i].Y;
  end;
  Result := Point(Round(x / Length(AEl.Shape.Points)), Round(y / Length(AEl.Shape.Points)));
end;

{ the middle of a ring sector, on its mid angle }
function SectorMiddle(const AEl: TTyChartElement): TPoint;
var mid, r: Double;
begin
  mid := (AEl.Shape.StartRad + AEl.Shape.EndRad) / 2;
  r := (AEl.Shape.R0 + AEl.Shape.R1) / 2;
  Result := Point(Round(AEl.Shape.CX + Cos(mid) * r), Round(AEl.Shape.CY + Sin(mid) * r));
end;

const
  cGauge = '{"animation":false,"color":["#5470c6"],"series":[{"type":"gauge","radius":"80%",'
    + '"progress":{"show":true,"width":14},"pointer":{"width":10},"detail":{"show":false},'
    + '"title":{"show":false},"data":[{"value":60,"name":"a"}]}]}';

{ THE OVERLAY IS GONE [F2b]: the hovered pointer is the state machine's, in
  the list, lifted where it is drawn; the arc beside it -- a dispatcher of
  its own -- is untouched, and the pointer's paint order does not move
  (z2EmphasisLift 0) }
procedure TAdvChartStatesMiscTest.TestAHoveredPointerIsLiftedInTheListAndTheArcIsNot;
var
  ptr, arc, ptr2, arc2: TTyChartElement;
  p: TPoint;
  item: TTyStItem;
begin
  NewChart(camOff);
  Load(cGauge);
  AssertTrue('the pointer', FindRole(carGaugePointer, 0, 0, ptr) >= 0);
  AssertTrue('the arc', FindRole(carGaugeProgress, 0, 0, arc) >= 0);
  p := PolyCentre(ptr);
  FChart.Move(p.X, p.Y);
  Draw;
  AssertTrue(FChart.ItemStates(0, 0, item));
  AssertEquals('the pointer in emphasis', 'emphasis', TyStNamesText(item.Host.States));
  AssertTrue(FChart.PeerStates(0, 0, item));
  AssertEquals('the arc is not', '', TyStNamesText(item.Host.States));
  FindRole(carGaugePointer, 0, 0, ptr2);
  FindRole(carGaugeProgress, 0, 0, arc2);
  AssertEquals('the pointer lifted in the list', IntToHex(TyChartLiftColor(ptr.Style.FillColor), 8),
    IntToHex(ptr2.Style.FillColor, 8));
  AssertEquals('at the same paint order', ptr.Z2, ptr2.Z2);
  AssertEquals('the arc as it was', IntToHex(arc.Style.FillColor, 8),
    IntToHex(arc2.Style.FillColor, 8));
  { and the arc's own hover }
  p := SectorMiddle(arc);
  FChart.Move(p.X, p.Y);
  Draw;
  AssertTrue(FChart.PeerStates(0, 0, item));
  AssertEquals('the arc in emphasis', 'emphasis', TyStNamesText(item.Host.States));
  AssertTrue(FChart.ItemStates(0, 0, item));
  AssertEquals('the pointer left it', '', TyStNamesText(item.Host.States));
end;

{ A ROUND CAP is a stretch of the arc's own Sausage upstream: the two discs
  follow the arc's state }
procedure TAdvChartStatesMiscTest.TestTheRoundCapsTakeTheirArcsState;
var
  arc, el: TTyChartElement;
  ai, k, caps: Integer;
  p: TPoint;
  rest: TTyChartColor;
begin
  NewChart(camOff);
  Load(StringReplace(cGauge, '"progress":{"show":true,"width":14}',
    '"progress":{"show":true,"width":14,"roundCap":true}', []));
  ai := FindRole(carGaugeProgress, 0, 0, arc);
  AssertTrue('the arc', ai >= 0);
  rest := arc.Style.FillColor;
  p := SectorMiddle(arc);
  FChart.Move(p.X, p.Y);
  Draw;
  caps := 0;
  for k := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(k);
    if (el.Shape.Kind <> cskCircle) or not el.Silent then Continue;
    if (k <> ai - 1) and (k <> ai - 2) then Continue;
    Inc(caps);
    AssertEquals(Format('cap %d lifted with the arc', [k]),
      IntToHex(TyChartLiftColor(rest), 8), IntToHex(el.Style.FillColor, 8));
  end;
  AssertEquals('both caps', 2, caps);
end;

{ RADAR SYMBOLS SIT AT z2 100 (RadarView.ts:67): a hovered ring rises by ten
  and stays under every symbol, its own and the other items' }
procedure TAdvChartStatesMiscTest.TestARadarSymbolStaysOverALiftedRing;
var
  k, ringZ2, minSym: Integer;
  el: TTyChartElement;
  hovered: Boolean;
begin
  NewChart(camOff);
  Load('{"animation":false,"radar":{"indicator":[{"name":"a","max":10},{"name":"b","max":10},'
    + '{"name":"c","max":10}]},"series":[{"type":"radar","symbolSize":10,'
    + '"data":[{"value":[6,8,4],"name":"p"},{"value":[3,4,9],"name":"q"}]}]}');
  ringZ2 := -1;
  hovered := False;
  for k := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(k);
    if (el.Datum.SeriesIndex = 0) and (el.Datum.DataIndex = 0)
      and (el.Shape.Kind <> cskPolyline) and (el.Anim.Role <> carRadarArea) and not hovered then
    begin
      FChart.Move(Round(TyShapeBounds(el.Shape).Left + 5), Round(TyShapeBounds(el.Shape).Top + 5));
      hovered := True;
    end;
  end;
  AssertTrue('a symbol', hovered);
  Draw;
  minSym := MaxInt;
  for k := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(k);
    if el.Datum.SeriesIndex <> 0 then Continue;
    if el.Anim.Role = carRadarLine then
    begin
      if el.Datum.DataIndex = 0 then ringZ2 := el.Z2;
    end
    else if (el.Anim.Role <> carRadarArea) and (el.Caption.FontSizeLogical <= 0) then
      minSym := Math.Min(minSym, el.Z2);
  end;
  AssertEquals('the hovered ring rose by ten', 10, ringZ2);
  AssertTrue(Format('every symbol over it: %d against %d', [minSym, ringZ2]), minSym > ringZ2);
end;

{ A MARKPOINT'S ENTER FADE OVER ITS STATE [F2b]: the role's opacity is a
  factor over what the list holds, so a blurred series' marker fades in to
  a tenth of its own and no further }
procedure TAdvChartStatesMiscTest.TestAMarkPointFadesWithinItsEnterAnimation;
const
  cOpt = '{"color":["#5470c6","#91cc75"],"xAxis":{"type":"category","data":["A","B","C"]},'
    + '"yAxis":{"type":"value","max":40},"series":[{"type":"bar","data":[5,20,36],'
    + '"markPoint":{"animationDuration":2000,"data":[{"type":"max","name":"max"}]}},'
    + '{"type":"bar","emphasis":{"focus":"series"},"data":[8,12,6]}]}';
var
  k, mk: Integer;
  el: TTyChartElement;
  b: TTyRectF;
  f: TTyPaintList;
  blurred, plain: Double;
begin
  NewChart(camAlways);
  Load(cOpt);
  FChart.AnimTick(T0 + 1);
  FChart.AnimTick(T0 + 300);
  Draw;
  { hover the second series' first bar: the first is blurred, its marker
    with it }
  for k := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(k);
    if (el.Datum.SeriesIndex = 1) and (el.Datum.DataIndex = 0) and not el.Silent
      and (el.Caption.FontSizeLogical <= 0) then
    begin
      b := TyShapeBounds(el.Shape);
      FChart.Move(Round((b.Left + b.Right) / 2), Round(b.Bottom - 3));
      Break;
    end;
  end;
  FChart.AnimTick(T0 + 400);
  Draw;
  mk := -1;
  for k := 0 to FChart.List.Count - 1 do
    if FChart.List.Element(k).Anim.Role = carMarkPoint then mk := k;
  AssertTrue('the markPoint', mk >= 0);
  AssertEquals('blurred in the list', 0.1, FChart.List.Element(mk).Style.Alpha, 1e-12);
  f := FChart.Frame;
  AssertTrue('still fading in', FChart.AnimClipCount > 0);
  AssertTrue(Format('the frame within the tenth: %g', [f.Element(mk).Style.Alpha]),
    (f.Element(mk).Style.Alpha > 0) and (f.Element(mk).Style.Alpha < 0.1));
  blurred := f.Element(mk).Style.Alpha;
  { the same fade on a chart nobody hovers: the blurred frame is a tenth of
    it -- the fade multiplies what the list holds, it does not replace it }
  NewChart(camAlways);
  Load(cOpt);
  FChart.AnimTick(T0 + 1);
  FChart.AnimTick(T0 + 300);
  Draw;
  FChart.AnimTick(T0 + 400);
  Draw;
  mk := -1;
  for k := 0 to FChart.List.Count - 1 do
    if FChart.List.Element(k).Anim.Role = carMarkPoint then mk := k;
  AssertTrue('the markPoint, unblurred', mk >= 0);
  AssertTrue('still fading in, unblurred', FChart.AnimClipCount > 0);
  plain := FChart.Frame.Element(mk).Style.Alpha;
  AssertTrue(Format('the unblurred frame shows: %g', [plain]), plain > 0);
  AssertEquals('a tenth of the unblurred fade', 0.1 * plain, blurred, 1e-9);
end;

{ THE LABEL OF A PICTORIAL BAR hangs off the silent bar rect: silent with
  it, nothing to hover (zrender's isHover answers SILENT up the host chain) }
procedure TAdvChartStatesMiscTest.TestAPictorialLabelTakesNoPointer;
var
  k, found: Integer;
  el: TTyChartElement;
  b: TTyRectF;
  d: TTyChartDatumRef;
begin
  NewChart(camOff);
  Load('{"animation":false,"xAxis":{"type":"category","data":["A","B","C"]},'
    + '"yAxis":{"type":"value","max":40},"series":[{"type":"pictorialBar","symbol":"rect",'
    + '"label":{"show":true,"position":"top","fontSize":20},"data":[5,20,30]}]}');
  found := 0;
  for k := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(k);
    if (el.Caption.FontSizeLogical <= 0) or (el.Datum.SeriesIndex <> 0) then Continue;
    Inc(found);
    AssertTrue('silent', el.Silent);
    b := TyShapeBounds(el.Shape);
    d := FChart.HitTestAt(Round((b.Left + b.Right) / 2), Round((b.Top + b.Bottom) / 2));
    AssertTrue('nothing under the words', d.SeriesIndex < 0);
  end;
  AssertEquals('three labels', 3, found);
end;

{ A FULL UPDATE MAKES THE GAUGE ANEW (GaugeView creates its pointers and
  arcs in the update too): no hover survives it }
procedure TAdvChartStatesMiscTest.TestAFullUpdateMakesTheGaugeAnew;
var
  ptr: TTyChartElement;
  p: TPoint;
  item: TTyStItem;
begin
  NewChart(camOff);
  Load(cGauge);
  FindRole(carGaugePointer, 0, 0, ptr);
  p := PolyCentre(ptr);
  FChart.Move(p.X, p.Y);
  Draw;
  AssertTrue(FChart.ItemStates(0, 0, item));
  AssertEquals('hovered', 'emphasis', TyStNamesText(item.Host.States));
  FChart.Update;
  Draw;
  AssertTrue(FChart.ItemStates(0, 0, item));
  AssertEquals('a new pointer', '', TyStNamesText(item.Host.States));
end;

initialization
  RegisterTest(TAdvChartStatesMiscOracleTest);
  RegisterTest(TAdvChartStatesMiscTest);
finalization
  FreeAndNil(GFix);
end.
