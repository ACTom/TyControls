unit test.advchart.statesmarks;
{$mode objfpc}{$H+}
{ THE MARKERS' OWN STATES, HELD TO UPSTREAM [R2-B].

  tools/advchart-oracle/states-marks.js drives the real ECharts 6.1 build with
  states-misc.js' harness over the markers of bar series: a markPoint's,
  a markLine's and a markArea's hover (each item a highDownDispatcher, its
  states read from the item and then the marker component), their own
  emphasis.focus / blurScope around the host series, the data items' own
  emphasis and blur, a held blur over a hovered marker, a click selecting
  the host's item. Every element per sample, a label with its computed
  transform too.

  The replay is states-misc's, with the marker comparison widened: a marker
  element's state list, its paint order against its rest, its opacity as a
  factor of its rest, its fill and stroke (the rest colour or its lift
  through the skin, a declared one as written), its line width, a symbol's
  scale against its rest, a label's place against its rest (to 1e-9: the
  port adds the scaled anchor to the rest place) and its declared ink. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Measure,
     tyControls.AdvChart.Color, tyControls.AdvChart.Style, tyControls.AdvChart.Scale,
     tyControls.AdvChart.JsMath,
     tyControls.AdvChart.Anim, tyControls.AdvChart.AnimView,
     tyControls.AdvChart.States, tyControls.AdvChart.Events, tyControls.AdvanceChart,
     tyControls.AdvChart.Handlers,
     tyControls.FontUnits,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TSkProbe = class(TTyAdvanceChart)
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
    { [R2-I1] the event target under a point }
    function TargetAt(AX, AY: Integer): TTyChartEventTarget;
  end;

  TSkLogger = class
  public
    Log: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Handle(Sender: TObject; const AEvent: TTyChartEvent);
    { [R2-I4] the oracle's '@mkWords' }
    function MkWords(const AParams: TTyChartParams): string;
  end;

  TAdvChartStatesMarksOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TSkProbe;
    FLogger: TSkLogger;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FKeysCompared, FTrackedCompared, FEventsCompared,
      FMarksCompared: Integer;
    { [R2-I1] labels hidden at rest, compared where a state shows them }
    FHiddenPlaces: Integer;
    { [R2-I3] text boxes and dashes compared }
    FBoxes, FDashes: Integer;
    { [R2-I4] a state's words compared }
    FWords: Integer;
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
    procedure BoxAt(const AWhere, APart: string; AEl: TJSONObject; ASample: Integer;
      const ABox: TTyRectF);
    procedure RunCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheStatesAsUpstream;
  end;

  { the pieces the replay does not reach on its own }
  TAdvChartStatesMarksTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TSkProbe;
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
    procedure TestAHoveredPinGrowsAboutItsOrigin;
    procedure TestTheKeyboardLiftsAMarkerAsThePointerDoes;
    procedure TestAHoveredMarkerTakesNoOverlay;
    { [R2-I1] }
    procedure TestAHoveredMarkerLabelIsLaidOutByItsEmphasisTextConfig;
    procedure TestATreeEdgeIsATargetOfNoData;
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
        + 'advchart-states-marks.json');
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

function TSkProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TSkProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TSkProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TSkProbe.ClickAt(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
  MouseDown(mbLeft, [ssLeft], AX, AY);
  MouseUp(mbLeft, [], AX, AY);
end;

function TSkProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TSkProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

function TSkProbe.Primary: TTyChartColor;
begin
  Result := StPrimaryInk;
end;

function TSkProbe.TargetAt(AX, AY: Integer): TTyChartEventTarget;
begin
  Result := EventTargetAt(AX, AY);
end;

procedure TSkProbe.Update;
begin
  FullUpdate;
end;

{ ==================== the log ==================== }

constructor TSkLogger.Create;
begin
  inherited Create;
  Log := TStringList.Create;
end;

destructor TSkLogger.Destroy;
begin
  Log.Free;
  inherited Destroy;
end;

procedure TSkLogger.Handle(Sender: TObject; const AEvent: TTyChartEvent);
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

function TSkLogger.MkWords(const AParams: TTyChartParams): string;
begin
  Result := AParams[0].ComponentType + ':' + AParams[0].Name + ':' + AParams[0].Status
    + ':' + IntToStr(AParams[0].DataIndex);
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

procedure TAdvChartStatesMarksOracleTest.SetUp;
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
  FLogger := TSkLogger.Create;
  TyChartRegisterFormatter('mkWords', @FLogger.MkWords);
  FSeen := TStringList.Create;
  FTally := TStringList.Create;
end;

procedure TAdvChartStatesMarksOracleTest.TearDown;
begin
  FreeAndNil(FSeen);
  FreeAndNil(FTally);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  TyChartUnregisterFormatter('mkWords');
  FreeAndNil(FLogger);
  inherited TearDown;
end;

procedure TAdvChartStatesMarksOracleTest.Miss(const AWhere: string; const AOnce: string);
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

procedure TAdvChartStatesMarksOracleTest.NewChart;
var i: Integer;
begin
  FreeAndNil(FChart);
  FChart := TSkProbe.Create(FForm);
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

procedure TAdvChartStatesMarksOracleTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartStatesMarksOracleTest.Settle(AStart: Double);
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

procedure TAdvChartStatesMarksOracleTest.CompareEvents(const AWhere: string;
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

procedure TAdvChartStatesMarksOracleTest.CompareSelection(const AWhere: string;
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

const
  cAlignNames: array[TTyTextAnchorH] of string = ('left', 'center', 'right');
  cVAlignNames: array[TTyTextAnchorV] of string = ('top', 'middle', 'bottom');

{ [R2-I3] normalizeLineDash's lengths as the fixture writes them }
function DashText(const A: TTyDoubleArray): string;
var j: Integer;
begin
  if Length(A) = 0 then Exit('null');
  Result := '[';
  for j := 0 to High(A) do
  begin
    if j > 0 then Result := Result + ',';
    Result := Result + TyJsNumberToString(A[j]);
  end;
  Result := Result + ']';
end;

procedure TAdvChartStatesMarksOracleTest.BoxAt(const AWhere, APart: string;
  AEl: TJSONObject; ASample: Integer; const ABox: TTyRectF);
var vx, vy, vw, vh: TJSONData;
begin
  if not (ValueAt(AEl, 'bx', ASample, vx) and ValueAt(AEl, 'by', ASample, vy)
    and ValueAt(AEl, 'bw', ASample, vw) and ValueAt(AEl, 'bh', ASample, vh)) then Exit;
  if (Abs(ABox.Left - NumOf(vx)) > 1e-6) or (Abs(ABox.Top - NumOf(vy)) > 1e-6)
    or (Abs((ABox.Right - ABox.Left) - NumOf(vw)) > 1e-6)
    or (Abs((ABox.Bottom - ABox.Top) - NumOf(vh)) > 1e-6) then
    Miss(Format('%s %s: box (%s, %s, %s, %s), upstream (%s, %s, %s, %s)', [AWhere, APart,
      FloatToStr(ABox.Left), FloatToStr(ABox.Top), FloatToStr(ABox.Right - ABox.Left),
      FloatToStr(ABox.Bottom - ABox.Top), FloatToStr(NumOf(vx)), FloatToStr(NumOf(vy)),
      FloatToStr(NumOf(vw)), FloatToStr(NumOf(vh))]), AWhere + APart + 'box');
end;

procedure TAdvChartStatesMarksOracleTest.CompareMarker(const AWhere: string;
  AEl: TJSONObject; ASample: Integer);
const
  cColourKeys: array[0..1] of string = ('style.fill', 'style.stroke');
var
  map: TJSONObject;
  st: TTyStElement;
  idx, rs, j: Integer;
  v, rv: TJSONData;
  want, rest, got, portRest: Double;
  el: TTyChartElement;
  part, key: string;
  isText: Boolean;
  cf, cr, cp, crp: TTyChartColor;
  hasP: Boolean;
begin
  map := AEl.Objects['map'];
  part := map.Strings['part'];
  if not FChart.MarkerStates(map.Integers['s'], part, st, idx) then
  begin
    { an element upstream keeps ignored throughout and the port need not
      build }
    if ValueAt(AEl, 'ignore', ASample, v) and v.AsBoolean then Exit;
    Miss(Format('%s %s: no marker element', [AWhere, part]), AEl.Strings['id'] + 'none');
    Exit;
  end;
  Inc(FMarksCompared);
  el := FChart.List.Element(idx);
  isText := Pos('#label', part) > 0;
  if ValueAt(AEl, 'states', ASample, v) and (v.AsString <> TyStNamesText(st.States)) then
    Miss(Format('%s %s: states "%s", upstream "%s"', [AWhere, part,
      TyStNamesText(st.States), v.AsString]), AWhere + part + 'st');
  rs := RestSample(AEl);
  { visible as upstream }
  if ValueAt(AEl, 'ignore', ASample, v) and (v.AsBoolean <> el.Ignore) then
    Miss(Format('%s %s: ignore %s, upstream %s', [AWhere, part, BoolToStr(el.Ignore, True),
      v.AsJSON]), AWhere + part + 'ign');
  { the paint order against the rest, and what the list draws }
  if (rs >= 0) and ValueAt(AEl, 'z2', ASample, v) and ValueAt(AEl, 'z2', rs, rv) then
  begin
    if st.Cur.Num[stkZ2] - st.Rest.Num[stkZ2] <> NumOf(v) - NumOf(rv) then
      Miss(Format('%s %s: z2 lifted by %s, upstream %s', [AWhere, part,
        FloatToStr(st.Cur.Num[stkZ2] - st.Rest.Num[stkZ2]), FloatToStr(NumOf(v) - NumOf(rv))]),
        AWhere + part + 'z2');
    if el.Z2 <> Round(st.Cur.Num[stkZ2]) then
      Miss(Format('%s %s: the list draws z2 %d, the state %s', [AWhere, part, el.Z2,
        FloatToStr(st.Cur.Num[stkZ2])]), AWhere + part + 'z2l');
  end;
  { the opacity as a factor over the rest: an end symbol's rest has none }
  if ValueAt(AEl, 'style.opacity', ASample, v) then want := NumOf(v) else want := 1;
  rest := 1;
  if (rs >= 0) and ValueAt(AEl, 'style.opacity', rs, rv) then rest := NumOf(rv);
  portRest := st.Rest.Num[stkOpacity];
  got := el.Style.Alpha;
  if rest > 0 then want := want / rest * portRest;
  if Abs(got - want) > 1e-12 then
    Miss(Format('%s %s: opacity %s, upstream %s', [AWhere, part,
      FloatToStr(got), FloatToStr(want)]), AWhere + part + 'op');
  if isText then
  begin
    { [R2-I1] A LABEL HIDDEN AT REST keeps the transform its last showing
      left it (an ignored text is not laid out): shown, its place is
      compared as it is, to 1e-9 }
    if (rs >= 0) and ValueAt(AEl, 'ignore', rs, rv) and rv.AsBoolean then
    begin
      if not el.Ignore and ValueAt(AEl, 'tx', ASample, v) and ValueAt(AEl, 'ty', ASample, rv) then
      begin
        Inc(FHiddenPlaces);
        if (Abs(el.Caption.X - NumOf(v)) > 1e-9) or (Abs(el.Caption.Y - NumOf(rv)) > 1e-9) then
          Miss(Format('%s %s: shown at (%s, %s), upstream (%s, %s)', [AWhere, part,
            FloatToStr(el.Caption.X), FloatToStr(el.Caption.Y), FloatToStr(NumOf(v)),
            FloatToStr(NumOf(rv))]), AWhere + part + 'hp');
      end;
    end
    { the place against the rest: the scaled anchor added to the rest place }
    else if (rs >= 0) and ValueAt(AEl, 'tx', ASample, v) and ValueAt(AEl, 'tx', rs, rv)
      and (Abs((el.Caption.X - st.Rest.Num[stkX]) - (NumOf(v) - NumOf(rv))) > 1e-9) then
      Miss(Format('%s %s: x moved %s, upstream %s', [AWhere, part,
        FloatToStr(el.Caption.X - st.Rest.Num[stkX]), FloatToStr(NumOf(v) - NumOf(rv))]),
        AWhere + part + 'tx');
    if (rs >= 0) and ValueAt(AEl, 'ignore', rs, rv) and rv.AsBoolean then
    else if (rs >= 0) and ValueAt(AEl, 'ty', ASample, v) and ValueAt(AEl, 'ty', rs, rv)
      and (Abs((el.Caption.Y - st.Rest.Num[stkY]) - (NumOf(v) - NumOf(rv))) > 1e-9) then
      Miss(Format('%s %s: y moved %s, upstream %s', [AWhere, part,
        FloatToStr(el.Caption.Y - st.Rest.Num[stkY]), FloatToStr(NumOf(v) - NumOf(rv))]),
        AWhere + part + 'ty');
    { a declared ink: as written }
    if ValueAt(AEl, 'style.fill', ASample, v) and (v.JSONType = jtString)
      and not ((rs >= 0) and ValueAt(AEl, 'style.fill', rs, rv) and (rv.JSONType = jtString)
        and (rv.AsString = v.AsString))
      and ColourOf(v.AsString, cf) and (el.Caption.Colour <> cf) then
      Miss(Format('%s %s: ink %s, upstream %s', [AWhere, part,
        IntToHex(el.Caption.Colour, 8), v.AsString]), AWhere + part + 'ink');
    { [R2-I4] A words case: the text the state shows (its formatter's) }
    if not el.Ignore and ValueAt(AEl, 'txt', ASample, v) then
    begin
      Inc(FWords);
      if el.Caption.Text <> v.AsString then
        Miss(Format('%s %s: text "%s", upstream "%s"', [AWhere, part, el.Caption.Text,
          v.AsString]), AWhere + part + 'txt');
    end;
    { [R2-I3] A textBox case: the merged style's size, the alignment the
      style says, and the box through the transform -- the text as the
      state lays it out }
    if not el.Ignore and ValueAt(AEl, 'fs', ASample, v) and ValueAt(AEl, 'bx', ASample, rv) then
    begin
      Inc(FBoxes);
      { the caption's size in css px (a skin's points or the author's px) }
      if Abs(TyFontPxOf(el.Caption.FontSizeLogical) - NumOf(v)) > 1e-9 then
        Miss(Format('%s %s: font size %s px, upstream %s', [AWhere, part,
          FloatToStr(TyFontPxOf(el.Caption.FontSizeLogical)), FloatToStr(NumOf(v))]),
          AWhere + part + 'fs');
      if ValueAt(AEl, 'al', ASample, v) and (v.AsString <> '')
        and (v.AsString <> cAlignNames[el.Caption.AnchorH]) then
        Miss(Format('%s %s: align %s, upstream %s', [AWhere, part,
          cAlignNames[el.Caption.AnchorH], v.AsString]), AWhere + part + 'al');
      if ValueAt(AEl, 'va', ASample, v) and (v.AsString <> '')
        and (v.AsString <> cVAlignNames[el.Caption.AnchorV]) then
        Miss(Format('%s %s: vertical align %s, upstream %s', [AWhere, part,
          cVAlignNames[el.Caption.AnchorV], v.AsString]), AWhere + part + 'va');
      BoxAt(AWhere, part, AEl, ASample, el.Shape.Bounds);
    end;
    Exit;
  end;
  { [R2-I3] a dash case: the dash as the list draws it, and its phase }
  if ValueAt(AEl, 'dash', ASample, v) then
  begin
    Inc(FDashes);
    if DashText(el.Style.DashLogical) <> v.AsString then
      Miss(Format('%s %s: dash %s, upstream %s', [AWhere, part,
        DashText(el.Style.DashLogical), v.AsString]), AWhere + part + 'dash');
    if ValueAt(AEl, 'dashOff', ASample, rv) and (rv.JSONType <> jtNull)
      and (Abs(el.Style.DashOffsetLogical - NumOf(rv)) > 1e-12) then
      Miss(Format('%s %s: dash phase %s, upstream %s', [AWhere, part,
        FloatToStr(el.Style.DashOffsetLogical), FloatToStr(NumOf(rv))]), AWhere + part + 'doff');
  end;
  { the colours: the rest's as the port's rest, its lift as the port's lift,
    a declared one as written }
  for j := 0 to High(cColourKeys) do
  begin
    key := cColourKeys[j];
    if not ValueAt(AEl, key, ASample, v) or (v.JSONType <> jtString) then Continue;
    if not ColourOf(v.AsString, cf) then Continue;
    { a stroke of no width draws nothing: its colour is not compared }
    if (key = 'style.stroke') and not (ValueAt(AEl, 'style.lineWidth', ASample, rv)
      and (NumOf(rv) > 0)) then Continue;
    if key = 'style.fill' then
    begin
      hasP := el.Style.HasFill;
      cp := el.Style.FillColor;
      crp := st.Rest.Color[stkFill];
    end
    else
    begin
      hasP := el.Style.StrokeColor <> 0;
      cp := el.Style.StrokeColor;
      crp := st.Rest.Color[stkStroke];
    end;
    if (rs >= 0) and ValueAt(AEl, key, rs, rv) and (rv.JSONType = jtString)
      and ColourOf(rv.AsString, cr) then
    begin
      if cf = cr then cf := crp
      else if cf = TyChartLiftColor(cr) then cf := TyChartLiftColor(crp);
    end;
    if not hasP or (cp <> cf) then
      Miss(Format('%s %s %s: %s, upstream %s', [AWhere, part, key, IntToHex(cp, 8),
        v.AsString]), AWhere + part + key);
  end;
  { the width where a stroke is drawn }
  if ValueAt(AEl, 'style.lineWidth', ASample, v) and Tracked(AEl, 'style.lineWidth')
    and ValueAt(AEl, 'style.stroke', ASample, rv) and (rv.JSONType = jtString)
    and ColourOf(rv.AsString, cr) and (el.Style.StrokeWidthLogical <> NumOf(v)) then
    Miss(Format('%s %s: line width %s, upstream %s', [AWhere, part,
      FloatToStr(el.Style.StrokeWidthLogical), FloatToStr(NumOf(v))]), AWhere + part + 'lw');
  { a symbol's scale against its rest }
  if (rs >= 0) and ValueAt(AEl, 'scaleX', ASample, v) and ValueAt(AEl, 'scaleX', rs, rv) then
  begin
    want := NumOf(v) / NumOf(rv);
    if st.Cur.Has[stkScale] then got := st.Cur.Num[stkScale] else got := 1;
    if Abs(got - want) > 1e-12 then
      Miss(Format('%s %s: scale %s, upstream %s', [AWhere, part, FloatToStr(got),
        FloatToStr(want)]), AWhere + part + 'sc');
  end;
end;

procedure TAdvChartStatesMarksOracleTest.CompareElement(const AWhere: string;
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

procedure TAdvChartStatesMarksOracleTest.RunCase(ACase: TJSONObject);
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
  end;
end;

procedure TAdvChartStatesMarksOracleTest.TestTheStatesAsUpstream;
var
  cases: TJSONArray;
  i: Integer;
begin
  cases := Fix.Arrays['cases'];
  AssertTrue('the fixture has its cases', cases.Count >= 14);
  for i := 0 to cases.Count - 1 do RunCase(cases.Objects[i]);
  if FBad > 0 then
    Fail(Format('%d mismatches over %d samples (%s):%s', [FBad, FCompared,
      FTally.CommaText, FReport]));
  AssertTrue(Format('keys compared: %d, tracked %d, events %d, marker samples %d, '
    + 'hidden labels shown %d, text boxes %d, dashes %d, words %d',
    [FKeysCompared, FTrackedCompared, FEventsCompared, FMarksCompared, FHiddenPlaces,
      FBoxes, FDashes, FWords]),
    (FEventsCompared > 30) and (FMarksCompared > 1000) and (FHiddenPlaces > 20)
    and (FBoxes > 100) and (FDashes > 50) and (FWords > 100));
end;

{ ==================== by hand ==================== }

procedure TAdvChartStatesMarksTest.SetUp;
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

procedure TAdvChartStatesMarksTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartStatesMarksTest.NewChart(AMode: TTyChartAnimationMode);
begin
  FreeAndNil(FChart);
  FChart := TSkProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := AMode;
  FChart.AnimNow := T0;
  FChart.SetBounds(0, 0, cW, cH);
end;

procedure TAdvChartStatesMarksTest.Load(const AOption: string);
begin
  FChart.Option := AOption;
  AssertEquals('the option parses', '', FChart.OptionError);
  Draw;
end;

procedure TAdvChartStatesMarksTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartStatesMarksTest.FindRole(ARole: TTyChartAnimRole; ASeries,
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

const
  cPin = '{"animation":false,"color":["#5470c6"],"xAxis":{"type":"category","data":["A","B","C"]},'
    + '"yAxis":{"type":"value","max":40},"series":[{"type":"bar","data":[5,30,12],'
    + '"markPoint":{"data":[{"type":"max","name":"max"}]}}]}';

{ A HOVERED PIN GROWS ABOUT ITS SYMBOL'S ORIGIN, not its box's middle: the
  path's own scale (emphasisState.scaleX = _sizeX * ratio) is about the
  path's place, and a pin's box hangs below it (its tip at the bottom) --
  every edge of the drawn box moves away from the origin by a tenth of its
  distance; and the inside label, 40 % down the box, rides it }
procedure TAdvChartStatesMarksTest.TestAHoveredPinGrowsAboutItsOrigin;
var
  pin, pin2, lab, lab2: TTyChartElement;
  b0, b1: TTyRectF;
  ox, oy: Double;
  i: Integer;
begin
  NewChart(camOff);
  Load(cPin);
  AssertTrue('the pin', FindRole(carMarkPoint, 0, 0, pin) >= 0);
  AssertTrue('its label', FindRole(carMarkPointLabel, 0, 0, lab) >= 0);
  b0 := TyShapeBounds(pin.Shape);
  ox := pin.Anim.G[0];
  oy := pin.Anim.G[1];
  AssertTrue('the pin hangs off its origin', Abs((b0.Top + b0.Bottom) / 2 - oy) > 1);
  FChart.Move(Round(ox), Round((b0.Top + oy) / 2));
  Draw;
  i := FindRole(carMarkPoint, 0, 0, pin2);
  AssertTrue(i >= 0);
  b1 := TyShapeBounds(pin2.Shape);
  AssertEquals('left', ox + (b0.Left - ox) * 1.1, b1.Left, 1e-9);
  AssertEquals('right', ox + (b0.Right - ox) * 1.1, b1.Right, 1e-9);
  AssertEquals('top', oy + (b0.Top - oy) * 1.1, b1.Top, 1e-9);
  AssertEquals('bottom', oy + (b0.Bottom - oy) * 1.1, b1.Bottom, 1e-9);
  AssertTrue('lifted', pin2.Style.FillColor = TyChartLiftColor(pin.Style.FillColor));
  FindRole(carMarkPointLabel, 0, 0, lab2);
  AssertEquals('the label stays across', lab.Caption.X, lab2.Caption.X, 1e-9);
  AssertEquals('the label rides the grown box (40 % down it, as at rest)',
    oy + (lab.Caption.Y - oy) * 1.1, lab2.Caption.Y, 1e-9);
  { and out again: as built }
  FChart.Move(3, 3);
  Draw;
  FindRole(carMarkPoint, 0, 0, pin2);
  b1 := TyShapeBounds(pin2.Shape);
  AssertEquals('back', b0.Top, b1.Top, 0);
  FindRole(carMarkPointLabel, 0, 0, lab2);
  AssertEquals('the label back', lab.Caption.Y, lab2.Caption.Y, 0);
end;

{ THE KEYBOARD'S MARKER STOP is the pointer over it: the marker enters
  emphasis on the shared model (the overlay drew nothing for a marker:
  its datum names no series) }
procedure TAdvChartStatesMarksTest.TestTheKeyboardLiftsAMarkerAsThePointerDoes;
var
  pin, pin2: TTyChartElement;
  st: TTyStElement;
  idx: Integer;
begin
  NewChart(camOff);
  Load(cPin);
  AssertTrue('the pin', FindRole(carMarkPoint, 0, 0, pin) >= 0);
  AssertTrue('the markers stop', FChart.KbTakeMarkerForTest(0));
  Draw;
  AssertTrue(FChart.MarkerStates(0, 'mp0', st, idx));
  AssertEquals('in emphasis', 'emphasis', TyStNamesText(st.States));
  FindRole(carMarkPoint, 0, 0, pin2);
  AssertTrue('lifted', pin2.Style.FillColor = TyChartLiftColor(pin.Style.FillColor));
  FChart.KbLeaveForTest;
  Draw;
  AssertTrue(FChart.MarkerStates(0, 'mp0', st, idx));
  AssertEquals('and out', '', TyStNamesText(st.States));
end;

{ IN MOTION, THE LIST IS WHAT IS DRAWN: a marker has no state proxy (its
  model does not animate), so the frame carries the list's state values --
  a hovered markLine is 3 wide in the frame of an animating chart too }
procedure TAdvChartStatesMarksTest.TestAHoveredMarkerTakesNoOverlay;
var
  k, n: Integer;
  el: TTyChartElement;
  st: TTyStElement;
  idx: Integer;
begin
  NewChart(camAlways);
  Load('{"color":["#5470c6"],"xAxis":{"type":"category","data":["A","B","C"]},'
    + '"yAxis":{"type":"value","max":40},"series":[{"type":"bar","data":[5,30,12],'
    + '"markLine":{"symbol":"none","data":[{"yAxis":20,"name":"y"}]}}]}');
  FChart.AnimTick(T0 + 5000);
  Draw;
  AssertTrue(FChart.MarkerStates(0, 'ml0', st, idx));
  el := FChart.List.Element(idx);
  FChart.Move(Round((el.Shape.Points[0].X + el.Shape.Points[High(el.Shape.Points)].X) / 2),
    Round(el.Shape.Points[0].Y));
  FChart.AnimTick(T0 + 5016);
  Draw;
  AssertTrue(FChart.MarkerStates(0, 'ml0', st, idx));
  AssertEquals('in emphasis', 'emphasis', TyStNamesText(st.States));
  n := 0;
  for k := 0 to FChart.Frame.Count - 1 do
  begin
    el := FChart.Frame.Element(k);
    if (el.Datum.Kind = ctkMarkLine) and (el.Caption.FontSizeLogical <= 0) then
    begin
      AssertEquals('3 wide as drawn', 3, el.Style.StrokeWidthLogical, 0);
      Inc(n);
    end;
  end;
  AssertTrue('the frame drew the line', n > 0);
end;

{ [R2-I1] UNDER THE EMPHASIS textConfig a hovered marker's label is laid
  out as a label at rest with that config would be: its anchor, its
  alignment, its turn and its box -- a circle markPoint whose label sits
  left at rest and right, turned 30 and 8 away under emphasis (emphasis.scale
  false: the path does not grow), against one at rest right, turned, 8 away;
  a markArea's top label against one at rest insideBottom }
procedure TAdvChartStatesMarksTest.TestAHoveredMarkerLabelIsLaidOutByItsEmphasisTextConfig;
const
  cHead = '{"animation":false,"color":["#5470c6"],"xAxis":{"type":"category","data":["A","B","C","D"]},'
    + '"yAxis":{"type":"value","max":40},"series":[{"type":"bar","data":[5,30,12,20],';
  cHover = cHead + '"markPoint":{"symbol":"circle","symbolSize":20,"label":{"position":"left"},'
    + '"emphasis":{"scale":false,"label":{"position":"right","rotate":30,"distance":8}},'
    + '"data":[{"type":"max","name":"max"}]},'
    + '"markArea":{"label":{"show":true},"emphasis":{"label":{"position":"insideBottom"}},'
    + '"data":[[{"xAxis":"C","name":"area"},{"xAxis":"D"}]]}}]}';
  cRest = cHead + '"markPoint":{"symbol":"circle","symbolSize":20,'
    + '"label":{"position":"right","rotate":30,"distance":8},'
    + '"data":[{"type":"max","name":"max"}]},'
    + '"markArea":{"label":{"show":true,"position":"insideBottom"},'
    + '"data":[[{"xAxis":"C","name":"area"},{"xAxis":"D"}]]}}]}';
var
  want, got: array[0..1] of TTyChartElement;
  st: TTyStElement;
  idx, k: Integer;
  pin: TTyChartElement;
  b0, b1: TTyRectF;
  parts: array[0..1] of string = ('mp0#label', 'ma0#label');
begin
  NewChart(camOff);
  Load(cRest);
  for k := 0 to 1 do
  begin
    AssertTrue(parts[k] + ' at rest', FChart.MarkerStates(0, parts[k], st, idx));
    want[k] := FChart.List.Element(idx);
  end;
  NewChart(camOff);
  Load(cHover);
  AssertTrue('the pin', FindRole(carMarkPoint, 0, 0, pin) >= 0);
  b0 := TyShapeBounds(pin.Shape);
  FChart.Move(Round((b0.Left + b0.Right) / 2), Round((b0.Top + b0.Bottom) / 2));
  Draw;
  AssertTrue(FChart.MarkerStates(0, parts[0], st, idx));
  AssertEquals('the label in emphasis', 'emphasis', TyStNamesText(st.States));
  got[0] := FChart.List.Element(idx);
  { the markArea: hovered in its middle, away from its label }
  AssertTrue(FChart.MarkerStates(0, 'ma0', st, idx));
  b1 := TyShapeBounds(FChart.List.Element(idx).Shape);
  FChart.Move(Round((b1.Left + b1.Right) / 2), Round(b1.Top + (b1.Bottom - b1.Top) * 0.3));
  Draw;
  AssertTrue(FChart.MarkerStates(0, parts[1], st, idx));
  AssertEquals('the area label in emphasis', 'emphasis', TyStNamesText(st.States));
  got[1] := FChart.List.Element(idx);
  for k := 0 to 1 do
  begin
    AssertEquals(parts[k] + ' x', want[k].Caption.X, got[k].Caption.X, 1e-9);
    AssertEquals(parts[k] + ' y', want[k].Caption.Y, got[k].Caption.Y, 1e-9);
    AssertEquals(parts[k] + ' alignment', Ord(want[k].Caption.AnchorH), Ord(got[k].Caption.AnchorH));
    AssertEquals(parts[k] + ' vertical alignment', Ord(want[k].Caption.AnchorV), Ord(got[k].Caption.AnchorV));
    AssertEquals(parts[k] + ' turn', want[k].Caption.RotationRad, got[k].Caption.RotationRad, 1e-12);
    b0 := TyShapeBounds(want[k].Shape);
    b1 := TyShapeBounds(got[k].Shape);
    AssertEquals(parts[k] + ' box left', b0.Left, b1.Left, 1e-9);
    AssertEquals(parts[k] + ' box top', b0.Top, b1.Top, 1e-9);
    AssertEquals(parts[k] + ' box right', b0.Right, b1.Right, 1e-9);
    AssertEquals(parts[k] + ' box bottom', b0.Bottom, b1.Bottom, 1e-9);
    AssertEquals(parts[k] + ' ink', IntToHex(want[k].Caption.Colour, 8), IntToHex(got[k].Caption.Colour, 8));
  end;
  AssertTrue('the turn is the config''s', Abs(got[0].Caption.RotationRad) > 0.5);
end;

{ [R2-I1] A TREE EDGE IS NO SILENT ELEMENT (TreeView.drawEdge): the pointer
  on it finds the edge -- its curve, within max(lineWidth, 5) / 2 of it, a
  quarter of the way along where the curve is off its chord -- and the
  chart reads no datum there (no ecData: no tooltip, no event, no
  dispatcher) and shows the prototype's pointer, not the cursor of the node
  the edge leads to }
procedure TAdvChartStatesMarksTest.TestATreeEdgeIsATargetOfNoData;
var
  k, e: Integer;
  el: TTyChartElement;
  t, mt, x, y: Double;
  c: TTyPathCmd;
  x0, y0: Double;
  tg: TTyChartEventTarget;
begin
  NewChart(camOff);
  Load('{"animation":false,"series":[{"type":"tree","expandAndCollapse":false,"top":60,"bottom":60,'
    + '"left":80,"right":120,"symbolSize":12,"label":{"show":false},'
    + '"data":[{"name":"root","children":[{"name":"x","cursor":"help"},{"name":"y","cursor":"help"}]}]}]}');
  e := -1;
  for k := 0 to FChart.List.Count - 1 do
    if FChart.List.Element(k).Anim.Role = carTreeEdge then
    begin
      e := k;
      Break;
    end;
  AssertTrue('an edge', e >= 0);
  el := FChart.List.Element(e);
  AssertFalse('not silent', el.Silent);
  AssertEquals('a curve', 2, Length(el.Shape.Cmds));
  { a quarter of the way along the cubic }
  x0 := el.Shape.Cmds[0].X;
  y0 := el.Shape.Cmds[0].Y;
  c := el.Shape.Cmds[1];
  t := 0.25;
  mt := 1 - t;
  x := mt * mt * mt * x0 + 3 * mt * mt * t * c.X1 + 3 * mt * t * t * c.X2 + t * t * t * c.X;
  y := mt * mt * mt * y0 + 3 * mt * mt * t * c.Y1 + 3 * mt * t * t * c.Y2 + t * t * t * c.Y;
  AssertEquals('the list finds the edge there', e,
    FChart.List.HitTestElement(Round(x), Round(y), 96, False));
  AssertFalse('the chart reads no datum there',
    TyChartDatumValid(FChart.HitTestAt(Round(x), Round(y))));
  tg := FChart.TargetAt(Round(x), Round(y));
  AssertTrue('a target', tg.Id <> 0);
  AssertFalse('of no data', tg.HasData);
  AssertEquals('and no dispatcher', 0, tg.HdKind);
  FChart.Move(Round(x), Round(y));
  AssertEquals('the prototype''s cursor', 'pointer', FChart.CursorName);
end;

initialization
  RegisterTest(TAdvChartStatesMarksOracleTest);
  RegisterTest(TAdvChartStatesMarksTest);
finalization
  FreeAndNil(GFix);

end.
