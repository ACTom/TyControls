unit test.advchart.animfullupdate;
{$mode objfpc}{$H+}
{ FULL-UPDATE TRANSITIONS ON THE REAL CONTROL, held to upstream.
  [Batch 96, AN5]

  tools/advchart-oracle/full-update-anim.js drives the real ECharts 6.1
  build under the hand-driven clock: an option set at T0 and settled, then
  at T1 + t the events of each sample -- a legend action, a dataZoom by
  dispatchAction, the inside wheel or the slider's handle and panel, a graph
  pan, a pointer hover, a notMerge setOption -- and one frame. Recorded per
  sample: every element of every series view (a view the legend removed
  too), and every leaf of every cartesian axis group by its anid.

  The replay drives the control the same way -- DispatchAction,
  DispatchDataZoom, MouseMove / MouseDown / MouseUp / the wheel, Option --
  in camAlways with the injected clocks (AnimNow, DataZoomNow), AnimTick
  and a render per sample, and compares:
    - every series element upstream animates against the proxy that stands
      for it (a leaving one against its ghost, found by its old row):
      present where upstream's is, every tracked key BIT FOR BIT, the
      animator count, the other keys still;
    - every axis leaf against the axis proxy of its anid (AnimAxisProxy),
      once the control has made them (a full update does): present exactly
      where upstream's is, x / y / rotation of a label and the four ends of
      a line bit for bit at every sample, the animator count;
    - the state list and state animators of a hovered element through the
      re-render;
    - the clips, all of them. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Measure,
     tyControls.AdvChart.Scale,
     tyControls.AdvChart.Anim, tyControls.AdvChart.AnimOpt,
     tyControls.AdvChart.AnimView, tyControls.AdvChart.AnimAxis,
     tyControls.AdvanceChart, tyControls.AdvChart.Events,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TFuProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Wheel(AX, AY: Integer; ADelta: Double);
    procedure Move(AX, AY: Integer);
    procedure Down(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
    function List: TTyPaintList;
    function Frame: TTyPaintList;
  end;

  TFuKind = (fukStatic, fukModel, fukAxis, fukUnknown);
  TFuMap = record
    Kind: TFuKind;
    Series, Index: Integer;
    Role: string;
    Ghost: Boolean;
    AxisKey, Anid: string;
  end;

  TAdvChartAnimFullUpdateTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TFuProbe;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FAxisCompared, FStateCompared: Integer;
    FReport: string;
    FSeen, FTally, FEvents: TStringList;
    procedure OnEv(Sender: TObject; const AEvent: TTyChartEvent);
    procedure Miss(const AWhere: string; const AOnce: string = '');
    procedure NewChart(AMode: TTyChartAnimationMode);
    function Draw: TBGRABitmap;
    procedure Load(const AOption: string);
    procedure Settle(AStart: Double);
    procedure RunCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestFullUpdatesAsUpstream;
    procedure TestTheAxesMoveInTheDynamicLayer;
    procedure TestAPayloadOverridesEveryTiming;
    procedure TestSubPixelOptimizeRoundsAsJavaScript;
    procedure TestHeadlessWaitsForTheWindow;
    procedure TestOffSnapsAndANewOptionDropsTheAxes;
    procedure TestAHoverHeldThroughANewOptionSendsNoOver;
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
        + 'advchart-full-update-anim.json');
      GFix := GetJSON(sl.Text);
    finally
      sl.Free;
    end;
  end;
  Result := TJSONObject(GFix);
end;

function T0: Double;
begin
  Result := Fix.Objects['clock'].Floats['T0'];
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

function SameBits(A, B: Double): Boolean;
begin
  Result := Hex(A) = Hex(B);
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
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

function NumsOf(AData: TJSONData; out ANums: TTyDoubleArray): Boolean;
var i: Integer;
begin
  ANums := nil;
  Result := False;
  if AData = nil then Exit;
  if IsHex16(AData) then
  begin
    SetLength(ANums, 1);
    ANums[0] := FromHex(AData.AsString);
    Exit(True);
  end;
  if AData.JSONType <> jtArray then Exit;
  SetLength(ANums, AData.Count);
  for i := 0 to AData.Count - 1 do
  begin
    if not IsHex16(AData.Items[i]) then Exit(False);
    ANums[i] := FromHex(AData.Items[i].AsString);
  end;
  Result := True;
end;

function ValNums(const V: TTyAnimValue; out ANums: TTyDoubleArray): Boolean;
begin
  ANums := nil;
  case V.Kind of
    avkNumber, avkBool:
      begin
        SetLength(ANums, 1);
        ANums[0] := V.Num;
        Result := True;
      end;
    avkArray:
      begin
        ANums := Copy(V.Arr, 0, Length(V.Arr));
        Result := True;
      end;
  else
    Result := False;
  end;
end;

{ the state animators of a proxy, as the oracle writes them }
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

function TFuProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TFuProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TFuProbe.Wheel(AX, AY: Integer; ADelta: Double);
begin
  { a zrDelta of d is a wheel delta of 120 d }
  DoMouseWheel([], Round(ADelta * 120), Point(AX, AY));
end;

procedure TFuProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TFuProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
end;

procedure TFuProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

function TFuProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TFuProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

{ ==================== mapping upstream's elements ==================== }

function ScopeAt(AEl: TJSONObject; ASample: Integer): string;
var d: TJSONData;
begin
  Result := '';
  d := AEl.Find('scopes');
  if (d is TJSONArray) and (ASample < d.Count) then Result := d.Items[ASample].AsString;
end;

function HasLeave(AEl: TJSONObject): Boolean;
var
  d: TJSONData;
  i: Integer;
begin
  Result := False;
  d := AEl.Find('scopes');
  if not (d is TJSONArray) then Exit;
  for i := 0 to d.Count - 1 do
    if Pos('leave:', d.Items[i].AsString) > 0 then Exit(True);
end;

function DataIndexOf(AEls: TJSONArray; const AId: string): Integer;
var
  i: Integer;
  e: TJSONObject;
  d: TJSONData;
begin
  for i := 0 to AEls.Count - 1 do
  begin
    e := AEls.Objects[i];
    if e.Strings['id'] <> AId then Continue;
    d := e.Find('dataIndex');
    if (d <> nil) and (d.JSONType = jtNumber) then Exit(d.AsInteger);
    Exit(-1);
  end;
  Result := -1;
end;

function MapElement(AEls: TJSONArray; AEl: TJSONObject): TFuMap;
var
  id, owner, typ, stype, base, host: string;
  p, k, di: Integer;
  hasTrack, hasAnim: Boolean;
  d, a: TJSONData;
begin
  Result := Default(TFuMap);
  Result.Kind := fukStatic;
  id := AEl.Strings['id'];
  owner := AEl.Strings['owner'];
  typ := AEl.Strings['type'];
  { an axis leaf, by its anid: every one of them }
  if AEl.Strings['role'] = 'axis' then
  begin
    Result.Kind := fukAxis;
    Result.AxisKey := owner;
    Result.Anid := Copy(id, Pos('/', id) + 1, MaxInt);
    Exit;
  end;
  d := AEl.Find('track');
  hasTrack := (d <> nil) and (d.JSONType = jtObject) and (d.Count > 0);
  hasAnim := False;
  a := AEl.Find('animators');
  if (a <> nil) and (a.JSONType = jtArray) then
    for k := 0 to a.Count - 1 do
      if a.Items[k].AsInteger > 0 then hasAnim := True;
  if not (hasTrack or hasAnim) then Exit;
  di := -1;
  d := AEl.Find('dataIndex');
  if (d <> nil) and (d.JSONType = jtNumber) then di := d.AsInteger;
  Result.Kind := fukUnknown;
  p := Pos(':', owner);
  if p = 0 then Exit;
  Result.Series := StrToIntDef(Copy(owner, 7, p - 7), -1);
  stype := Copy(owner, p + 1, MaxInt);
  base := Copy(id, Pos('/', id) + 1, MaxInt);
  if Pos('#', base) > 0 then base := Copy(base, 1, Pos('#', base) - 1);
  host := Copy(id, 1, Pos('/', id)) + base;
  Result.Ghost := HasLeave(AEl);
  if (Pos('#label', id) > 0) or (Pos('#guide', id) > 0) then
  begin
    Result.Kind := fukModel;
    if Pos('#label', id) > 0 then Result.Role := 'label' else Result.Role := 'guide';
    Result.Index := DataIndexOf(AEls, host);
    Exit;
  end;
  if stype = 'bar' then
  begin
    if typ = 'rect' then
    begin
      Result.Kind := fukModel;
      Result.Role := 'bar';
      Result.Index := di;
    end;
  end
  else if stype = 'pie' then
  begin
    Result.Kind := fukModel;
    Result.Role := 'sector';
    Result.Index := di;
  end
  else if stype = 'line' then
  begin
    if Pos('#clip', id) > 0 then
    begin
      Result.Kind := fukModel;
      Result.Role := 'lineClip';
      Result.Index := -1;
    end
    else if typ = 'ec-polyline' then
    begin
      Result.Kind := fukModel;
      Result.Role := 'linePoly';
      Result.Index := -1;
    end
    else if typ = 'ec-polygon' then
    begin
      Result.Kind := fukModel;
      Result.Role := 'lineArea';
      Result.Index := -1;
    end
    else if (typ = 'group') and (di >= 0) then
    begin
      Result.Kind := fukModel;
      Result.Role := 'lineSymbol';
      Result.Index := di;
    end
    else if (typ = 'path') and (di >= 0) and Result.Ghost then
    begin
      Result.Kind := fukModel;
      Result.Role := 'lineSymbol';
      Result.Index := di;
    end
    else if (typ = 'path') and (di >= 0) then
      { a symbol's path: its states (a hover held), no animation of its own
        but the state transition's }
      Result.Kind := fukStatic;
  end
  else if stype = 'scatter' then
  begin
    if di >= 0 then
    begin
      Result.Kind := fukModel;
      Result.Role := 'symbol';
      Result.Index := di;
    end;
  end
  else if stype = 'graph' then
    Result.Kind := fukStatic;
end;

function PresentAt(AEl: TJSONObject; ASample: Integer): Boolean;
var
  d: TJSONData;
  i: Integer;
begin
  d := AEl.Find('present');
  if (d = nil) or (d.JSONType <> jtArray) then Exit(True);
  for i := 0 to d.Count - 1 do
    if d.Items[i].AsInteger = ASample then Exit(True);
  Result := False;
end;

{ the element's data index at sample ASample -- a legend's filter or a
  dataZoom's window moves the rows -- a label's and a label line's their
  host's }
function IndexAt(AEls: TJSONArray; AEl: TJSONObject; ASample: Integer): Integer;
var
  d: TJSONData;
  id: string;
begin
  d := AEl.Find('dataIndices');
  if (d is TJSONArray) and (d.Items[ASample].JSONType = jtNumber) then
    Exit(d.Items[ASample].AsInteger);
  d := AEl.Find('dataIndex');
  if (d <> nil) and (d.JSONType = jtNumber) then Exit(d.AsInteger);
  id := AEl.Strings['id'];
  if Pos('#', id) > 0 then Exit(DataIndexOf(AEls, Copy(id, 1, Pos('#', id) - 1)));
  Result := -1;
end;

{ in its leave at sample ASample: present, and leaving since a sample it has
  been present at ever after (an element upstream reuses -- a line's symbol
  switched back on -- is a ghost no more) }
function LeavingAt(AEl: TJSONObject; ASample: Integer): Boolean;
var
  s: Integer;
  d: TJSONData;
begin
  Result := False;
  d := AEl.Find('scopes');
  if not (d is TJSONArray) then Exit;
  for s := ASample downto 0 do
  begin
    if not PresentAt(AEl, s) then Exit(False);
    if Pos('leave:', d.Items[s].AsString) > 0 then Exit(True);
  end;
end;

{ the first child of element AId leaving at ASample }
function ChildLeaving(AEls: TJSONArray; const AId: string; ASample: Integer): Boolean;
var i: Integer;
begin
  for i := 0 to AEls.Count - 1 do
    if AEls.Objects[i].Strings['id'] = AId + '.0' then
      Exit(LeavingAt(AEls.Objects[i], ASample));
  Result := False;
end;

{ how many of the element's animators at ASample are state transitions }
function StateAnimCount(AEl: TJSONObject; ASample: Integer): Integer;
var
  sa: TJSONData;
  i: Integer;
  s: string;
begin
  Result := 0;
  sa := AEl.Find('stateAnimators');
  if not (sa is TJSONArray) then Exit;
  s := sa.Items[ASample].AsString;
  if s = '' then Exit;
  Result := 1;
  for i := 1 to Length(s) do
    if s[i] = ' ' then Inc(Result);
end;

{ AS IT WAS AT THE START at ASample: no animator, every tracked key at its
  first sample's value -- an element the first render left standing, which
  the control draws from its list with no proxy yet (a line's polyline
  before its first update, a symbol's place) }
function AsAtStart(AEl: TJSONObject; ASample: Integer): Boolean;
var
  d, sa: TJSONData;
  tr: TJSONObject;
  i, n: Integer;
begin
  Result := False;
  { its state transitions run on the states' own proxy }
  n := 0;
  sa := AEl.Find('stateAnimators');
  if (sa is TJSONArray) and (sa.Items[ASample].AsString <> '') then
  begin
    n := 1;
    for i := 1 to Length(sa.Items[ASample].AsString) do
      if sa.Items[ASample].AsString[i] = ' ' then Inc(n);
  end;
  d := AEl.Find('animators');
  if (d is TJSONArray) and (d.Items[ASample].AsInteger > n) then Exit;
  d := AEl.Find('track');
  if d is TJSONObject then
  begin
    tr := TJSONObject(d);
    for i := 0 to tr.Count - 1 do
    begin
      { the state keys move with the states }
      if (tr.Names[i] = 'states') or (tr.Names[i] = 'z2') or (Pos('style.', tr.Names[i]) = 1) then
        Continue;
      if tr.Items[i].Items[ASample].AsJSON <> tr.Items[i].Items[0].AsJSON then Exit;
    end;
  end;
  Result := True;
end;

{ which proxy holds a key upstream tracks on an element of role ARole }
procedure KeyTarget(const ARole, AKey: string; out ARoleOut, AKeyOut: string);
begin
  ARoleOut := ARole;
  AKeyOut := AKey;
  if (ARole = 'linePoly') and (AKey = 'shape.__points') then AKeyOut := 'shape.points'
  else if (ARole = 'lineArea') and (AKey = 'shape.points') then ARoleOut := 'linePoly';
end;

{ the value of a key at sample ASample: the track's, else the final one }
function ValueAt(AEl: TJSONObject; const AKey: string; ASample: Integer): TJSONData;
var tr: TJSONData;
begin
  Result := nil;
  tr := AEl.Find('track');
  if (tr is TJSONObject) and (TJSONObject(tr).Find(AKey) <> nil) then
    Result := TJSONObject(tr).Arrays[AKey].Items[ASample]
  else if TJSONObject(AEl.Find('final')).Find(AKey) <> nil then
    Result := TJSONObject(AEl.Find('final')).Find(AKey);
  if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
end;

{ ==================== plumbing ==================== }

procedure TAdvChartAnimFullUpdateTest.SetUp;
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
  FEvents := TStringList.Create;
  FBad := 0;
  FCompared := 0;
  FAxisCompared := 0;
  FStateCompared := 0;
  FReport := '';
end;

procedure TAdvChartAnimFullUpdateTest.TearDown;
begin
  FreeAndNil(FSeen);
  FreeAndNil(FTally);
  FreeAndNil(FEvents);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartAnimFullUpdateTest.OnEv(Sender: TObject; const AEvent: TTyChartEvent);
begin
  FEvents.Add(AEvent.EventType);
end;

procedure TAdvChartAnimFullUpdateTest.Miss(const AWhere: string; const AOnce: string);
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
  { a few of each case }
  if n <= 12 then
    FReport := FReport + LineEnding + '  ' + AWhere;
end;

procedure TAdvChartAnimFullUpdateTest.NewChart(AMode: TTyChartAnimationMode);
begin
  FreeAndNil(FChart);
  FChart := TFuProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := AMode;
  FChart.AnimNow := T0;
  FChart.DataZoomNow := T0;
  FChart.SetBounds(0, 0, cW, cH);
end;

function TAdvChartAnimFullUpdateTest.Draw: TBGRABitmap;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  Result := FBmp;
end;

procedure TAdvChartAnimFullUpdateTest.Load(const AOption: string);
begin
  FChart.Option := AOption;
  AssertEquals('the option parses', '', FChart.OptionError);
  Draw;
end;

{ the oracle's settle: frames every 250 ms to 5 s }
procedure TAdvChartAnimFullUpdateTest.Settle(AStart: Double);
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
  AssertEquals('settled', 0, FChart.AnimClipCount);
end;

{ ==================== the timelines ==================== }

type
  TFuEntry = record
    Map: TFuMap;
    Els: array of Integer;
  end;

procedure TAdvChartAnimFullUpdateTest.RunCase(ACase: TJSONObject);
var
  name, s, key, tRole, tKey, eid, want, got: string;
  samples, events, els, clips: TJSONArray;
  si, ei, k, j, n, ti, sumAnim, live, ghosts: Integer;
  t: Double;
  e, el, track: TJSONObject;
  maps: array of TFuMap;
  entries: array of TFuEntry;
  m: TFuMap;
  p, tp: TTyChartAnimProxy;
  present, upPresent, flushed: Boolean;
  up, gotN: TTyDoubleArray;
  fv, tr: TJSONData;
  tracked: TStringList;

  function ProxyOf(const AM: TFuMap; const ARole: string): TTyChartAnimProxy;
  begin
    if AM.Ghost then Result := FChart.AnimFindGhost(AM.Series, AM.Index, ARole)
    else Result := FChart.AnimFindProxy(AM.Series, AM.Index, ARole);
  end;

begin
  name := ACase.Strings['id'];
  samples := Fix.Arrays['samplesMs'];
  events := ACase.Arrays['events'];
  els := ACase.Arrays['elements'];
  clips := ACase.Arrays['clips'];
  NewChart(camAlways);
  Load(ACase.Objects['option'].AsJSON);
  Settle(T0);
  { one entry per element: its row is the sample's }
  SetLength(maps, els.Count);
  entries := nil;
  for k := 0 to els.Count - 1 do
  begin
    maps[k] := MapElement(els, els.Objects[k]);
    if maps[k].Kind = fukUnknown then
      Miss(Format('%s: %s is not mapped', [name, els.Objects[k].Strings['id']]));
    if maps[k].Kind <> fukModel then Continue;
    n := Length(entries);
    SetLength(entries, n + 1);
    entries[n].Map := maps[k];
    SetLength(entries[n].Els, 1);
    entries[n].Els[0] := k;
  end;
  tracked := TStringList.Create;
  try
    for si := 0 to samples.Count - 1 do
    begin
      t := samples.Floats[si];
      FChart.AnimNow := T1 + t;
      FChart.DataZoomNow := T1 + t;
      flushed := False;
      for ei := 0 to events.Count - 1 do
      begin
        e := events.Objects[ei];
        if e.Floats['at'] <> t then Continue;
        s := e.Strings['type'];
        if (s = 'over') or (s = 'out') or (s = 'move') then
          FChart.Move(e.Integers['x'], e.Integers['y'])
        else if s = 'down' then
          FChart.Down(e.Integers['x'], e.Integers['y'])
        else if s = 'up' then
          { the control's mouseup is zrender's mouseup and then its click }
          FChart.Up(e.Integers['x'], e.Integers['y'])
        else if s = 'click' then
        else if s = 'wheel' then
          FChart.Wheel(e.Integers['x'], e.Integers['y'], e.Floats['delta'])
        else if s = 'action' then
        begin
          tr := e.Objects['payload'];
          if TJSONObject(tr).Strings['type'] = 'dataZoom' then
            FChart.DispatchDataZoom(TJSONObject(tr).Integers['dataZoomIndex'],
              TJSONObject(tr).Floats['start'], TJSONObject(tr).Floats['end'])
          else
            FChart.DispatchAction(tr.AsJSON);
        end
        else if s = 'setOption' then
        begin
          FChart.Option := e.Objects['option'].AsJSON;
          flushed := True;
        end
        else
          Fail('unknown event ' + s);
      end;
      if not flushed then FChart.AnimTick(T1 + t);
      Draw;
      { THE CLIPS }
      if FChart.AnimClipCount <> clips.Integers[si] then
        Miss(Format('%s t=%s: %d clips here, %d upstream', [name, FloatToStr(t),
          FChart.AnimClipCount, clips.Integers[si]]), name + 'clips');
      { ---- the series ---- }
      ghosts := 0;
      for j := 0 to High(entries) do
      begin
        m := entries[j].Map;
        el := els.Objects[entries[j].Els[0]];
        m.Index := IndexAt(els, el, si);
        { a leaving element is a ghost only while it leaves; before, it is
          the element it was }
        upPresent := PresentAt(el, si);
        if m.Ghost then
        begin
          if not LeavingAt(el, si) then
          begin
            { a line symbol's path is no proxy of its own but in its leave }
            if el.Strings['type'] = 'path' then Continue;
            m.Ghost := False;
            { a ghost that has finished: nothing of it any more }
            if not upPresent then Continue;
          end;
        end;
        { a line symbol's group whose path is leaving: the ghost of the
          path stands for both }
        if (el.Strings['type'] = 'group') and ChildLeaving(els, el.Strings['id'], si) then
          Continue;
        sumAnim := 0;
        if el.Find('animators') is TJSONArray then
          sumAnim := el.Arrays['animators'].Items[si].AsInteger;
        { a line's polyline and a symbol's path run their states on the
          states' own proxy }
        if (m.Role = 'linePoly') or (m.Role = 'lineArea') or (m.Role = 'lineSymbol') then
          Dec(sumAnim, StateAnimCount(el, si));
        p := ProxyOf(m, m.Role);
        present := p <> nil;
        eid := el.Strings['id'];
        { a container whose content leaves: its ghost stands for it }
        if (not m.Ghost) and upPresent and (p = nil)
          and (FChart.AnimFindGhost(m.Series, m.Index, m.Role) <> nil) then Continue;
        if m.Ghost then
        begin
          if present <> upPresent then
            Miss(Format('%s t=%s %s: a ghost here %s, upstream %s', [name, FloatToStr(t),
              eid, BoolToStr(present, True), BoolToStr(upPresent, True)]), name + eid + 'ghost');
          if present then Inc(ghosts);
        end
        else if upPresent and not present then
        begin
          if AsAtStart(el, si) then Continue;
          Miss(Format('%s t=%s: no proxy for %s (%d,%d,%s)', [name, FloatToStr(t), eid,
            m.Series, m.Index, m.Role]), name + eid + 'none');
          Continue;
        end;
        if (p = nil) or not upPresent then Continue;
        Inc(FCompared);
        if p.AnimatorCount <> sumAnim then
          Miss(Format('%s t=%s %s: %d animators here, %d upstream (%s)', [name,
            FloatToStr(t), eid, p.AnimatorCount, sumAnim,
            ScopeAt(els.Objects[entries[j].Els[0]], si)]), name + eid + 'anim');
        tracked.Clear;
        for k := 0 to High(entries[j].Els) do
        begin
          el := els.Objects[entries[j].Els[k]];
          if not (el.Find('track') is TJSONObject) then Continue;
          track := el.Objects['track'];
          for ti := 0 to track.Count - 1 do
          begin
            key := track.Names[ti];
            if (key = 'states') or (key = 'z2') or (key = 'style.fill')
              or (key = 'style.stroke') or (key = 'style.lineWidth') then Continue;
            KeyTarget(m.Role, key, tRole, tKey);
            if tRole = m.Role then
            begin
              tp := p;
              tracked.Add(tKey);
            end
            else
              tp := ProxyOf(m, tRole);
            if tp = nil then
            begin
              Miss(Format('%s: no %s proxy for %s', [name, tRole, eid]), name + eid + tRole);
              Continue;
            end;
            if not NumsOf(track.Arrays[key].Items[si], up) then Continue;
            if not ValNums(tp.GetAnimProp(tKey), gotN) then
            begin
              if AsAtStart(el, si) then Continue;
              Miss(Format('%s: %s %s is not modelled', [name, eid, key]), name + eid + key + 'mod');
              Continue;
            end;
            if Length(up) <> Length(gotN) then
            begin
              Miss(Format('%s t=%s %s: %s has %d numbers here, %d upstream', [name,
                FloatToStr(t), eid, key, Length(gotN), Length(up)]), name + eid + key + 'len');
              Continue;
            end;
            for n := 0 to High(gotN) do
              if not SameBits(gotN[n], up[n]) then
              begin
                Miss(Format('%s t=%s %s: %s[%d] %s here, %s upstream', [name,
                  FloatToStr(t), eid, key, n, Fmt(gotN[n]), Fmt(up[n])]), name + eid + key);
                Break;
              end;
          end;
        end;
      end;
      live := FChart.AnimGhostCount;
      if live <> ghosts then
        Miss(Format('%s t=%s: %d ghosts here, %d upstream', [name, FloatToStr(t), live,
          ghosts]), name + 'ghosts');
      { ---- the states of a hovered element through the re-render ---- }
      for k := 0 to els.Count - 1 do
      begin
        el := els.Objects[k];
        if el.Strings['role'] <> 'el' then Continue;
        if el.Find('dataIndex').JSONType <> jtNumber then Continue;
        if (el.Strings['type'] <> 'rect') and (el.Strings['type'] <> 'path')
          and (el.Strings['type'] <> 'sector') then Continue;
        if (el.Strings['type'] = 'path') and (Pos('line', el.Strings['owner']) = 0) then Continue;
        if not PresentAt(el, si) then Continue;
        if HasLeave(el) then Continue;
        fv := ValueAt(el, 'states', si);
        tr := el.Find('stateAnimators');
        if (fv = nil) or ((fv.AsString = '') and (tr.JSONType = jtNull)
          and not (el.Find('track') is TJSONObject)) then Continue;
        n := StrToIntDef(Copy(el.Strings['owner'], 7, Pos(':', el.Strings['owner']) - 7), -1);
        p := FChart.AnimStateProxy(n, IndexAt(els, el, si), 'host');
        if p = nil then
        begin
          if fv.AsString <> '' then
            Miss(Format('%s t=%s %s: no state proxy, upstream "%s"', [name, FloatToStr(t),
              el.Strings['id'], fv.AsString]), name + el.Strings['id'] + 'stpx');
          Continue;
        end;
        Inc(FStateCompared);
        if p.CurrentStates <> fv.AsString then
          Miss(Format('%s t=%s %s: states "%s", upstream "%s"', [name, FloatToStr(t),
            el.Strings['id'], p.CurrentStates, fv.AsString]), name + el.Strings['id'] + 'st'
            + FloatToStr(t));
        if tr.JSONType = jtNull then want := '' else want := TJSONArray(tr).Strings[si];
        got := StateAnimsOf(p);
        if want <> got then
          Miss(Format('%s t=%s %s: state animators "%s", upstream "%s"', [name, FloatToStr(t),
            el.Strings['id'], got, want]), name + el.Strings['id'] + 'sa' + FloatToStr(t));
      end;
      { ---- the axes, once the control made their proxies ---- }
      if FChart.AnimAxisProxyCount > 0 then
        for k := 0 to els.Count - 1 do
        begin
          if maps[k].Kind <> fukAxis then Continue;
          el := els.Objects[k];
          eid := el.Strings['id'];
          p := FChart.AnimAxisProxy(maps[k].AxisKey, maps[k].Anid);
          upPresent := PresentAt(el, si);
          { a leaf the port does not model }
          if (Pos('minor', maps[k].Anid) = 1) or (Pos('area_', maps[k].Anid) = 1)
            or (maps[k].Anid = 'name') then Continue;
          if (p <> nil) <> upPresent then
          begin
            Miss(Format('%s t=%s %s: a leaf here %s, upstream %s', [name, FloatToStr(t), eid,
              BoolToStr(p <> nil, True), BoolToStr(upPresent, True)]), name + eid + 'leaf');
            Continue;
          end;
          if p = nil then Continue;
          Inc(FAxisCompared);
          sumAnim := 0;
          if el.Find('animators') is TJSONArray then
            sumAnim := el.Arrays['animators'].Items[si].AsInteger;
          if p.AnimatorCount <> sumAnim then
            Miss(Format('%s t=%s %s: %d animators here, %d upstream', [name, FloatToStr(t),
              eid, p.AnimatorCount, sumAnim]), name + eid + 'aanim');
          for ti := 0 to 6 do
          begin
            case ti of
              0: key := 'x';
              1: key := 'y';
              2: key := 'rotation';
              3: key := 'shape.x1';
              4: key := 'shape.y1';
              5: key := 'shape.x2';
            else
              key := 'shape.y2';
            end;
            if (ti < 3) <> (el.Strings['type'] = 'text') then Continue;
            fv := ValueAt(el, key, si);
            if not IsHex16(fv) then Continue;
            if p.GetAnimProp(key).Kind <> avkNumber then
            begin
              Miss(Format('%s %s: %s is not modelled', [name, eid, key]), name + eid + key + 'mod');
              Continue;
            end;
            if not SameBits(p.Num(key), FromHex(fv.AsString)) then
              Miss(Format('%s t=%s %s: %s %s here, %s upstream', [name, FloatToStr(t), eid,
                key, Fmt(p.Num(key)), Fmt(FromHex(fv.AsString))]), name + eid + key);
          end;
        end;
    end;
  finally
    tracked.Free;
  end;
  { AT REST }
  if FChart.AnimClipCount = 0 then
  begin
    if FChart.AnimLive then Miss(name + ': still live with no clip');
    if FChart.AnimGhostCount <> 0 then Miss(name + ': a ghost outlives its fade');
  end;
end;

procedure TAdvChartAnimFullUpdateTest.TestFullUpdatesAsUpstream;
var
  cases: TJSONArray;
  i: Integer;
begin
  cases := Fix.Arrays['cases'];
  AssertTrue('the fixture has its cases', cases.Count >= 13);
  for i := 0 to cases.Count - 1 do RunCase(cases.Objects[i]);
  if FBad > 0 then
    Fail(Format('%d mismatches over %d proxy samples, %d axis samples, %d state samples (%s):%s',
      [FBad, FCompared, FAxisCompared, FStateCompared, FTally.CommaText, FReport]));
  { not a vacuous pass }
  AssertTrue(Format('only %d proxy samples', [FCompared]), FCompared >= 4000);
  AssertTrue(Format('only %d axis samples', [FAxisCompared]), FAxisCompared >= 7000);
  AssertTrue(Format('only %d state samples', [FStateCompared]), FStateCompared >= 2000);
end;

{ ==================== by hand ==================== }

const
  cStack = '{"color":["#5470c6","#91cc75"],"legend":{},"xAxis":{"type":"category",'
    + '"data":["A","B","C","D","E"]},"yAxis":{"type":"value","axisLine":{"show":true},'
    + '"axisTick":{"show":true}},"series":[{"name":"s0","type":"bar","stack":"a",'
    + '"data":[5,20,36,10,8]},{"name":"s1","type":"bar","stack":"a","data":[8,12,6,30,4]}]}';

{ WHILE THE GROUP TRANSITIONS, the axes are drawn from their proxies in the
  dynamic layer: a split line half way to its new place is ink where no
  line of either layout is }
procedure TAdvChartAnimFullUpdateTest.TestTheAxesMoveInTheDynamicLayer;
var
  p: TTyChartAnimProxy;
  y, d: Double;
  iy, x: Integer;
  bmp: TBGRABitmap;
  c, c2: TBGRAPixel;
begin
  NewChart(camAlways);
  Load(cStack);
  Settle(T0);
  FChart.AnimNow := T1;
  FChart.DispatchAction('{"type":"legendToggleSelect","name":"s0"}');
  AssertTrue('the axes have proxies', FChart.AnimAxisProxyCount > 0);
  p := FChart.AnimAxisProxy('yAxis0', 'line_20');
  AssertNotNull('line_20 is matched', p);
  FChart.AnimNow := T1 + 250;
  FChart.AnimTick(T1 + 250);
  bmp := Draw;
  AssertTrue('live', FChart.AnimLive);
  AssertEquals('it moves', 1, p.AnimatorCount);
  y := p.Num('shape.y1');
  { not where it goes }
  d := Abs(y - p.FinalOf('shape.y1').Num);
  AssertTrue(Format('half way (%g to %g)', [y, p.FinalOf('shape.y1').Num]), d > 3);
  iy := Floor(y);
  x := 357;
  c := bmp.GetPixel(x, iy);
  c2 := bmp.GetPixel(x, iy + 3);
  AssertTrue(Format('ink at the line in motion (%d,%d,%d vs %d,%d,%d)', [c.red, c.green,
    c.blue, c2.red, c2.green, c2.blue]), (c.red <> c2.red) or (c.green <> c2.green)
    or (c.blue <> c2.blue));
  { and at rest the static layer draws them where the layout does }
  FChart.AnimTick(T1 + 2000);
  Draw;
  AssertFalse('at rest', FChart.AnimLive);
end;

{ getAnimationConfig: the update payload's animation overrides enter,
  update and leave alike; a call's own payload goes first }
procedure TAdvChartAnimFullUpdateTest.TestAPayloadOverridesEveryTiming;
var
  root: TJSONData;
  m: TTyAnimModel;
  t: TTyAnimTiming;
  o: TTyAnimCallOpts;
begin
  root := GetJSON('{"series":[{"type":"bar","animationDuration":700,'
    + '"animationDurationUpdate":400,"animationEasingUpdate":"linear","data":[1,2]}]}');
  try
    m := TyAnimSeriesModel(root, 0, 2);
    AssertTrue(TyAnimGetConfig(atUpdate, m, TyAnimCallAt(0), t));
    AssertEquals('the model''s update', 400, t.Duration, 0);
    m.HasPayload := True;
    m.Payload := TyAnimNoOverride;
    m.Payload.HasDuration := True;
    m.Payload.Duration := 100;
    m.Payload.HasEasing := True;
    m.Payload.Easing := 'cubicOut';
    AssertTrue(TyAnimGetConfig(atEnter, m, TyAnimCallAt(0), t));
    AssertEquals('enter', 100, t.Duration, 0);
    AssertEquals('enter easing', 'cubicOut', t.Easing);
    AssertTrue(TyAnimGetConfig(atUpdate, m, TyAnimCallAt(0), t));
    AssertEquals('update', 100, t.Duration, 0);
    AssertTrue(TyAnimGetConfig(atLeave, m, TyAnimCallAt(0), t));
    AssertEquals('leave', 100, t.Duration, 0);
    AssertEquals('the delay is the model''s', 0, t.Delay, 0);
    o := TyAnimCallAt(0);
    o.HasPayload := True;
    o.Payload := TyAnimNoOverride;
    o.Payload.HasDuration := True;
    o.Payload.Duration := 33;
    AssertTrue(TyAnimGetConfig(atUpdate, m, o, t));
    AssertEquals('the call''s own first', 33, t.Duration, 0);
    AssertEquals('and only its own', 'linear', t.Easing);
  finally
    root.Free;
  end;
end;

{ zrender rounds with Math.round: a half goes up, never to the even }
procedure TAdvChartAnimFullUpdateTest.TestSubPixelOptimizeRoundsAsJavaScript;
var x1, y1, x2, y2: Double;
begin
  { 10.25 doubled is 20.5: Math.round 21 (banker's would be 20); with an
    even width 21 + 2 is odd -> (21 + 1) / 2 = 11 (banker's: 10) }
  AssertEquals(11, TySubPixelOptimize(10.25, 2, True), 0);
  AssertEquals(10.5, TySubPixelOptimize(10.25, 1, True), 0);
  AssertEquals(11.5, TySubPixelOptimize(10.75, 1, True), 0);
  AssertEquals(10.5, TySubPixelOptimize(10.25, 0.6, True), 0);
  AssertEquals(-10.5, TySubPixelOptimize(-10.25, 1, False), 0);
  AssertEquals('nought leaves it', 10.3, TySubPixelOptimize(10.3, 0, True), 0);
  AssertEquals('an even width: the whole pixel', 10, TySubPixelOptimize(10.2, 2, True), 0);
  x1 := 60.3; y1 := 20.2; x2 := 360.1; y2 := 20.1;
  TySubPixelOptimizeLine(x1, y1, x2, y2, 1);
  AssertEquals('along x: x untouched', 60.3, x1, 0);
  AssertEquals(20.5, y1, 0);
  AssertEquals(20.5, y2, 0);
  { the ends compared by Math.round of their doubles: 10.25 and 10 are not
    the same half pixel (21 against 20), so the line is left alone }
  x1 := 50; y1 := 10.25; x2 := 90; y2 := 10;
  TySubPixelOptimizeLine(x1, y1, x2, y2, 1);
  AssertEquals('not level: untouched', 10.25, y1, 0);
  AssertEquals('not level: untouched', 10, y2, 0);
end;

{ camAuto with no window paint: the update waits, and nothing moves }
procedure TAdvChartAnimFullUpdateTest.TestHeadlessWaitsForTheWindow;
begin
  NewChart(camAuto);
  Load(cStack);
  FChart.AnimNow := T1;
  FChart.DispatchAction('{"type":"legendToggleSelect","name":"s0"}');
  Draw;
  AssertEquals('no clip', 0, FChart.AnimClipCount);
  AssertEquals('no axis proxy', 0, FChart.AnimAxisProxyCount);
  AssertFalse('not live', FChart.AnimLive);
end;

{ camOff: a legend toggle snaps; and a new option (notMerge) has new axis
  views: no groupTransition, the proxies of the last one dropped }
procedure TAdvChartAnimFullUpdateTest.TestOffSnapsAndANewOptionDropsTheAxes;
begin
  NewChart(camOff);
  Load(cStack);
  FChart.DispatchAction('{"type":"legendToggleSelect","name":"s0"}');
  Draw;
  AssertEquals('off: no clip', 0, FChart.AnimClipCount);
  AssertEquals('off: no axis proxy', 0, FChart.AnimAxisProxyCount);
  NewChart(camAlways);
  Load(cStack);
  Settle(T0);
  FChart.AnimNow := T1;
  FChart.DispatchAction('{"type":"legendToggleSelect","name":"s0"}');
  AssertTrue('a toggle makes them', FChart.AnimAxisProxyCount > 0);
  FChart.AnimNow := T1 + 2000;
  FChart.AnimTick(T1 + 2000);
  FChart.Option := StringReplace(cStack, '[5,20,36,10,8]', '[6,21,30,9,7]', []);
  Draw;
  AssertEquals('a new option drops them', 0, FChart.AnimAxisProxyCount);
end;

{ THE POINTER OVER A REUSED ELEMENT through a notMerge option: zrender's
  hover target is the same element, so moving on it sends no out and no
  over, and it stays in emphasis }
procedure TAdvChartAnimFullUpdateTest.TestAHoverHeldThroughANewOptionSendsNoOver;
const
  cOpt = '{"xAxis":{"type":"category","data":["A","B","C","D","E"]},'
    + '"yAxis":{"type":"value","max":40,"min":-10},"series":[{"type":"bar","data":%s}]}';
var
  p: TTyChartAnimProxy;
  cx, cy: Integer;
begin
  NewChart(camAlways);
  Load(Format(cOpt, ['[5,20,36,10,-8]']));
  Settle(T0);
  p := FChart.AnimFindProxy(0, 2, 'bar');
  AssertNotNull('bar C', p);
  cx := Round(p.Num('shape.x') + p.Num('shape.width') / 2);
  cy := Round(p.Num('shape.y') + p.Num('shape.height') / 2);
  FChart.OnChartEvent := @OnEv;
  FChart.Move(cx, cy);
  AssertTrue('over it', FEvents.IndexOf('mouseover') >= 0);
  FEvents.Clear;
  FChart.AnimNow := T1;
  { the bar stays under the pointer: 30 of 40 still reaches it }
  FChart.Option := Format(cOpt, ['[15,8,30,25,4]']);
  Draw;
  AssertEquals('still in emphasis', 'emphasis',
    FChart.AnimStateProxy(0, 2, 'host').CurrentStates);
  FChart.Move(cx + 1, cy);
  AssertEquals('no out', -1, FEvents.IndexOf('mouseout'));
  AssertEquals('no over', -1, FEvents.IndexOf('mouseover'));
  AssertTrue('a move', FEvents.IndexOf('mousemove') >= 0);
end;

initialization
  RegisterTest(TAdvChartAnimFullUpdateTest);
finalization
  FreeAndNil(GFix);
end.
