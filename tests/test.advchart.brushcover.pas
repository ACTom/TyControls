unit test.advchart.brushcover;
{$mode objfpc}{$H+}
{ The brush component's covers -- held to upstream to the bit [Batch 126,
  C17].

  tools/advchart-oracle/brush-cover.js runs the real ECharts 6.1 build
  through cases of pointer steps on zrender's own Handler, actions and
  merges, on a fake clock, and records after every step: each brush
  component's panels, its controller (on or off, the painting option, the
  track, the covers -- their ranges, their main shapes and handles, which of
  them answer the pointer and with what cursor), the areas its model keeps
  (range, coordRange, coordRanges, the round trip's offset), the cursor the
  pointer got, the brush / brushend / globalcursortaken events with their
  areas, and the brushSelect dispatches the throttle ran.

  The port is driven the same way -- MouseMove / MouseDown / MouseUp,
  DispatchAction, SetOption -- on the same clock (BrushNow / BrushTick),
  with a headless render after each step. A click is part of the port's
  MouseUp; the click step itself changes nothing upstream. Compared through
  the chart's own API: BrushControllerOf, BrushModelAreas, BrushHitTest,
  BrushCursorName, BrushEventAt, BrushSelectAt and the chart events. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Events, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Brush, tyControls.AdvanceChart.Export,
     tyControls.AdvanceChart;
type
  TBcProbe = class(TTyAdvanceChart)
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

  TAdvChartBrushCoverOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TBcProbe;
    FRoot: TJSONData;
    FBad, FCompared, FSteps, FStepNo: Integer;
    FReport, FName: string;
    FClock: Double;
    { upstream's state carried forward: a record's null fields are the
      record before's }
    FPanels: TJSONArray;
    FBrushes: array of TJSONData;
    { the port's logs read so far }
    FEvSeen, FSelSeen, FChartEvSeen: Integer;
    procedure Miss(const AWhat: string);
    procedure SameHex(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure SameRange(const AWhat: string; const AGot: TTyBrushRange;
      ALine: Boolean; AWant: TJSONData);
    procedure NewChart;
    procedure RenderNow;
    function RoleAt(AX, AY: Integer): string;
    procedure CheckPanels;
    procedure CheckBrush(AB: Integer);
    procedure CheckArea(const AWhat: string; const A: TTyBrushArea; AW: TJSONObject;
      AOutput: Boolean);
    procedure CheckEvents(ARec: TJSONObject);
    procedure CheckSelects(ARec: TJSONObject);
    procedure CheckRecord(ARec: TJSONObject; AStep: TJSONObject);
    procedure RunScenario(ASc: TJSONObject);
    procedure RunGroup(const APrefixes: array of string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRectCoversAsUpstream;
    procedure TestModesAndShapesAsUpstream;
    procedure TestPanelsAndTheActionAsUpstream;
    procedure TestStyleAndSwitchingAsUpstream;
    procedure TestTheThrottleAsUpstream;
  end;

  { What the oracle does not reach. }
  TAdvChartBrushCoverTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TBcProbe;
    procedure Show(const AOption: string);
    procedure RenderNow;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheCoversAreDrawnAndStayInTheExport;
    procedure TestACoverHidesTheItemBeneath;
    procedure TestTheActionNamesOneBrush;
    procedure TestNotMergeDropsTheAreasAndTheBrush;
    procedure TestTheEventPayloadIsJson;
    procedure TestTheGeometryHelpers;
  end;

implementation

const
  cW = 600;
  cH = 400;
  cUpFill = 'rgba(234,237,245,0.5)';
  cUpStroke = '#cfd2d7';

{ ==================== the probe ==================== }

constructor TBcProbe.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Events := TStringList.Create;
  OnChartEvent := @OnEv;
end;

destructor TBcProbe.Destroy;
begin
  Events.Free;
  inherited Destroy;
end;

procedure TBcProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TBcProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
end;

procedure TBcProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TBcProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

procedure TBcProbe.OnEv(Sender: TObject; const AEvent: TTyChartEvent);
begin
  if (AEvent.EventType = 'brush') or (AEvent.EventType = 'brushend')
    or (AEvent.EventType = 'globalcursortaken') then
    Events.Add(AEvent.EventType + #9 + AEvent.Payload);
end;

{ ==================== the fixture's numbers ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-brush-cover.json';
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

{ ==================== the oracle test ==================== }

procedure TAdvChartBrushCoverOracleTest.SetUp;
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

procedure TAdvChartBrushCoverOracleTest.TearDown;
var i: Integer;
begin
  FreeAndNil(FPanels);
  for i := 0 to High(FBrushes) do FreeAndNil(FBrushes[i]);
  FBrushes := nil;
  FreeAndNil(FRoot);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartBrushCoverOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if (FBad <= 400) and (Pos(FName + ': ' + AWhat, FReport) = 0) then
    FReport := FReport + LineEnding + '  ' + FName + ' @' + IntToStr(FStepNo) + ': ' + AWhat;
end;

procedure TAdvChartBrushCoverOracleTest.SameHex(const AWhat: string; AGot: Double;
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

procedure TAdvChartBrushCoverOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

procedure TAdvChartBrushCoverOracleTest.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is %s upstream, %s here', [AWhat, BoolToStr(AWant, True),
      BoolToStr(AGot, True)]));
end;

{ a range against upstream's nesting: a line's pair, else pairs }
procedure TAdvChartBrushCoverOracleTest.SameRange(const AWhat: string;
  const AGot: TTyBrushRange; ALine: Boolean; AWant: TJSONData);
var i: Integer;
begin
  if (AWant = nil) or (AWant.JSONType = jtNull) then
  begin
    SameStr(AWhat + ' (absent)', IntToStr(Length(AGot)), '0');
    Exit;
  end;
  if ALine then
  begin
    SameStr(AWhat + ' length', IntToStr(Length(AGot) * 2), IntToStr(AWant.Count));
    if (Length(AGot) = 1) and (AWant.Count = 2) then
    begin
      SameHex(AWhat + '[0]', AGot[0][0], AWant.Items[0]);
      SameHex(AWhat + '[1]', AGot[0][1], AWant.Items[1]);
    end;
    Exit;
  end;
  SameStr(AWhat + ' length', IntToStr(Length(AGot)), IntToStr(AWant.Count));
  for i := 0 to Min(Length(AGot), AWant.Count) - 1 do
  begin
    SameHex(Format('%s[%d][0]', [AWhat, i]), AGot[i][0], AWant.Items[i].Items[0]);
    SameHex(Format('%s[%d][1]', [AWhat, i]), AGot[i][1], AWant.Items[i].Items[1]);
  end;
end;

procedure TAdvChartBrushCoverOracleTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TBcProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.AnimationMode := camOff;
end;

procedure TAdvChartBrushCoverOracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height), 96);
  finally
    bmp.Free;
  end;
end;

function TAdvChartBrushCoverOracleTest.RoleAt(AX, AY: Integer): string;
var b, i: Integer; p: TTyBrushPiece;
begin
  if FChart.BrushHitTest(AX, AY, b, i, p) then
    Result := Format('brush%d.cover%d.%s', [b, i, TyBrushPieceName(p)])
  else
    Result := '';
end;

procedure TAdvChartBrushCoverOracleTest.CheckPanels;
var
  b, i: Integer;
  ctl: TTyBrushController;
  pl: TJSONData;
  p: TJSONObject;
  what: string;
begin
  if FPanels = nil then Exit;
  for b := 0 to FPanels.Count - 1 do
  begin
    ctl := FChart.BrushControllerOf(b);
    if ctl = nil then
    begin
      Miss(Format('brush %d has no controller', [b]));
      Continue;
    end;
    pl := FPanels.Items[b];
    if pl.JSONType = jtNull then
    begin
      SameBool(Format('brush %d has panels', [b]), ctl.HasPanels, False);
      Continue;
    end;
    SameBool(Format('brush %d has panels', [b]), ctl.HasPanels, True);
    SameStr(Format('brush %d panel count', [b]), IntToStr(Length(ctl.Panels)), IntToStr(pl.Count));
    for i := 0 to Min(pl.Count, Length(ctl.Panels)) - 1 do
    begin
      p := TJSONObject(pl.Items[i]);
      what := Format('brush %d panel %d', [b, i]);
      SameStr(what + ' id', Nul(ctl.Panels[i].Id), p.Strings['panelId']);
      SameHex(what + ' x', ctl.Panels[i].Rect.X, p.Arrays['rect'].Items[0]);
      SameHex(what + ' y', ctl.Panels[i].Rect.Y, p.Arrays['rect'].Items[1]);
      SameHex(what + ' width', ctl.Panels[i].Rect.W, p.Arrays['rect'].Items[2]);
      SameHex(what + ' height', ctl.Panels[i].Rect.H, p.Arrays['rect'].Items[3]);
    end;
  end;
end;

function InkWord(const AInk: TTyBrushInk; const ATheme: string): string;
begin
  if AInk.Written then Result := AInk.Text else Result := ATheme;
end;

procedure TAdvChartBrushCoverOracleTest.CheckArea(const AWhat: string;
  const A: TTyBrushArea; AW: TJSONObject; AOutput: Boolean);
var
  ln: Boolean;
  d: TJSONData;
  k: Integer;
begin
  ln := A.Opt.BrushType in [btLineX, btLineY];
  SameStr(AWhat + ' type', TyBrushTypeName(A.Opt.BrushType), AW.Strings['brushType']);
  d := AW.Find('id');
  if (d <> nil) and (d.JSONType = jtString) then
    SameStr(AWhat + ' id', A.Opt.Id, d.AsString);
  d := AW.Find('panelId');
  if (d = nil) or (d.JSONType = jtNull) then
    SameBool(AWhat + ' has a panel', A.Opt.HasPanel and (A.Opt.PanelId <> ''), False)
  else
    SameStr(AWhat + ' panel', Nul(A.Opt.PanelId), d.AsString);
  d := AW.Find('range');
  if (d <> nil) and (d.JSONType <> jtNull) then SameRange(AWhat + ' range', A.Opt.Range, ln, d);
  d := AW.Find('coordRange');
  if (d <> nil) and (d.JSONType <> jtNull) then
    SameRange(AWhat + ' coordRange', A.CoordRange, ln, d)
  else if AOutput then
    SameBool(AWhat + ' has a coordRange', A.HasCoordRange, False);
  d := AW.Find('coordRanges');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    SameStr(AWhat + ' coordRanges', IntToStr(Length(A.CoordRanges)), IntToStr(d.Count));
    for k := 0 to Min(d.Count, Length(A.CoordRanges)) - 1 do
      SameRange(Format('%s coordRanges[%d]', [AWhat, k]), A.CoordRanges[k], ln, d.Items[k]);
  end;
  d := AW.Find('rangeOffset');
  if (d <> nil) and (d.JSONType = jtObject) then
  begin
    SameBool(AWhat + ' has an offset', A.HasOffset, True);
    SameRange(AWhat + ' offset', A.Offset, ln, TJSONObject(d).Find('offset'));
    SameRange(AWhat + ' xyMinMax', A.OffsetXY, False, TJSONObject(d).Find('xyMinMax'));
  end
  else if AOutput then
    SameBool(AWhat + ' has an offset', A.HasOffset, False);
end;

procedure TAdvChartBrushCoverOracleTest.CheckBrush(AB: Integer);
var
  w, o, st, cv, mn, hs, h: TJSONObject;
  ctl: TTyBrushController;
  c: TTyBrushCover;
  ord_: TTyIntegerArray;
  k, q, pos_: Integer;
  what, kind, cur, en: string;
  p: TTyBrushPiece;
  areas: TTyBrushAreaArray;
  d: TJSONData;
  live: Boolean;
begin
  if (AB > High(FBrushes)) or (FBrushes[AB] = nil) then Exit;
  w := TJSONObject(FBrushes[AB]);
  ctl := FChart.BrushControllerOf(AB);
  if ctl = nil then
  begin
    Miss(Format('brush %d has no controller', [AB]));
    Exit;
  end;
  { the controller }
  if ctl.Enabled then en := TyBrushTypeName(ctl.Opt.BrushType) else en := '(null)';
  SameStr(Format('brush %d enabled', [AB]), en, JStr(w.Find('enabled')));
  d := w.Find('option');
  if (d <> nil) and (d.JSONType = jtObject) and ctl.Enabled then
  begin
    o := TJSONObject(d);
    what := Format('brush %d option', [AB]);
    SameStr(what + ' type', TyBrushTypeName(ctl.Opt.BrushType), o.Strings['brushType']);
    SameBool(what + ' multiple', ctl.Opt.Multiple, o.Strings['brushMode'] <> 'single');
    SameBool(what + ' transformable', ctl.Opt.Transformable, o.Booleans['transformable']);
    SameBool(what + ' removeOnClick', ctl.Opt.RemoveOnClick, o.Booleans['removeOnClick']);
    st := o.Objects['style'];
    SameStr(what + ' fill', InkWord(ctl.Opt.Style.Fill, cUpFill), st.Strings['fill']);
    SameStr(what + ' stroke', InkWord(ctl.Opt.Style.Stroke, cUpStroke), st.Strings['stroke']);
    SameStr(what + ' lineWidth', Fmt(ctl.Opt.Style.LineWidth), Fmt(st.Floats['lineWidth']));
  end;
  SameBool(Format('brush %d dragging', [AB]), ctl.Dragging, w.Booleans['dragging']);
  if ctl.Creating >= 0 then cur := IntToStr(ctl.IndexOf(ctl.Creating)) else cur := '(null)';
  SameStr(Format('brush %d creating', [AB]), cur, JStr(w.Find('creating')));
  { the covers }
  SameStr(Format('brush %d cover count', [AB]), IntToStr(Length(ctl.Covers)),
    IntToStr(w.Arrays['covers'].Count));
  ord_ := ctl.GroupOrder;
  for k := 0 to Min(Length(ctl.Covers), w.Arrays['covers'].Count) - 1 do
  begin
    c := ctl.Covers[k];
    cv := w.Arrays['covers'].Objects[k];
    what := Format('brush %d cover %d', [AB, k]);
    SameStr(what + ' type', TyBrushTypeName(c.Opt.BrushType), cv.Strings['brushType']);
    if cv.Find('panelId').JSONType = jtNull then
      SameBool(what + ' has a panel', c.Opt.HasPanel, False)
    else
      SameStr(what + ' panel', Nul(c.Opt.PanelId), cv.Strings['panelId']);
    if cv.Find('id').JSONType = jtString then SameStr(what + ' id', c.Opt.Id, cv.Strings['id'])
    else SameBool(what + ' has an id', c.Opt.HasId, False);
    SameRange(what + ' range', c.Opt.Range, c.Opt.BrushType in [btLineX, btLineY], cv.Find('range'));
    SameBool(what + ' multiple', c.Opt.Multiple, cv.Strings['brushMode'] <> 'single');
    SameBool(what + ' transformable', c.Opt.Transformable, cv.Booleans['transformable']);
    SameBool(what + ' removeOnClick', c.Opt.RemoveOnClick, cv.Booleans['removeOnClick']);
    pos_ := -1;
    for q := 0 to High(ord_) do
      if ord_[q] = k then pos_ := q;
    SameStr(what + ' order', IntToStr(pos_), IntToStr(cv.Integers['order']));
    mn := cv.Objects['main'];
    if c.Opt.BrushType = btPolygon then
    begin
      if c.Closed then kind := 'polygon' else kind := 'polyline';
    end
    else
      kind := 'rect';
    SameStr(what + ' main kind', kind, mn.Strings['kind']);
    live := c.Live;
    SameBool(what + ' main silent', ctl.PieceSilent(k, bpMain), mn.Booleans['silent']);
    { the cursor the element carries: Displayable's 'pointer' on a fresh
      polyline, the rect's 'move' as created, updateCommon's after }
    if kind = 'polyline' then cur := 'pointer'
    else if not live then cur := 'move'
    else cur := TyBrushPieceCursor(bpMain, c.Opt.Transformable);
    SameStr(what + ' main cursor', cur, JStr(mn.Find('cursor')));
    if kind = 'rect' then
    begin
      SameHex(what + ' main x', c.Main.X, mn.Arrays['rect'].Items[0]);
      SameHex(what + ' main y', c.Main.Y, mn.Arrays['rect'].Items[1]);
      SameHex(what + ' main width', c.Main.W, mn.Arrays['rect'].Items[2]);
      SameHex(what + ' main height', c.Main.H, mn.Arrays['rect'].Items[3]);
    end
    else
    begin
      SameStr(what + ' points', IntToStr(Length(c.Points)), IntToStr(mn.Arrays['points'].Count));
      for q := 0 to Min(Length(c.Points), mn.Arrays['points'].Count) - 1 do
      begin
        SameHex(Format('%s point %d x', [what, q]), c.Points[q].X, mn.Arrays['points'].Items[q].Items[0]);
        SameHex(Format('%s point %d y', [what, q]), c.Points[q].Y, mn.Arrays['points'].Items[q].Items[1]);
      end;
    end;
    st := mn.Objects['style'];
    SameStr(what + ' fill', InkWord(c.Opt.Style.Fill, cUpFill), st.Strings['fill']);
    SameStr(what + ' stroke', InkWord(c.Opt.Style.Stroke, cUpStroke), st.Strings['stroke']);
    SameStr(what + ' lineWidth', Fmt(c.Opt.Style.LineWidth), Fmt(st.Floats['lineWidth']));
    d := cv.Find('handles');
    if (d = nil) or (d.JSONType = jtNull) then
    begin
      for p := bpW to bpNW do
        SameBool(what + ' has ' + TyBrushPieceName(p), TyBrushHasPiece(c.Opt.BrushType, p), False);
    end
    else
    begin
      hs := TJSONObject(d);
      for p := bpW to bpNW do
      begin
        SameBool(what + ' has ' + TyBrushPieceName(p), TyBrushHasPiece(c.Opt.BrushType, p),
          hs.Find(TyBrushPieceName(p)) <> nil);
        if hs.Find(TyBrushPieceName(p)) = nil then Continue;
        h := hs.Objects[TyBrushPieceName(p)];
        SameHex(what + ' ' + TyBrushPieceName(p) + ' x', c.Handle[p].X, h.Arrays['rect'].Items[0]);
        SameHex(what + ' ' + TyBrushPieceName(p) + ' y', c.Handle[p].Y, h.Arrays['rect'].Items[1]);
        SameHex(what + ' ' + TyBrushPieceName(p) + ' width', c.Handle[p].W, h.Arrays['rect'].Items[2]);
        SameHex(what + ' ' + TyBrushPieceName(p) + ' height', c.Handle[p].H, h.Arrays['rect'].Items[3]);
        SameBool(what + ' ' + TyBrushPieceName(p) + ' silent', ctl.PieceSilent(k, p), h.Booleans['silent']);
        SameBool(what + ' ' + TyBrushPieceName(p) + ' invisible',
          not live or not c.Opt.Transformable, h.Booleans['invisible']);
        if not live then cur := 'pointer'
        else if c.Opt.Transformable then cur := TyBrushPieceCursor(p, True)
        else cur := '(null)';
        SameStr(what + ' ' + TyBrushPieceName(p) + ' cursor', cur, JStr(h.Find('cursor')));
      end;
    end;
  end;
  { the model's areas }
  areas := FChart.BrushModelAreas(AB);
  SameStr(Format('brush %d area count', [AB]), IntToStr(Length(areas)),
    IntToStr(w.Arrays['areas'].Count));
  for k := 0 to Min(Length(areas), w.Arrays['areas'].Count) - 1 do
    CheckArea(Format('brush %d area %d', [AB, k]), areas[k], w.Arrays['areas'].Objects[k], False);
end;

procedure TAdvChartBrushCoverOracleTest.CheckEvents(ARec: TJSONObject);
var
  evs: TJSONArray;
  i, k, n: Integer;
  e: TJSONObject;
  got: TTyBrushEventRec;
  t, pl: string;
  pj: TJSONData;
begin
  evs := ARec.Arrays['events'];
  { the order, by type }
  n := FChart.Events.Count - FChartEvSeen;
  SameStr('the event count', IntToStr(n), IntToStr(evs.Count));
  for i := 0 to Min(n, evs.Count) - 1 do
  begin
    t := FChart.Events[FChartEvSeen + i];
    t := Copy(t, 1, Pos(#9, t) - 1);
    SameStr(Format('event %d type', [i]), t, evs.Objects[i].Strings['type']);
  end;
  FChartEvSeen := FChart.Events.Count;
  { the brush ones, with their areas }
  k := 0;
  for i := 0 to evs.Count - 1 do
  begin
    e := evs.Objects[i];
    t := e.Strings['type'];
    if (t <> 'brush') and (t <> 'brushend') then Continue;
    if FEvSeen + k >= FChart.BrushEventCount then
    begin
      Miss('no brush event logged for ' + t);
      Inc(k);
      Continue;
    end;
    got := FChart.BrushEventAt(FEvSeen + k);
    Inc(k);
    SameStr('logged event type', got.EventType, t);
    SameBool(t + ' from the view', got.FromSelf, (e.Find('from') <> nil) and (e.Find('from').JSONType = jtString));
    { the payload is JSON, its brushId the model's (fpjson drops a \u0000:
      read as the fixture writes it) }
    pj := nil;
    try
      try
        pj := GetJSON(StringReplace(got.Payload, '\u0000', '<NUL>', [rfReplaceAll]));
      except
        pj := nil;
      end;
      SameBool(t + ' payload parses', pj is TJSONObject, True);
      if (pj is TJSONObject) and (e.Find('brushId') <> nil) then
      begin
        pl := '';
        if TJSONObject(pj).Find('brushId') <> nil then pl := TJSONObject(pj).Strings['brushId'];
        SameStr(t + ' brushId', pl, e.Strings['brushId']);
      end;
    finally
      pj.Free;
    end;
    if (e.Find('areas') = nil) or (e.Find('areas').JSONType <> jtArray) then Continue;
    SameStr(t + ' area count', IntToStr(Length(got.Areas)), IntToStr(e.Arrays['areas'].Count));
    for n := 0 to Min(Length(got.Areas), e.Arrays['areas'].Count) - 1 do
      CheckArea(Format('%s area %d', [t, n]), got.Areas[n], e.Arrays['areas'].Objects[n],
        got.FromSelf);
  end;
  FEvSeen := FChart.BrushEventCount;
end;

procedure TAdvChartBrushCoverOracleTest.CheckSelects(ARec: TJSONObject);
var
  ss: TJSONArray;
  i, b, k, n: Integer;
  s: TTyBrushSelectRec;
  bt, ar: TJSONArray;
begin
  ss := ARec.Arrays['selects'];
  n := FChart.BrushSelectCount - FSelSeen;
  SameStr('brushSelect count', IntToStr(n), IntToStr(ss.Count));
  for i := 0 to Min(n, ss.Count) - 1 do
  begin
    s := FChart.BrushSelectAt(FSelSeen + i);
    SameStr(Format('brushSelect %d time', [i]), Fmt(s.Time - 1700000000000),
      Fmt(ss.Objects[i].Floats['t']));
    bt := ss.Objects[i].Arrays['batch'];
    SameStr(Format('brushSelect %d batch', [i]), IntToStr(Length(s.Batch)), IntToStr(bt.Count));
    for b := 0 to Min(Length(s.Batch), bt.Count) - 1 do
    begin
      ar := bt.Objects[b].Arrays['areas'];
      SameStr(Format('brushSelect %d brush %d areas', [i, b]), IntToStr(Length(s.Batch[b].Areas)),
        IntToStr(ar.Count));
      for k := 0 to Min(Length(s.Batch[b].Areas), ar.Count) - 1 do
      begin
        SameStr(Format('brushSelect %d area %d type', [i, k]),
          TyBrushTypeName(s.Batch[b].Areas[k].Opt.BrushType), ar.Objects[k].Strings['brushType']);
        SameRange(Format('brushSelect %d area %d range', [i, k]), s.Batch[b].Areas[k].Opt.Range,
          s.Batch[b].Areas[k].Opt.BrushType in [btLineX, btLineY], ar.Objects[k].Find('range'));
      end;
    end;
  end;
  FSelSeen := FChart.BrushSelectCount;
end;

procedure TAdvChartBrushCoverOracleTest.CheckRecord(ARec: TJSONObject; AStep: TJSONObject);
var
  d: TJSONData;
  b: Integer;
  cur, want: string;
begin
  d := ARec.Find('panels');
  if (d <> nil) and (d.JSONType = jtArray) then
  begin
    FreeAndNil(FPanels);
    FPanels := TJSONArray(d.Clone);
  end;
  d := ARec.Find('brushes');
  if d is TJSONArray then
  begin
    if Length(FBrushes) < d.Count then SetLength(FBrushes, d.Count);
    for b := 0 to d.Count - 1 do
      if d.Items[b].JSONType <> jtNull then
      begin
        FreeAndNil(FBrushes[b]);
        FBrushes[b] := d.Items[b].Clone;
      end;
    SameStr('the brush count', IntToStr(FChart.BrushCount), IntToStr(d.Count));
  end;
  CheckPanels;
  for b := 0 to High(FBrushes) do CheckBrush(b);
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
  CheckEvents(ARec);
  CheckSelects(ARec);
end;

procedure TAdvChartBrushCoverOracleTest.RunScenario(ASc: TJSONObject);
var
  steps: TJSONArray;
  st, rec: TJSONObject;
  i, x, y: Integer;
  typ, hov, mine: string;
  b: Integer;
begin
  FName := ASc.Strings['id'];
  NewChart;
  FreeAndNil(FPanels);
  for b := 0 to High(FBrushes) do FreeAndNil(FBrushes[b]);
  FBrushes := nil;
  FEvSeen := 0;
  FSelSeen := 0;
  FChartEvSeen := 0;
  FClock := 1700000000000;
  FChart.BrushNow := FClock;
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
    if (typ = 'mousemove') or (typ = 'mousedown') or (typ = 'mouseup') or (typ = 'click') then
    begin
      x := st.Integers['x'];
      y := st.Integers['y'];
      { the piece the Handler finds before the step }
      hov := JStr(steps.Objects[i].Find('hover'));
      mine := RoleAt(x, y);
      if (Pos('brush', hov) = 1) or (mine <> '') then
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

procedure TAdvChartBrushCoverOracleTest.RunGroup(const APrefixes: array of string);
var
  sc: TJSONArray;
  i, k: Integer;
  id: string;
  ran: Integer;
begin
  sc := TJSONObject(FRoot).Arrays['scenarios'];
  ran := 0;
  for i := 0 to sc.Count - 1 do
  begin
    id := sc.Objects[i].Strings['id'];
    for k := 0 to High(APrefixes) do
      if Pos(APrefixes[k], id) = 1 then
      begin
        RunScenario(sc.Objects[i]);
        Inc(ran);
        Break;
      end;
  end;
  AssertTrue('the group ran cases', ran > 0);
  AssertTrue('compared something', FCompared > 0);
  if FBad > 0 then
    Fail(Format('%d of %d comparisons over %d steps differ from upstream:%s',
      [FBad, FCompared, FSteps, FReport]));
end;

procedure TAdvChartBrushCoverOracleTest.TestRectCoversAsUpstream;
begin
  RunGroup(['R-']);
end;

procedure TAdvChartBrushCoverOracleTest.TestModesAndShapesAsUpstream;
begin
  RunGroup(['M-', 'P-', 'L-']);
end;

procedure TAdvChartBrushCoverOracleTest.TestPanelsAndTheActionAsUpstream;
begin
  RunGroup(['G-', 'T-', 'A-', 'Q-']);
end;

procedure TAdvChartBrushCoverOracleTest.TestStyleAndSwitchingAsUpstream;
begin
  RunGroup(['S-', 'D-']);
end;

procedure TAdvChartBrushCoverOracleTest.TestTheThrottleAsUpstream;
begin
  RunGroup(['TH-']);
end;

{ ==================== by hand ==================== }

procedure TAdvChartBrushCoverTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TBcProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.AnimationMode := camOff;
  FChart.BrushNow := 1700000000000;
end;

procedure TAdvChartBrushCoverTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartBrushCoverTest.Show(const AOption: string);
begin
  FChart.SetOption(AOption, True);
  RenderNow;
end;

procedure TAdvChartBrushCoverTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height), 96);
  finally
    bmp.Free;
  end;
end;

const
  cBarChart = '{"animation":false,"backgroundColor":"#ffffff","xAxis":{"type":"category","data":["a","b","c","d"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[10,20,30,40]}],';

procedure TAdvChartBrushCoverTest.TestTheCoversAreDrawnAndStayInTheExport;
var
  bmp, ex, nx: TBGRABitmap;

  function Reddish(B: TBGRABitmap): Integer;
  var xx, yy: Integer; q: TBGRAPixel;
  begin
    Result := 0;
    for yy := 80 to 100 do
      for xx := 100 to 130 do
      begin
        q := B.GetPixel(xx, yy);
        if (q.red > 200) and (q.green < 120) and (q.blue < 120) then Inc(Result);
      end;
  end;

begin
  { a red cover, laid by the action over the empty top-left of the grid }
  Show(cBarChart + '"brush":{"xAxisIndex":0,"brushStyle":{"color":"#ff0000","borderWidth":0}}}');
  FChart.DispatchAction('{"type":"brush","areas":[{"brushType":"rect","range":[[95,140],[70,110]]}]}');
  AssertEquals('one cover', 1, Length(FChart.BrushControllerOf(0).Covers));
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
    AssertTrue('the cover is drawn', Reddish(bmp) > 400);
  finally
    bmp.Free;
  end;
  { NOT HIDDEN BY THE EXCLUSION. BrushView's controller mounts its group on
    zrender's root, not in the view's group, so getDataURL's
    `excludeComponents: ['brush']` ignores an empty group and the covers
    are in the picture either way; the brush view is never a view that
    drew. [milestone C14-C22: C17 hid them, which upstream cannot do] }
  nx := FChart.RenderToBitmap('{"backgroundColor":"#ffffff"}');
  AssertFalse('the brush view holds nothing', cvBrush in FChart.LastViewsDrawn);
  ex := FChart.RenderToBitmap('{"excludeComponents":["brush"],"backgroundColor":"#ffffff"}');
  try
    AssertTrue('the export draws it', Reddish(nx) > 400);
    AssertTrue('and excluding the brush does not hide it', Reddish(ex) > 400);
  finally
    ex.Free;
    nx.Free;
  end;
end;

procedure TAdvChartBrushCoverTest.TestACoverHidesTheItemBeneath;
var
  el: Integer;
  d: TTyChartDatumRef;
  ctl: TTyBrushController;
  bx, by: Integer;
begin
  Show(cBarChart + '"brush":{"xAxisIndex":0}}');
  { the tallest bar's middle }
  bx := 90 + Round(450 * 7 / 8);
  by := 250;
  d := FChart.HitTestAt(bx, by, el);
  AssertTrue('the bar answers', d.SeriesIndex = 0);
  FChart.DispatchAction('{"type":"brush","areas":[{"brushType":"rect","range":[[' + IntToStr(bx - 20)
    + ',' + IntToStr(bx + 20) + '],[' + IntToStr(by - 20) + ',' + IntToStr(by + 20) + ']]}]}');
  RenderNow;
  ctl := FChart.BrushControllerOf(0);
  AssertEquals('the cover answers the pointer (transformable)', False, ctl.PieceSilent(0, bpMain));
  d := FChart.HitTestAt(bx, by, el);
  AssertTrue('under the cover the bar does not', d.SeriesIndex < 0);
  d := FChart.HitTestAt(bx, by + 40, el);
  AssertTrue('beside it it does', d.SeriesIndex = 0);
end;

procedure TAdvChartBrushCoverTest.TestTheActionNamesOneBrush;
begin
  Show(cBarChart + '"brush":[{"xAxisIndex":0},{"xAxisIndex":0,"id":"second"}]}');
  AssertEquals('two brushes', 2, FChart.BrushCount);
  FChart.DispatchAction('{"type":"brush","brushIndex":1,"areas":[{"brushType":"lineX","xAxisIndex":0,"coordRange":[1,2]}]}');
  AssertEquals('the first keeps none', 0, Length(FChart.BrushModelAreas(0)));
  AssertEquals('the second has one', 1, Length(FChart.BrushModelAreas(1)));
  FChart.DispatchAction('{"type":"brush","brushId":"second","areas":[]}');
  AssertEquals('by id', 0, Length(FChart.BrushModelAreas(1)));
  FChart.DispatchAction('{"type":"brush","areas":[{"brushType":"rect","range":[[1,2],[3,4]]}]}');
  AssertEquals('none named: all, the first', 1, Length(FChart.BrushModelAreas(0)));
  AssertEquals('none named: all, the second', 1, Length(FChart.BrushModelAreas(1)));
  { no areas: the areas stay }
  FChart.DispatchAction('{"type":"brush"}');
  AssertEquals('kept', 1, Length(FChart.BrushModelAreas(0)));
end;

procedure TAdvChartBrushCoverTest.TestNotMergeDropsTheAreasAndTheBrush;
begin
  Show(cBarChart + '"brush":{"xAxisIndex":0}}');
  FChart.DispatchAction('{"type":"takeGlobalCursor","key":"brush","brushOption":{"brushType":"rect"}}');
  FChart.DispatchAction('{"type":"brush","areas":[{"brushType":"rect","range":[[100,200],[100,200]]}]}');
  RenderNow;
  AssertTrue('on', FChart.BrushControllerOf(0).Enabled);
  { a merge keeps the model }
  FChart.SetOption('{"title":{"text":"x"}}', False);
  RenderNow;
  AssertEquals('a merge keeps the areas', 1, Length(FChart.BrushModelAreas(0)));
  AssertTrue('and the brush on', FChart.BrushControllerOf(0).Enabled);
  { notMerge: a new model and view }
  Show(cBarChart + '"brush":{"xAxisIndex":0}}');
  AssertEquals('a new model has none', 0, Length(FChart.BrushModelAreas(0)));
  AssertEquals('nor covers', 0, Length(FChart.BrushControllerOf(0).Covers));
  AssertFalse('and draws nothing', FChart.BrushControllerOf(0).Enabled);
end;

procedure TAdvChartBrushCoverTest.TestTheEventPayloadIsJson;
var
  d: TJSONData;
  o: TJSONObject;
  e: TTyBrushEventRec;
begin
  Show(cBarChart + '"brush":{"xAxisIndex":0}}');
  FChart.DispatchAction('{"type":"takeGlobalCursor","key":"brush","brushOption":{"brushType":"lineX"}}');
  RenderNow;
  FChart.BrushClearLogs;
  FChart.Move(150, 150);
  FChart.Down(150, 150);
  FChart.Move(250, 200);
  FChart.Up(250, 200);
  AssertEquals('brush, brushend', 2, FChart.BrushEventCount);
  e := FChart.BrushEventAt(1);
  AssertEquals('brushend', 'brushend', e.EventType);
  AssertTrue('the brush id holds its NULs', Pos('\u0000', e.Payload) > 0);
  d := GetJSON(e.Payload);
  try
    o := TJSONObject(d);
    AssertEquals('the type', 'brushend', o.Strings['type']);
    AssertEquals('from itself', o.Strings['brushId'], o.Strings['$from']);
    AssertEquals('one area', 1, o.Arrays['areas'].Count);
    AssertEquals('lineX', 'lineX', o.Arrays['areas'].Objects[0].Strings['brushType']);
    { a line's xyMinMax holds NaN: JSON's null }
    AssertTrue('NaN as null', o.Arrays['areas'].Objects[0].Objects['__rangeOffset']
      .Arrays['xyMinMax'].Arrays[1].Items[0].JSONType = jtNull);
  finally
    d.Free;
  end;
end;

procedure TAdvChartBrushCoverTest.TestTheGeometryHelpers;
var
  r: TTyBrushRange;
begin
  { windingLine: on the line is Infinity, an end counts half }
  AssertTrue('on the line', IsInfinite(TyBrushWindingLine(0, 0, 0, 10, 0, 5)));
  AssertEquals('an end', -0.5, TyBrushWindingLine(5, 0, 5, 10, 0, 0));
  AssertEquals('a horizontal edge', 0, TyBrushWindingLine(0, 3, 10, 3, 1, 3));
  { a line's stroke: within half the width }
  AssertTrue(TyBrushLineContainStroke(0, 0, 10, 0, 2, 5, 1));
  AssertFalse(TyBrushLineContainStroke(0, 0, 10, 0, 2, 5, 1.5));
  { driftRect: the west edge past the east swaps them }
  SetLength(r, 2);
  r[0][0] := 10;
  r[0][1] := 20;
  r[1][0] := 30;
  r[1][1] := 40;
  r := TyBrushDrift(btRect, r, bpW, 15, 99);
  AssertEquals('x min', 20, r[0][0]);
  AssertEquals('x max', 25, r[0][1]);
  AssertEquals('y untouched', 30, r[1][0]);
end;

initialization
  RegisterTest(TAdvChartBrushCoverOracleTest);
  RegisterTest(TAdvChartBrushCoverTest);
end.
