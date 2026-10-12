unit test.advchart.parallelbrush;
{$mode objfpc}{$H+}
{ Brushing along a parallel axis -- held to upstream to the bit [Batch 130,
  C20].

  tools/advchart-oracle/parallel-brush.js runs the real ECharts 6.1 build
  through cases of pointer steps on zrender's own Handler, actions and
  merges, on a fake clock, and records after every step: each parallelAxis
  view's BrushController (on or off, its option, the group's transform and
  its inverse, the panel along the axis, the track, the covers -- ranges,
  main shapes, handles, which of them answer the pointer and with what
  cursor), the axis model's active intervals, every row's opacity and
  active state, the cursor, the axisAreaSelect actions the views
  dispatched, the axisareaselected and brushselected events, an inside
  dataZoom's window and whether globalPan is held.

  The port is driven the same way -- MouseMove / MouseDown / MouseUp,
  DispatchAction, SetOption -- on the same clock, with a headless render
  after each step. A click is part of the port's MouseUp; the click step
  itself changes nothing upstream. Compared through the chart's own API:
  ParallelBrushOf, ParallelIntervals, ParallelSolvedOf, BrushHitTest,
  BrushCursorName, ParallelBrushActionAt, DataZoomInsideRange,
  BrushGlobalPanTaken and the chart events. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Events, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Brush, tyControls.AdvChart.Parallel, tyControls.AdvChart.Scale,
     tyControls.AdvanceChart;
