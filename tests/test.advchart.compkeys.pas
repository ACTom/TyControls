unit test.advchart.compkeys;
{$mode objfpc}{$H+}
{ THE COMPONENT KEYBOARD [F5].

  ECharts has no keyboard for its components either, so the keys are the
  port's design (tyControls.AdvChart.KeyNav: the focus stops and the parts
  of a component). What can be held to upstream is what every key does:
  the pointer's own handler on that component, with its payload. So the
  oracles here replay the fixtures the pointer suites replay, with the
  pointer's steps done by keys:

  - a legend item hovered and clicked (select-legend): Tab / an arrow onto
    the item, Space for the click -- the events, every series' and the
    legend's state, step by step;
  - a scroll legend's page buttons (legend-scroll): PageDown / PageUp --
    the legendscroll events and the legend as laid out;
  - a slider's handle and window drags that end at an end, an inside's pan
    to an end and its wheel at the grid's centre (datazoom-interact):
    Shift+Home / Shift+End, Home / End, Shift+Left / Shift+Right -- the
    action's numbers and every window, bit for bit;
  - the timeline's next / prev / play buttons and a tick at an end
    (timeline): Right / Left / Space / Home / End -- the model, the timer,
    the events and the view;
  - a piecewise visualMap's pieces hovered and clicked (visualmap-interact):
    the hover link's batches, datarangeselected, the series' states;
  - a geo region highlighted and downplayed by the action (geo-interact):
    the keyboard's own focus is that action.

  The hand-written tests pin the stops, the keys of every component, the
  ring, the accessible tree's component nodes and -- on Windows -- the MSAA
  server's view of them. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, LCLType, LMessages, BGRABitmap, BGRABitmapTypes,
     {$IFDEF WINDOWS} Windows, {$ENDIF} Types,
     tyControls.Controller, tyControls.Types,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Events, tyControls.AdvChart.KeyNav, tyControls.AdvChart.Legend,
     tyControls.AdvChart.DataZoom, tyControls.AdvChart.DataZoomAct, tyControls.AdvChart.DataZoomView,
     tyControls.AdvChart.VisualMapView, tyControls.AdvChart.Geo, tyControls.AdvChart.Toolbox,
     tyControls.AdvChart.Brush, tyControls.AdvChart.Handlers,
     tyControls.Accessible, tyControls.AdvanceChart,
     test.advchart.select, test.advchart.keyboard, test.advchart.legendscroll,
     test.advchart.timeline, test.advchart.datazoominteract,
     test.advchart.visualmapinteract, test.advchart.geointeract;
