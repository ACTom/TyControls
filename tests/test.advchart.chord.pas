unit test.advchart.chord;
{$mode objfpc}{$H+}
{ THE CHORD SERIES, HELD TO UPSTREAM [Batch 120, C11].

  tools/advchart-oracle/chord.js runs the real ECharts 6.1 build in node
  (server-side, animation off for the static cases, zrender's width table
  for text, Math.random the port's xorshift32) and records, chart by chart:

    the graph    every node's key, name, data index and value; every kept
                 link's option row, ends, data index, value and name;
    the layout   every node's angle, value, ratio, start and end angles;
                 every link's two arcs (s1, s2, t1, t2 and their angles);
    the pieces   every sector's corner radii and PathProxy data, fill,
                 stroke, width, opacity and z2; every ribbon's PathProxy
                 data, fill (a colour, a gradient), stroke, width, opacity;
    the labels   text, place, alignment, colour, opacity, z2, hidden;
    the legend   its items' colours, and the chord after each action;
    states       after each action or pointer step: every element's hover
                 flag, state list, fill, opacity, z2 and its label's;
    the pointer  the tooltip each hover shows, the click events;
    conversions  convertToPixel / containPixel on a chord.

  This replays it through the control, bit for bit. Text is measured with
  zrender's width table. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Color,
     tyControls.AdvChart.Labels, tyControls.AdvChart.States,
     tyControls.AdvChart.Tooltip, tyControls.AdvChart.Events,
     tyControls.AdvChart.ZrPath, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Chord, tyControls.AdvChart.Legend,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Convert,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TChordProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    Events: array of TTyChartEvent;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Down(AX, AY: Integer);
    procedure Move(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
    function ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
    function NodeStates(ASeries, AView: Integer; out AItem: TTyStItem): Boolean;
    function EdgeStates(ASeries, ARaw: Integer; out AItem: TTyStItem): Boolean;
  end;

  TAdvChartChordTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChordProbe;
    FRoot: TJSONData;
    FBad, FCompared, FNodes, FEdges, FLabels, FStates, FTips, FEvents: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure SameInt(const AWhat: string; AGot, AWant: Integer);
    procedure SameColour(const AWhat: string; AHas: Boolean; AGot: TTyChartColor;
      AWant: TJSONData);
    procedure Finish(const AWhat: string; AMin: Integer);
    function Cases: TJSONArray;
    function CaseById(const AId: string): TJSONObject;
    procedure NewChart;
    procedure RenderNow(AW, AH: Integer);
    procedure Show(ACase: TJSONObject);
    procedure Step(AStep: TJSONObject);
    function FindNode(ASeries, ARaw: Integer; out AEl: TTyChartElement): Integer;
    function FindEdge(ASeries, ARaw: Integer; out AEl: TTyChartElement): Integer;
    function FindLabel(AHostIndex: Integer; out AEl: TTyChartElement): Boolean;
    procedure CheckPath(const AWhat: string; const APath: TTyZrPath; AWant: TJSONArray);
    procedure CheckGraph(ASeries: TJSONObject);
    procedure CheckPieces(ASeries: TJSONObject);
    procedure CheckLabels(ASeries: TJSONObject);
    procedure CheckLegend(ALegend: TJSONData);
    procedure CheckEls(AEls: TJSONArray);
    procedure CheckTip(AState: TJSONObject);
    procedure CheckEvents(AState: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheGraphAndTheLayoutAreUpstreams;
    procedure TestTheSectorsAndRibbonsAreUpstreams;
    procedure TestTheLabelsAreUpstreams;
    procedure TestTheLegendFiltersTheNodes;
    procedure TestTheStatesAndThePointerAreUpstreams;
    procedure TestNothingConvertsOnAChord;
    { beyond the fixture }
    procedure TestADuplicateKeyDrawsNothing;
    procedure TestARibbonIsHitInsideAndNotOutside;
    procedure TestTheArcsBecomeCubicsOnTheCircle;
  end;

implementation

{ ==================== the probe ==================== }

function TChordProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TChordProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TChordProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TChordProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
end;

procedure TChordProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TChordProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

procedure TChordProbe.OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
begin
  if AEvent.EventType <> 'click' then Exit;
  SetLength(Events, Length(Events) + 1);
  Events[High(Events)] := AEvent;
end;

function TChordProbe.ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
begin
  Result := TooltipContent(ADatum, TooltipSpecFor(ADatum));
end;

function TChordProbe.NodeStates(ASeries, AView: Integer; out AItem: TTyStItem): Boolean;
begin
  Result := ItemStates(ASeries, AView, AItem);
end;

function TChordProbe.EdgeStates(ASeries, ARaw: Integer; out AItem: TTyStItem): Boolean;
begin
  Result := ChordEdgeStates(ASeries, ARaw, AItem);
end;

{ ==================== helpers ==================== }

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function HexOf(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function Txt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function SameBits(A, B: Double): Boolean;
begin
  Result := (HexOf(A) = HexOf(B)) or (IsNan(A) and IsNan(B));
end;

function IsNull(AData: TJSONData): Boolean;
begin
  Result := (AData = nil) or (AData.JSONType = jtNull);
end;

function AlignName(AH: TTyTextAnchorH): string;
begin
  case AH of
    tahLeft: Result := 'left';
    tahRight: Result := 'right';
  else
    Result := 'center';
  end;
end;

function VAlignName(AV: TTyTextAnchorV): string;
begin
  case AV of
    tavTop: Result := 'top';
    tavBottom: Result := 'bottom';
  else
    Result := 'middle';
  end;
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

function AllFinite(AArr: TJSONArray): Boolean;
var i: Integer; v: Double;
begin
  Result := False;
  for i := 0 to AArr.Count - 1 do
  begin
    v := FromHex(AArr.Strings[i]);
    if IsNan(v) or IsInfinite(v) then Exit;
  end;
  Result := True;
end;

{ ==================== the case ==================== }

procedure TAdvChartChordTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-chord.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-chord.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FNodes := 0;
  FEdges := 0;
  FLabels := 0;
  FStates := 0;
  FTips := 0;
  FEvents := 0;
  FReport := '';
end;

procedure TAdvChartChordTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartChordTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 16000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartChordTest.Same(const AWhat: string; AGot: Double; AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  if IsNull(AWant) then
  begin
    Bad(AWhat + ': upstream has no number');
    Exit;
  end;
  want := FromHex(AWant.AsString);
  if not SameBits(AGot, want) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(want)]));
end;

procedure TAdvChartChordTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s "%s", upstream "%s"', [AWhat, AGot, AWant]));
end;

procedure TAdvChartChordTest.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s %s, upstream %s', [AWhat, BoolToStr(AGot, True), BoolToStr(AWant, True)]));
end;

procedure TAdvChartChordTest.SameInt(const AWhat: string; AGot, AWant: Integer);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s %d, upstream %d', [AWhat, AGot, AWant]));
end;

{ a colour upstream holds as a string: the packed colour it parses to }
procedure TAdvChartChordTest.SameColour(const AWhat: string; AHas: Boolean;
  AGot: TTyChartColor; AWant: TJSONData);
var want: TTyChartColor;
begin
  Inc(FCompared);
  if IsNull(AWant) or (AWant.JSONType <> jtString)
    or not TyTryParseChartColor(AWant.AsString, want) then
  begin
    if AHas then Bad(Format('%s %s, upstream no colour', [AWhat, IntToHex(AGot, 8)]));
    Exit;
  end;
  if (not AHas) or (AGot <> want) then
    Bad(Format('%s %s (%s), upstream %s', [AWhat, IntToHex(AGot, 8),
      BoolToStr(AHas, True), AWant.AsString]));
end;

procedure TAdvChartChordTest.Finish(const AWhat: string; AMin: Integer);
begin
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
  AssertTrue(Format('%s: only %d compared', [AWhat, FCompared]), FCompared >= AMin);
end;

function TAdvChartChordTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

function TAdvChartChordTest.CaseById(const AId: string): TJSONObject;
var i: Integer;
begin
  for i := 0 to Cases.Count - 1 do
    if Cases.Objects[i].Strings['id'] = AId then Exit(Cases.Objects[i]);
  Result := nil;
  Fail('no case ' + AId);
end;

procedure TAdvChartChordTest.NewChart;
var m: TJSONObject;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TChordProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(
    TZrSsrMeasurer.Create(m.Arrays['ratio'], m.Integers['firstCode']));
  FChart.OnChartEvent := @FChart.OnEvent;
  FChart.AnimationMode := camOff;
end;

procedure TAdvChartChordTest.RenderNow(AW, AH: Integer);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, AW, AH), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartChordTest.Show(ACase: TJSONObject);
begin
  NewChart;
  FChart.SetBounds(0, 0, ACase.Integers['W'], ACase.Integers['H']);
  FChart.Option := ACase.Objects['option'].AsJSON;
  RenderNow(ACase.Integers['W'], ACase.Integers['H']);
end;

procedure TAdvChartChordTest.Step(AStep: TJSONObject);
var a: TJSONArray; d: TJSONData;
begin
  FChart.Events := nil;
  d := AStep.Find('hover');
  if d is TJSONArray then
  begin
    a := TJSONArray(d);
    FChart.Move(a.Integers[0], a.Integers[1]);
    Exit;
  end;
  d := AStep.Find('click');
  if d is TJSONArray then
  begin
    a := TJSONArray(d);
    FChart.Move(a.Integers[0], a.Integers[1]);
    FChart.Down(a.Integers[0], a.Integers[1]);
    FChart.Up(a.Integers[0], a.Integers[1]);
    Exit;
  end;
  if AStep.Find('leave') <> nil then
  begin
    FChart.Move(-10, -10);
    Exit;
  end;
  d := AStep.Find('action');
  if d is TJSONObject then
  begin
    if not FChart.DispatchAction(d.AsJSON) then Bad('the action was refused: ' + d.AsJSON);
    Exit;
  end;
  Bad('an unknown step ' + AStep.AsJSON);
end;

function TAdvChartChordTest.FindNode(ASeries, ARaw: Integer;
  out AEl: TTyChartElement): Integer;
var
  i: Integer;
  l: TTyPaintList;
begin
  AEl := Default(TTyChartElement);
  Result := -1;
  l := FChart.List;
  if l = nil then Exit;
  for i := 0 to l.Count - 1 do
    if (l.Element(i).Datum.Kind = ctkSeries) and (l.Element(i).Datum.SeriesIndex = ASeries)
      and not l.Element(i).Datum.IsEdge and (l.Element(i).Datum.RawDataIndex = ARaw)
      and (l.Element(i).Anim.Role = carChord) then
    begin
      AEl := l.Element(i);
      Exit(i);
    end;
end;

function TAdvChartChordTest.FindEdge(ASeries, ARaw: Integer;
  out AEl: TTyChartElement): Integer;
var
  i: Integer;
  l: TTyPaintList;
begin
  AEl := Default(TTyChartElement);
  Result := -1;
  l := FChart.List;
  if l = nil then Exit;
  for i := 0 to l.Count - 1 do
    if (l.Element(i).Datum.Kind = ctkSeries) and (l.Element(i).Datum.SeriesIndex = ASeries)
      and l.Element(i).Datum.IsEdge and (l.Element(i).Datum.RawDataIndex = ARaw)
      and (l.Element(i).Anim.Role = carChord) then
    begin
      AEl := l.Element(i);
      Exit(i);
    end;
end;

function TAdvChartChordTest.FindLabel(AHostIndex: Integer;
  out AEl: TTyChartElement): Boolean;
var
  i: Integer;
  l: TTyPaintList;
begin
  AEl := Default(TTyChartElement);
  Result := False;
  l := FChart.List;
  for i := 0 to l.Count - 1 do
    if (l.Element(i).Anim.Role = carLabel)
      and (l.Element(i).Caption.LmHostPlus1 = AHostIndex + 1) then
    begin
      AEl := l.Element(i);
      Exit(True);
    end;
end;

procedure TAdvChartChordTest.CheckPath(const AWhat: string; const APath: TTyZrPath;
  AWant: TJSONArray);
var
  got: TTyDoubleArray;
  k: Integer;
begin
  got := PathData(APath);
  SameInt(AWhat + ' path length', Length(got), AWant.Count);
  if Length(got) <> AWant.Count then Exit;
  for k := 0 to High(got) do
    Same(Format('%s path[%d]', [AWhat, k]), got[k], AWant.Items[k]);
end;

{ ==================== the graph and the layout ==================== }

procedure TAdvChartChordTest.CheckGraph(ASeries: TJSONObject);
var
  si, i: Integer;
  S: TTyChordSolved;
  nodes, edges: TJSONArray;
  o, lay: TJSONObject;
  what: string;
  n, m: Integer;
begin
  si := ASeries.Integers['index'];
  S := FChart.ChordSolved(si);
  SameBool(Format('s%d built', [si]), S.Valid, True);
  if not S.Valid then Exit;
  nodes := ASeries.Arrays['nodes'];
  edges := ASeries.Arrays['edges'];
  SameInt(Format('s%d nodes', [si]), Length(S.Nodes), nodes.Count);
  SameInt(Format('s%d links', [si]), Length(S.Edges), edges.Count);
  if (Length(S.Nodes) <> nodes.Count) or (Length(S.Edges) <> edges.Count) then Exit;
  n := 0;
  m := 0;
  for i := 0 to nodes.Count - 1 do
  begin
    o := nodes.Objects[i];
    what := Format('s%d node %d', [si, i]);
    Inc(FNodes);
    SameStr(what + ' key', S.Nodes[i].Key, o.Strings['key']);
    SameStr(what + ' name', S.Nodes[i].Name, o.Strings['name']);
    SameInt(what + ' data index', S.Nodes[i].DataIndex, o.Integers['index']);
    if S.Nodes[i].DataIndex >= 0 then Inc(n);
    Same(what + ' value', S.Nodes[i].DataValue, o.Find('value'));
    SameBool(what + ' laid out', S.Nodes[i].HasLayout, not IsNull(o.Find('layout')));
    if IsNull(o.Find('layout')) or not S.Nodes[i].HasLayout then Continue;
    lay := o.Objects['layout'];
    Same(what + ' angle', S.Nodes[i].Angle, lay.Find('angle'));
    Same(what + ' value', S.Nodes[i].Value, lay.Find('value'));
    SameBool(what + ' has a ratio', S.Nodes[i].HasRatio, not IsNull(lay.Find('ratio')));
    if S.Nodes[i].HasRatio and not IsNull(lay.Find('ratio')) then
      Same(what + ' ratio', S.Nodes[i].Ratio, lay.Find('ratio'));
    Same(what + ' cx', S.CX, lay.Find('cx'));
    Same(what + ' cy', S.CY, lay.Find('cy'));
    Same(what + ' r0', S.R0, lay.Find('r0'));
    Same(what + ' r', S.R, lay.Find('r'));
    Same(what + ' start angle', S.Nodes[i].StartAngle, lay.Find('startAngle'));
    Same(what + ' end angle', S.Nodes[i].EndAngle, lay.Find('endAngle'));
    SameBool(what + ' clockwise', S.Clockwise, lay.Booleans['clockwise']);
  end;
  SameInt(Format('s%d node count', [si]), n, ASeries.Integers['count']);
  for i := 0 to edges.Count - 1 do
  begin
    o := edges.Objects[i];
    what := Format('s%d link %d', [si, i]);
    Inc(FEdges);
    SameInt(what + ' row', S.Edges[i].Row, o.Integers['row']);
    SameInt(what + ' source', S.Edges[i].Source, o.Integers['source']);
    SameInt(what + ' target', S.Edges[i].Target, o.Integers['target']);
    SameInt(what + ' data index', S.Edges[i].DataIndex, o.Integers['index']);
    if S.Edges[i].DataIndex >= 0 then Inc(m);
    Same(what + ' value', S.Edges[i].Value, o.Find('value'));
    if not IsNull(o.Find('name')) then SameStr(what + ' name', S.Edges[i].Name, o.Strings['name']);
    SameBool(what + ' laid out', S.Edges[i].HasLayout, not IsNull(o.Find('layout')));
    if IsNull(o.Find('layout')) or not S.Edges[i].HasLayout then Continue;
    lay := o.Objects['layout'];
    Same(what + ' s1 x', S.Edges[i].S1X, lay.Arrays['s1'].Items[0]);
    Same(what + ' s1 y', S.Edges[i].S1Y, lay.Arrays['s1'].Items[1]);
    Same(what + ' s2 x', S.Edges[i].S2X, lay.Arrays['s2'].Items[0]);
    Same(what + ' s2 y', S.Edges[i].S2Y, lay.Arrays['s2'].Items[1]);
    Same(what + ' t1 x', S.Edges[i].T1X, lay.Arrays['t1'].Items[0]);
    Same(what + ' t1 y', S.Edges[i].T1Y, lay.Arrays['t1'].Items[1]);
    Same(what + ' t2 x', S.Edges[i].T2X, lay.Arrays['t2'].Items[0]);
    Same(what + ' t2 y', S.Edges[i].T2Y, lay.Arrays['t2'].Items[1]);
    Same(what + ' source start', S.Edges[i].SStart, lay.Find('sStartAngle'));
    Same(what + ' source end', S.Edges[i].SEnd, lay.Find('sEndAngle'));
    Same(what + ' target start', S.Edges[i].TStart, lay.Find('tStartAngle'));
    Same(what + ' target end', S.Edges[i].TEnd, lay.Find('tEndAngle'));
    Same(what + ' r', S.R0, lay.Find('r'));
    Same(what + ' layout value', S.Edges[i].LayoutValue, lay.Find('value'));
  end;
  SameInt(Format('s%d link count', [si]), m, ASeries.Integers['edgeCount']);
end;

procedure TAdvChartChordTest.TestTheGraphAndTheLayoutAreUpstreams;
var
  c, s: Integer;
  cs: TJSONObject;
begin
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    FWhere := cs.Strings['id'];
    Show(cs);
    for s := 0 to cs.Arrays['series'].Count - 1 do
      CheckGraph(cs.Arrays['series'].Objects[s]);
  end;
  AssertTrue(Format('enough nodes (%d) and links (%d)', [FNodes, FEdges]),
    (FNodes >= 120) and (FEdges >= 150));
  Finish('the graph and the layout', 4000);
end;

{ ==================== the sectors and the ribbons ==================== }

procedure TAdvChartChordTest.CheckPieces(ASeries: TJSONObject);
var
  si, i, at, k: Integer;
  S: TTyChordSolved;
  o, el, f: TJSONObject;
  stops: TJSONArray;
  what: string;
  e: TTyChartElement;
  d: TJSONData;
  want: TTyChartColor;
  hasStroke: Boolean;
begin
  si := ASeries.Integers['index'];
  S := FChart.ChordSolved(si);
  if not S.Valid then Exit;
  for i := 0 to ASeries.Arrays['nodes'].Count - 1 do
  begin
    o := ASeries.Arrays['nodes'].Objects[i];
    what := Format('s%d node %d', [si, i]);
    at := FindNode(si, i, e);
    Inc(FCompared);
    if IsNull(o.Find('el')) then
    begin
      if at >= 0 then Bad(what + ': a sector upstream has not');
      Continue;
    end;
    el := o.Objects['el'];
    { a sector at no number is no sector here }
    if not AllFinite(el.Arrays['path']) then
    begin
      if at >= 0 then Bad(what + ': a sector of no number');
      Continue;
    end;
    if at < 0 then
    begin
      Bad(what + ': no sector');
      Continue;
    end;
    CheckPath(what, TyChordSectorPath(S, i), el.Arrays['path']);
    SameInt(what + ' corners', Length(TyChordCorners(S, i)), el.Arrays['cr'].Count);
    if Length(TyChordCorners(S, i)) = el.Arrays['cr'].Count then
      for k := 0 to el.Arrays['cr'].Count - 1 do
        Same(what + ' corner ' + IntToStr(k), TyChordCorners(S, i)[k], el.Arrays['cr'].Items[k]);
    d := el.Find('fill');
    if d.JSONType = jtObject then
    begin
      Inc(FCompared);
      if e.Style.FillGradient.Kind = cgkNone then Bad(what + ': no gradient fill');
    end
    else
      SameColour(what + ' fill', e.Style.HasFill, e.Style.FillColor, d);
    hasStroke := (el.Find('stroke').JSONType = jtString)
      and TyTryParseChartColor(el.Strings['stroke'], want)
      and not IsNull(el.Find('lineWidth')) and (FromHex(el.Strings['lineWidth']) > 0);
    SameBool(what + ' stroked', e.Style.StrokeWidthLogical > 0, hasStroke);
    if hasStroke and (e.Style.StrokeWidthLogical > 0) then
    begin
      SameColour(what + ' stroke', True, e.Style.StrokeColor, el.Find('stroke'));
      Same(what + ' line width', e.Style.StrokeWidthLogical, el.Find('lineWidth'));
    end;
    Same(what + ' opacity', e.Style.Alpha, el.Find('opacity'));
    SameInt(what + ' z2', e.Z2, el.Integers['z2']);
  end;
  for i := 0 to ASeries.Arrays['edges'].Count - 1 do
  begin
    o := ASeries.Arrays['edges'].Objects[i];
    what := Format('s%d link %d', [si, i]);
    at := FindEdge(si, i, e);
    Inc(FCompared);
    if IsNull(o.Find('el')) then
    begin
      if at >= 0 then Bad(what + ': a ribbon upstream has not');
      Continue;
    end;
    el := o.Objects['el'];
    if at < 0 then
    begin
      Bad(what + ': no ribbon');
      Continue;
    end;
    CheckPath(what, TyChordRibbonPath(S, i), el.Arrays['path']);
    { a path of no number: the element is there, with no outline }
    if not AllFinite(el.Arrays['path']) then
    begin
      SameInt(what + ' outline of a NaN path', Length(e.Shape.Points) + Length(e.Shape.Cmds), 0);
      Continue;
    end;
    d := el.Find('fill');
    if d.JSONType = jtObject then
    begin
      f := TJSONObject(d);
      Inc(FCompared);
      if e.Style.FillGradient.Kind <> cgkLinear then
      begin
        Bad(what + ': no linear gradient');
        Continue;
      end;
      SameBool(what + ' gradient global', e.Style.FillGradient.Global, f.Booleans['global']);
      if f.Booleans['global'] then
      begin
        Same(what + ' gradient x', e.Style.FillGradient.X, f.Find('x'));
        Same(what + ' gradient y', e.Style.FillGradient.Y, f.Find('y'));
        Same(what + ' gradient x2', e.Style.FillGradient.X2, f.Find('x2'));
        Same(what + ' gradient y2', e.Style.FillGradient.Y2, f.Find('y2'));
      end;
      stops := f.Arrays['stops'];
      SameInt(what + ' stops', Length(e.Style.FillGradient.Stops), stops.Count);
      if Length(e.Style.FillGradient.Stops) = stops.Count then
        for k := 0 to stops.Count - 1 do
        begin
          SameColour(what + ' stop ' + IntToStr(k), True,
            e.Style.FillGradient.Stops[k].Color, stops.Objects[k].Find('color'));
          Inc(FCompared);
          if e.Style.FillGradient.Stops[k].Offset <> stops.Objects[k].Floats['offset'] then
            Bad(what + ' stop offset ' + IntToStr(k));
        end;
    end
    else
    begin
      SameColour(what + ' fill', e.Style.HasFill, e.Style.FillColor, d);
      Inc(FCompared);
      if e.Style.FillGradient.Kind <> cgkNone then Bad(what + ': a gradient upstream has not');
    end;
    hasStroke := (el.Find('stroke').JSONType = jtString)
      and TyTryParseChartColor(el.Strings['stroke'], want)
      and not IsNull(el.Find('lineWidth')) and (FromHex(el.Strings['lineWidth']) > 0);
    SameBool(what + ' stroked', e.Style.StrokeWidthLogical > 0, hasStroke);
    if hasStroke and (e.Style.StrokeWidthLogical > 0) then
    begin
      SameColour(what + ' stroke', True, e.Style.StrokeColor, el.Find('stroke'));
      Same(what + ' line width', e.Style.StrokeWidthLogical, el.Find('lineWidth'));
    end;
    Same(what + ' opacity', e.Style.Alpha, el.Find('opacity'));
    SameInt(what + ' z2', e.Z2, el.Integers['z2']);
  end;
end;

procedure TAdvChartChordTest.TestTheSectorsAndRibbonsAreUpstreams;
var
  c, s: Integer;
  cs: TJSONObject;
begin
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    FWhere := cs.Strings['id'];
    Show(cs);
    for s := 0 to cs.Arrays['series'].Count - 1 do
      CheckPieces(cs.Arrays['series'].Objects[s]);
  end;
  Finish('the sectors and the ribbons', 12000);
end;

{ ==================== the labels ==================== }

procedure TAdvChartChordTest.CheckLabels(ASeries: TJSONObject);
var
  si, i, at: Integer;
  o, el, lab: TJSONObject;
  what: string;
  e, cap: TTyChartElement;
  have: Boolean;
begin
  si := ASeries.Integers['index'];
  for i := 0 to ASeries.Arrays['nodes'].Count - 1 do
  begin
    o := ASeries.Arrays['nodes'].Objects[i];
    if IsNull(o.Find('el')) then Continue;
    el := o.Objects['el'];
    if IsNull(el.Find('label')) then Continue;
    lab := el.Objects['label'];
    what := Format('s%d node %d label', [si, i]);
    at := FindNode(si, i, e);
    if at < 0 then Continue;
    Inc(FLabels);
    have := FindLabel(at, cap) and not cap.Ignore;
    SameBool(what + ' drawn', have, not lab.Booleans['ignore']);
    if not have or lab.Booleans['ignore'] then Continue;
    SameStr(what + ' text', cap.Caption.Text, lab.Strings['text']);
    Same(what + ' x', cap.Caption.LmBaseX, lab.Find('x'));
    Same(what + ' y', cap.Caption.LmBaseY, lab.Find('y'));
    SameStr(what + ' align', AlignName(cap.Caption.LmStyleAH), lab.Strings['align']);
    SameStr(what + ' vertical align', VAlignName(cap.Caption.LmStyleAV), lab.Strings['va']);
    { a node coloured by a gradient object hands its label that object
      (inheritColor): the port inks the words in its first stop }
    if lab.Find('fill').JSONType = jtString then
      SameColour(what + ' fill', True, cap.Caption.Colour, lab.Find('fill'));
    SameBool(what + ' stroked', cap.Caption.StrokeWidthLogical > 0, not IsNull(lab.Find('stroke')));
    Same(what + ' opacity', cap.Style.Alpha, lab.Find('opacity'));
    SameInt(what + ' z2', cap.Z2, lab.Integers['z2']);
  end;
end;

procedure TAdvChartChordTest.TestTheLabelsAreUpstreams;
var
  c, s: Integer;
  cs: TJSONObject;
begin
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    FWhere := cs.Strings['id'];
    Show(cs);
    for s := 0 to cs.Arrays['series'].Count - 1 do
      CheckLabels(cs.Arrays['series'].Objects[s]);
  end;
  AssertTrue(Format('enough labels (%d)', [FLabels]), FLabels >= 100);
  Finish('the labels', 900);
end;

{ ==================== the legend ==================== }

procedure TAdvChartChordTest.CheckLegend(ALegend: TJSONData);
var
  items: TJSONArray;
  i: Integer;
  info: TTyLegendLayout;
begin
  if IsNull(ALegend) then Exit;
  items := TJSONObject(ALegend).Arrays['items'];
  info := FChart.LegendLayout(0);
  SameInt('legend items', Length(info.Items), items.Count);
  if Length(info.Items) <> items.Count then Exit;
  for i := 0 to items.Count - 1 do
  begin
    SameStr('legend item ' + IntToStr(i), info.Items[i].Name, items.Objects[i].Strings['name']);
    { a switched-off item wears the theme's inactive ink, not the node's }
    if info.Items[i].Selected then
      SameColour('legend item ' + IntToStr(i) + ' colour', True, info.Items[i].Colour,
        items.Objects[i].Find('fill'));
  end;
end;

procedure TAdvChartChordTest.TestTheLegendFiltersTheNodes;
var
  c, s, k: Integer;
  cs, st: TJSONObject;
  states: TJSONArray;
begin
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['group'] <> 'legend' then Continue;
    FWhere := cs.Strings['id'];
    Show(cs);
    CheckLegend(cs.Find('legend'));
    states := cs.Arrays['states'];
    for k := 1 to states.Count - 1 do
    begin
      FWhere := Format('%s after step %d', [cs.Strings['id'], k]);
      Step(cs.Arrays['steps'].Objects[k - 1]);
      RenderNow(cs.Integers['W'], cs.Integers['H']);
      st := states.Objects[k];
      CheckLegend(st.Find('legend'));
      for s := 0 to st.Arrays['series'].Count - 1 do
      begin
        CheckGraph(st.Arrays['series'].Objects[s]);
        CheckPieces(st.Arrays['series'].Objects[s]);
      end;
    end;
  end;
  Finish('the legend', 1500);
end;

{ ==================== the states and the pointer ==================== }

procedure TAdvChartChordTest.CheckEls(AEls: TJSONArray);
var
  i: Integer;
  o, lab: TJSONObject;
  item: TTyStItem;
  ok: Boolean;
  what: string;
  fillHas: Boolean;
begin
  for i := 0 to AEls.Count - 1 do
  begin
    o := AEls.Objects[i];
    what := Format('s%d %s%d', [o.Integers['s'], o.Strings['k'], o.Integers['raw']]);
    if o.Strings['k'] = 'n' then
      ok := FChart.NodeStates(o.Integers['s'], o.Integers['index'], item)
    else
      ok := FChart.EdgeStates(o.Integers['s'], o.Integers['raw'], item);
    SameBool(what + ' has states', ok, True);
    if not ok then Continue;
    Inc(FStates);
    SameInt(what + ' hover', item.Host.HoverState, o.Integers['hover']);
    SameStr(what + ' states', TyStNamesText(item.Host.States), o.Strings['states']);
    Same(what + ' opacity', item.Host.Cur.Num[stkOpacity], o.Find('opacity'));
    SameInt(what + ' z2', Round(item.Host.Cur.Num[stkZ2]), o.Integers['z2']);
    if o.Find('fill').JSONType = jtString then
    begin
      fillHas := item.Host.Cur.Has[stkFill] and not item.Host.Cur.None[stkFill];
      SameColour(what + ' fill', fillHas, item.Host.Cur.Color[stkFill], o.Find('fill'));
    end;
    if IsNull(o.Find('label')) or not item.Label_.Exists then Continue;
    lab := o.Objects['label'];
    SameBool(what + ' label shown', item.Label_.Cur.Num[stkIgnore] = 0, not lab.Booleans['ignore']);
    if not lab.Booleans['ignore'] then
      Same(what + ' label opacity', item.Label_.Cur.Num[stkOpacity], lab.Find('opacity'));
  end;
end;

type
  TTipRow = record
    Marker, Name, Value: string;
    HasMarker, HasName, HasValue: Boolean;
  end;

function TipRowsText(ABlock: TTyTooltipBlock): string;
var
  ink: TTyTooltipInk;
  lines: TTyTooltipLineArray;
  i, j, k: Integer;
  row: TTipRow;

  function Q(AHas: Boolean; const S: string): string;
  begin
    if AHas then Result := '"' + S + '"' else Result := 'null';
  end;

begin
  Result := '';
  ink := Default(TTyTooltipInk);
  ink.NameWeight := 400;
  ink.ValueWeight := 900;
  ink.MarkerSizeLogical := 10;
  lines := TyTooltipFlatten(ABlock, ink);
  for i := 0 to High(lines) do
  begin
    for k := 1 to lines[i].BlankLinesBefore do Result := Result + '{null null null}';
    row := Default(TTipRow);
    for j := 0 to High(lines[i].Runs) do
      if lines[i].Runs[j].Kind = ttrMarker then
      begin
        row.HasMarker := True;
        if lines[i].Runs[j].MarkerSizeLogical = 10 then row.Marker := 'item'
        else row.Marker := 'subItem';
      end
      else if lines[i].Runs[j].FontWeight = 900 then
      begin
        row.HasValue := True;
        row.Value := lines[i].Runs[j].Text;
      end
      else
      begin
        row.HasName := True;
        row.Name := lines[i].Runs[j].Text;
      end;
    Result := Result + '{' + Q(row.HasMarker, row.Marker) + ' ' + Q(row.HasName, row.Name)
      + ' ' + Q(row.HasValue, row.Value) + '}';
  end;
end;

procedure TAdvChartChordTest.CheckTip(AState: TJSONObject);
var
  tip: TJSONObject;
  lines: TJSONArray;
  k: Integer;
  want, got, which: string;
  block: TTyTooltipBlock;
  d: TTyChartDatumRef;

  function Q(ARow: TJSONObject; const AKey: string): string;
  begin
    if IsNull(ARow.Find(AKey)) then Result := 'null' else Result := '"' + ARow.Strings[AKey] + '"';
  end;

begin
  if IsNull(AState.Find('tip')) then Exit;
  tip := AState.Objects['tip'];
  Inc(FTips);
  { upstream's params.dataIndex is the RAW index, a link's or a node's }
  d := FChart.TooltipShownDatum;
  if d.SeriesIndex < 0 then which := ''
  else if d.IsEdge then which := Format('edge:%d:%d', [d.SeriesIndex, d.RawDataIndex])
  else which := Format('item:%d:%d', [d.SeriesIndex, d.RawDataIndex]);
  SameStr('the tooltip shows', which, tip.Strings['which']);
  if which <> tip.Strings['which'] then Exit;
  lines := tip.Arrays['lines'];
  want := '';
  for k := 0 to lines.Count - 1 do
    want := want + '{' + Q(lines.Objects[k], 'marker') + ' ' + Q(lines.Objects[k], 'name')
      + ' ' + Q(lines.Objects[k], 'value') + '}';
  block := FChart.ContentOf(d);
  try
    if block = nil then got := '' else got := TipRowsText(block);
  finally
    block.Free;
  end;
  SameStr('the tooltip reads', got, want);
end;

procedure TAdvChartChordTest.CheckEvents(AState: TJSONObject);
var
  evs: TJSONArray;
  k: Integer;
  e: TJSONObject;
  p: TTyChartCallbackParams;
  want: string;
begin
  evs := AState.Arrays['events'];
  SameInt('click events', Length(FChart.Events), evs.Count);
  if Length(FChart.Events) <> evs.Count then Exit;
  for k := 0 to evs.Count - 1 do
  begin
    Inc(FEvents);
    e := evs.Objects[k];
    SameBool('event ' + IntToStr(k) + ' has params', FChart.Events[k].HasParams, True);
    p := FChart.Events[k].Params;
    SameStr('event data type', p.DataType, e.Strings['dataType']);
    SameInt('event data index', p.RawDataIndex, e.Integers['dataIndex']);
    SameStr('event name', p.Name, e.Strings['name']);
    SameStr('event series type', p.SeriesType, e.Strings['seriesType']);
    if e.Booleans['valueIsNumber'] then want := TyJsNumberToString(FromHex(e.Strings['value']))
    else if IsNull(e.Find('value')) then want := ''
    else want := e.Strings['value'];
    SameStr('event value', p.ValueText, want);
  end;
end;

procedure TAdvChartChordTest.TestTheStatesAndThePointerAreUpstreams;
var
  c, k: Integer;
  cs, st: TJSONObject;
  states, steps: TJSONArray;
begin
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if (cs.Strings['group'] <> 'state') and (cs.Strings['group'] <> 'hover') then Continue;
    FWhere := cs.Strings['id'];
    Show(cs);
    states := cs.Arrays['states'];
    steps := cs.Arrays['steps'];
    CheckEls(states.Objects[0].Arrays['els']);
    for k := 1 to states.Count - 1 do
    begin
      FWhere := Format('%s step %d %s', [cs.Strings['id'], k - 1, steps.Objects[k - 1].AsJSON]);
      Step(steps.Objects[k - 1]);
      RenderNow(cs.Integers['W'], cs.Integers['H']);
      st := states.Objects[k];
      CheckEls(st.Arrays['els']);
      CheckTip(st);
      CheckEvents(st);
    end;
  end;
  AssertTrue(Format('enough states (%d), tooltips (%d), events (%d)',
    [FStates, FTips, FEvents]), (FStates >= 300) and (FTips >= 10) and (FEvents >= 4));
  Finish('the states and the pointer', 2000);
end;

{ ==================== the conversions ==================== }

procedure TAdvChartChordTest.TestNothingConvertsOnAChord;
var
  cs, p: TJSONObject;
  arr: TJSONArray;
  k: Integer;
  r: TTyConvertResult;
  pt: TJSONArray;
  fd, vd: TJSONData;
begin
  cs := CaseById('convert');
  FWhere := 'convert';
  Show(cs);
  arr := cs.Arrays['convert'];
  for k := 0 to arr.Count - 1 do
  begin
    p := arr.Objects[k];
    if p.Strings['op'] = 'contain' then
    begin
      pt := TJSONArray(GetJSON(p.Strings['value']));
      try
        SameBool('contain ' + p.Strings['value'],
          FChart.ContainPixel(p.Strings['finder'], pt.Floats[0], pt.Floats[1]),
          p.Objects['out'].Booleans['v']);
      finally
        pt.Free;
      end;
    end
    else
    begin
      fd := GetJSON(p.Strings['finder']);
      vd := GetJSON(p.Strings['value']);
      try
        if p.Strings['op'] = 'to' then
          r := FChart.ConvertToPixelData(fd, vd)
        else
          r := FChart.ConvertFromPixelData(fd, vd);
      finally
        fd.Free;
        vd.Free;
      end;
      SameBool(p.Strings['op'] + ' answers nothing', r.Kind = cvkNone,
        p.Objects['out'].Strings['k'] = 'none');
    end;
  end;
  Finish('the conversions', 5);
end;

{ ==================== by hand ==================== }

procedure TAdvChartChordTest.TestADuplicateKeyDrawsNothing;
var S: TTyChordSolved;
begin
  NewChart;
  FChart.SetBounds(0, 0, 400, 300);
  FChart.Option := '{"animation":false,"series":[{"type":"chord","data":[{"name":"A"},'
    + '{"name":"A"}],"links":[{"source":0,"target":1,"value":2}]}]}';
  RenderNow(400, 300);
  S := FChart.ChordSolved(0);
  { upstream's Graph.update indexes the node addNode refused and throws }
  AssertFalse('a second node of one key refuses the graph', S.Valid);
  AssertEquals('and nothing is drawn', 0, FChart.List.Count);
end;

procedure TAdvChartChordTest.TestARibbonIsHitInsideAndNotOutside;
var
  S: TTyChordSolved;
  e: TTyChartElement;
  mid, x, y: Double;
begin
  NewChart;
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Option := '{"animation":false,"series":[{"type":"chord","data":[{"name":"A"},'
    + '{"name":"B"},{"name":"C"}],"links":[{"source":"A","target":"B","value":40},'
    + '{"source":"B","target":"C","value":20}]}]}';
  RenderNow(600, 400);
  S := FChart.ChordSolved(0);
  AssertTrue('laid out', S.Laid);
  AssertTrue('the ribbon is drawn', FindEdge(0, 0, e) >= 0);
  { just inside the circle on its source arc's middle: in the ribbon }
  mid := (S.Edges[0].SStart + S.Edges[0].SEnd) / 2;
  x := S.CX + (S.R0 - 10) * Cos(mid);
  y := S.CY + (S.R0 - 10) * Sin(mid);
  AssertTrue('a point under the source arc is in it', TyShapeContains(e.Shape, x, y, 0));
  { the centre of the ring, between two ribbons that bow toward it but
    stop short: the A -> B ribbon does not reach the far side }
  mid := mid + Pi;
  x := S.CX + (S.R0 - 10) * Cos(mid);
  y := S.CY + (S.R0 - 10) * Sin(mid);
  AssertFalse('the opposite side of the circle is not', TyShapeContains(e.Shape, x, y, 0));
end;

procedure TAdvChartChordTest.TestTheArcsBecomeCubicsOnTheCircle;
var
  p: TTyZrPath;
  cmds: TTyPathCmdArray;
  pts: TTyPointFArray;
  k: Integer;
  r: Double;
begin
  p := nil;
  TyZrMoveTo(p, 110, 100);
  TyZrArc(p, 100, 100, 10, 0, Pi * 1.5, False);
  TyZrClose(p);
  TyZrPathToCmds(p, cmds, pts);
  { a move, the line to the arc's start, three quarter-turn cubics, the close }
  AssertEquals('commands', 6, Length(cmds));
  AssertTrue('a quarter turn a cubic', cmds[2].Kind = pckCurve);
  { every cubic's end on the circle }
  for k := 2 to 4 do
  begin
    r := Sqrt(Sqr(cmds[k].X - 100) + Sqr(cmds[k].Y - 100));
    AssertEquals('on the circle', 10, r, 1e-9);
  end;
  AssertEquals('the last quarter ends at three o''clock less a quarter', 90,
    cmds[4].Y, 1e-9);
  AssertTrue('the outline sampled', Length(pts) > 20);
end;

initialization
  RegisterTest(TAdvChartChordTest);
end.