type
  TPbProbe = class(TTyAdvanceChart)
  public
    Events: TStringList;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Down(AX, AY: Integer);
    procedure Move(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
    procedure OnEv(Sender: TObject; const AEvent: TTyChartEvent);
  end;

  TAdvChartParallelBrushOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TPbProbe;
    FRoot: TJSONData;
    FBad, FCompared, FSteps, FStepNo: Integer;
    FReport, FName: string;
    FClock: Double;
    { upstream's state carried forward: a record's null axes are the record
      before's }
    FAxes: array of TJSONData;
    FActSeen, FEvSeen: Integer;
    procedure Miss(const AWhat: string);
    procedure SameHex(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure NewChart;
    procedure RenderNow;
    function RoleAt(AX, AY: Integer): string;
    procedure CheckAxis(AK: Integer);
    procedure CheckRows(ARec: TJSONObject);
    procedure CheckActions(ARec: TJSONObject);
    procedure CheckEvents(ARec: TJSONObject);
    procedure CheckRecord(ARec: TJSONObject; AStep: TJSONObject);
    procedure RunScenario(ASc: TJSONObject);
    procedure RunGroup(const AIds: array of string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestHorizontalAndVerticalAsUpstream;
    procedure TestTheAxisTypesAsUpstream;
    procedure TestTheActionAndManyIntervalsAsUpstream;
    procedure TestMovingAndResizingAsUpstream;
    procedure TestRealtimeAsUpstream;
    procedure TestTheAreaSelectStyleAsUpstream;
    procedure TestGlobalPanAsUpstream;
  end;

  { What the oracle does not reach. }
  TAdvChartParallelBrushTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TPbProbe;
    procedure Show(const AOption: string);
    procedure RenderNow;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheCoversAreDrawnAlongTheAxis;
    procedure TestTheEventsCanBeSubscribed;
    procedure TestTheNamedAxisWaitsForTheNextUpdate;
    procedure TestNotMergeDropsTheControllers;
    procedure TestACoverHidesTheRowBeneath;
    procedure TestTheHelpers;
  end;

implementation

const
  cW = 600;
  cH = 400;
  { the areaSelectStyle colours upstream's defaults write; DEFAULT_BRUSH_OPT's
    tokens, which a cover laid from the intervals takes }
  cUpInk = 'rgba(160,197,232)';
  cUpBrushFill = '#cfd2d7';
  cUpBrushStroke = 'rgba(234,237,245,0.5)';

{ ==================== the probe ==================== }

constructor TPbProbe.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Events := TStringList.Create;
  OnChartEvent := @OnEv;
end;

destructor TPbProbe.Destroy;
begin
  Events.Free;
  inherited Destroy;
end;

procedure TPbProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TPbProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
end;

procedure TPbProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TPbProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

procedure TPbProbe.OnEv(Sender: TObject; const AEvent: TTyChartEvent);
begin
  if (AEvent.EventType = 'axisareaselected') or (AEvent.EventType = 'brushselected') then
    Events.Add(AEvent.EventType + #9 + AEvent.Payload);
end;

{ ==================== the fixture's numbers ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-parallel-brush.json';
end;

function HexNum(AData: TJSONData): Double;
var q: QWord;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  q := StrToQWord('$' + AData.AsString);
  Result := 0;
  System.Move(q, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if IsNan(A) then Exit('NaN');
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function Nul(const S: string): string;
begin
  Result := StringReplace(S, #0, '<NUL>', [rfReplaceAll]);
end;

function JStr(AData: TJSONData): string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Result := '(null)'
  else if AData.JSONType = jtString then Result := AData.AsString
  else Result := AData.AsJSON;
end;

{ a colour as upstream holds it: written, the areaSelectStyle default
  (a skin stands in), or DEFAULT_BRUSH_OPT's }
function InkWord(const AInk: TTyBrushInk; const ABrushDefault: string): string;
begin
  if AInk.Written then Result := AInk.Text
  else if AInk.Skin <> '' then Result := cUpInk
  else Result := ABrushDefault;
end;

function ActiveWord(A: TTyParallelActive): string;
begin
  case A of
    ppaActive: Result := 'active';
    ppaInactive: Result := 'inactive';
  else
    Result := 'normal';
  end;
end;

{ ==================== the oracle test ==================== }

procedure TAdvChartParallelBrushOracleTest.SetUp;
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
  FSteps := 0;
  FReport := '';
end;

procedure TAdvChartParallelBrushOracleTest.TearDown;
var i: Integer;
begin
  for i := 0 to High(FAxes) do FreeAndNil(FAxes[i]);
  FAxes := nil;
  FreeAndNil(FRoot);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartParallelBrushOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if (FBad <= 400) and (Pos(FName + ': ' + AWhat, FReport) = 0) then
    FReport := FReport + LineEnding + '  ' + FName + ' @' + IntToStr(FStepNo) + ': ' + AWhat;
end;

procedure TAdvChartParallelBrushOracleTest.SameHex(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double; ok: Boolean; q: QWord;
begin
  Inc(FCompared);
  want := HexNum(AWant);
  if IsNan(want) or IsNan(AGot) then ok := IsNan(want) and IsNan(AGot)
  else ok := AGot = want;
  if not ok then
  begin
    q := 0;
    System.Move(AGot, q, SizeOf(q));
    Miss(Format('%s is %s upstream, %s here (%s / %s)', [AWhat, Fmt(want), Fmt(AGot),
      JStr(AWant), LowerCase(IntToHex(q, 16))]));
  end;
end;

procedure TAdvChartParallelBrushOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

procedure TAdvChartParallelBrushOracleTest.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is %s upstream, %s here', [AWhat, BoolToStr(AWant, True),
      BoolToStr(AGot, True)]));
end;

procedure TAdvChartParallelBrushOracleTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TPbProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.AnimationMode := camOff;
end;

procedure TAdvChartParallelBrushOracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height), 96);
  finally
    bmp.Free;
  end;
end;

function TAdvChartParallelBrushOracleTest.RoleAt(AX, AY: Integer): string;
var b, i: Integer; p: TTyBrushPiece;
begin
  Result := '';
  if not FChart.BrushHitTest(AX, AY, b, i, p) then Exit;
  if b >= TyParallelBrushBase then
    Result := Format('axis%d.cover%d.%s', [b - TyParallelBrushBase, i, TyBrushPieceName(p)])
  else
    Result := Format('brush%d.cover%d.%s', [b, i, TyBrushPieceName(p)]);
end;

procedure TAdvChartParallelBrushOracleTest.CheckAxis(AK: Integer);
var
  w, c, o, st, pn, cv, mn, hs, h: TJSONObject;
  ctl: TTyBrushController;
  cov: TTyBrushCover;
  iv: TTyParallelIntervalArray;
  ord_: TTyIntegerArray;
  d: TJSONData;
  k, q, pos_: Integer;
  what, en, cur: string;
  p: TTyBrushPiece;
  live: Boolean;
begin
  if (AK > High(FAxes)) or (FAxes[AK] = nil) then Exit;
  w := TJSONObject(FAxes[AK]);
  what := Format('axis %d', [AK]);
  { the model's active intervals }
  iv := FChart.ParallelIntervals(AK);
  SameStr(what + ' interval count', IntToStr(Length(iv)), IntToStr(w.Arrays['intervals'].Count));
  for k := 0 to Min(Length(iv), w.Arrays['intervals'].Count) - 1 do
  begin
    SameHex(Format('%s interval %d [0]', [what, k]), iv[k][0], w.Arrays['intervals'].Arrays[k].Items[0]);
    SameHex(Format('%s interval %d [1]', [what, k]), iv[k][1], w.Arrays['intervals'].Arrays[k].Items[1]);
  end;
  d := w.Find('ctl');
  ctl := FChart.ParallelBrushOf(AK);
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  c := TJSONObject(d);
  if ctl = nil then
  begin
    Miss(what + ' has no controller');
    Exit;
  end;
  if ctl.Enabled then en := TyBrushTypeName(ctl.Opt.BrushType) else en := '(null)';
  SameStr(what + ' enabled', en, JStr(c.Find('enabled')));
  d := c.Find('option');
  if (d <> nil) and (d.JSONType = jtObject) and ctl.Enabled then
  begin
    o := TJSONObject(d);
    SameStr(what + ' option type', TyBrushTypeName(ctl.Opt.BrushType), o.Strings['brushType']);
    SameBool(what + ' option multiple', ctl.Opt.Multiple, o.Strings['brushMode'] <> 'single');
    SameBool(what + ' option transformable', ctl.Opt.Transformable, o.Booleans['transformable']);
    SameBool(what + ' option removeOnClick', ctl.Opt.RemoveOnClick, o.Booleans['removeOnClick']);
    SameBool(what + ' option z unset', IsNan(ctl.Opt.Z), o.Find('z').JSONType = jtNull);
    st := o.Objects['style'];
    SameStr(what + ' option fill', InkWord(ctl.Opt.Style.Fill, cUpBrushFill), JStr(st.Find('fill')));
    SameStr(what + ' option stroke', InkWord(ctl.Opt.Style.Stroke, cUpBrushStroke), JStr(st.Find('stroke')));
    SameHex(what + ' option lineWidth', ctl.Opt.Style.LineWidth, st.Find('lineWidth'));
    SameHex(what + ' option opacity', ctl.Opt.Style.Opacity, st.Find('opacity'));
  end;
  { the group: its transform and the inverse the pointer comes through }
  for k := 0 to 5 do
    SameHex(Format('%s transform[%d]', [what, k]), ctl.Xf[k], c.Arrays['transform'].Items[k]);
  d := c.Find('inv');
  SameBool(what + ' has an inverse', ctl.HasInv, (d <> nil) and (d.JSONType = jtArray));
  if (d <> nil) and (d.JSONType = jtArray) and ctl.HasInv then
    for k := 0 to 5 do
      SameHex(Format('%s inv[%d]', [what, k]), ctl.Inv[k], d.Items[k]);
  { the panel }
  d := c.Find('panel');
  if (d <> nil) and (d.JSONType = jtObject) then
  begin
    pn := TJSONObject(d);
    SameBool(what + ' has a panel', ctl.HasPanels and (Length(ctl.Panels) = 1), True);
    if Length(ctl.Panels) = 1 then
    begin
      SameStr(what + ' panel id', ctl.Panels[0].Id, 'pl');
      SameHex(what + ' panel x0', ctl.Panels[0].Rect.X, pn.Find('x0'));
      SameHex(what + ' panel y0', ctl.Panels[0].Rect.Y, pn.Find('y0'));
      SameHex(what + ' panel x1', ctl.Panels[0].Rect.X + ctl.Panels[0].Rect.W, pn.Find('x1'));
      SameHex(what + ' panel y1', ctl.Panels[0].Rect.Y + ctl.Panels[0].Rect.H, pn.Find('y1'));
      SameHex(what + ' panel other[0]', ctl.Panels[0].Rect.Y, pn.Arrays['other'].Items[0]);
      SameHex(what + ' panel other[1]', ctl.Panels[0].Rect.Y + ctl.Panels[0].Rect.H,
        pn.Arrays['other'].Items[1]);
    end;
  end;
  SameBool(what + ' dragging', ctl.Dragging, c.Booleans['dragging']);
  if ctl.Creating >= 0 then cur := IntToStr(ctl.IndexOf(ctl.Creating)) else cur := '(null)';
  SameStr(what + ' creating', cur, JStr(c.Find('creating')));
  { the covers }
  SameStr(what + ' cover count', IntToStr(Length(ctl.Covers)), IntToStr(c.Arrays['covers'].Count));
  ord_ := ctl.GroupOrder;
  for k := 0 to Min(Length(ctl.Covers), c.Arrays['covers'].Count) - 1 do
  begin
    cov := ctl.Covers[k];
    cv := c.Arrays['covers'].Objects[k];
    what := Format('axis %d cover %d', [AK, k]);
    SameStr(what + ' type', TyBrushTypeName(cov.Opt.BrushType), cv.Strings['brushType']);
    SameStr(what + ' panel', cov.Opt.PanelId, JStr(cv.Find('panelId')));
    SameStr(what + ' range length', IntToStr(Length(cov.Opt.Range) * 2),
      IntToStr(cv.Arrays['range'].Count));
    if Length(cov.Opt.Range) = 1 then
    begin
      SameHex(what + ' range[0]', cov.Opt.Range[0][0], cv.Arrays['range'].Items[0]);
      SameHex(what + ' range[1]', cov.Opt.Range[0][1], cv.Arrays['range'].Items[1]);
    end;
    pos_ := -1;
    for q := 0 to High(ord_) do
      if ord_[q] = k then pos_ := q;
    SameStr(what + ' order', IntToStr(pos_), IntToStr(cv.Integers['order']));
    mn := cv.Objects['main'];
    live := cov.Live;
    SameBool(what + ' main silent', ctl.PieceSilent(k, bpMain), mn.Booleans['silent']);
    if not live then cur := 'move' else cur := ctl.PieceCursor(bpMain, cov.Opt.Transformable);
    SameStr(what + ' main cursor', cur, JStr(mn.Find('cursor')));
    SameBool(what + ' main draggable', True, mn.Booleans['draggable']);
    SameHex(what + ' main x', cov.Main.X, mn.Arrays['rect'].Items[0]);
    SameHex(what + ' main y', cov.Main.Y, mn.Arrays['rect'].Items[1]);
    SameHex(what + ' main width', cov.Main.W, mn.Arrays['rect'].Items[2]);
    SameHex(what + ' main height', cov.Main.H, mn.Arrays['rect'].Items[3]);
    st := mn.Objects['style'];
    SameStr(what + ' fill', InkWord(cov.Opt.Style.Fill, cUpBrushFill), JStr(st.Find('fill')));
    SameStr(what + ' stroke', InkWord(cov.Opt.Style.Stroke, cUpBrushStroke), JStr(st.Find('stroke')));
    SameHex(what + ' lineWidth', cov.Opt.Style.LineWidth, st.Find('lineWidth'));
    { the element's style: an opacity not set is the displayable's 1 }
    if IsNan(cov.Opt.Style.Opacity) then SameHex(what + ' opacity', 1, st.Find('opacity'))
    else SameHex(what + ' opacity', cov.Opt.Style.Opacity, st.Find('opacity'));
    d := cv.Find('handles');
    if (d = nil) or (d.JSONType = jtNull) then
    begin
      Miss(what + ' has no handles upstream');
      Continue;
    end;
    hs := TJSONObject(d);
    for p := bpW to bpE do
    begin
      if hs.Find(TyBrushPieceName(p)) = nil then
      begin
        Miss(what + ' no ' + TyBrushPieceName(p) + ' upstream');
        Continue;
      end;
      h := hs.Objects[TyBrushPieceName(p)];
      SameHex(what + ' ' + TyBrushPieceName(p) + ' x', cov.Handle[p].X, h.Arrays['rect'].Items[0]);
      SameHex(what + ' ' + TyBrushPieceName(p) + ' y', cov.Handle[p].Y, h.Arrays['rect'].Items[1]);
      SameHex(what + ' ' + TyBrushPieceName(p) + ' width', cov.Handle[p].W, h.Arrays['rect'].Items[2]);
      SameHex(what + ' ' + TyBrushPieceName(p) + ' height', cov.Handle[p].H, h.Arrays['rect'].Items[3]);
      SameBool(what + ' ' + TyBrushPieceName(p) + ' silent', ctl.PieceSilent(k, p), h.Booleans['silent']);
      SameBool(what + ' ' + TyBrushPieceName(p) + ' invisible',
        not live or not cov.Opt.Transformable, h.Booleans['invisible']);
      if not live then cur := 'pointer'
      else cur := ctl.PieceCursor(p, cov.Opt.Transformable);
      SameStr(what + ' ' + TyBrushPieceName(p) + ' cursor', cur, JStr(h.Find('cursor')));
    end;
  end;
end;

procedure TAdvChartParallelBrushOracleTest.CheckRows(ARec: TJSONObject);
var
  rows, items: TJSONArray;
  r, i, k, si: Integer;
  sol: TTyParallelSolved;
  found: Boolean;
begin
  rows := ARec.Arrays['rows'];
  for r := 0 to rows.Count - 1 do
  begin
    si := rows.Objects[r].Integers['seriesIndex'];
    items := rows.Objects[r].Arrays['items'];
    sol := FChart.ParallelSolvedOf(si);
    if not sol.Valid then
    begin
      Miss(Format('series %d is not solved', [si]));
      Continue;
    end;
    for i := 0 to items.Count - 1 do
    begin
      found := False;
      for k := 0 to High(sol.Rows) do
        if sol.Rows[k].Row = i then
        begin
          found := True;
          SameHex(Format('series %d row %d opacity', [si, i]), sol.Rows[k].Opacity,
            items.Objects[i].Find('opacity'));
          SameStr(Format('series %d row %d active', [si, i]), ActiveWord(sol.Rows[k].Active),
            items.Objects[i].Strings['active']);
        end;
      if not found then Miss(Format('series %d has no row %d', [si, i]));
    end;
  end;
end;

procedure TAdvChartParallelBrushOracleTest.CheckActions(ARec: TJSONObject);
var
  acts: TJSONArray;
  i, k, n: Integer;
  a: TTyParallelBrushAction;
  w: TJSONObject;
begin
  acts := ARec.Arrays['actions'];
  n := FChart.ParallelBrushActionCount - FActSeen;
  SameStr('the view action count', IntToStr(n), IntToStr(acts.Count));
  for i := 0 to Min(n, acts.Count) - 1 do
  begin
    a := FChart.ParallelBrushActionAt(FActSeen + i);
    w := acts.Objects[i];
    SameStr(Format('action %d axis id', [i]), Nul(a.AxisId), w.Strings['parallelAxisId']);
    SameStr(Format('action %d interval count', [i]), IntToStr(Length(a.Intervals)),
      IntToStr(w.Arrays['intervals'].Count));
    for k := 0 to Min(Length(a.Intervals), w.Arrays['intervals'].Count) - 1 do
    begin
      SameHex(Format('action %d interval %d [0]', [i, k]), a.Intervals[k][0],
        w.Arrays['intervals'].Arrays[k].Items[0]);
      SameHex(Format('action %d interval %d [1]', [i, k]), a.Intervals[k][1],
        w.Arrays['intervals'].Arrays[k].Items[1]);
    end;
  end;
  FActSeen := FChart.ParallelBrushActionCount;
end;

procedure TAdvChartParallelBrushOracleTest.CheckEvents(ARec: TJSONObject);
var
  evs, ivs, bt: TJSONArray;
  i, k, n: Integer;
  e, pj: TJSONObject;
  line, t, pl: string;
  d, pd: TJSONData;
begin
  evs := ARec.Arrays['events'];
  n := FChart.Events.Count - FEvSeen;
  SameStr('the event count', IntToStr(n), IntToStr(evs.Count));
  for i := 0 to Min(n, evs.Count) - 1 do
  begin
    line := FChart.Events[FEvSeen + i];
    t := Copy(line, 1, Pos(#9, line) - 1);
    pl := Copy(line, Pos(#9, line) + 1, MaxInt);
    e := evs.Objects[i];
    SameStr(Format('event %d type', [i]), t, e.Strings['type']);
    if t <> e.Strings['type'] then Continue;
    pd := nil;
    try
      try
        pd := GetJSON(StringReplace(pl, '\u0000', '<NUL>', [rfReplaceAll]));
      except
        pd := nil;
      end;
      SameBool(Format('event %d payload parses', [i]), pd is TJSONObject, True);
      if not (pd is TJSONObject) then Continue;
      pj := TJSONObject(pd);
      if t = 'axisareaselected' then
      begin
        d := pj.Find('parallelAxisId');
        SameStr(Format('event %d parallelAxisId', [i]), JStr(d), JStr(e.Find('parallelAxisId')));
        ivs := e.Arrays['intervals'];
        d := pj.Find('intervals');
        if not (d is TJSONArray) then
        begin
          Miss(Format('event %d has no intervals', [i]));
          Continue;
        end;
        SameStr(Format('event %d interval count', [i]), IntToStr(d.Count), IntToStr(ivs.Count));
        for k := 0 to Min(d.Count, ivs.Count) - 1 do
        begin
          SameStr(Format('event %d interval %d [0]', [i, k]),
            TyJsNumberToString(TJSONArray(d).Arrays[k].Items[0].AsFloat), ivs.Arrays[k].Strings[0]);
          SameStr(Format('event %d interval %d [1]', [i, k]),
            TyJsNumberToString(TJSONArray(d).Arrays[k].Items[1].AsFloat), ivs.Arrays[k].Strings[1]);
        end;
      end
      else
      begin
        bt := e.Arrays['batch'];
        d := pj.Find('batch');
        if not (d is TJSONArray) then
        begin
          Miss(Format('event %d has no batch', [i]));
          Continue;
        end;
        SameStr(Format('event %d batch', [i]), IntToStr(d.Count), IntToStr(bt.Count));
        for k := 0 to Min(d.Count, bt.Count) - 1 do
          if TJSONArray(d).Items[k] is TJSONObject then
            SameStr(Format('event %d batch %d areas', [i, k]),
              IntToStr(TJSONObject(TJSONArray(d).Items[k]).Arrays['areas'].Count),
              IntToStr(bt.Objects[k].Integers['areas']));
      end;
    finally
      pd.Free;
    end;
  end;
  FEvSeen := FChart.Events.Count;
end;

procedure TAdvChartParallelBrushOracleTest.CheckRecord(ARec: TJSONObject; AStep: TJSONObject);
var
  d: TJSONData;
  k: Integer;
  cur, want: string;
  lo, hi: Double;
begin
  d := ARec.Find('axes');
  if d is TJSONArray then
  begin
    if Length(FAxes) < d.Count then SetLength(FAxes, d.Count);
    for k := 0 to d.Count - 1 do
      if d.Items[k].JSONType <> jtNull then
      begin
        FreeAndNil(FAxes[k]);
        FAxes[k] := d.Items[k].Clone;
      end;
  end;
  for k := 0 to High(FAxes) do CheckAxis(k);
  CheckRows(ARec);
  { the cursor of a move: the brush's own words, else none of the brush's }
  if (AStep <> nil) and (AStep.Strings['type'] = 'mousemove') then
  begin
    want := JStr(ARec.Find('cursor'));
    cur := FChart.BrushCursorName;
    if (want = 'crosshair') or (want = 'move') or (Pos('-resize', want) > 0) then
      SameStr('the cursor', cur, want)
    else
      SameStr('the cursor (not the brush''s: ' + want + ')', cur, '');
  end;
  CheckActions(ARec);
  CheckEvents(ARec);
  d := ARec.Find('zoom');
  if d is TJSONArray then
  begin
    SameBool('the inside dataZoom is there', FChart.DataZoomInsideRange(0, lo, hi), True);
    SameHex('dataZoom start', lo, d.Items[0]);
    SameHex('dataZoom end', hi, d.Items[1]);
  end;
  SameBool('globalPan held', FChart.BrushGlobalPanTaken, ARec.Booleans['panTaken']);
end;

procedure TAdvChartParallelBrushOracleTest.RunScenario(ASc: TJSONObject);
var
  steps: TJSONArray;
  st, rec: TJSONObject;
  i, x, y, k: Integer;
  typ, hov, mine: string;
begin
  FName := ASc.Strings['id'];
  NewChart;
  for k := 0 to High(FAxes) do FreeAndNil(FAxes[k]);
  FAxes := nil;
  FActSeen := 0;
  FEvSeen := 0;
  FClock := 1700000000000;
  FChart.BrushNow := FClock;
  FChart.DataZoomNow := FClock;
  FChart.SetOption(ASc.Objects['option'].AsJSON, True);
  RenderNow;
  FStepNo := -1;
  CheckRecord(ASc.Objects['initial'], nil);
  steps := ASc.Arrays['steps'];
  for i := 0 to steps.Count - 1 do
  begin
    FStepNo := i;
    Inc(FSteps);
    st := steps.Objects[i].Objects['step'];
    rec := steps.Objects[i].Objects['record'];
    typ := st.Strings['type'];
    FClock := FClock + st.Floats['dt'];
    FChart.BrushNow := FClock;
    FChart.BrushTick(FClock);
    FChart.DataZoomNow := FClock;
    FChart.DataZoomTick(FClock);
    if (typ = 'mousemove') or (typ = 'mousedown') or (typ = 'mouseup') or (typ = 'click') then
    begin
      x := st.Integers['x'];
      y := st.Integers['y'];
      { the piece the Handler finds before the step: a parallel axis'
        (the oracle does not name a brush component's) }
      hov := JStr(steps.Objects[i].Find('hover'));
      mine := RoleAt(x, y);
      if (Pos('axis', hov) = 1) or (Pos('axis', mine) = 1) then
        SameStr('the hover', mine, hov);
      if typ = 'mousemove' then FChart.Move(x, y)
      else if typ = 'mousedown' then FChart.Down(x, y)
      else if typ = 'mouseup' then FChart.Up(x, y);
    end
    else if typ = 'action' then
      FChart.DispatchAction(st.Objects['payload'].AsJSON)
    else if typ = 'set' then
      FChart.SetOption(st.Objects['option'].AsJSON, st.Get('notMerge', False));
    RenderNow;
    CheckRecord(rec, st);
  end;
end;

procedure TAdvChartParallelBrushOracleTest.RunGroup(const AIds: array of string);
var
  sc: TJSONArray;
  i, k, ran: Integer;
begin
  sc := TJSONObject(FRoot).Arrays['scenarios'];
  ran := 0;
  for i := 0 to sc.Count - 1 do
    for k := 0 to High(AIds) do
      if sc.Objects[i].Strings['id'] = AIds[k] then
      begin
        RunScenario(sc.Objects[i]);
        Inc(ran);
      end;
  AssertEquals('the group ran its cases', Length(AIds), ran);
  AssertTrue('compared something', FCompared > 0);
  if GetEnvironmentVariable('TY_PARALLELBRUSH_COUNTS') = '1' then
    WriteLn(Format('parallel brush %s: %d comparisons over %d steps',
      [AIds[0], FCompared, FSteps]));
  if FBad > 0 then
    Fail(Format('%d of %d comparisons over %d steps differ from upstream:%s',
      [FBad, FCompared, FSteps, FReport]));
end;

procedure TAdvChartParallelBrushOracleTest.TestHorizontalAndVerticalAsUpstream;
begin
  RunGroup(['H-VALUE', 'V-VALUE']);
end;

procedure TAdvChartParallelBrushOracleTest.TestTheAxisTypesAsUpstream;
begin
  RunGroup(['T-TYPES']);
end;

procedure TAdvChartParallelBrushOracleTest.TestTheActionAndManyIntervalsAsUpstream;
begin
  RunGroup(['M-MULTI']);
end;

procedure TAdvChartParallelBrushOracleTest.TestMovingAndResizingAsUpstream;
begin
  RunGroup(['D-DRAG']);
end;

procedure TAdvChartParallelBrushOracleTest.TestRealtimeAsUpstream;
begin
  RunGroup(['RT-OFF']);
end;

procedure TAdvChartParallelBrushOracleTest.TestTheAreaSelectStyleAsUpstream;
begin
  RunGroup(['S-STYLE']);
end;

procedure TAdvChartParallelBrushOracleTest.TestGlobalPanAsUpstream;
begin
  RunGroup(['G-PAN']);
end;

{ ==================== by hand ==================== }

const
  cRows = '[[12,85,40],[30,22,95],[47,61,8],[55,38,72],[68,9,26],[79,74,53]]';
  cPar = '{"animation":false,"backgroundColor":"#ffffff",'
    + '"parallelAxis":[{"dim":0,"min":0,"max":100},{"dim":1,"min":0,"max":100},'
    + '{"dim":2,"min":0,"max":100}],"series":[{"type":"parallel","data":' + cRows + '}]';

procedure TAdvChartParallelBrushTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TPbProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.AnimationMode := camOff;
  FChart.BrushNow := 1700000000000;
end;

procedure TAdvChartParallelBrushTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartParallelBrushTest.Show(const AOption: string);
begin
  FChart.SetOption(AOption, True);
  RenderNow;
end;

procedure TAdvChartParallelBrushTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height), 96);
  finally
    bmp.Free;
  end;
end;

{ a red band laid along the middle axis (x 300, horizontal layout) by the
  action and the update after it: drawn there and only there }
procedure TAdvChartParallelBrushTest.TestTheCoversAreDrawnAlongTheAxis;
var
  bmp: TBGRABitmap;
  bare: Integer;

  function Count(AX0, AY0, AX1, AY1: Integer; ARed: Boolean): Integer;
  var xx, yy: Integer; q: TBGRAPixel;
  begin
    Result := 0;
    for yy := AY0 to AY1 do
      for xx := AX0 to AX1 do
      begin
        q := bmp.GetPixel(xx, yy);
        if ARed then
        begin
          if (q.red > 200) and (q.green < 140) and (q.blue < 140) then Inc(Result);
        end
        else if (q.red < 250) or (q.green < 250) or (q.blue < 250) then Inc(Result);
      end;
  end;

  procedure Paint;
  begin
    bmp.Fill(BGRA(255, 255, 255, 255));
    FChart.Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
  end;

begin
  Show(cPar + ',"parallel":{"parallelAxisDefault":{"areaSelectStyle":'
    + '{"color":"#ff0000","borderColor":"#ff0000","opacity":1}}}}');
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  try
    Paint;
    bare := Count(292, 190, 308, 270, False);
    { a drag up the middle axis (x 300, from y 340 up to 60): 20..60 of
      0..100 is y 172..284, 20 px across; the cover drawn is the
      controller's, in the areaSelectStyle }
    FChart.Move(300, 284);
    FChart.Down(300, 284);
    FChart.Move(300, 230);
    FChart.Move(300, 172);
    FChart.Up(300, 172);
    Paint;
    AssertEquals('one cover', 1, Length(FChart.ParallelBrushOf(1).Covers));
    AssertTrue('the band is drawn on the axis', Count(292, 190, 308, 270, True) > 1000);
    AssertEquals('nothing on the other axes', 0, Count(70, 190, 90, 270, True)
      + Count(510, 190, 530, 270, True));
    AssertEquals('nothing above the band', 0, Count(292, 100, 308, 150, True));
    { an update lays the cover again from the interval: over the dist's
      DEFAULT_BRUSH_OPT -- the brush's default look, not the red }
    FChart.SetOption('{}', False);
    Paint;
    AssertEquals('still one cover', 1, Length(FChart.ParallelBrushOf(1).Covers));
    AssertEquals('no red now', 0, Count(292, 190, 308, 270, True));
    AssertTrue('the brush''s default band', Count(292, 190, 308, 270, False) > bare + 500);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartParallelBrushTest.TestTheEventsCanBeSubscribed;
var
  log: TStringList;
  ids: array[0..4] of Integer;
  i: Integer;
const
  cTypes: array[0..4] of string = ('axisAreaSelected', 'brushSelected', 'brush', 'brushEnd',
    'globalCursorTaken');
begin
  Show(cPar + '}');
  { upstream lowercases the name it is given; every one of these is a
    chart event }
  for i := 0 to High(cTypes) do
  begin
    ids[i] := FChart.ChartOn(cTypes[i], @FChart.OnEv);
    AssertTrue(cTypes[i] + ' is subscribed', ids[i] > 0);
  end;
  log := FChart.Events;
  log.Clear;
  FChart.OnChartEvent := nil;
  FChart.DispatchAction('{"type":"axisAreaSelect","parallelAxisIndex":0,"intervals":[[10,40]]}');
  AssertEquals('both through ChartOn', 2, log.Count);
  AssertEquals('axisareaselected first', 'axisareaselected', Copy(log[0], 1, Pos(#9, log[0]) - 1));
  AssertEquals('then brushselected', 'brushselected', Copy(log[1], 1, Pos(#9, log[1]) - 1));
  AssertTrue('the payload has the intervals', Pos('"intervals":[[10,40]]', log[0]) > 0);
  { a drag on the axis dispatches the action from the view: its event too }
  log.Clear;
  FChart.Move(300, 300);
  FChart.Down(300, 300);
  FChart.Move(300, 200);
  FChart.Up(300, 200);
  RenderNow;
  AssertTrue('the view''s action is heard', (log.Count >= 2)
    and (Copy(log[0], 1, Pos(#9, log[0]) - 1) = 'axisareaselected'));
  for i := 0 to High(ids) do FChart.ChartOff(ids[i]);
  log.Clear;
  FChart.DispatchAction('{"type":"axisAreaSelect","intervals":[]}');
  AssertEquals('off', 0, log.Count);
end;

{ fromAxisAreaSelect lasts until an update renders the view again: the paint
  that follows the action (its relayout) is not one }
procedure TAdvChartParallelBrushTest.TestTheNamedAxisWaitsForTheNextUpdate;
var bmp: TBGRABitmap;
begin
  Show(cPar + '}');
  FChart.DispatchAction('{"type":"axisAreaSelect","parallelAxisIndex":2,"intervals":[[10,30],[50,70]]}');
  RenderNow;
  RenderNow;
  AssertEquals('the paints lay nothing', 0, Length(FChart.ParallelBrushOf(2).Covers));
  AssertEquals('the rows took the intervals', 2, Length(FChart.ParallelIntervals(2)));
  { an action naming another axis renders this one }
  FChart.DispatchAction('{"type":"axisAreaSelect","parallelAxisIndex":0,"intervals":[]}');
  AssertEquals('another axis'' action lays both', 2, Length(FChart.ParallelBrushOf(2).Covers));
  { a resize renders every view: the axis the action named too }
  FChart.DispatchAction('{"type":"axisAreaSelect","parallelAxisIndex":2,"intervals":[[5,15]]}');
  RenderNow;
  AssertEquals('still the two', 2, Length(FChart.ParallelBrushOf(2).Covers));
  bmp := TBGRABitmap.Create(cW - 20, cH, BGRA(255, 255, 255, 255));
  try
    FChart.SetBounds(0, 0, cW - 20, cH);
    FChart.Render(bmp.Canvas, Rect(0, 0, cW - 20, cH), 96);
  finally
    bmp.Free;
  end;
  AssertEquals('the resize lays the one', 1, Length(FChart.ParallelBrushOf(2).Covers));
end;

procedure TAdvChartParallelBrushTest.TestNotMergeDropsTheControllers;
begin
  Show(cPar + '}');
  FChart.Move(300, 300);
  FChart.Down(300, 300);
  FChart.Move(300, 200);
  FChart.Up(300, 200);
  RenderNow;
  AssertEquals('a cover', 1, Length(FChart.ParallelBrushOf(1).Covers));
  AssertEquals('an interval', 1, Length(FChart.ParallelIntervals(1)));
  { a merge keeps both }
  FChart.SetOption('{"series":[{"lineStyle":{"width":2}}]}', False);
  RenderNow;
  AssertEquals('kept by a merge', 1, Length(FChart.ParallelBrushOf(1).Covers));
  { notMerge: new models, new views }
  FChart.SetOption(cPar + '}', True);
  RenderNow;
  AssertEquals('no interval', 0, Length(FChart.ParallelIntervals(1)));
  AssertEquals('no cover', 0, Length(FChart.ParallelBrushOf(1).Covers));
  { no parallel: no controllers }
  FChart.SetOption('{"animation":false,"xAxis":{},"yAxis":{},"series":[{"type":"line","data":[1,2]}]}', True);
  RenderNow;
  AssertTrue('none', FChart.ParallelBrushOf(0) = nil);
end;

procedure TAdvChartParallelBrushTest.TestACoverHidesTheRowBeneath;
var
  el, b, i: Integer;
  d: TTyChartDatumRef;
  p: TTyBrushPiece;
begin
  Show(cPar + '}');
  { the first row crosses axis 1 (x 300) at 85 of 100: y 102 }
  d := FChart.HitTestAt(300, 102, el);
  AssertEquals('the row answers, no cover there', 0, d.SeriesIndex);
  AssertFalse('no cover hit', FChart.BrushHitTest(300, 102, b, i, p));
  FChart.DispatchAction('{"type":"axisAreaSelect","parallelAxisIndex":1,"intervals":[[80,90]]}');
  FChart.SetOption('{}', False);
  RenderNow;
  AssertTrue('axis 1 has its cover now', Length(FChart.ParallelBrushOf(1).Covers) = 1);
  AssertTrue('the cover is hit', FChart.BrushHitTest(300, 102, b, i, p));
  AssertEquals('axis 1''s', TyParallelBrushBase + 1, b);
  d := FChart.HitTestAt(300, 102, el);
  AssertEquals('the row beneath does not answer', -1, d.SeriesIndex);
end;

procedure TAdvChartParallelBrushTest.TestTheHelpers;
var
  r: TTyXYWH;
  ss: TTyParallelSelectStyle;
  d: TJSONData;
  c: TTyBrushController;
  lx, ly: Double;
begin
  { an inverse extent turns over; the extra is 10% up to 30 }
  r := TyParallelBrushPanelRect(280, 0, 20);
  AssertEquals('x', -28, r.X, 0);
  AssertEquals('w', 336, r.W, 0);
  AssertEquals('y', -10, r.Y, 0);
  AssertEquals('h', 20, r.H, 0);
  r := TyParallelBrushPanelRect(0, 440, 40);
  AssertEquals('the extra is at most 30', -30, r.X, 0);
  AssertEquals('w', 500, r.W, 0);
  { the defaults, a written width and colour, a null border }
  ss := TyParallelSelectStyleOf(nil);
  AssertEquals('width', 20, ss.Width, 0);
  AssertEquals('border', 1, ss.Style.LineWidth, 0);
  AssertEquals('opacity', 0.3, ss.Style.Opacity, 0);
  AssertFalse('the skin''s fill', ss.Style.Fill.Written);
  d := GetJSON('{"areaSelectStyle":{"width":30,"color":"#00ff00","borderWidth":null}}');
  try
    ss := TyParallelSelectStyleOf(d);
  finally
    d.Free;
  end;
  AssertEquals('written width', 30, ss.Width, 0);
  AssertTrue('written fill', ss.Style.Fill.Written and (ss.Style.Fill.Text = '#00ff00'));
  AssertTrue('a null border leaves the brush''s', IsNan(ss.Style.LineWidth));
  AssertEquals('the brush''s border then', 2, TyParallelBrushOpt(ss).Style.LineWidth, 0);
  { a turned controller: the pointer comes in local, a lineX handle's
    cursor goes vertical }
  c := TTyBrushController.Create;
  try
    AssertEquals('unmounted: ew', 'ew-resize', c.PieceCursor(bpW, True));
    c.Mount(190, 340, Pi / 2);
    AssertTrue('an inverse', c.HasInv);
    c.ToLocal(190, 240, lx, ly);
    AssertEquals('100 up the axis', 100, lx, 1e-9);
    AssertEquals('on it', 0, ly, 1e-9);
    AssertEquals('turned: ns', 'ns-resize', c.PieceCursor(bpW, True));
    AssertEquals('turned: ns', 'ns-resize', c.PieceCursor(bpE, True));
    AssertEquals('the main moves', 'move', c.PieceCursor(bpMain, True));
    c.Mount(0, 0, 0);
    AssertFalse('nothing to undo: no inverse', c.HasInv);
  finally
    c.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartParallelBrushOracleTest);
  RegisterTest(TAdvChartParallelBrushTest);
end.
