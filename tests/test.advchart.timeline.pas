unit test.advchart.timeline;
{$mode objfpc}{$H+}
{ The timeline component -- held to upstream to the bit [Batch 129, C21].

  tools/advchart-oracle/timeline.js runs the real ECharts 6.1 build through
  cases of setOption, actions, pointer steps on zrender's own Handler and
  waits on a controlled clock, and records after every step: the timeline
  model's currentIndex and autoPlay, the pending play timer, the
  timelinechanged / timelineplaychanged events, the raw merge layer
  getOption rests on, every element of the slider view in display order
  (its role, transform, global matrix, bounding rect, path or line shape,
  style, states, hover and z2), the two groups, and every bar of every bar
  series.

  The port is replayed the same way: the clock is the chart's AnimNow and
  TimelineNow; a step's fired play timers each get TimelineTick at their due
  instant, a render and an AnimTick there; then the step -- Option /
  SetOption, DispatchAction, MouseMove / MouseDown / MouseUp / MouseLeave,
  SetBounds -- a render and an AnimTick at the step's instant. Compared
  through TimelineView (the elements), TimelineDue, OnChartEvent,
  GetOptionJson (structurally) and the paint list's bars. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StrConsts,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape, tyControls.AdvChart.Events,
     tyControls.AdvChart.Anim, tyControls.AdvChart.GfxEl,
     tyControls.AdvChart.ZrPath, tyControls.AdvChart.Timeline,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Color,
     tyControls.AdvChart.Export,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TTlProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    Events: TStringList;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Down(AX, AY: Integer);
    procedure Move(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
    procedure Leave;
    procedure OnEv(Sender: TObject; const AEvent: TTyChartEvent);
    function List: TTyPaintList;
    function Frame: TTyPaintList;
  end;

  TAdvChartTimelineOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTlProbe;
    FRoot: TJSONData;
    FBad, FCompared, FStates: Integer;
    FReport, FName: string;
    FStateNo: Integer;
    FColours: Boolean;
    FBmp: TBGRABitmap;
    FSavedSource: TTyDateTimeNameSource;
    procedure Miss(const AWhat: string);
    procedure SameHex(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure NewChart(AW, AH: Integer);
    procedure RenderNow;
    procedure SetClock(AMs: Double);
    procedure CheckState(AState: TJSONObject);
    procedure CheckView(AView: TJSONData);
    procedure CheckEl(AEl: TTyGfxEl; AIndex: Integer; AWant: TJSONObject);
    procedure CheckBars(ABars: TJSONArray);
    procedure CheckTree(ATree: TJSONData);
    procedure RunCase(ACase: TJSONObject);
    procedure RunGroup(const AGroups: array of string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLayoutAsUpstream;
    procedure TestControlsAndLabelsAsUpstream;
    procedure TestClicksAndDragsAsUpstream;
    procedure TestHoverAsUpstream;
    procedure TestPlayAsUpstream;
    procedure TestActionsAndOptionAsUpstream;
    procedure TestAnimationAsUpstream;
  end;

  { What the oracle does not reach. }
  TAdvChartTimelineTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTlProbe;
    FBmp: TBGRABitmap;
    procedure RenderNow;
    procedure Show(const AOption: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestThePreprocessorWritesWhatUpstreamWrites;
    procedure TestSetCurrentIndexWrapsAndClamps;
    procedure TestAChangeWithoutATimelineDoesNothing;
    procedure TestTheOptionPropertyKeepsTheHostsText;
    procedure TestANotMergeTakesTheTimerAndTheCheckpoint;
    procedure TestTheEventsAreRegistrable;
    procedure TestTheExportCanLeaveTheTimelineOut;
    procedure TestTheTimelineIsDrawnInTheSkinsInk;
    procedure TestATimeAxisOverStringsDrawsNothingAtNaN;
  end;

implementation

const
  T0 = 1700000000000.0;

{ ==================== the probe ==================== }

function TTlProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Exit(Measurer);
  Result := inherited NewTextMeasurer(APPI);
end;

constructor TTlProbe.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Events := TStringList.Create;
  OnChartEvent := @OnEv;
end;

destructor TTlProbe.Destroy;
begin
  Events.Free;
  inherited Destroy;
end;

procedure TTlProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTlProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
end;

procedure TTlProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TTlProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

procedure TTlProbe.Leave;
begin
  MouseLeave;
end;

procedure TTlProbe.OnEv(Sender: TObject; const AEvent: TTyChartEvent);
begin
  if (AEvent.EventType = 'timelinechanged') or (AEvent.EventType = 'timelineplaychanged') then
    Events.Add(AEvent.EventType + #9 + AEvent.Payload);
end;

function TTlProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TTlProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

{ ==================== the fixture ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-timeline.json';
end;

function HexNum(AData: TJSONData): Double;
var q: QWord;
begin
  if (AData = nil) or (AData.JSONType <> jtString) then Exit(NaN);
  q := StrToQWord('$' + AData.AsString);
  Move(q, Result, SizeOf(Result));
end;

function HexOf(AValue: Double): string;
var q: QWord;
begin
  Move(AValue, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

{ the oracle's NaN is the canonical one; the port's may carry the sign bit }
function SameBitsOrNaN(A, B: Double): Boolean;
begin
  if IsNan(A) and IsNan(B) then Exit(True);
  Result := HexOf(A) = HexOf(B);
end;

{ PathProxy's data: each command's code, then its numbers }
function PathData(const APath: TTyZrPath): TTyDoubleArray;
const
  cCode: array[TTyZrCmd] of Integer = (1, 2, 3, 4, 5, 6, 7);
var
  i, k, n: Integer;
begin
  Result := nil;
  n := 0;
  for i := 0 to High(APath) do
  begin
    SetLength(Result, n + 1 + TyZrArgCount(APath[i].Cmd));
    Result[n] := cCode[APath[i].Cmd];
    Inc(n);
    for k := 0 to TyZrArgCount(APath[i].Cmd) - 1 do
    begin
      Result[n] := APath[i].V[k];
      Inc(n);
    end;
  end;
end;

{ a JSON value as JavaScript's String() of it }
function JText(A: TJSONData): string;
begin
  Result := '';
  if A = nil then Exit;
  case A.JSONType of
    jtString: Result := A.AsString;
    jtNumber: Result := FloatToStr(A.AsFloat);
    jtBoolean: if A.AsBoolean then Result := 'true' else Result := 'false';
  end;
end;

function RoleName(const ARole: TTyTlRole): string;
begin
  case ARole.Kind of
    tlrLine: Result := 'line';
    tlrProgress: Result := 'progress';
    tlrTick: Result := 'tick:' + IntToStr(ARole.Index);
    tlrLabel: Result := 'label:' + IntToStr(ARole.Index);
    tlrNext: Result := 'next';
    tlrPrev: Result := 'prev';
    tlrPlay: Result := 'play';
    tlrStop: Result := 'stop';
  else
    Result := 'pointer';
  end;
end;

{ structural equality: objects by their keys, arrays item by item, numbers
  as doubles }
function SameJson(A, B: TJSONData; const APath: string; out AWhere: string): Boolean;
var
  i, k: Integer;
  oa, ob: TJSONObject;
begin
  AWhere := APath;
  if (A = nil) or (B = nil) then Exit(A = B);
  if (A.JSONType = jtNumber) and (B.JSONType = jtNumber) then
  begin
    Result := SameBitsOrNaN(A.AsFloat, B.AsFloat);
    if not Result then AWhere := APath + ' ' + A.AsJSON + ' vs ' + B.AsJSON;
    Exit;
  end;
  if A.JSONType <> B.JSONType then
  begin
    AWhere := APath + ' ' + A.AsJSON + ' vs ' + B.AsJSON;
    Exit(False);
  end;
  case A.JSONType of
    jtNull: Result := True;
    jtBoolean: Result := A.AsBoolean = B.AsBoolean;
    jtString: Result := A.AsString = B.AsString;
    jtArray:
      begin
        if A.Count <> B.Count then
        begin
          AWhere := APath + Format(' %d vs %d items', [A.Count, B.Count]);
          Exit(False);
        end;
        for i := 0 to A.Count - 1 do
          if not SameJson(A.Items[i], B.Items[i], APath + '[' + IntToStr(i) + ']', AWhere) then
            Exit(False);
        Result := True;
      end;
    jtObject:
      begin
        oa := TJSONObject(A);
        ob := TJSONObject(B);
        for i := 0 to oa.Count - 1 do
        begin
          k := ob.IndexOfName(oa.Names[i]);
          if k < 0 then
          begin
            AWhere := APath + '.' + oa.Names[i] + ' only here';
            Exit(False);
          end;
          if not SameJson(oa.Items[i], ob.Items[k], APath + '.' + oa.Names[i], AWhere) then
            Exit(False);
        end;
        for i := 0 to ob.Count - 1 do
          if oa.IndexOfName(ob.Names[i]) < 0 then
          begin
            AWhere := APath + '.' + ob.Names[i] + ' only upstream';
            Exit(False);
          end;
        Result := True;
      end;
  else
    Result := A.AsJSON = B.AsJSON;
  end;
  if not Result and (AWhere = APath) then AWhere := APath + ' ' + A.AsJSON + ' vs ' + B.AsJSON;
end;

{ an event's payload with the view's uid as the oracle writes it }
function EventJson(const APayload: string): TJSONData;
var
  d: TJSONData;
  f: TJSONData;
begin
  d := GetJSON(APayload);
  if d is TJSONObject then
  begin
    f := TJSONObject(d).Find('from');
    if (f <> nil) and (f.JSONType = jtString) and (Copy(f.AsString, 1, 6) = 'ec_tl_') then
      TJSONObject(d).Elements['from'] := TJSONString.Create('@view');
  end;
  Result := d;
end;

{ ==================== the oracle replay ==================== }

procedure TAdvChartTimelineOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  { upstream's month names are its English locale's: the port's pinned to
    its own (English) resourcestrings }
  FSavedSource := TyDateTimeNameSource;
  TyDateTimeNameSource := dnTranslation;
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
  FBmp := nil;
  FBad := 0;
  FCompared := 0;
  FStates := 0;
  FReport := '';
end;

procedure TAdvChartTimelineOracleTest.TearDown;
begin
  TyDateTimeNameSource := FSavedSource;
  FreeAndNil(FRoot);
  if FChart <> nil then FChart.Measurer := nil;
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartTimelineOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 300 then
    FReport := FReport + LineEnding + '  ' + FName + ' #' + IntToStr(FStateNo) + ': ' + AWhat;
end;

procedure TAdvChartTimelineOracleTest.SameHex(const AWhat: string; AGot: Double;
  AWant: TJSONData);
begin
  Inc(FCompared);
  if (AWant = nil) or (AWant.JSONType = jtNull) then
  begin
    Miss(AWhat + ': nothing upstream, ' + FloatToStr(AGot) + ' here');
    Exit;
  end;
  if not SameBitsOrNaN(AGot, HexNum(AWant)) then
    Miss(Format('%s: upstream %s (%s), here %s (%s)', [AWhat, AWant.AsString,
      FloatToStr(HexNum(AWant)), HexOf(AGot), FloatToStr(AGot)]));
end;

procedure TAdvChartTimelineOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then Miss(Format('%s: upstream "%s", here "%s"', [AWhat, AWant, AGot]));
end;

procedure TAdvChartTimelineOracleTest.NewChart(AW, AH: Integer);
var m: TJSONObject;
begin
  FreeAndNil(FChart);
  FreeAndNil(FBmp);
  FChart := TTlProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(m.Arrays['ratio'],
    m.Integers['firstCode']));
  FChart.SetBounds(0, 0, AW, AH);
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := T0;
  FChart.TimelineNow := T0;
  FBmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
end;

procedure TAdvChartTimelineOracleTest.RenderNow;
begin
  if (FBmp.Width <> FChart.Width) or (FBmp.Height <> FChart.Height) then
    FBmp.SetSize(FChart.Width, FChart.Height);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
end;

procedure TAdvChartTimelineOracleTest.SetClock(AMs: Double);
begin
  FChart.AnimNow := AMs;
  FChart.TimelineNow := AMs;
end;

procedure TAdvChartTimelineOracleTest.CheckTree(ATree: TJSONData);
var
  got: TJSONData;
  where: string;
begin
  Inc(FCompared);
  got := GetJSON(FChart.GetOptionJson);
  try
    if not SameJson(got, ATree, 'tree', where) then Miss(where);
  finally
    got.Free;
  end;
end;

procedure TAdvChartTimelineOracleTest.CheckBars(ABars: TJSONArray);
var
  s, i, k: Integer;
  lst: TTyPaintList;
  arr, b: TJSONArray;
  el: TTyChartElement;
  found: Boolean;
  x0, x1, y0, y1, bx, by, bw, bh: Double;
  w: string;

  procedure Near(const AWhat: string; AWant, AGot: Double);
  begin
    Inc(FCompared);
    if not (Abs(AWant - AGot) <= 1e-9) then
      Miss(Format('%s: upstream %.17g, here %.17g', [AWhat, AWant, AGot]));
  end;

begin
  lst := FChart.Frame;
  if lst = nil then Exit;
  for s := 0 to ABars.Count - 1 do
  begin
    if ABars.Items[s].JSONType = jtNull then Continue;
    arr := TJSONArray(ABars.Items[s]);
    w := 'bars[' + IntToStr(s) + ']';
    for i := 0 to arr.Count - 1 do
    begin
      found := False;
      el := Default(TTyChartElement);
      for k := 0 to lst.Count - 1 do
      begin
        el := lst.Element(k);
        if (el.Datum.SeriesIndex <> s) or (el.Datum.DataIndex <> i) or el.Ignore then Continue;
        if not (el.Shape.Kind in [cskRect, cskRoundRect]) then Continue;
        found := True;
        Break;
      end;
      Inc(FCompared);
      if arr.Items[i].JSONType = jtNull then
      begin
        if found then Miss(Format('%s[%d]: no bar upstream, one here', [w, i]));
        Continue;
      end;
      if not found then
      begin
        Miss(Format('%s[%d]: no bar here', [w, i]));
        Continue;
      end;
      b := TJSONArray(arr.Items[i]);
      bx := HexNum(b.Items[0]);
      by := HexNum(b.Items[1]);
      bw := HexNum(b.Items[2]);
      bh := HexNum(b.Items[3]);
      x0 := Min(bx, bx + bw);
      x1 := Max(bx, bx + bw);
      y0 := Min(by, by + bh);
      y1 := Max(by, by + bh);
      Near(Format('%s[%d].left', [w, i]), x0, el.Shape.Bounds.Left);
      Near(Format('%s[%d].right', [w, i]), x1, el.Shape.Bounds.Right);
      Near(Format('%s[%d].top', [w, i]), y0, el.Shape.Bounds.Top);
      Near(Format('%s[%d].bottom', [w, i]), y1, el.Shape.Bounds.Bottom);
    end;
  end;
end;

procedure TAdvChartTimelineOracleTest.CheckEl(AEl: TTyGfxEl; AIndex: Integer;
  AWant: TJSONObject);
var
  w: string;
  t, st, sh: TJSONObject;
  d: TJSONData;
  a: TJSONArray;
  i: Integer;
  r: TTyXYWH;
  pd: TTyDoubleArray;
  v: TTyAnimValue;
  cg, cw: TTyChartColor;
  gotFill, wantFill: string;
  meas: ITyTextMeasurer;
begin
  w := AWant.Strings['role'];
  meas := FChart.Measurer;
  SameStr(w + '.type', AEl.ZrType, AWant.Strings['type']);
  Inc(FCompared);
  if AEl.Silent <> AWant.Booleans['silent'] then Miss(w + '.silent');
  Inc(FCompared);
  if not SameBitsOrNaN(AEl.Z2, AWant.Floats['z2']) then
    Miss(Format('%s.z2: upstream %g, here %g', [w, AWant.Floats['z2'], AEl.Z2]));
  Inc(FCompared);
  if not SameBitsOrNaN(AEl.Z, AWant.Floats['z']) then
    Miss(Format('%s.z: upstream %g, here %g', [w, AWant.Floats['z'], AEl.Z]));
  t := AWant.Objects['t'];
  SameHex(w + '.x', AEl.X, t.Find('x'));
  SameHex(w + '.y', AEl.Y, t.Find('y'));
  SameHex(w + '.rotation', AEl.Rotation, t.Find('rotation'));
  SameHex(w + '.scaleX', AEl.ScaleX, t.Find('scaleX'));
  SameHex(w + '.scaleY', AEl.ScaleY, t.Find('scaleY'));
  SameHex(w + '.originX', AEl.OriginX, t.Find('originX'));
  SameHex(w + '.originY', AEl.OriginY, t.Find('originY'));
  d := AWant.Find('m');
  Inc(FCompared);
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    if AEl.HasTransform then Miss(w + '.m: none upstream, one here');
  end
  else if not AEl.HasTransform then
    Miss(w + '.m: one upstream, none here')
  else
    for i := 0 to 5 do SameHex(Format('%s.m[%d]', [w, i]), AEl.Transform[i], TJSONArray(d).Items[i]);
  { the states and the hover }
  a := AWant.Arrays['states'];
  w := AWant.Strings['role'];
  gotFill := AEl.CurrentStates;
  wantFill := '';
  for i := 0 to a.Count - 1 do
  begin
    if wantFill <> '' then wantFill := wantFill + ',';
    wantFill := wantFill + a.Strings[i];
  end;
  SameStr(w + '.states', gotFill, wantFill);
  Inc(FCompared);
  if FChart.TimelineView.Hover[AIndex] <> (AWant.Integers['hover'] = 2) then
    Miss(w + '.hover: upstream ' + IntToStr(AWant.Integers['hover']));
  { the bounding rect }
  r := TyGfxRect(AEl, meas);
  a := AWant.Arrays['rect'];
  SameHex(w + '.rect.x', r.X, a.Items[0]);
  SameHex(w + '.rect.y', r.Y, a.Items[1]);
  SameHex(w + '.rect.w', r.W, a.Items[2]);
  SameHex(w + '.rect.h', r.H, a.Items[3]);
  { the geometry }
  sh := TJSONObject(AWant.Find('shape'));
  if sh <> nil then
  begin
    SameHex(w + '.x1', TyTlJsNum(AEl.Shape.Find('x1')), sh.Find('x1'));
    SameHex(w + '.y1', TyTlJsNum(AEl.Shape.Find('y1')), sh.Find('y1'));
    SameHex(w + '.x2', TyTlJsNum(AEl.Shape.Find('x2')), sh.Find('x2'));
    SameHex(w + '.y2', TyTlJsNum(AEl.Shape.Find('y2')), sh.Find('y2'));
  end;
  d := AWant.Find('path');
  if d is TJSONArray then
  begin
    pd := PathData(TyGfxPath(AEl));
    Inc(FCompared);
    if Length(pd) <> d.Count then
      Miss(Format('%s.path: upstream %d numbers, here %d', [w, d.Count, Length(pd)]))
    else
      for i := 0 to High(pd) do SameHex(Format('%s.path[%d]', [w, i]), pd[i], d.Items[i]);
  end;
  { the style }
  st := AWant.Objects['style'];
  v := AEl.StyleValue('opacity');
  SameHex(w + '.opacity', v.Num, st.Find('opacity'));
  if AEl.Kind <> gkText then
  begin
    v := AEl.StyleValue('lineWidth');
    SameHex(w + '.lineWidth', v.Num, st.Find('lineWidth'));
  end
  else
  begin
    SameStr(w + '.text', JText(AEl.Style.Find('text')), st.Strings['text']);
    SameStr(w + '.align', JText(AEl.Style.Find('align')), st.Strings['align']);
    SameStr(w + '.verticalAlign', JText(AEl.Style.Find('verticalAlign')),
      st.Strings['verticalAlign']);
  end;
  if FColours then
  begin
    for i := 0 to 1 do
    begin
      if i = 0 then wantFill := 'fill' else wantFill := 'stroke';
      d := st.Find(wantFill);
      v := AEl.StyleValue(wantFill);
      Inc(FCompared);
      if (d = nil) or (d.JSONType = jtNull) then
      begin
        if (v.Kind = avkString) and (v.Str <> 'none') and (v.Str <> '') then
          Miss(Format('%s.%s: none upstream, %s here', [w, wantFill, v.Str]));
        Continue;
      end;
      if not TyTryParseChartColor(d.AsString, cw) then Continue;
      if (v.Kind <> avkString) or not TyTryParseChartColor(v.Str, cg) then
        Miss(Format('%s.%s: upstream %s, none here', [w, wantFill, d.AsString]))
      else if cg <> cw then
        Miss(Format('%s.%s: upstream %s, here %s', [w, wantFill, d.AsString, v.Str]));
    end;
  end;
end;

procedure TAdvChartTimelineOracleTest.CheckView(AView: TJSONData);
var
  v: TTyTimelineView;
  els: TJSONArray;
  order: TTyIntegerArray;
  g: TJSONObject;
  i, j, k: Integer;
  got, want: string;

  procedure Group(const AName: string; AEl: TTyGfxEl; AWant: TJSONObject);
  begin
    SameHex(AName + '.x', AEl.X, AWant.Find('x'));
    SameHex(AName + '.y', AEl.Y, AWant.Find('y'));
    SameHex(AName + '.rotation', AEl.Rotation, AWant.Find('rotation'));
    SameHex(AName + '.originX', AEl.OriginX, AWant.Find('originX'));
    SameHex(AName + '.originY', AEl.OriginY, AWant.Find('originY'));
  end;

begin
  v := FChart.TimelineView;
  Inc(FCompared);
  if (AView = nil) or (AView.JSONType = jtNull) then
  begin
    if (v <> nil) and v.Shown then Miss('view: none upstream, one here');
    Exit;
  end;
  if (v = nil) or not v.Shown then
  begin
    Miss('view: one upstream, none here');
    Exit;
  end;
  v.UpdateTransforms;
  g := TJSONObject(AView);
  Group('main', v.MainGroup, g.Objects['main']);
  Group('label', v.LabelGroup, g.Objects['label']);
  els := g.Arrays['els'];
  order := v.DisplayOrder;
  { the display order, by role }
  got := '';
  for i := 0 to High(order) do got := got + RoleName(v.RoleOf(order[i])) + ' ';
  want := '';
  for i := 0 to els.Count - 1 do want := want + els.Objects[i].Strings['role'] + ' ';
  SameStr('order', Trim(got), Trim(want));
  { each element by its role, wherever the order put it }
  for i := 0 to els.Count - 1 do
  begin
    k := -1;
    for j := 0 to High(v.Els) do
      if RoleName(v.RoleOf(j)) = els.Objects[i].Strings['role'] then
      begin
        k := j;
        Break;
      end;
    Inc(FCompared);
    if k < 0 then
    begin
      Miss('no element here for ' + els.Objects[i].Strings['role']);
      Continue;
    end;
    CheckEl(v.Els[k], k, els.Objects[i]);
  end;
end;

procedure TAdvChartTimelineOracleTest.CheckState(AState: TJSONObject);
var
  d: TJSONData;
  m: TJSONObject;
  v: TTyTimelineView;
  evs: TJSONArray;
  i: Integer;
  got, want: TJSONData;
  where: string;
  p: Integer;
  due: Double;
begin
  Inc(FStates);
  v := FChart.TimelineView;
  { the model }
  d := AState.Find('model');
  Inc(FCompared);
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    if v <> nil then Miss('model: none upstream, one here');
  end
  else if v = nil then
    Miss('model: one upstream, none here')
  else
  begin
    m := TJSONObject(d);
    if m.Find('currentIndex').JSONType = jtNumber then
    begin
      Inc(FCompared);
      if not SameBitsOrNaN(v.CurrentIndex, m.Floats['currentIndex']) then
        Miss(Format('currentIndex: upstream %g, here %g', [m.Floats['currentIndex'], v.CurrentIndex]));
    end;
    Inc(FCompared);
    if v.PlayState <> TyTlTruthy(m.Find('autoPlay')) then Miss('autoPlay');
  end;
  { the timer }
  due := FChart.TimelineDue;
  d := AState.Find('timer');
  Inc(FCompared);
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    if not IsNan(due) then Miss(Format('timer: none upstream, %g here', [due - T0]));
  end
  else if IsNan(due) or (due - T0 <> d.AsFloat) then
    Miss(Format('timer: upstream %g, here %g', [d.AsFloat, due - T0]));
  { the events }
  evs := AState.Arrays['events'];
  Inc(FCompared);
  if evs.Count <> FChart.Events.Count then
    Miss(Format('events: upstream %d (%s), here %d (%s)', [evs.Count, evs.AsJSON,
      FChart.Events.Count, FChart.Events.CommaText]))
  else
    for i := 0 to evs.Count - 1 do
    begin
      p := Pos(#9, FChart.Events[i]);
      SameStr(Format('event[%d].type', [i]), Copy(FChart.Events[i], 1, p - 1),
        evs.Objects[i].Strings['type']);
      got := EventJson(Copy(FChart.Events[i], p + 1, MaxInt));
      want := GetJSON(evs.Objects[i].Strings['payload']);
      try
        Inc(FCompared);
        if not SameJson(got, want, Format('event[%d]', [i]), where) then Miss(where);
      finally
        got.Free;
        want.Free;
      end;
    end;
  FChart.Events.Clear;
  CheckTree(AState.Find('tree'));
  CheckView(AState.Find('view'));
  if AState.Find('bars') is TJSONArray then CheckBars(TJSONArray(AState.Find('bars')));
end;

procedure TAdvChartTimelineOracleTest.RunCase(ACase: TJSONObject);
var
  steps, states, fired: TJSONArray;
  st, sp: TJSONObject;
  i, k: Integer;
  t: Double;
  kind, opts: string;
begin
  FName := ACase.Strings['id'];
  FColours := ACase.Booleans['colours'];
  NewChart(ACase.Integers['W'], ACase.Integers['H']);
  states := ACase.Arrays['states'];
  steps := ACase.Arrays['steps'];
  SetClock(T0);
  FChart.Option := ACase.Objects['option'].AsJSON;
  RenderNow;
  FChart.AnimTick(T0);
  FStateNo := 0;
  CheckState(states.Objects[0]);
  for i := 0 to steps.Count - 1 do
  begin
    sp := steps.Objects[i];
    st := states.Objects[i + 1];
    FStateNo := i + 1;
    fired := st.Arrays['fired'];
    for k := 0 to fired.Count - 1 do
    begin
      t := T0 + fired.Floats[k];
      SetClock(t);
      FChart.TimelineTick(t);
      RenderNow;
      FChart.AnimTick(t);
    end;
    t := T0 + st.Floats['t'];
    SetClock(t);
    kind := sp.Strings['kind'];
    if kind = 'set' then
    begin
      if (sp.Find('opts') <> nil) and (sp.Find('opts').JSONType = jtObject) then
        opts := sp.Objects['opts'].AsJSON
      else
        opts := '';
      FChart.SetOption(sp.Objects['option'].AsJSON, opts);
    end
    else if kind = 'action' then
      FChart.DispatchAction(sp.Objects['payload'].AsJSON)
    else if kind = 'move' then
      FChart.Move(sp.Integers['x'], sp.Integers['y'])
    else if kind = 'down' then
      FChart.Down(sp.Integers['x'], sp.Integers['y'])
    else if kind = 'up' then
      FChart.Up(sp.Integers['x'], sp.Integers['y'])
    else if kind = 'tap' then
    begin
      FChart.Down(sp.Integers['x'], sp.Integers['y']);
      FChart.Up(sp.Integers['x'], sp.Integers['y']);
    end
    else if kind = 'leave' then
      FChart.Leave
    else if kind = 'resize' then
      FChart.SetBounds(0, 0, sp.Integers['w'], sp.Integers['h']);
    RenderNow;
    FChart.AnimTick(t);
    CheckState(st);
  end;
end;

procedure TAdvChartTimelineOracleTest.RunGroup(const AGroups: array of string);
var
  cases: TJSONArray;
  i, k: Integer;
  c: TJSONObject;
  ran: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  ran := 0;
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    for k := 0 to High(AGroups) do
      if c.Strings['group'] = AGroups[k] then
      begin
        RunCase(c);
        Inc(ran);
        Break;
      end;
  end;
  AssertTrue('cases ran', ran > 0);
  AssertTrue(Format('%d of %d comparisons over %d states differ:%s',
    [FBad, FCompared, FStates, FReport]), FBad = 0);
end;

procedure TAdvChartTimelineOracleTest.TestLayoutAsUpstream;
begin
  RunGroup(['layout']);
end;

procedure TAdvChartTimelineOracleTest.TestControlsAndLabelsAsUpstream;
begin
  RunGroup(['control', 'label']);
end;

procedure TAdvChartTimelineOracleTest.TestClicksAndDragsAsUpstream;
begin
  RunGroup(['click', 'drag']);
end;

procedure TAdvChartTimelineOracleTest.TestHoverAsUpstream;
begin
  RunGroup(['hover']);
end;

procedure TAdvChartTimelineOracleTest.TestPlayAsUpstream;
begin
  RunGroup(['play']);
end;

procedure TAdvChartTimelineOracleTest.TestActionsAndOptionAsUpstream;
begin
  RunGroup(['action', 'option']);
end;

procedure TAdvChartTimelineOracleTest.TestAnimationAsUpstream;
begin
  RunGroup(['anim']);
end;

{ ==================== by hand ==================== }

const
  cBase = '{baseOption: {timeline: {axisType: "category", data: ["a", "b", "c"]},'
    + ' xAxis: {type: "category", data: ["x", "y"]}, yAxis: {},'
    + ' series: [{type: "bar", data: [1, 2]}]},'
    + ' options: [{title: {text: "F0"}}, {title: {text: "F1"}}, {title: {text: "F2"}}]}';

procedure TAdvChartTimelineTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TTlProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, 600, 400);
  FChart.AnimationMode := camOff;
  FChart.AnimNow := T0;
  FChart.TimelineNow := T0;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
end;

procedure TAdvChartTimelineTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartTimelineTest.RenderNow;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
end;

procedure TAdvChartTimelineTest.Show(const AOption: string);
begin
  FChart.Option := AOption;
  AssertEquals('the option parses', '', FChart.OptionError);
  RenderNow;
end;

procedure TAdvChartTimelineTest.TestThePreprocessorWritesWhatUpstreamWrites;
var
  o: TJSONObject;
  tl: TJSONObject;
begin
  o := TJSONObject(GetJSON('{"timeline": {"type": "time", "label": {"color": "#111", '
    + '"normal": {"color": "#222"}}, "itemStyle": {"emphasis": {"label": {"show": false}}}, '
    + '"controlPosition": "none", "controlStyle": {"show": true}, '
    + '"data": [{"name": "n"}, [1], 3, {"value": 2, "name": "m"}]}}'));
  try
    TyTimelinePreprocess(o);
    tl := o.Objects['timeline'];
    AssertEquals('type time is axisType time', 'time', tl.Strings['axisType']);
    AssertTrue('the type goes', tl.Find('type') = nil);
    { the label's own keys copied into its normal -- not over what it has }
    AssertEquals('normal keeps its own colour', '#222', tl.Objects['label'].Objects['normal'].Strings['color']);
    { the emphasis label moved out of the item style }
    AssertTrue('the emphasis label out of the item style',
      tl.Objects['itemStyle'].Objects['emphasis'].Find('label') = nil);
    AssertFalse('and into the label', tl.Objects['label'].Objects['emphasis'].Booleans['show']);
    { controlPosition 'none' with a show written: the position stays }
    AssertEquals('the position written', 'none', tl.Objects['controlStyle'].Strings['position']);
    AssertTrue('show kept', tl.Objects['controlStyle'].Booleans['show']);
    AssertTrue('controlPosition goes', tl.Find('controlPosition') = nil);
    { an item with a name only takes it as its value, and gets an item style }
    AssertEquals('the name is the value', 'n', tl.Arrays['data'].Objects[0].Strings['value']);
    AssertTrue('an item style', tl.Arrays['data'].Objects[0].Objects['itemStyle'].Find('emphasis') <> nil);
    AssertEquals('a value written stays', 2, tl.Arrays['data'].Objects[3].Integers['value']);
    AssertTrue('a list is no object', tl.Arrays['data'].Items[1].JSONType = jtArray);
  finally
    o.Free;
  end;
  { a label nobody wrote: a temporary -- the option gets no label }
  o := TJSONObject(GetJSON('{"timeline": [{"itemStyle": {"emphasis": {"label": {"color": "red"}}}}, null]}'));
  try
    TyTimelinePreprocess(o);
    tl := o.Arrays['timeline'].Objects[0];
    AssertTrue('no label written', tl.Find('label') = nil);
    AssertTrue('the emphasis label is gone all the same',
      tl.Objects['itemStyle'].Objects['emphasis'].Find('label') = nil);
  finally
    o.Free;
  end;
end;

procedure TAdvChartTimelineTest.TestSetCurrentIndexWrapsAndClamps;
begin
  AssertEquals('5 of 4 wraps to 1', 1, TyTimelineNormIndex(5, 4, True), 0);
  AssertEquals('-1 of 4 wraps to 3', 3, TyTimelineNormIndex(-1, 4, True), 0);
  AssertEquals('-9 of 4 wraps to 3', 3, TyTimelineNormIndex(-9, 4, True), 0);
  AssertEquals('1.5 of 4 stays', 1.5, TyTimelineNormIndex(1.5, 4, True), 0);
  AssertEquals('9 of 4 clamps to 3', 3, TyTimelineNormIndex(9, 4, False), 0);
  AssertEquals('-4 clamps to 0', 0, TyTimelineNormIndex(-4, 4, False), 0);
  AssertTrue('no data and a loop: NaN', IsNan(TyTimelineNormIndex(2, 0, True)));
end;

procedure TAdvChartTimelineTest.TestAChangeWithoutATimelineDoesNothing;
begin
  Show('{xAxis: {type: "category", data: ["x"]}, yAxis: {}, series: [{type: "bar", data: [1]}]}');
  FChart.Events.Clear;
  { upstream throws reading the replaceMerge of no model; the port does
    nothing, and says nothing }
  FChart.DispatchAction('{"type": "timelineChange", "currentIndex": 1}');
  AssertEquals('no event', 0, FChart.Events.Count);
  AssertTrue('no view', FChart.TimelineView = nil);
end;

procedure TAdvChartTimelineTest.TestTheOptionPropertyKeepsTheHostsText;
var before: string;
begin
  Show(cBase);
  before := FChart.Option;
  FChart.DispatchAction('{"type": "timelineChange", "currentIndex": 2}');
  RenderNow;
  AssertEquals('the property is the host''s text', before, FChart.Option);
  AssertTrue('the frame was merged', Pos('"F2"', FChart.GetOptionJson) > 0);
  { the same text again is no change: the index stays where the action put it }
  FChart.Option := before;
  RenderNow;
  AssertEquals('still at 2', 2, FChart.TimelineView.CurrentIndex, 0);
end;

procedure TAdvChartTimelineTest.TestANotMergeTakesTheTimerAndTheCheckpoint;
var
  uid: string;
  cp: TTyGfxEl;
begin
  Show(StringReplace(cBase, 'data: ["a", "b", "c"]', 'data: ["a", "b", "c"], autoPlay: true, playInterval: 500', []));
  AssertEquals('the timer armed at the render', T0 + 500, FChart.TimelineDue, 0);
  uid := FChart.TimelineView.Uid;
  cp := FChart.TimelineView.Checkpoint;
  AssertTrue('a checkpoint', cp <> nil);
  FChart.SetOption('{xAxis: {type: "category", data: ["x"]}, yAxis: {}, series: [{type: "bar", data: [1]}]}', True);
  AssertTrue('no timer', IsNan(FChart.TimelineDue));
  AssertTrue('no view', FChart.TimelineView = nil);
  FChart.SetOption(cBase, True);
  RenderNow;
  AssertTrue('a new view', FChart.TimelineView.Uid <> uid);
  AssertTrue('not playing: no timer', IsNan(FChart.TimelineDue));
end;

procedure TAdvChartTimelineTest.TestTheEventsAreRegistrable;
begin
  AssertEquals('timelinechanged', 'timelinechanged', TyChartEventTypeOf('timelineChanged'));
  AssertEquals('timelineplaychanged', 'timelineplaychanged', TyChartEventTypeOf('timelinePlayChanged'));
  AssertTrue('an action event', TyChartEventIsAction('timelinechanged'));
end;

procedure TAdvChartTimelineTest.TestTheExportCanLeaveTheTimelineOut;
var v: TTyChartView;
begin
  AssertTrue('timeline is a view', TyChartViewOf('timeline', v));
  AssertTrue('the timeline''s', v = cvTimeline);
  AssertEquals('named', 'timeline', TyChartViewName(cvTimeline));
end;

procedure TAdvChartTimelineTest.TestTheTimelineIsDrawnInTheSkinsInk;
var
  v: TTyTimelineView;
  i: Integer;
  found: Boolean;
begin
  Show(cBase);
  v := FChart.TimelineView;
  AssertTrue('shown', (v <> nil) and v.Shown);
  { the ticks' default fill is the skin's, not upstream's token }
  found := False;
  for i := 0 to High(v.Els) do
    if v.RoleOf(i).Kind = tlrTick then
    begin
      found := True;
      AssertTrue('a tick has a fill', v.Els[i].StyleValue('fill').Kind = avkString);
      AssertTrue('not upstream''s accent20', v.Els[i].StyleValue('fill').Str <> '#c0c9e6');
    end;
  AssertTrue('ticks', found);
end;

{ [Milestone D9-D14] the default axisType is 'time': data that are not dates
  are NaN, every tick and label sits at NaN (upstream draws them there; the
  oracle's time-strings case has the places). The render, a hover, a click
  and a drag on the line raise nothing, the NaN elements stay out of the
  paint list, and the host's own traps are on again afterwards. }
procedure TAdvChartTimelineTest.TestATimeAxisOverStringsDrawsNothingAtNaN;
var
  v: TTyTimelineView;
  i, ticks: Integer;
  meas: ITyTextMeasurer;
  a, b: Double;
  raised: string;
begin
  Show('{"baseOption": {"timeline": {"data": ["a", "b", "c", "d"]}, '
    + '"xAxis": {"type": "category", "data": ["x", "y"]}, "yAxis": {}, '
    + '"series": [{"type": "bar", "data": [1, 2]}]}, '
    + '"options": [{}, {}, {}, {}]}');
  v := FChart.TimelineView;
  AssertTrue('shown', (v <> nil) and v.Shown);
  meas := FChart.NewTextMeasurer(96);
  ticks := 0;
  for i := 0 to High(v.Els) do
    case v.RoleOf(i).Kind of
      tlrTick:
        begin
          Inc(ticks);
          AssertTrue('a tick at NaN', IsNan(v.Els[i].X));
          AssertFalse('a tick at NaN is not drawn', v.Drawable(i, meas));
        end;
      tlrLine: AssertTrue('the line is drawn', v.Drawable(i, meas));
    end;
  AssertEquals('four ticks', 4, ticks);
  { over the line, where a tick would be; a click there; a drag along it }
  FChart.Move(300, 370);
  FChart.Down(300, 370);
  FChart.Move(320, 370);
  FChart.Up(320, 370);
  RenderNow;
  FChart.DispatchAction('{"type": "timelineChange", "currentIndex": 2}');
  RenderNow;
  AssertEquals('the action still moves the index', 2, v.CurrentIndex, 0);
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

initialization
  RegisterTest(TAdvChartTimelineOracleTest);
  RegisterTest(TAdvChartTimelineTest);
end.