type
  { the keyboard probe, and coming in by Tab }
  TCkProbe = class(TKbProbe)
  public
    procedure Enter(ABackward: Boolean);
    procedure PtrDown(AX, AY: Integer);
    procedure PtrMove(AX, AY: Integer);
    procedure PtrUp(AX, AY: Integer);
  end;

  TCkZoomLog = class
  public
    Actions: array of TTyDzAction;
    procedure OnZoom(Sender: TObject; const AAction: TTyDzAction);
  end;

  TAdvChartComponentKeysTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCkProbe;
    FBmp: TBGRABitmap;
    FLog: TKbLog;
    FZoom: TCkZoomLog;
    { the events chart.on does not take (restore, showtip): through
      OnChartEvent, filtered }
    FExtra: TStringList;
    procedure OnAny(Sender: TObject; const AEvent: TTyChartEvent);
    procedure Load(const AOption: string; const AEvents: array of string;
      AW: Integer = 600; AH: Integer = 400);
    procedure Frame;
    procedure Logged;
    function Stop: string;
    function StopsText: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheStopTable;
    procedure TestTabWalksTheStopsAndLeavesAtTheEnds;
    procedure TestComingInByTabStartsAtAnEnd;
    procedure TestAnExitKeepsTheComponentsPart;
    procedure TestTheLegendIsThePointerOnItsItems;
    procedure TestAScrollLegendPagesAsItsPager;
    procedure TestTheSelectorButtons;
    procedure TestTheSliderMovesAndResizes;
    procedure TestTheInsidePansAndZooms;
    procedure TestTheTimelineStepsAndPlays;
    procedure TestTheToolboxButtons;
    procedure TestEscapeClearsTheBrush;
    procedure TestTheVisualMapHandles;
    procedure TestTheVisualMapPieces;
    procedure TestAHandleKeyIsAWholeDrag;
    procedure TestAHandleNodeReadsAPointerDrag;
    procedure TestTheMarkersAreItems;
    procedure TestTheGraphEdgesAreItems;
    procedure TestTheGeoRegionsAreItems;
    procedure TestTheRingIsOnThePart;
    procedure TestAComponentKeepsItsKeysInTheChart;
    procedure TestTheTreeHasTheComponents;
    {$IFDEF WINDOWS}
    procedure TestTheMsaaComponents;
    procedure TestTheWindowAnnouncesTheParts;
    {$ENDIF}
  end;

  { the legend's oracle, through the select harness }
  TAdvChartComponentKeysOracleTest = class(TAdvChartSelectHarness)
  published
    procedure TestALegendItemByKeysIsThePointersItem;
  end;

  { the other components' oracles, each through its own suite's harness }
  TAdvChartComponentKeysOracle2Test = class(TTestCase)
  published
    procedure TestAScrollLegendsPagerByKeys;
    procedure TestTheDataZoomsByKeys;
    procedure TestTheTimelineByKeys;
    procedure TestThePiecesByKeys;
    procedure TestTheGeoHighlightByKeys;
  end;

implementation

type
  TLsCrack = class(TAdvChartLegendScrollTest);
  { the harnesses' clock base }
const
  T0 = 1700000000000.0;
type
  TTlCrack = class(TAdvChartTimelineOracleTest);
  TDzCrack = class(TAdvChartDataZoomInteractOracleTest);
  TVmCrack = class(TAdvChartVisualMapInteractOracleTest);
  TGiCrack = class(TAdvChartGeoInteractOracleTest);
  { the keyboard of another suite's probe }
  TAnyKeys = class(TTyAdvanceChart)
  public
    function Key(AKey: Word; AShift: TShiftState = []): Word;
  end;

function TAnyKeys.Key(AKey: Word; AShift: TShiftState): Word;
begin
  Result := AKey;
  KeyDown(Result, AShift);
end;

function Keys(AChart: TTyAdvanceChart): TAnyKeys;
begin
  Result := TAnyKeys(AChart);
end;

procedure TCkProbe.Enter(ABackward: Boolean);
begin
  KbEnter(ABackward);
end;

procedure TCkProbe.PtrDown(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
end;

procedure TCkProbe.PtrMove(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TCkProbe.PtrUp(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

{ a visualMap handle's thumb centre on the canvas }
function CkThumbAt(AChart: TTyAdvanceChart; AHandle: Integer): TPoint;
var
  L: TTyVisualMapLayout;
  pr: TTyXYWH;
  cx, cy: Double;
  M: TTyMat2D;
begin
  L := AChart.VisualMapLayout(0);
  M := L.Handles[AHandle].Thumb;
  pr := L.Handles[AHandle].PathRect;
  cx := pr.X + pr.W / 2;
  cy := pr.Y + pr.H / 2;
  Result := Point(Round(M[0] * cx + M[2] * cy + M[4] + L.GroupX),
    Round(M[1] * cx + M[3] * cy + M[5] + L.GroupY));
end;

procedure TCkZoomLog.OnZoom(Sender: TObject; const AAction: TTyDzAction);
begin
  SetLength(Actions, Length(Actions) + 1);
  Actions[High(Actions)] := AAction;
end;

function StopName(const S: TTyKbStop): string;
const
  cNames: array[TTyKbStopKind] of string = ('items', 'markers', 'geo', 'legend',
    'visualMap', 'dataZoom', 'timeline', 'toolbox', 'brush');
begin
  Result := Format('%s%d/%d', [cNames[S.Kind], S.Index, S.Sub]);
end;

const
  cTwoBars = '"xAxis":{"type":"category","data":["a","b","c","d"]},"yAxis":{},'
    + '"series":[{"type":"bar","name":"A","data":[1,2,3,4]},'
    + '{"type":"bar","name":"B","data":[2,3,1,4]}]';

{ ==================== hand-written ==================== }

procedure TAdvChartComponentKeysTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TCkProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FLog := TKbLog.Create;
  FZoom := TCkZoomLog.Create;
  FChart.OnDataZoom := @FZoom.OnZoom;
  FExtra := TStringList.Create;
  FChart.OnChartEvent := @OnAny;
  FBmp := nil;
end;

procedure TAdvChartComponentKeysTest.OnAny(Sender: TObject; const AEvent: TTyChartEvent);
begin
  if FExtra.IndexOf(AEvent.EventType) >= 0 then FLog.Handle(Sender, AEvent);
end;

procedure TAdvChartComponentKeysTest.TearDown;
begin
  FBmp.Free;
  if FChart <> nil then FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  FLog.Free;
  FZoom.Free;
  FExtra.Free;
  inherited TearDown;
end;

procedure TAdvChartComponentKeysTest.Load(const AOption: string;
  const AEvents: array of string; AW, AH: Integer);
var i: Integer;
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
  FChart.SetBounds(0, 0, AW, AH);
  FChart.ClearKeyboardItem;
  FChart.Option := AOption;
  for i := 0 to High(AEvents) do
    if (FExtra.IndexOf(AEvents[i]) < 0) and (FChart.ChartOn(AEvents[i], @FLog.Handle) < 0) then
      FExtra.Add(AEvents[i]);
  Frame;
  Logged;
  FZoom.Actions := nil;
end;

procedure TAdvChartComponentKeysTest.Frame;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
end;

procedure TAdvChartComponentKeysTest.Logged;
begin
  FLog.Lines.Clear;
end;

function TAdvChartComponentKeysTest.Stop: string;
begin
  Result := StopName(FChart.KeyboardStop) + ':' + IntToStr(FChart.KeyboardPart);
end;

function TAdvChartComponentKeysTest.StopsText: string;
var s: TTyKbStopArray; i: Integer;
begin
  s := FChart.KeyboardStops;
  Result := '';
  for i := 0 to High(s) do
  begin
    if i > 0 then Result := Result + ' ';
    Result := Result + StopName(s[i]);
  end;
end;

{ the pure rules: Tab's walk, the component commands, the part walk }
procedure TAdvChartComponentKeysTest.TestTheStopTable;
var
  n, p: Integer;
  s: TTyKbStopArray;
begin
  AssertTrue(TyKbIsTab(VK_TAB, []));
  AssertTrue('Shift+Tab is the chart''s too', TyKbIsTab(VK_TAB, [ssShift]));
  AssertFalse('Ctrl+Tab is not', TyKbIsTab(VK_TAB, [ssCtrl]));
  AssertFalse(TyKbIsTab(VK_RIGHT, []));
  AssertTrue(TyKbTab(3, 0, False, n));
  AssertEquals(1, n);
  AssertFalse('past the last: the form''s', TyKbTab(3, 2, False, n));
  AssertFalse('before the first: the form''s', TyKbTab(3, 0, True, n));
  AssertTrue(TyKbTab(3, 2, True, n));
  AssertEquals(1, n);
  AssertTrue('no stop counts as the first', TyKbTab(3, -1, False, n));
  AssertEquals(1, n);
  AssertFalse('one stop: Tab leaves', TyKbTab(1, 0, False, n));
  AssertFalse('no stops', TyKbTab(0, -1, False, n));
  AssertTrue(TyKbComponentCommandOf(VK_LEFT, [ssShift]) = kbcShrink);
  AssertTrue(TyKbComponentCommandOf(VK_DOWN, [ssShift]) = kbcShrink);
  AssertTrue(TyKbComponentCommandOf(VK_RIGHT, [ssShift]) = kbcGrow);
  AssertTrue(TyKbComponentCommandOf(VK_UP, [ssShift]) = kbcGrow);
  AssertTrue(TyKbComponentCommandOf(VK_HOME, [ssShift]) = kbcGrowStart);
  AssertTrue(TyKbComponentCommandOf(VK_END, [ssShift]) = kbcGrowEnd);
  AssertTrue(TyKbComponentCommandOf(VK_RIGHT, []) = kbcNext);
  AssertTrue(TyKbComponentCommandOf(VK_SPACE, []) = kbcActivate);
  AssertTrue('Ctrl is not the chart''s', TyKbComponentCommandOf(VK_RIGHT, [ssCtrl]) = kbcNone);
  AssertTrue('Shift+Space is nothing', TyKbComponentCommandOf(VK_SPACE, [ssShift]) = kbcNone);
  AssertTrue(TyKbIsComponentMove(kbcShrink));
  AssertTrue(TyKbIsComponentMove(kbcPageNext));
  AssertFalse(TyKbIsComponentMove(kbcActivate));
  p := -1;
  AssertTrue(TyKbPartMove(3, kbcNext, p));
  AssertEquals('from none: the first part', 0, p);
  p := -1;
  AssertTrue(TyKbPartMove(3, kbcLast, p));
  AssertEquals('End from none: the last', 2, p);
  AssertFalse('no wrap', TyKbPartMove(3, kbcNext, p));
  AssertTrue('Up is the previous', TyKbPartMove(3, kbcPrevSeries, p));
  AssertEquals(1, p);
  AssertTrue('Down the next', TyKbPartMove(3, kbcNextSeries, p));
  AssertEquals(2, p);
  p := 0;
  AssertTrue(TyKbPartMove(25, kbcPageNext, p));
  AssertEquals('a page is a tenth', 3, p);
  AssertFalse('not a move', TyKbPartMove(3, kbcActivate, p));
  SetLength(s, 2);
  s[0] := TyKbStop(ksItems, 0, 0);
  s[1] := TyKbStop(ksVisualMap, 2, 1);
  AssertEquals(1, TyKbStopPos(s, TyKbStop(ksVisualMap, 2, 1)));
  AssertEquals('the other handle is another stop', -1, TyKbStopPos(s, TyKbStop(ksVisualMap, 2, 0)));
end;

procedure TAdvChartComponentKeysTest.TestTabWalksTheStopsAndLeavesAtTheEnds;
var
  order: TStringList;
  i: Integer;
begin
  Load('{"animation":false,"legend":{},"toolbox":{"feature":{"restore":{}}},'
    + '"brush":{},"dataZoom":[{"type":"slider"}],'
    + '"visualMap":{"type":"continuous","min":0,"max":10,"calculable":true,"seriesIndex":0},'
    + '"xAxis":{"type":"category","data":["a","b","c","d"]},"yAxis":{},'
    + '"series":[{"type":"bar","name":"A","data":[1,2,3,4],'
    + '"markPoint":{"data":[{"type":"max"},{"type":"min"}]}}]}', []);
  AssertEquals('the stops in their order',
    'items0/0 markers0/0 legend0/0 visualMap0/0 visualMap0/1 dataZoom0/0 toolbox0/0 brush0/0',
    StopsText);
  AssertEquals('the items first', 'items0/0:-1', Stop);
  order := TStringList.Create;
  try
    for i := 1 to 7 do
    begin
      AssertEquals('Tab is taken while a stop follows', 0, FChart.Key(VK_TAB));
      order.Add(Stop);
    end;
    AssertEquals('a part taken up as Tab lands',
      'markers0/0:0,legend0/0:0,visualMap0/0:0,visualMap0/1:0,dataZoom0/0:0,toolbox0/0:0,brush0/0:0',
      order.CommaText);
    AssertEquals('past the last stop Tab is the form''s', VK_TAB, FChart.Key(VK_TAB));
    AssertEquals('brush0/0:0', Stop);
    order.Clear;
    for i := 1 to 7 do
    begin
      AssertEquals('Shift+Tab is taken while a stop precedes', 0, FChart.Key(VK_TAB, [ssShift]));
      order.Add(Stop);
    end;
    AssertEquals('Shift+Tab walks back',
      'toolbox0/0:0,dataZoom0/0:0,visualMap0/1:0,visualMap0/0:0,legend0/0:0,markers0/0:0,items0/0:-1',
      order.CommaText);
    AssertEquals('before the first Shift+Tab is the form''s', VK_TAB, FChart.Key(VK_TAB, [ssShift]));
    AssertEquals('Ctrl+Tab is never the chart''s', VK_TAB, FChart.Key(VK_TAB, [ssCtrl]));
  finally
    order.Free;
  end;
  { the items' stop takes its item up again as Tab lands back on it }
  FChart.Key(VK_RIGHT);
  AssertEquals(0, FChart.KeyboardItem.DataIndex);
  FChart.Key(VK_TAB);
  AssertFalse('the item lets go', TyChartDatumValid(FChart.KeyboardItem));
  FChart.Key(VK_TAB, [ssShift]);
  AssertEquals('and comes back', 0, FChart.KeyboardItem.DataIndex);
end;

procedure TAdvChartComponentKeysTest.TestComingInByTabStartsAtAnEnd;
begin
  Load('{"animation":false,"legend":{},"dataZoom":[{"type":"inside"}],' + cTwoBars + '}', []);
  FChart.Enter(True);
  AssertEquals('Shift+Tab in: the last stop, nothing taken yet', 'dataZoom0/0:-1', Stop);
  FChart.Enter(False);
  AssertEquals('Tab in: the first', 'items0/0:-1', Stop);
  FChart.Key(VK_TAB);
  AssertEquals('legend0/0:0', Stop);
  { a click in keeps the stop: KbEnter is only Tab's }
  FChart.Enter(True);
  AssertEquals('dataZoom0/0:-1', Stop);
  FChart.Key(VK_RIGHT);
  AssertEquals('a stop of one part: the first key takes it up and acts', 'dataZoom0/0:0', Stop);
end;

procedure TAdvChartComponentKeysTest.TestAnExitKeepsTheComponentsPart;
begin
  Load('{"animation":false,"legend":{},' + cTwoBars + '}', ['highlight', 'downplay']);
  FChart.Key(VK_TAB);
  FChart.Key(VK_RIGHT);
  Logged;
  FChart.LeaveFocus;
  AssertEquals('an exit lets the part go', 'legend0/0:-1', Stop);
  AssertEquals('the pointer leaving',
    'downplay {"type":"downplay","seriesName":"B","name":null,"excludeSeriesId":[]}', FLog.Text);
  Logged;
  AssertEquals('the first key back is taken', 0, FChart.Key(VK_LEFT));
  AssertEquals('and takes the same part up, without moving', 'legend0/0:1', Stop);
  AssertEquals('highlight {"type":"highlight","seriesName":"B","name":null,"excludeSeriesId":[]}',
    FLog.Text);
  AssertEquals(VK_RETURN, FChart.Key(VK_RETURN, [ssCtrl]));
  FChart.Key(VK_ESCAPE);
  AssertEquals('Escape forgets it', 'legend0/0:-1', Stop);
  FChart.Key(VK_END);
  AssertEquals('after Escape a key starts from the ends', 'legend0/0:1', Stop);
  FChart.ClearKeyboardItem;
  AssertEquals('nothing held anywhere: the items again', 'items0/0:-1', Stop);
end;

procedure TAdvChartComponentKeysTest.TestTheLegendIsThePointerOnItsItems;
var L: TTyLegendLayout;
begin
  Load('{"animation":false,"legend":{},' + cTwoBars + '}',
    ['highlight', 'downplay', 'legendselectchanged']);
  AssertEquals(0, FChart.Key(VK_TAB));
  AssertEquals('legend0/0:0', Stop);
  AssertEquals('the item''s mouseover: the highlight action',
    'highlight {"type":"highlight","seriesName":"A","name":null,"excludeSeriesId":[]}', FLog.Text);
  Logged;
  AssertEquals(0, FChart.Key(VK_RIGHT));
  AssertEquals('legend0/0:1', Stop);
  AssertEquals('downplay {"type":"downplay","seriesName":"A","name":null,"excludeSeriesId":[]} | '
    + 'highlight {"type":"highlight","seriesName":"B","name":null,"excludeSeriesId":[]}', FLog.Text);
  Logged;
  AssertEquals('Space is the click', 0, FChart.Key(VK_SPACE));
  AssertEquals('downplay, legendToggleSelect, highlight',
    'downplay {"type":"downplay","seriesName":"B","name":null,"excludeSeriesId":[]} | '
    + 'legendselectchanged {"name":"B","selected":{"A":true,"B":false},"type":"legendselectchanged"} | '
    + 'highlight {"type":"highlight","seriesName":"B","name":null,"excludeSeriesId":[]}', FLog.Text);
  Frame;
  L := FChart.LegendLayout(0);
  AssertFalse('B is off', L.Items[1].Selected);
  AssertEquals('Enter too', 0, FChart.Key(VK_RETURN));
  Frame;
  AssertTrue('B is on again', FChart.LegendLayout(0).Items[1].Selected);
  Logged;
  AssertEquals('Escape lets the item go', 0, FChart.Key(VK_ESCAPE));
  AssertEquals('downplay {"type":"downplay","seriesName":"B","name":null,"excludeSeriesId":[]}', FLog.Text);
  AssertEquals('with nothing held Escape is the form''s', VK_ESCAPE, FChart.Key(VK_ESCAPE));
  AssertEquals('so is Enter', VK_RETURN, FChart.Key(VK_RETURN));
  { a legend that selects nothing leaves Enter and Space to the form }
  Load('{"animation":false,"legend":{"selectedMode":false},' + cTwoBars + '}',
    ['legendselectchanged']);
  FChart.Key(VK_TAB);
  Logged;
  AssertEquals(VK_SPACE, FChart.Key(VK_SPACE));
  AssertEquals('', FLog.Text);
end;

procedure TAdvChartComponentKeysTest.TestAScrollLegendPagesAsItsPager;
var
  s: string;
  i, n: Integer;
  L: TTyLegendLayout;
begin
  s := '';
  for i := 0 to 29 do
  begin
    if i > 0 then s := s + ',';
    s := s + '{"type":"bar","name":"Series ' + IntToStr(i) + '","data":[1,2]}';
  end;
  Load('{"animation":false,"legend":{"type":"scroll"},"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{},"series":[' + s + ']}', ['legendscroll']);
  FChart.Key(VK_TAB);
  AssertEquals('legend0/0:0', Stop);
  L := FChart.LegendLayout(0);
  AssertTrue('the pager shows', L.ShowController);
  n := L.PageNextIndex;
  AssertTrue(n > 0);
  AssertEquals('PageDown is the next page button', 0, FChart.Key(VK_NEXT));
  AssertTrue('the pager''s legendscroll', Pos('legendscroll {"type":"legendscroll","scrollDataIndex":'
    + IntToStr(n) + ',"legendId":', FLog.Text) = 1);
  AssertEquals('the page''s first item', 'legend0/0:' + IntToStr(n), Stop);
  Logged;
  FChart.Key(VK_PRIOR);
  AssertEquals('PageUp the previous', 'legend0/0:0', Stop);
  AssertEquals(1, FLog.Lines.Count);
  { End: the pager a page at a time until the last item shows }
  FChart.Key(VK_END);
  AssertEquals('legend0/0:29', Stop);
  Frame;
  L := FChart.LegendLayout(0);
  AssertEquals('the last page', L.PageCount - 1, L.PageIndex);
  { Home: back to the first page }
  FChart.Key(VK_HOME);
  Frame;
  AssertEquals(0, FChart.LegendLayout(0).PageIndex);
  AssertEquals('legend0/0:0', Stop);
end;

procedure TAdvChartComponentKeysTest.TestTheSelectorButtons;
begin
  Load('{"animation":false,"legend":{"selector":true},' + cTwoBars + '}',
    ['legendselectall', 'legendinverseselect']);
  FChart.Key(VK_TAB);
  FChart.Key(VK_END);
  AssertEquals('the parts: the items, then the selector''s buttons', 'legend0/0:3', Stop);
  AssertEquals(0, FChart.Key(VK_SPACE));
  AssertEquals('the inverse button''s click', 'legendinverseselect',
    Copy(FLog.Text, 1, Length('legendinverseselect')));
  Frame;
  AssertFalse(FChart.LegendLayout(0).Items[0].Selected);
  FChart.Key(VK_LEFT);
  Logged;
  FChart.Key(VK_RETURN);
  AssertEquals('the all button''s', 'legendselectall', Copy(FLog.Text, 1, Length('legendselectall')));
  Frame;
  AssertTrue(FChart.LegendLayout(0).Items[0].Selected);
end;

procedure TAdvChartComponentKeysTest.TestTheSliderMovesAndResizes;
var
  st: TTyDzSliderState;

  procedure Range(const AWhat: string; ALo, AHi: Double);
  begin
    st := FChart.DataZoomSliderState(0);
    AssertEquals(AWhat + ' start', ALo, st.Range[0], 1e-9);
    AssertEquals(AWhat + ' end', AHi, st.Range[1], 1e-9);
  end;

const
  cData = '"xAxis":{"type":"category","data":["c0","c1","c2","c3","c4","c5","c6","c7","c8",'
    + '"c9","c10","c11","c12","c13","c14","c15","c16","c17","c18","c19"]},"yAxis":{},'
    + '"series":[{"type":"line","data":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20]}]';
begin
  Load('{"animation":false,"dataZoom":[{"type":"slider","start":20,"end":60}],' + cData + '}', [], 800, 600);
  FChart.Key(VK_TAB);
  AssertEquals('dataZoom0/0:0', Stop);
  AssertTrue('the window''s labels, as over the filler', FChart.DataZoomSliderState(0).LabelsShown);
  AssertEquals(0, FChart.Key(VK_RIGHT));
  Range('a tenth of the window right', 24, 64);
  AssertEquals('one action', 1, Length(FZoom.Actions));
  AssertEquals('the slider''s own', 0, FZoom.Actions[0].FromSlider);
  AssertFalse('not a batch', FZoom.Actions[0].Batch);
  AssertFalse('the panel click''s: no realtime animation', FZoom.Actions[0].Realtime);
  FChart.Key(VK_HOME);
  Range('Home', 0, 40);
  FChart.Key(VK_END);
  Range('End', 60, 100);
  FChart.Key(VK_PRIOR);
  Range('PageUp: a window back', 20, 60);
  FChart.Key(VK_UP);
  Range('Up is toward the end', 24, 64);
  FChart.Key(VK_DOWN);
  Range('Down toward the start', 20, 60);
  FChart.Key(VK_LEFT, [ssShift]);
  Range('Shift+Left: the end handle a tenth in', 20, 56);
  FChart.Key(VK_RIGHT, [ssShift]);
  Range('Shift+Right: out by a tenth of this window', 20, 59.6);
  FChart.Key(VK_HOME, [ssShift]);
  Range('Shift+Home: the start handle to the start', 0, 59.6);
  FChart.Key(VK_END, [ssShift]);
  Range('Shift+End: the end handle to the end', 0, 100);
  FZoom.Actions := nil;
  AssertEquals('taken at the ends', 0, FChart.Key(VK_RIGHT));
  AssertEquals('nothing moves, nothing dispatched', 0, Length(FZoom.Actions));
  FChart.Key(VK_ESCAPE);
  AssertFalse('the labels go with the part', FChart.DataZoomSliderState(0).LabelsShown);
  { zoomLock: a handle moves the window, as in the drag }
  Load('{"animation":false,"dataZoom":[{"type":"slider","start":20,"end":60,"zoomLock":true}],'
    + cData + '}', [], 800, 600);
  FChart.Key(VK_TAB);
  FChart.Key(VK_LEFT, [ssShift]);
  Range('zoomLock', 16, 56);
end;

procedure TAdvChartComponentKeysTest.TestTheInsidePansAndZooms;
var
  lo, hi: Double;

  procedure Range(const AWhat: string; ALo, AHi: Double);
  begin
    FChart.DataZoomInsideRange(0, lo, hi);
    AssertEquals(AWhat + ' start', ALo, lo, 1e-9);
    AssertEquals(AWhat + ' end', AHi, hi, 1e-9);
  end;

const
  cData = '"xAxis":{"type":"category","data":["a","b","c","d","e","f","g","h"]},"yAxis":{},'
    + '"series":[{"type":"bar","data":[1,2,3,4,5,6,7,8]}]';
begin
  Load('{"animation":false,"dataZoom":[{"type":"inside","start":20,"end":60}],' + cData + '}', [], 800, 600);
  FChart.Key(VK_TAB);
  AssertEquals('dataZoom0/0:0', Stop);
  FChart.Key(VK_RIGHT);
  Range('the pan by a tenth', 24, 64);
  AssertEquals(1, Length(FZoom.Actions));
  AssertTrue('the roam''s batch', FZoom.Actions[0].Batch);
  FChart.Key(VK_HOME);
  Range('Home', 0, 40);
  FChart.Key(VK_END);
  Range('End', 60, 100);
  { a wheel notch in about the grid's centre: the window's own centre }
  FChart.Key(VK_LEFT, [ssShift]);
  Range('one notch in', 80 - 20 / 1.1, 80 + 20 / 1.1);
  FChart.Key(VK_RIGHT, [ssShift]);
  Range('one notch out', 60, 100);
  Load('{"animation":false,"dataZoom":[{"type":"inside","start":20,"end":60,"zoomLock":true}],'
    + cData + '}', [], 800, 600);
  FChart.Key(VK_TAB);
  FZoom.Actions := nil;
  AssertEquals('zoomLock: still taken', 0, FChart.Key(VK_LEFT, [ssShift]));
  AssertEquals('no zoom', 0, Length(FZoom.Actions));
  Range('zoomLock', 20, 60);
  FChart.Key(VK_RIGHT);
  Range('it still pans', 24, 64);
end;

procedure TAdvChartComponentKeysTest.TestTheTimelineStepsAndPlays;
const
  cOpt = '{"baseOption":{"animation":false,"timeline":{"axisType":"category",'
    + '"data":["2002","2003","2004","2005"]},'
    + '"xAxis":{"type":"category","data":["A"]},"yAxis":{},"series":[{"type":"bar"}]},'
    + '"options":[{"series":[{"data":[1]}]},{"series":[{"data":[2]}]},'
    + '{"series":[{"data":[3]}]},{"series":[{"data":[4]}]}]}';
begin
  Load(cOpt, ['timelinechanged', 'timelineplaychanged']);
  FChart.TimelineNow := 1000;
  AssertEquals('the timeline is a stop', 'items0/0 timeline0/0', StopsText);
  FChart.Key(VK_TAB);
  AssertEquals('timeline0/0:0', Stop);
  AssertEquals(0, FChart.Key(VK_RIGHT));
  Frame;
  AssertEquals('the next button''s', 1, FChart.TimelineView.CurrentIndex, 0);
  AssertEquals(1, FLog.Lines.Count);
  AssertTrue(Pos('timelinechanged {"currentIndex":1,', FLog.Text) = 1);
  FChart.Key(VK_END);
  Frame;
  AssertEquals('End: the last tick''s', 3, FChart.TimelineView.CurrentIndex, 0);
  FChart.Key(VK_LEFT);
  Frame;
  AssertEquals('the prev button''s', 2, FChart.TimelineView.CurrentIndex, 0);
  FChart.Key(VK_HOME);
  Frame;
  AssertEquals('Home: the first tick''s', 0, FChart.TimelineView.CurrentIndex, 0);
  Logged;
  AssertEquals('Space is the play button', 0, FChart.Key(VK_SPACE));
  Frame;
  AssertTrue('playing', FChart.TimelineView.PlayState);
  AssertTrue(Pos('timelineplaychanged {"type":"timelineplaychanged","playState":true', FLog.Text) = 1);
  AssertFalse('a timer is set', IsNan(FChart.TimelineDue));
  FChart.Key(VK_SPACE);
  Frame;
  AssertFalse('the stop button''s', FChart.TimelineView.PlayState);
  AssertEquals('Enter is the form''s', VK_RETURN, FChart.Key(VK_RETURN));
end;

procedure TAdvChartComponentKeysTest.TestTheToolboxButtons;
var
  spec: TTyToolboxSpec;
  i, restore: Integer;
  emph, title, pa, aa: Boolean;
begin
  Load('{"animation":false,"toolbox":{"feature":{"dataZoom":{},"restore":{}}},' + cTwoBars + '}',
    ['restore']);
  AssertTrue(Pos('toolbox0/0', StopsText) > 0);
  FChart.Key(VK_TAB);
  AssertEquals('toolbox0/0:0', Stop);
  FChart.ToolboxFrame;
  AssertTrue(FChart.ToolboxIconState(0, 0, emph, title, pa, aa));
  AssertTrue('the icon''s emphasis, as hovered', emph);
  AssertTrue('its title shows', title);
  spec := FChart.ToolboxSpec(0);
  restore := -1;
  for i := 0 to High(spec.Icons) do
    if spec.Icons[i].Feature = 'restore' then restore := i;
  AssertTrue(restore > 0);
  FChart.Key(VK_END);
  AssertEquals('toolbox0/0:' + IntToStr(restore), Stop);
  FChart.ToolboxFrame;
  FChart.ToolboxIconState(0, 0, emph, title, pa, aa);
  AssertFalse('the first icon left', title);
  AssertEquals('Enter is the click', 0, FChart.Key(VK_RETURN));
  AssertEquals('restore {"type":"restore"}', FLog.Text);
  { the zoom icon's click: the select cursor taken }
  FChart.Key(VK_HOME);
  FChart.Key(VK_SPACE);
  AssertTrue('the zoom icon', FChart.ToolboxZoomActive);
end;

procedure TAdvChartComponentKeysTest.TestEscapeClearsTheBrush;
var c: TTyBrushController;
begin
  Load('{"animation":false,"brush":{"xAxisIndex":0},' + cTwoBars + '}', ['brush']);
  AssertTrue(FChart.DispatchAction('{"type":"brush","areas":[{"brushType":"lineX",'
    + '"coordRange":[1,2],"xAxisIndex":0}]}'));
  Frame;
  c := FChart.BrushControllerOf(0);
  AssertEquals('one cover', 1, Length(c.Covers));
  AssertEquals('the brush puts its buttons in a toolbox', 'items0/0 toolbox0/0 brush0/0', StopsText);
  FChart.AccessibleSync;
  AssertEquals('the brush''s node says its areas', '1 selected areas',
    FChart.AccessibleStopNode(TyKbStop(ksBrush, 0, 0), 0).AccessibleValue);
  FChart.Key(VK_TAB);
  FChart.Key(VK_TAB);
  AssertEquals('brush0/0:0', Stop);
  AssertEquals('arrows stay in the chart', 0, FChart.Key(VK_LEFT));
  Logged;
  AssertEquals('Escape is the clear button', 0, FChart.Key(VK_ESCAPE));
  Frame;
  AssertEquals('no cover', 0, Length(FChart.BrushControllerOf(0).Covers));
  FChart.AccessibleSync;
  AssertEquals('and now none', '0 selected areas',
    FChart.AccessibleStopNode(TyKbStop(ksBrush, 0, 0), 0).AccessibleValue);
  AssertTrue('the brush action with no areas', Pos('brush {"type":"brush","command":"clear","areas":[]', FLog.Text) = 1);
  AssertEquals('nothing to clear: the form''s', VK_ESCAPE, FChart.Key(VK_ESCAPE));
  AssertEquals('nothing to activate', VK_RETURN, FChart.Key(VK_RETURN));
end;

procedure TAdvChartComponentKeysTest.TestTheVisualMapHandles;
var live: TTyVmLive;
begin
  Load('{"animation":false,"visualMap":{"type":"continuous","min":0,"max":100,"calculable":true},'
    + '"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{},'
    + '"series":[{"type":"bar","data":[10,50,90]}]}', ['datarangeselected']);
  AssertEquals('a stop per handle', 'items0/0 visualMap0/0 visualMap0/1', StopsText);
  FChart.Key(VK_TAB);
  AssertEquals('visualMap0/0:0', Stop);
  live := FChart.VisualMapLive(0);
  AssertTrue('the thumb in emphasis, as hovered', live.ThumbEmph[0]);
  AssertEquals(0, FChart.Key(VK_RIGHT));
  live := FChart.VisualMapLive(0);
  AssertEquals('a fiftieth of the bar up', 2, live.Interval[0], 1e-6);
  AssertEquals(100, live.Interval[1], 1e-9);
  AssertTrue('the drag''s selectDataRange (realtime)', Pos('datarangeselected', FLog.Text) = 1);
  AssertEquals(1, FLog.Lines.Count);
  FChart.Key(VK_PRIOR);
  AssertEquals('a page down is a tenth, clamped', 0, FChart.VisualMapLive(0).Interval[0], 1e-9);
  FChart.Key(VK_TAB);
  AssertEquals('visualMap0/1:0', Stop);
  AssertFalse('the first thumb left', FChart.VisualMapLive(0).ThumbEmph[0]);
  AssertTrue(FChart.VisualMapLive(0).ThumbEmph[1]);
  FChart.Key(VK_DOWN);
  AssertEquals('Down lowers the end', 98, FChart.VisualMapLive(0).Interval[1], 1e-6);
  FChart.Key(VK_HOME);
  AssertEquals('Home: down to the other handle (no crossing)', 0,
    FChart.VisualMapLive(0).Interval[1], 1e-9);
  FChart.Key(VK_END);
  AssertEquals(100, FChart.VisualMapLive(0).Interval[1], 1e-9);
  FChart.Key(VK_ESCAPE);
  AssertFalse(FChart.VisualMapLive(0).ThumbEmph[1]);
end;

{ [fin] a key on a handle is a whole drag -- the move AND the release: a
  drag that is not realtime dispatches only at its release; and the handle's
  node in the same tree reads the value the key left }
procedure TAdvChartComponentKeysTest.TestAHandleKeyIsAWholeDrag;
var
  live: TTyVmLive;
  n: TLazAccessibleObject;
begin
  Load('{"animation":false,"visualMap":{"type":"continuous","min":0,"max":100,"calculable":true,'
    + '"realtime":false},"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{},'
    + '"series":[{"type":"bar","data":[10,50,90]}]}', ['datarangeselected']);
  FChart.AccessibleSync;
  n := FChart.AccessibleStopNode(TyKbStop(ksVisualMap, 0, 0), 0);
  AssertTrue('the start handle''s node', n <> nil);
  AssertEquals('0', n.AccessibleValue);
  FChart.Key(VK_TAB);
  AssertEquals('visualMap0/0:0', Stop);
  AssertEquals(0, FChart.Key(VK_RIGHT));
  live := FChart.VisualMapLive(0);
  AssertEquals('a fiftieth of the bar up', 2, live.Interval[0], 1e-6);
  AssertFalse('released: no drag left running', live.Dragging);
  AssertEquals('not realtime: the release dispatches', 1, FLog.Lines.Count);
  AssertTrue(Pos('datarangeselected', FLog.Text) = 1);
  FChart.AccessibleSync;
  n := FChart.AccessibleStopNode(TyKbStop(ksVisualMap, 0, 0), 0);
  AssertEquals('the node reads the value the key left', '2', n.AccessibleValue);
end;

{ [fin] A VALUE THAT MOVES WITH NO NEW LAYOUT: a pointer drag of a handle
  that is not realtime moves the handle and dispatches nothing until the
  release -- the same tree, and its node's value read again on the sync }
procedure TAdvChartComponentKeysTest.TestAHandleNodeReadsAPointerDrag;
var
  p: TPoint;
  n0, n: TLazAccessibleObject;
begin
  Load('{"animation":false,"visualMap":{"type":"continuous","min":0,"max":100,"calculable":true,'
    + '"realtime":false,"right":20,"top":"middle"},"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{},"series":[{"type":"bar","data":[10,50,90]}]}', ['datarangeselected']);
  FChart.AccessibleSync;
  n0 := FChart.AccessibleStopNode(TyKbStop(ksVisualMap, 0, 1), 0);
  AssertTrue('the end handle''s node', n0 <> nil);
  AssertEquals('100', n0.AccessibleValue);
  p := CkThumbAt(FChart, 1);
  AssertEquals('the press is on the upper thumb', 'vm0.handle1', FChart.VisualMapRoleAt(p.X, p.Y));
  FChart.PtrMove(p.X, p.Y);
  FChart.PtrDown(p.X, p.Y);
  FChart.PtrMove(p.X, p.Y + 20);
  AssertTrue('it drags', FChart.VisualMapLive(0).Dragging);
  AssertEquals('nothing dispatched yet', 0, FLog.Lines.Count);
  AssertTrue('the handle moved', FChart.VisualMapLive(0).Interval[1] < 100);
  FChart.AccessibleSync;
  n := FChart.AccessibleStopNode(TyKbStop(ksVisualMap, 0, 1), 0);
  AssertTrue('no new layout: the same tree', n = n0);
  AssertEquals('its value read again', TyChartValueText(FChart.VisualMapLive(0).Interval[1]),
    n.AccessibleValue);
  FChart.PtrUp(p.X, p.Y + 20);
end;

procedure TAdvChartComponentKeysTest.TestTheVisualMapPieces;
begin
  Load('{"animation":false,"visualMap":{"type":"piecewise","pieces":[{"lt":5},{"gte":5}]},'
    + '"xAxis":{"type":"category","data":["a","b","c","d"]},"yAxis":{},'
    + '"series":[{"type":"bar","data":[1,3,6,8]}]}',
    ['highlight', 'downplay', 'datarangeselected']);
  AssertEquals('items0/0 visualMap0/0', StopsText);
  FChart.Key(VK_TAB);
  AssertEquals('visualMap0/0:0', Stop);
  AssertTrue('the hover link''s highlight', Pos('highlight {"type":"highlight","batch":[', FLog.Text) = 1);
  Logged;
  FChart.Key(VK_RIGHT);
  AssertEquals('visualMap0/0:1', Stop);
  AssertTrue(Pos('downplay', FLog.Text) = 1);
  AssertTrue(Pos(' | highlight', FLog.Text) > 0);
  Logged;
  AssertEquals('Space is the item''s click', 0, FChart.Key(VK_SPACE));
  AssertTrue(Pos('datarangeselected', FLog.Text) = 1);
  AssertTrue('a piece off: ' + FLog.Text, Pos('false', FLog.Text) > 0);
end;

procedure TAdvChartComponentKeysTest.TestTheMarkersAreItems;
begin
  Load('{"animation":false,"tooltip":{},' + '"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{},"series":[{"type":"bar","data":[3,9,1],'
    + '"markPoint":{"data":[{"type":"max","name":"Top"},{"type":"min","name":"Low"}]}}]}', []);
  FChart.TooltipNow := 1000;
  AssertEquals('items0/0 markers0/0', StopsText);
  FChart.Key(VK_TAB);
  AssertEquals('markers0/0:0', Stop);
  AssertTrue('the marker''s tooltip', FChart.TooltipShown);
  FChart.Key(VK_RIGHT);
  AssertEquals('markers0/0:1', Stop);
  AssertEquals('no more markers', 0, FChart.Key(VK_RIGHT));
  AssertEquals('markers0/0:1', Stop);
  AssertEquals('a marker selects nothing', VK_RETURN, FChart.Key(VK_RETURN));
  FChart.Key(VK_ESCAPE);
  FChart.TooltipTick(5000);
  AssertFalse('its tooltip goes with it', FChart.TooltipShown);
  { [fin] a mark model with no marks is no stop: nothing to walk }
  Load('{"animation":false,' + '"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{},"series":[{"type":"bar","data":[3,9,1],"markPoint":{"data":[]}}]}', []);
  AssertEquals('no marks, no stop', 'items0/0', StopsText);
end;

procedure TAdvChartComponentKeysTest.TestTheGraphEdgesAreItems;
var d: TTyChartDatumRef;
begin
  Load('{"animation":false,"series":[{"type":"graph","layout":"none","selectedMode":"single",'
    + '"data":[{"name":"A","x":0,"y":0},{"name":"B","x":100,"y":0},{"name":"C","x":50,"y":80}],'
    + '"links":[{"source":"A","target":"B"},{"source":"B","target":"C"}]}]}',
    ['highlight', 'downplay', 'selectchanged']);
  FChart.Key(VK_RIGHT);
  AssertEquals('highlight {"type":"highlight","seriesIndex":0,"dataIndex":0}', FLog.Text);
  Logged;
  AssertEquals('Down: the graph''s edges', 0, FChart.Key(VK_DOWN));
  AssertEquals('downplay {"type":"downplay","seriesIndex":0,"dataIndex":0} | '
    + 'highlight {"type":"highlight","seriesIndex":0,"dataType":"edge","dataIndex":0}', FLog.Text);
  d := FChart.KeyboardItem;
  AssertTrue('an edge', d.IsEdge);
  AssertEquals(0, d.RawDataIndex);
  Logged;
  FChart.Key(VK_RIGHT);
  AssertEquals('downplay {"type":"downplay","seriesIndex":0,"dataType":"edge","dataIndex":0} | '
    + 'highlight {"type":"highlight","seriesIndex":0,"dataType":"edge","dataIndex":1}', FLog.Text);
  Logged;
  AssertEquals('Enter is the edge''s click', 0, FChart.Key(VK_RETURN));
  AssertTrue(Pos('selectchanged', FLog.Text) = 1);
  FChart.AccessibleSync;
  AssertTrue('the edge''s item in the tree', FChart.AccessibleFocusedChild <> nil);
  AssertEquals('B > C', FChart.AccessibleFocusedChild.AccessibleName);
  AssertTrue('selected', FChart.AccessibleSelected(FChart.AccessibleFocusedChild));
  FChart.Key(VK_UP);
  AssertFalse('back on the nodes', FChart.KeyboardItem.IsEdge);
  AssertEquals('the row kept', 1, FChart.KeyboardItem.DataIndex);
  AssertTrue('an edge by its raw index', FChart.SetKeyboardItem(0, 0, True));
  AssertTrue(FChart.KeyboardItem.IsEdge);
end;

procedure TAdvChartComponentKeysTest.TestTheGeoRegionsAreItems;
const
  cMap = '{"type":"FeatureCollection","features":['
    + '{"type":"Feature","properties":{"name":"A"},"geometry":{"type":"Polygon",'
    + '"coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}},'
    + '{"type":"Feature","properties":{"name":"B"},"geometry":{"type":"Polygon",'
    + '"coordinates":[[[20,0],[30,0],[30,10],[20,10],[20,0]]]}}]}';
begin
  AssertTrue(TyChartRegisterMap('f5keys', cMap));
  try
    Load('{"animation":false,"tooltip":{},"geo":{"map":"f5keys","selectedMode":"single"}}',
      ['highlight', 'downplay', 'geoselectchanged', 'showtip']);
    AssertEquals('geo0/0', StopsText);
    FChart.TooltipNow := 1000;
    AssertEquals('the only stop: Tab leaves', VK_TAB, FChart.Key(VK_TAB));
    AssertEquals(0, FChart.Key(VK_RIGHT));
    AssertEquals('geo0/0:0', Stop);
    { the showTip, then the view's own (TooltipView._tryShow dispatches one
      from itself after a component's tooltip) }
    AssertEquals(3, FLog.Lines.Count);
    AssertEquals('highlight {"type":"highlight","geoIndex":0,"name":"A"}', FLog.Lines[0]);
    AssertEquals('showtip {"type":"showtip","geoIndex":0,"name":"A"}', FLog.Lines[1]);
    AssertTrue(Pos('showtip {"type":"showtip","from":', FLog.Lines[2]) = 1);
    AssertTrue('the region''s tooltip', FChart.TooltipShown);
    Logged;
    FChart.Key(VK_RIGHT);
    AssertEquals('downplay {"type":"downplay","geoIndex":0,"name":"A"}', FLog.Lines[0]);
    AssertEquals('highlight {"type":"highlight","geoIndex":0,"name":"B"}', FLog.Lines[1]);
    AssertEquals('showtip {"type":"showtip","geoIndex":0,"name":"B"}', FLog.Lines[2]);
    Logged;
    AssertEquals('Enter is the region''s click', 0, FChart.Key(VK_RETURN));
    AssertTrue(Pos('geoselectchanged', FLog.Text) = 1);
    AssertTrue(Pos('"B":true', FLog.Text) > 0);
    FChart.AccessibleSync;
    AssertTrue('selected in the tree', FChart.AccessibleSelected(FChart.AccessibleFocusedChild));
    { no selectedMode: Enter is the form's }
    Load('{"animation":false,"geo":{"map":"f5keys"}}', ['geoselectchanged']);
    FChart.Key(VK_RIGHT);
    AssertEquals(VK_RETURN, FChart.Key(VK_RETURN));
  finally
    TyChartUnregisterMap('f5keys');
  end;
end;

procedure TAdvChartComponentKeysTest.TestTheRingIsOnThePart;
var
  st: TTyStyleSet;
  ring: TBGRAPixel;
  b: TTyRectF;
  L: TTyDzSliderLayout;
  M: TTyMat2D;
  r: TTyXYWH;

  function CountRing: Integer;
  var
    px: TBGRAPixel;
    x, y: Integer;
  begin
    Result := 0;
    for y := Floor(b.Top) - 8 to Ceil(b.Bottom) + 8 do
      for x := Floor(b.Left) - 8 to Ceil(b.Right) + 8 do
      begin
        if (x >= Floor(b.Left) - 1) and (x <= Ceil(b.Right)) and (y >= Floor(b.Top) - 1)
          and (y <= Ceil(b.Bottom)) then Continue;
        if (x < 0) or (y < 0) or (x >= FBmp.Width) or (y >= FBmp.Height) then Continue;
        px := FBmp.GetPixel(x, y);
        if (Abs(px.red - ring.red) <= 2) and (Abs(px.green - ring.green) <= 2)
          and (Abs(px.blue - ring.blue) <= 2) then Inc(Result);
      end;
  end;

  function Fresh: Integer;
  begin
    FBmp.Fill(BGRA(255, 255, 255, 255));
    Frame;
    Result := CountRing;
  end;

begin
  st := FCtl.Model.ResolveStyle('TyAdvChartFocusItem', '', []);
  ring := ColorToBGRA(TyColorToLCL(st.OutlineColor));
  Load('{"animation":false,"legend":{},' + cTwoBars + '}', []);
  b := FChart.LegendLayout(0).Items[1].Bounds;
  AssertEquals('no ring', 0, Fresh);
  FChart.Key(VK_TAB);
  FChart.Key(VK_RIGHT);
  AssertTrue(Format('the ring round the legend item (%d px)', [Fresh]),
    Fresh >= 2 * Round((b.Right - b.Left) + (b.Bottom - b.Top)));
  { the window's path: the part is dynamic content }
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.RenderLayered(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
  AssertTrue('the cached path draws it too', CountRing > 0);
  FChart.Key(VK_ESCAPE);
  AssertEquals('Escape takes it away', 0, Fresh);
  { a slider's window: the filler's box }
  Load('{"animation":false,"dataZoom":[{"type":"slider","start":20,"end":60}],' + cTwoBars + '}', []);
  L := FChart.DataZoomSliderLayout(0);
  M := TyDzGlobal(L, dzrFiller);
  r := L.Kids[dzrFiller].Shape;
  b := TyRectF(M[0] * r.X + M[2] * r.Y + M[4], M[1] * r.X + M[3] * r.Y + M[5],
    M[0] * (r.X + r.W) + M[2] * (r.Y + r.H) + M[4], M[1] * (r.X + r.W) + M[3] * (r.Y + r.H) + M[5]);
  b := TyRectF(Math.Min(b.Left, b.Right), Math.Min(b.Top, b.Bottom), Math.Max(b.Left, b.Right),
    Math.Max(b.Top, b.Bottom));
  AssertEquals('no ring on the slider', 0, Fresh);
  FChart.Key(VK_TAB);
  AssertTrue(Format('the ring round the window (%d px)', [Fresh]),
    Fresh >= 2 * Round((b.Right - b.Left) + (b.Bottom - b.Top)));
end;

procedure TAdvChartComponentKeysTest.TestAComponentKeepsItsKeysInTheChart;
var r: LRESULT;
begin
  Load('{"animation":false,"legend":{},' + cTwoBars + '}', []);
  FChart.Key(VK_TAB);
  AssertEquals('taken at the first part', 0, FChart.Key(VK_LEFT));
  AssertEquals(0, FChart.Key(VK_UP));
  AssertEquals(0, FChart.Key(VK_PRIOR));
  AssertEquals('Shift+arrows too', 0, FChart.Key(VK_LEFT, [ssShift]));
  AssertEquals('Ctrl+arrows are not the chart''s', VK_RIGHT, FChart.Key(VK_RIGHT, [ssCtrl]));
  { through LCL's own path }
  r := FChart.Perform(CN_KEYDOWN, VK_DOWN, 0);
  AssertEquals('an arrow before the interface', 1, r);
  r := FChart.Perform(CN_KEYDOWN, VK_TAB, 0);
  AssertEquals('Tab off the last stop: the form''s', 0, r);
end;

procedure TAdvChartComponentKeysTest.TestTheTreeHasTheComponents;
var
  root, lg, dz, tb, it: TLazAccessibleObject;
  kids: TTyAccObjectArray;
begin
  Load('{"animation":false,"legend":{},"toolbox":{"feature":{"restore":{}}},'
    + '"dataZoom":[{"type":"slider","start":20,"end":60}],' + cTwoBars + '}', ['highlight']);
  FChart.AccessibleSync;
  root := FChart.GetAccessibleObject;
  AssertEquals('two series lists', 2, FChart.AccessibleSeriesCount);
  AssertEquals('and three components', 5, root.GetChildAccessibleObjectsCount);
  lg := FChart.AccessibleStopNode(TyKbStop(ksLegend, 0, 0), -1);
  AssertTrue(lg <> nil);
  AssertTrue('after the series', TyAccChildren(root)[2] = lg);
  AssertEquals(Ord(larGroup), Ord(lg.AccessibleRole));
  AssertEquals('Legend', lg.AccessibleName);
  kids := TyAccChildren(lg);
  AssertEquals(2, Length(kids));
  AssertEquals(Ord(larCheckBox), Ord(kids[0].AccessibleRole));
  AssertEquals('A', kids[0].AccessibleName);
  AssertEquals('B', kids[1].AccessibleName);
  AssertTrue('checked: selected', FChart.AccessibleSelected(kids[1]));
  dz := FChart.AccessibleStopNode(TyKbStop(ksDataZoom, 0, 0), 0);
  AssertTrue(dz <> nil);
  AssertEquals(Ord(larTrackBar), Ord(dz.AccessibleRole));
  AssertEquals('Data zoom', dz.AccessibleName);
  AssertEquals('20% to 60%', dz.AccessibleValue);
  tb := FChart.AccessibleStopNode(TyKbStop(ksToolbox, 0, 0), -1);
  AssertEquals(Ord(larToolBar), Ord(tb.AccessibleRole));
  AssertEquals(Ord(larToolBarButton), Ord(TyAccChildren(tb)[0].AccessibleRole));
  { the keyboard's part is the focused child }
  AssertTrue('the platform may move the keyboard', FChart.AccessibleTakeFocus(dz));
  AssertEquals('dataZoom0/0:0', Stop);
  AssertTrue(FChart.AccessibleFocusedChild = dz);
  FChart.Key(VK_RIGHT);
  FChart.AccessibleSync;
  { a new layout: a new tree }
  dz := FChart.AccessibleStopNode(TyKbStop(ksDataZoom, 0, 0), 0);
  AssertEquals('the value follows the window', '24% to 64%', dz.AccessibleValue);
  it := FChart.AccessibleStopNode(TyKbStop(ksLegend, 0, 0), 1);
  Logged;
  AssertTrue(FChart.AccessibleTakeFocus(it));
  AssertEquals('legend0/0:1', Stop);
  AssertEquals('as the keys would', 'highlight {"type":"highlight","seriesName":"B","name":null,"excludeSeriesId":[]}',
    FLog.Text);
  FChart.Key(VK_SPACE);
  FChart.AccessibleSync;
  AssertFalse('unchecked by Space',
    FChart.AccessibleSelected(FChart.AccessibleStopNode(TyKbStop(ksLegend, 0, 0), 1)));
  { a new layout, a new tree: the objects read again }
  lg := FChart.AccessibleStopNode(TyKbStop(ksLegend, 0, 0), -1);
  AssertFalse('a component''s own node takes no focus', FChart.AccessibleTakeFocus(lg));
end;

{$IFDEF WINDOWS}

function NameOf(const A: IAccessible; AChild: LongInt): string;
var p: PWideChar;
begin
  p := nil;
  A.get_accName(TyAccChild(AChild), @p);
  Result := TyAccTakeBstr(p);
end;

function ValueOf(const A: IAccessible; AChild: LongInt): string;
var p: PWideChar;
begin
  p := nil;
  A.get_accValue(TyAccChild(AChild), @p);
  Result := TyAccTakeBstr(p);
end;

function ChildOf(const A: IAccessible; AChild: LongInt): IAccessible;
var
  p: Pointer;
  d: IDispatch;
begin
  Result := nil;
  p := nil;
  if A.get_accChild(TyAccChild(AChild), @p) <> S_OK then Exit;
  Pointer(d) := p;
  Result := d as IAccessible;
end;

procedure TAdvChartComponentKeysTest.TestTheMsaaComponents;
var
  root, lg, a, dz: IAccessible;
  n: LongInt;
  v: TTyAccVariant;
begin
  Load('{"animation":false,"legend":{},"dataZoom":[{"type":"slider","start":20,"end":60}],'
    + cTwoBars + '}', []);
  root := FChart.AccessibleLink.Root as IAccessible;
  AssertEquals(S_OK, root.get_accChildCount(@n));
  AssertEquals('two series, a legend, a dataZoom', 4, n);
  lg := ChildOf(root, 3);
  AssertEquals('Legend', NameOf(lg, TyAccChildSelf));
  v := Default(TTyAccVariant);
  lg.get_accRole(TyAccChild(TyAccChildSelf), @v);
  AssertEquals('ROLE_SYSTEM_GROUPING', $14, v.LVal);
  a := ChildOf(lg, 1);
  AssertEquals('A', NameOf(a, TyAccChildSelf));
  a.get_accRole(TyAccChild(TyAccChildSelf), @v);
  AssertEquals('ROLE_SYSTEM_CHECKBUTTON', $2C, v.LVal);
  a.get_accState(TyAccChild(TyAccChildSelf), @v);
  AssertTrue('checked', (v.LVal and TyAccStateChecked) <> 0);
  AssertTrue('a check box is not selected', (v.LVal and TyAccStateSelected) = 0);
  dz := ChildOf(root, 4);
  dz.get_accRole(TyAccChild(TyAccChildSelf), @v);
  AssertEquals('ROLE_SYSTEM_SLIDER', $33, v.LVal);
  AssertEquals('20% to 60%', ValueOf(dz, TyAccChildSelf));
  AssertEquals(S_OK, dz.accSelect(TyAccSelTakeFocus, TyAccChild(TyAccChildSelf)));
  AssertEquals('accSelect moved the keyboard', 'dataZoom0/0:0', Stop);
  FChart.Key(VK_RIGHT);
  AssertEquals('read again: the value now', '24% to 64%', ValueOf(dz, TyAccChildSelf));
  { Space through MSAA's view of the legend }
  AssertEquals(S_OK, a.accSelect(TyAccSelTakeFocus, TyAccChild(TyAccChildSelf)));
  FChart.Key(VK_SPACE);
  Frame;
  a.get_accState(TyAccChild(TyAccChildSelf), @v);
  AssertTrue('unchecked', (v.LVal and TyAccStateChecked) = 0);
end;

var
  GCkWnd: HWND;
  GCkChild: LongInt;
  GCkCount: Integer;

procedure CkFocusProc(AHook: THandle; AEvent: DWORD; AWnd: HWND;
  AObject, AChild: LongInt; AThread, ATime: DWORD); stdcall;
begin
  if (AEvent = $8005) and (AWnd = GCkWnd) and (AObject = TyAccObjIdClient) then
  begin
    GCkChild := AChild;
    Inc(GCkCount);
  end;
end;

function CkSetWinEventHook(AMin, AMax: DWORD; AMod: HMODULE; AProc: Pointer;
  AProcess, AThread, AFlags: DWORD): THandle; stdcall;
  external 'user32.dll' name 'SetWinEventHook';
function CkUnhookWinEvent(AHook: THandle): BOOL; stdcall;
  external 'user32.dll' name 'UnhookWinEvent';

type
  TObjectFromLresult = function(lResult: LRESULT; riid: PGUID; wParam: WPARAM;
    ppvObject: PPointer): HResult; stdcall;

procedure TAdvChartComponentKeysTest.TestTheWindowAnnouncesTheParts;
const
  IID_IAccessible: TGUID = '{618736E0-3C3D-11CF-810C-00AA00389B71}';
var
  lib: HMODULE;
  fromLresult: TObjectFromLresult;
  lres: LRESULT;
  p: Pointer;
  acc: IAccessible;
  hook: THandle;
begin
  { a window needs the widgetset: TY_KEYBOARD_WINDOW=1 in a run of its own
    (see test.advchart.keyboard) }
  if not (AppInitialized in Application.Flags) then
  begin
    if SysUtils.GetEnvironmentVariable('TY_KEYBOARD_WINDOW') = '1' then Application.Initialize
    else Ignore('needs an initialised widgetset (TY_KEYBOARD_WINDOW=1)');
  end;
  Load('{"animation":false,"legend":{},' + cTwoBars + '}', []);
  FForm.HandleNeeded;
  FChart.HandleNeeded;
  lres := SendMessage(FChart.Handle, $003D, 0, LPARAM(LongInt(TyAccObjIdClient)));
  AssertTrue('WM_GETOBJECT answered', lres > 0);
  lib := LoadLibrary('oleacc.dll');
  Pointer(fromLresult) := GetProcAddress(lib, 'ObjectFromLresult');
  p := nil;
  AssertEquals(S_OK, fromLresult(lres, @IID_IAccessible, 0, @p));
  Pointer(acc) := p;
  GCkWnd := FChart.Handle;
  GCkChild := 0;
  GCkCount := 0;
  hook := CkSetWinEventHook($8005, $8005, 0, @CkFocusProc, GetCurrentProcessId, 0, 0);
  AssertTrue(hook <> 0);
  try
    { the key through the window: WM_KEYDOWN, LCL's CN_KEYDOWN, KeyDown }
    SendMessage(FChart.Handle, WM_KEYDOWN, VK_TAB, 0);
    Application.ProcessMessages;
    AssertEquals('Tab through the window', 'legend0/0:0', Stop);
    AssertTrue('announced', GCkCount > 0);
    AssertTrue('a descendant', GCkChild < 0);
    AssertEquals('the legend item it names', 'A', NameOf(acc, GCkChild));
    GCkCount := 0;
    SendMessage(FChart.Handle, WM_KEYDOWN, VK_RIGHT, 0);
    Application.ProcessMessages;
    AssertTrue(GCkCount > 0);
    AssertEquals('B', NameOf(acc, GCkChild));
  finally
    CkUnhookWinEvent(hook);
  end;
  acc := nil;
  FChart.DestroyHandle;
end;
{$ENDIF}

{ ==================== against upstream: the legend ==================== }

{ select-legend's legend cases, every pointer step on a legend item done by
  keys: the item taken up (Tab onto the legend, or an arrow, or the platform
  taking it -- a hover onto it), Space for its click, Escape for the pointer
  leaving it; actions replayed as they are. The events and every series' and
  the legend's state as upstream records them. }
procedure TAdvChartComponentKeysOracleTest.TestALegendItemByKeysIsThePointersItem;
const
  cIds: array[0..7] of string = ('legend-bar-toggle', 'legend-hover-bar', 'legend-hover-focus',
    'legend-single', 'legend-hover-pie', 'legend-hoverlink-false', 'legend-held-hover',
    'legend-held-hover-moves');
var
  cases, steps: TJSONArray;
  cs, st, hit: TJSONObject;
  c, s, k, item, keyed: Integer;
  kind: string;
  found: Boolean;
  stop: TTyKbStop;
begin
  keyed := 0;
  stop := TyKbStop(ksLegend, 0, 0);
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    found := False;
    for k := 0 to High(cIds) do
      if cIds[k] = cs.Strings['id'] then found := True;
    if not found then Continue;
    Inc(FCases);
    FCaseOption := cs.Objects['option'];
    NewChart(cs.Objects['option']);
    steps := cs.Arrays['steps'];
    for s := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[s];
      kind := st.Strings['type'];
      FWhere := Format('%s step %d (%s)', [cs.Strings['id'], s, kind]);
      FLogger.Log.Clear;
      hit := nil;
      if st.Find('hit') is TJSONObject then hit := st.Objects['hit'];
      if (kind = 'move') or (kind = 'click') then
      begin
        if (hit <> nil) and (hit.Find('hd') is TJSONObject)
          and (hit.Objects['hd'].Find('legend') <> nil) then
        begin
          item := hit.Objects['hd'].Integers['legend'];
          { onto the item: the next one by an arrow, else the platform }
          if not (TyKbSameStop(FChart.KeyboardStop, stop) and (FChart.KeyboardPart = item)) then
          begin
            if TyKbSameStop(FChart.KeyboardStop, stop) and (FChart.KeyboardPart = item - 1) then
              AssertEquals(FWhere + ' Right', 0, Keys(FChart).Key(VK_RIGHT))
            else if TyKbSameStop(FChart.KeyboardStop, stop) and (FChart.KeyboardPart = item + 1) then
              AssertEquals(FWhere + ' Left', 0, Keys(FChart).Key(VK_LEFT))
            else
              AssertTrue(FWhere + ' onto the item', FChart.SetKeyboardStop(stop, item));
          end;
          if kind = 'click' then
            AssertEquals(FWhere + ' Space', 0, Keys(FChart).Key(VK_SPACE));
          Inc(keyed);
        end
        else if (hit = nil) and (FChart.KeyboardPart >= 0) then
        begin
          { off the item: Escape }
          AssertEquals(FWhere + ' Escape', 0, Keys(FChart).Key(VK_ESCAPE));
          Inc(keyed);
        end
        else if kind = 'move' then FChart.Move(st.Integers['x'], st.Integers['y'])
        else FChart.ClickAt(st.Integers['x'], st.Integers['y']);
      end
      else if kind = 'action' then
        AssertTrue(FWhere + ' dispatched', FChart.DispatchAction(st.Objects['payload'].AsJSON));
      FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
      CompareEvents(st.Arrays['events']);
      FRerendered := False;
      for k := 0 to st.Arrays['events'].Count - 1 do
        if Copy(st.Arrays['events'].Objects[k].Strings['type'], 1, 6) = 'legend' then
          FRerendered := True;
      CompareState(st.Objects['state'], kind = 'init');
      FRerendered := False;
    end;
  end;
  AssertTrue(Format('%d mismatches over %d comparisons:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertEquals('every case ran', Length(cIds), FCases);
  AssertTrue(Format('enough was done by keys (%d)', [keyed]), keyed >= 15);
end;

{ ==================== against upstream: the others ==================== }

procedure TAdvChartComponentKeysOracle2Test.TestAScrollLegendsPagerByKeys;
const
  cIds: array[0..3] of string = ('seq-pager', 'seq-pager-v', 'seq-pager-long', 'seq-pager-narrow');
var
  h: TLsCrack;
  arr, steps: TJSONArray;
  cs, st: TJSONObject;
  c, s, k, n, keyed: Integer;
  hit: string;
  found: Boolean;
begin
  h := TLsCrack.Create;
  try
    h.SetUp;
    try
      keyed := 0;
      n := 0;
      arr := TJSONObject(h.FRoot).Arrays['cases'];
      for c := 0 to arr.Count - 1 do
      begin
        cs := arr.Objects[c];
        found := False;
        for k := 0 to High(cIds) do
          if cIds[k] = cs.Strings['id'] then found := True;
        if not found then Continue;
        Inc(n);
        steps := cs.Arrays['steps'];
        h.NewChart(cs.Objects['option']);
        { the legend taken up first: its item's own highlight is not the
          pager's }
        AssertTrue('the legend', h.FChart.SetKeyboardStop(TyKbStop(ksLegend, 0, 0), 0));
        h.Frame;
        for s := 1 to steps.Count - 1 do
        begin
          st := steps.Objects[s];
          h.FWhere := Format('%s step %d (keys)', [cs.Strings['id'], s]);
          h.FLogger.Log.Clear;
          hit := st.Strings['hit'];
          if hit = 'pager:next' then
            AssertEquals(h.FWhere, 0, Keys(h.FChart).Key(VK_NEXT))
          else if hit = 'pager:prev' then
            AssertEquals(h.FWhere, 0, Keys(h.FChart).Key(VK_PRIOR))
          else
            Fail(h.FWhere + ': no key for ' + hit);
          Inc(keyed);
          h.Frame;
          { the item the keyboard moves to is taken up as the pointer
            would take it: not the pager's events }
          for k := h.FLogger.Log.Count - 1 downto 0 do
            if (Pos('highlight' + #9, h.FLogger.Log[k]) = 1)
              or (Pos('downplay' + #9, h.FLogger.Log[k]) = 1) then h.FLogger.Log.Delete(k);
          h.CompareEvents(st.Arrays['events']);
          h.CompareState(st.Objects['state']);
        end;
      end;
      AssertEquals('every case ran', Length(cIds), n);
      AssertTrue('keys', keyed >= 10);
      AssertEquals(Format('%d of %d comparisons differ:%s', [h.FBad, h.FCompared, h.FReport]), 0, h.FBad);
    finally
      h.TearDown;
    end;
  finally
    h.Free;
  end;
end;

procedure TAdvChartComponentKeysOracle2Test.TestTheDataZoomsByKeys;
var
  h: TDzCrack;
  checked: Integer;

  function Scenario(const AId: string): TJSONObject;
  var scs: TJSONArray; i: Integer;
  begin
    Result := nil;
    scs := TJSONObject(h.FRoot).Arrays['scenarios'];
    for i := 0 to scs.Count - 1 do
      if scs.Objects[i].Strings['id'] = AId then Exit(scs.Objects[i]);
    Fail('no scenario ' + AId);
  end;

  { the scenario's chart, its dataZoom taken up; then each key against the
    step whose action it is }
  procedure Run(const AId: string; const AKeys: array of Word;
    const AShifts: array of Boolean; const ASteps: array of Integer);
  var
    sc: TJSONObject;
    k: Integer;
    sh: TShiftState;
  begin
    sc := Scenario(AId);
    h.FChart.Option := '{}';
    h.FChart.Option := sc.Objects['option'].AsJSON;
    h.FChart.DataZoomNow := NaN;
    h.FChart.SetBounds(0, 0, 800, 600);
    h.FChart.Render(h.FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
    AssertTrue(AId + ' the dataZoom', h.FChart.SetKeyboardStop(TyKbStop(ksDataZoom, 0, 0), 0));
    for k := 0 to High(AKeys) do
    begin
      h.FActions := nil;
      if AShifts[k] then sh := [ssShift] else sh := [];
      AssertEquals(AId + ' taken', 0, Keys(h.FChart).Key(AKeys[k], sh));
      h.FName := Format('%s key %d (step %d)', [AId, k, ASteps[k]]);
      h.FKbStep := True;
      h.CheckStep(sc, sc.Arrays['steps'].Objects[ASteps[k]], False);
      h.FKbStep := False;
      Inc(checked);
    end;
  end;

begin
  h := TDzCrack.Create;
  try
    h.SetUp;
    try
      checked := 0;
      { a slider's handle to an end: Shift+Home / Shift+End }
      Run('H0CLAMP0', [VK_HOME], [True], [2]);
      Run('H1CLAMPLEN', [VK_END], [True], [3]);
      { the window to an end: Home / End -- zoomLock's handle too }
      Run('MOVEZONE', [VK_HOME], [False], [9]);
      Run('ZOOMLOCK', [VK_END], [True], [8]);
      { an inside: its pan to the start, a wheel notch in and out at the
        grid's centre }
      Run('IN-PAN-END', [VK_HOME], [False], [2]);
      Run('IN-WHEEL', [VK_LEFT, VK_RIGHT], [True, True], [1, 3]);
      AssertEquals('every key checked', 7, checked);
      AssertEquals(IntToStr(h.FBad) + ' of ' + IntToStr(h.FCompared)
        + ' disagree with upstream:' + h.FReport, 0, h.FBad);
      AssertTrue('compared', h.FCompared > 50);
    finally
      h.TearDown;
    end;
  finally
    h.Free;
  end;
end;

procedure TAdvChartComponentKeysOracle2Test.TestTheTimelineByKeys;
const
  cIds: array[0..3] of string = ('time-strings', 'inverse', 'click-noloop', 'anim');
var
  h: TTlCrack;
  cases, steps, states, fired: TJSONArray;
  cs, sp, st: TJSONObject;
  c, i, k, n, keyed, idx, cur, cnt: Integer;
  t: Double;
  kind, at: string;
  found: Boolean;
  key: Word;
begin
  h := TTlCrack.Create;
  try
    h.SetUp;
    try
      keyed := 0;
      n := 0;
      cases := TJSONObject(h.FRoot).Arrays['cases'];
      for c := 0 to cases.Count - 1 do
      begin
        cs := cases.Objects[c];
        found := False;
        for k := 0 to High(cIds) do
          if cIds[k] = cs.Strings['id'] then found := True;
        if not found then Continue;
        Inc(n);
        { what RunCase does, every tap a key }
        h.FName := cs.Strings['id'] + ' (keys)';
        h.FColours := cs.Booleans['colours'];
        h.NewChart(cs.Integers['W'], cs.Integers['H']);
        states := cs.Arrays['states'];
        steps := cs.Arrays['steps'];
        h.SetClock(T0);
        h.FChart.Option := cs.Objects['option'].AsJSON;
        h.RenderNow;
        h.FChart.AnimTick(T0);
        h.FStateNo := 0;
        h.FSkipRoles := '';
        { the pointer hovers what it taps; the keyboard hovers nothing }
        for i := 0 to steps.Count - 1 do
          if steps.Objects[i].Find('at') <> nil then
            h.FSkipRoles := h.FSkipRoles + ' ' + steps.Objects[i].Strings['at'];
        h.CheckState(states.Objects[0]);
        for i := 0 to steps.Count - 1 do
        begin
          sp := steps.Objects[i];
          st := states.Objects[i + 1];
          h.FStateNo := i + 1;
          fired := st.Arrays['fired'];
          for k := 0 to fired.Count - 1 do
          begin
            t := T0 + fired.Floats[k];
            h.SetClock(t);
            h.FChart.TimelineTick(t);
            h.RenderNow;
            h.FChart.AnimTick(t);
          end;
          t := T0 + st.Floats['t'];
          h.SetClock(t);
          kind := sp.Strings['kind'];
          if kind = 'action' then
            h.FChart.DispatchAction(sp.Objects['payload'].AsJSON)
          else if kind = 'tap' then
          begin
            at := sp.Strings['at'];
            if not TyKbSameStop(h.FChart.KeyboardStop, TyKbStop(ksTimeline, 0, 0)) then
              AssertTrue('the timeline', h.FChart.SetKeyboardStop(TyKbStop(ksTimeline, 0, 0), 0));
            key := 0;
            if at = 'next' then key := VK_RIGHT
            else if at = 'prev' then key := VK_LEFT
            else if (at = 'play') or (at = 'stop') then key := VK_SPACE
            else if (Copy(at, 1, 5) = 'tick:') or (Copy(at, 1, 6) = 'label:') then
            begin
              idx := StrToInt(Copy(at, Pos(':', at) + 1, MaxInt));
              cur := Round(h.FChart.TimelineView.CurrentIndex);
              cnt := h.FChart.TimelineView.Count;
              if idx = 0 then key := VK_HOME
              else if idx = cnt - 1 then key := VK_END
              else if (idx = cur + 1) and not h.FChart.TimelineView.Inverse then key := VK_RIGHT
              else if (idx = cur - 1) and not h.FChart.TimelineView.Inverse then key := VK_LEFT;
            end;
            if key = 0 then Fail(h.FName + ': no key for ' + at);
            AssertEquals(h.FName + ' ' + at, 0, Keys(h.FChart).Key(key));
            Inc(keyed);
          end
          else if kind <> 'wait' then
            Fail(h.FName + ': a step no key makes: ' + kind);
          h.RenderNow;
          h.FChart.AnimTick(t);
          h.CheckState(st);
        end;
        h.FSkipRoles := '';
      end;
      AssertEquals('every case ran', Length(cIds), n);
      AssertTrue(Format('keys (%d)', [keyed]), keyed >= 7);
      AssertEquals(Format('%d of %d comparisons differ:%s', [h.FBad, h.FCompared, h.FReport]), 0, h.FBad);
    finally
      h.TearDown;
    end;
  finally
    h.Free;
  end;
end;

procedure TAdvChartComponentKeysOracle2Test.TestThePiecesByKeys;
const
  cIds: array[0..1] of string = ('pw-single', 'pw-true');
var
  h: TVmCrack;
  cases, steps, vms: TJSONArray;
  c, st: TJSONObject;
  ci, si, k, n, keyed, piece, part: Integer;
  t, hov: string;
  d: TJSONData;
  found: Boolean;
  pcs: TTyIntegerArray;
  L: TTyVisualMapLayout;
  stop: TTyKbStop;
begin
  h := TVmCrack.Create;
  try
    h.SetUp;
    try
      keyed := 0;
      n := 0;
      stop := TyKbStop(ksVisualMap, 0, 0);
      cases := TJSONObject(h.FRoot).Arrays['cases'];
      for ci := 0 to cases.Count - 1 do
      begin
        c := TJSONObject(cases.Items[ci]);
        found := False;
        for k := 0 to High(cIds) do
          if cIds[k] = c.Strings['id'] then found := True;
        if not found then Continue;
        Inc(n);
        h.NewChart(False);
        steps := c.Arrays['steps'];
        for si := 0 to steps.Count - 1 do
        begin
          st := TJSONObject(steps.Items[si]);
          h.FName := c.Strings['id'] + '/' + IntToStr(si) + ' ' + st.Strings['t'] + ' (keys)';
          t := st.Strings['t'];
          h.FChart.Events.Clear;
          if t = 'init' then
          begin
            h.FChart.SetOption(c.Objects['option'].AsJSON, True);
            h.RenderNow;
            h.FChart.Events.Clear;
          end
          else
          begin
            hov := '';
            d := st.Find('hover');
            if (d <> nil) and (d.JSONType = jtString) then hov := d.AsString;
            { the piece the pointer is over: vm0.itemN.symbol }
            piece := -1;
            if Copy(hov, 1, 8) = 'vm0.item' then
              piece := StrToInt(Copy(hov, 9, Pos('.', Copy(hov, 9, MaxInt)) - 1));
            part := -1;
            if piece >= 0 then
            begin
              L := h.FChart.VisualMapLayout(0);
              pcs := nil;
              for k := 0 to High(L.Items) do
                if not L.Items[k].IsText then
                begin
                  SetLength(pcs, Length(pcs) + 1);
                  pcs[High(pcs)] := L.Items[k].PieceIndex;
                end;
              for k := 0 to High(pcs) do
                if pcs[k] = piece then part := k;
            end;
            if t = 'move' then
            begin
              if part >= 0 then
              begin
                if not (TyKbSameStop(h.FChart.KeyboardStop, stop) and (h.FChart.KeyboardPart = part)) then
                  AssertTrue(h.FName, h.FChart.SetKeyboardStop(stop, part));
              end
              else if h.FChart.KeyboardPart >= 0 then
                AssertEquals(h.FName, 0, Keys(h.FChart).Key(VK_ESCAPE))
              else
                Fail(h.FName + ': no key for ' + hov);
              Inc(keyed);
            end
            else if t = 'up' then
            begin
              AssertEquals(h.FName, 0, Keys(h.FChart).Key(VK_SPACE));
              Inc(keyed);
            end
            else if t <> 'down' then
              Fail(h.FName + ': no key for a ' + t);
            h.RenderNow;
          end;
          h.CheckEvents(st);
          vms := st.Arrays['vms'];
          for k := 0 to vms.Count - 1 do
            h.CheckVm(k, TJSONObject(vms.Items[k]), False);
          h.CheckSeries(st);
        end;
      end;
      AssertEquals('every case ran', Length(cIds), n);
      AssertTrue(Format('keys (%d)', [keyed]), keyed >= 5);
      AssertEquals(Format('%d of %d comparisons differ from upstream:%s',
        [h.FBad, h.FCompared, h.FReport]), 0, h.FBad);
    finally
      h.TearDown;
    end;
  finally
    h.Free;
  end;
end;

procedure TAdvChartComponentKeysOracle2Test.TestTheGeoHighlightByKeys;
var
  h: TGiCrack;
  cs, step, st, act: TJSONObject;
  cases, steps, states: TJSONArray;
  i, c, keyed, g, part: Integer;
  geo: TTyGeo;
  translated: Boolean;
  d: TJSONData;
begin
  h := TGiCrack.Create;
  try
    h.SetUp;
    try
      keyed := 0;
      cases := TJSONObject(h.FRoot).Arrays['cases'];
      cs := nil;
      for c := 0 to cases.Count - 1 do
        if cases.Objects[c].Strings['id'] = 'highlight' then cs := cases.Objects[c];
      AssertTrue('the case', cs <> nil);
      h.RegisterMaps;
      h.FWhere := 'highlight (keys)';
      h.NewChart(cs.Objects['option'].AsJSON);
      states := cs.Arrays['states'];
      steps := cs.Arrays['steps'];
      for i := 0 to states.Count - 1 do
      begin
        h.FWhere := Format('highlight state %d (keys)', [i]);
        if i > 0 then
        begin
          step := steps.Objects[i - 1];
          translated := False;
          if step.Find('action') <> nil then
          begin
            act := step.Objects['action'];
            { a plain highlight of a region by geoIndex and name: the
              keyboard's own focus; its downplay: Escape }
            d := act.Find('name');
            if (act.Count = 3) and (act.Find('geoIndex') <> nil) and (d <> nil)
              and (d.JSONType = jtString) then
            begin
              geo := h.FChart.GeoLayout(0);
              part := -1;
              for g := 0 to geo.GroupCount - 1 do
                if geo.GroupName(g) = d.AsString then part := g;
              if (act.Strings['type'] = 'highlight') and (part >= 0) then
              begin
                AssertTrue(h.FWhere, h.FChart.SetKeyboardStop(TyKbStop(ksGeo, 0, 0), part));
                translated := True;
              end
              else if (act.Strings['type'] = 'downplay') and (h.FChart.KeyboardPart = part) then
              begin
                AssertEquals(h.FWhere, 0, Keys(h.FChart).Key(VK_ESCAPE));
                translated := True;
              end;
            end;
            if translated then Inc(keyed)
            else h.FChart.DispatchAction(act.AsJSON);
          end
          else if step.Find('move') <> nil then
            h.FChart.Move(step.Arrays['move'].Integers[0], step.Arrays['move'].Integers[1])
          else if step.Find('leave') <> nil then
            h.FChart.Leave
          else
            Fail('a step this case does not have');
          h.Paint;
        end;
        st := states.Objects[i];
        h.CompareEvents(st.Arrays['events']);
        h.CompareTip(st.Find('tip'));
        h.CompareGeos(st.Arrays['geos']);
      end;
      AssertEquals('the highlight and its downplay by keys', 2, keyed);
      h.Finish('highlight by keys', 200);
    finally
      h.TearDown;
    end;
  finally
    h.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartComponentKeysTest);
  RegisterTest(TAdvChartComponentKeysOracleTest);
  RegisterTest(TAdvChartComponentKeysOracle2Test);
end.
