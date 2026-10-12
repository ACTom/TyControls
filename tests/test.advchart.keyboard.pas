unit test.advchart.keyboard;
{$mode objfpc}{$H+}
{ THE KEYBOARD AND THE ACCESSIBLE TREE [Batch 144].

  Upstream ECharts has no keyboard, so the keys are the port's own design
  (tyControls.AdvChart.KeyNav). What CAN be held to upstream is what the
  keys are built from:

  - a focus move is the highlight / downplay ACTION a page would dispatch
    for that item. TAdvChartKeyboardOracleTest replays the select-legend
    fixture's highlight cases with every plain item highlight (and the
    downplay of that same item) done by the keyboard instead, and compares
    the events and every item's state with upstream's, step by step;
  - Enter is what a click on the item dispatches: the fixture's click steps
    replayed as a focus move plus Enter, the events compared with the
    click's (less the click event itself), and nothing at all where the
    series has no selectedMode;
  - the accessible tree speaks the aria description's words: the
    decal-aria fixture's description scenarios replayed, the root's
    description compared with upstream's aria-label and every series' and
    row's phrase found in it, in order.

  The hand-written tests pin the keys themselves, the tooltip (upstream's
  showTip at the item), the ring, option changes, empty charts, several
  series types, the tab stop, the LCL tree and -- on Windows -- the MSAA
  server over it. }
interface
uses Classes, SysUtils, Math, TypInfo, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, LCLType, LMessages, BGRABitmap, BGRABitmapTypes,
     {$IFDEF WINDOWS} Windows, {$ENDIF} Types,
     tyControls.Controller, tyControls.Types,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Events, tyControls.AdvChart.Aria, tyControls.AdvChart.KeyNav,
     tyControls.Accessible, tyControls.AdvanceChart,
     test.advchart.select;
type
  { the keyboard of a TSelProbe (the harness's chart) }
  TKbCrack = class(TTyAdvanceChart)
  public
    function Key(AKey: Word; AShift: TShiftState = []): Word;
    procedure LeaveFocus;
  end;

  TKbProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { the window's own path: the static layer cached, the dynamic one only
      when HasDynamicContent says there is something in it }
    procedure RenderLayered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function Key(AKey: Word; AShift: TShiftState = []): Word;
    procedure LeaveFocus;
    procedure Hover(AX, AY: Integer);
  end;

  TKbLog = class
  public
    Lines: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Handle(Sender: TObject; const AEvent: TTyChartEvent);
    function Text: string;
  end;

  TAdvChartKeyboardOracleTest = class(TAdvChartSelectHarness)
  private
    FTranslated: Integer;
    procedure ReplayByKeys(const AIds: array of string);
  published
    procedure TestAFocusMoveIsTheHighlightAction;
    procedure TestEnterIsTheClicksSelect;
    procedure TestTheTreeSpeaksTheAriaWords;
  end;

  TAdvChartKeyboardTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TKbProbe;
    FBmp: TBGRABitmap;
    FLog: TKbLog;
    procedure Load(const AOption: string; AW: Integer = 600; AH: Integer = 400);
    procedure Frame;
    procedure Logged;
    function Item: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheMoveTable;
    procedure TestTheKeysWalkTheItems;
    procedure TestAPageIsATenth;
    procedure TestTheMovingKeysAreAlwaysTakenAndTabIsNot;
    procedure TestOnKeyDownMayTakeTheKey;
    procedure TestEscapeClearsAndAnExitKeepsThePlace;
    procedure TestTheDataIndexIsRawUnderAFilter;
    procedure TestHiddenAndChangedSeries;
    procedure TestSeveralSeriesTypes;
    procedure TestEnterNeedsASelectedMode;
    procedure TestTheTooltipIsShowTipAtTheItem;
    procedure TestTheRingIsTheThemesOutline;
    procedure TestTheTabStopStaysFalse;
    procedure TestTheTreeFollowsTheChart;
    procedure TestTheTreeIsCappedAndTheKeysAreNot;
    procedure TestTheTreeAnswersTheHost;
    procedure TestTheOrderedChildren;
    {$IFDEF WINDOWS}
    procedure TestTheMsaaTree;
    procedure TestTheMsaaNodesOutliveNothing;
    procedure TestTheWindowAnswersGetObject;
    {$ENDIF}
  end;

implementation

const
  cBars = '{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d"]},'
    + '"yAxis":{},"series":[{"type":"bar","data":[1,2,3,4]},'
    + '{"type":"line","data":[2,3,1]},{"type":"scatter","data":[[0,1],[1,2]]}]}';

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

{ ==================== probes ==================== }

function TKbCrack.Key(AKey: Word; AShift: TShiftState): Word;
begin
  Result := AKey;
  KeyDown(Result, AShift);
end;

procedure TKbCrack.LeaveFocus;
begin
  DoExit;
end;

procedure TKbProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TKbProbe.RenderLayered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

function TKbProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TKbProbe.Key(AKey: Word; AShift: TShiftState): Word;
begin
  Result := AKey;
  KeyDown(Result, AShift);
end;

procedure TKbProbe.LeaveFocus;
begin
  DoExit;
end;

procedure TKbProbe.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

constructor TKbLog.Create;
begin
  inherited Create;
  Lines := TStringList.Create;
end;

destructor TKbLog.Destroy;
begin
  Lines.Free;
  inherited Destroy;
end;

procedure TKbLog.Handle(Sender: TObject; const AEvent: TTyChartEvent);
var d: TJSONData;
begin
  if AEvent.Payload = '' then
  begin
    Lines.Add(AEvent.EventType);
    Exit;
  end;
  { the payload compact, as a page's JSON.stringify prints it }
  d := GetJSON(AEvent.Payload);
  try
    Lines.Add(AEvent.EventType + ' ' + d.FormatJSON([foSingleLineArray, foSingleLineObject,
      foSkipWhiteSpace]));
  finally
    d.Free;
  end;
end;

function TKbLog.Text: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to Lines.Count - 1 do
  begin
    if i > 0 then Result := Result + ' | ';
    Result := Result + Lines[i];
  end;
end;

function JsonText(const AJson: string): string;
var d: TJSONData;
begin
  d := GetJSON(AJson);
  try
    Result := d.AsJSON;
  finally
    d.Free;
  end;
end;

{ ==================== against upstream ==================== }

{ RunCases, with every plain item highlight done by the keyboard: a
  highlight whose payload is just type, seriesIndex and dataIndex, while the
  keyboard holds nothing, is SetKeyboardItem; the downplay of the item it
  holds is Escape. Everything else is replayed as the harness replays it. }
procedure TAdvChartKeyboardOracleTest.ReplayByKeys(const AIds: array of string);
var
  cases, steps: TJSONArray;
  cs, st, p: TJSONObject;
  c, s, k: Integer;
  kind: string;
  found, isPlain, done: Boolean;
  held: TTyChartDatumRef;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    found := False;
    for k := 0 to High(AIds) do
      if AIds[k] = cs.Strings['id'] then found := True;
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
      if kind = 'move' then FChart.Move(st.Integers['x'], st.Integers['y'])
      else if kind = 'click' then FChart.ClickAt(st.Integers['x'], st.Integers['y'])
      else if kind = 'action' then
      begin
        p := st.Objects['payload'];
        isPlain := (p.Count = 3) and (p.IndexOfName('seriesIndex') >= 0)
          and (p.IndexOfName('dataIndex') >= 0)
          and (p.Find('seriesIndex').JSONType = jtNumber)
          and (p.Find('dataIndex').JSONType = jtNumber);
        held := FChart.KeyboardItem;
        done := False;
        if isPlain and (p.Strings['type'] = 'highlight') and not TyChartDatumValid(held) then
        begin
          AssertTrue(FWhere + ' the keyboard takes the item',
            FChart.SetKeyboardItem(p.Integers['seriesIndex'], p.Integers['dataIndex']));
          done := True;
        end
        else if isPlain and (p.Strings['type'] = 'downplay') and TyChartDatumValid(held)
          and (held.SeriesIndex = p.Integers['seriesIndex'])
          and (held.RawDataIndex = p.Integers['dataIndex']) then
        begin
          AssertEquals(FWhere + ' Escape is taken', 0, TKbCrack(TTyAdvanceChart(FChart)).Key(VK_ESCAPE));
          done := True;
        end;
        if done then Inc(FTranslated)
        else AssertTrue(FWhere + ' dispatched', FChart.DispatchAction(p.AsJSON));
      end;
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
end;

procedure TAdvChartKeyboardOracleTest.TestAFocusMoveIsTheHighlightAction;
const
  cIds: array[0..7] of string = ('highlight-bar', 'highlight-line', 'focus-self-held',
    'focus-funnel-self', 'focus-heatmap-scatter', 'focus-sunburst',
    'emphasis-disabled', 'legend-reshown-new');
begin
  FTranslated := 0;
  ReplayByKeys(cIds);
  AssertTrue(Format('%d mismatches over %d comparisons:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertEquals('every case ran', Length(cIds), FCases);
  { 9 highlights taken by the keyboard, 5 of their downplays by Escape }
  AssertEquals('the steps that went through the keyboard', 14, FTranslated);
end;

procedure TAdvChartKeyboardOracleTest.TestEnterIsTheClicksSelect;
const
  cIds: array[0..2] of string = ('pie-single', 'bar-single', 'bar-off');
var
  cases, steps, want: TJSONArray;
  cs, st, dp, node: TJSONObject;
  c, s, k, si: Integer;
  found, hasMode: Boolean;
  sm: TJSONData;
  enters, silent: Integer;
begin
  enters := 0;
  silent := 0;
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    found := False;
    for k := 0 to High(cIds) do
      if cIds[k] = cs.Strings['id'] then found := True;
    if not found then Continue;
    Inc(FCases);
    NewChart(cs.Objects['option']);
    steps := cs.Arrays['steps'];
    for s := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[s];
      if st.Strings['type'] <> 'click' then Continue;
      if not (st.Find('hit') is TJSONObject) or not (st.Objects['hit'].Find('dp') is TJSONObject) then
        Continue;
      FWhere := Format('%s step %d', [cs.Strings['id'], s]);
      dp := st.Objects['hit'].Objects['dp'];
      si := dp.Integers['s'];
      AssertTrue(FWhere + ' focus', FChart.SetKeyboardItem(si, dp.Integers['i']));
      FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
      FLogger.Log.Clear;
      node := TJSONObject(cs.Objects['option'].Arrays['series'].Items[si]);
      sm := node.Find('selectedMode');
      hasMode := (sm <> nil) and not ((sm.JSONType = jtBoolean) and not sm.AsBoolean)
        and (sm.JSONType <> jtNull);
      if hasMode then
      begin
        AssertEquals(FWhere + ' Enter is taken', 0, TKbCrack(TTyAdvanceChart(FChart)).Key(VK_RETURN));
        { the click's events, less the click itself }
        want := TJSONArray.Create;
        try
          for k := 0 to st.Arrays['events'].Count - 1 do
            if st.Arrays['events'].Objects[k].Strings['type'] <> 'click' then
              want.Add(st.Arrays['events'].Objects[k].Clone);
          CompareEvents(want);
        finally
          want.Free;
        end;
        Inc(enters);
      end
      else
      begin
        { no selectedMode: a click still dispatches, a key does not -- and
          leaves Enter to the form }
        AssertEquals(FWhere + ' Enter is not taken', VK_RETURN, TKbCrack(TTyAdvanceChart(FChart)).Key(VK_RETURN));
        AssertEquals(FWhere + ' nothing dispatched', 0, FLogger.Log.Count);
        Inc(silent);
      end;
      FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
    end;
  end;
  AssertTrue(Format('%d mismatches over %d comparisons:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertEquals('every case ran', Length(cIds), FCases);
  AssertEquals('the clicks on a selectable series', 6, enters);
  AssertEquals('the clicks on a series without selectedMode', 2, silent);
end;

procedure TAdvChartKeyboardOracleTest.TestTheTreeSpeaksTheAriaWords;
var
  aria: TJSONObject;
  scs, steps: TJSONArray;
  sc, st, rec, opt: TJSONObject;
  i, j, k, r, at, phrases: Integer;
  want, nm: string;
  d: TJSONData;
  chart: TKbProbe;
  bmp: TBGRABitmap;
  sl: TStringList;
  root: TLazAccessibleObject;
  ser, items: TTyAccObjectArray;
  builtFromFacts, writesAria: Boolean;
  other: TKbProbe;
  ariaNode, mx: TJSONData;
  maxSeries: Integer;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-decal-aria.json'));
    aria := TJSONObject(GetJSON(sl.Text));
  finally
    sl.Free;
  end;
  chart := TKbProbe.Create(FForm);
  other := TKbProbe.Create(FForm);
  bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  phrases := 0;
  try
    chart.Parent := FForm;
    chart.Controller := FCtl;
    chart.SetBounds(0, 0, 600, 400);
    other.Parent := FForm;
    other.Controller := FCtl;
    other.SetBounds(0, 0, 600, 400);
    scs := aria.Arrays['scenarios'];
    for i := 0 to scs.Count - 1 do
    begin
      sc := scs.Objects[i];
      if Copy(sc.Strings['id'], 1, 6) <> 'label-' then Continue;
      steps := sc.Arrays['steps'];
      for j := 0 to steps.Count - 1 do
      begin
        st := steps.Objects[j];
        FWhere := sc.Strings['id'] + '#' + IntToStr(j);
        opt := TJSONObject(st.Objects['option'].Clone);
        try
          ariaNode := opt.Find('aria');
          writesAria := ariaNode <> nil;
          maxSeries := MaxInt;
          if ariaNode is TJSONObject then
          begin
            mx := TyAriaLabelKey(TJSONObject(ariaNode), ['series', 'maxCount']);
            if (mx <> nil) and (mx.JSONType = jtNumber) and (mx.AsFloat > 0) then
              maxSeries := mx.AsInteger;
          end;
          if st.Booleans['merge'] then chart.SetOption(opt.AsJSON, False)
          else
          begin
            opt.Add('animation', False);
            chart.SetOption(opt.AsJSON, True);
            { an option that writes no aria: the tree still describes the
              chart, in the words aria would use were it switched on }
            if not writesAria then
            begin
              opt.Add('aria', TJSONObject.Create(['enabled', True]));
              other.SetOption(opt.AsJSON, True);
              other.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
            end;
          end;
        finally
          opt.Free;
        end;
        chart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
        rec := st.Objects['record'];
        if not (rec.Find('error') = nil) and (rec.Find('error').JSONType <> jtNull) then Continue;
        d := rec.Objects['aria'].Find('label');
        if (d = nil) or (d.JSONType = jtNull) then want := '' else want := d.AsString;
        if not writesAria then
        begin
          AssertFalse(FWhere + ' merge steps write aria', st.Booleans['merge']);
          AssertEquals(FWhere + ' upstream writes nothing', '', want);
          want := other.AriaDescription;
          AssertTrue(FWhere + ' the sentence aria would write', want <> '');
        end;
        chart.AccessibleSync;
        root := chart.GetAccessibleObject;
        Inc(FCompared);
        { every one of these options writes aria: the description is upstream's }
        if root.AccessibleDescription <> want then
          Bad('description' + LineEnding + '    upstream: ' + want + LineEnding
            + '    here:     ' + root.AccessibleDescription);
        AssertEquals(FWhere + ' the role', Ord(larChart), Ord(root.AccessibleRole));
        { the phrases are the description's own, where it is built from the facts
          (not a hand-written description, not the templates switched off) }
        builtFromFacts := Pos('This is a chart', want) = 1;
        ser := TyAccChildren(root);
        if not builtFromFacts then Continue;
        at := 0;
        for k := 0 to High(ser) do
        begin
          AssertEquals(FWhere + ' a series is a list', Ord(larListBox), Ord(ser[k].AccessibleRole));
          { series.maxCount: the sentence stops, the tree does not }
          if k >= maxSeries then Continue;
          nm := ser[k].AccessibleName;
          Inc(FCompared);
          if (nm = '') or (Pos(nm, Copy(want, at + 1, MaxInt)) = 0) then
          begin
            Bad(Format('series %d phrase "%s" not in the description after %d', [k, nm, at]));
            Continue;
          end;
          at := at + Pos(nm, Copy(want, at + 1, MaxInt)) + Length(nm) - 1;
          Inc(phrases);
          items := TyAccChildren(ser[k]);
          { the first maxCount rows are in the sentence, in order }
          for r := 0 to Math.Min(High(items), 1) do
          begin
            nm := items[r].AccessibleName;
            AssertEquals(FWhere + ' an item', Ord(larListItem), Ord(items[r].AccessibleRole));
            Inc(FCompared);
            if Pos(nm, Copy(want, at + 1, MaxInt)) = 0 then
              Bad(Format('series %d row %d phrase "%s" not in the description', [k, r, nm]))
            else
            begin
              at := at + Pos(nm, Copy(want, at + 1, MaxInt)) + Length(nm) - 1;
              Inc(phrases);
            end;
          end;
        end;
      end;
    end;
  finally
    bmp.Free;
    other.Free;
    chart.Free;
    aria.Free;
  end;
  AssertTrue(Format('%d mismatches over %d comparisons:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('only %d phrases found', [phrases]), phrases >= 30);
end;

{ ==================== hand-written ==================== }

procedure TAdvChartKeyboardTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TKbProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FLog := TKbLog.Create;
  FBmp := nil;
end;

procedure TAdvChartKeyboardTest.TearDown;
begin
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  FLog.Free;
  inherited TearDown;
end;

procedure TAdvChartKeyboardTest.Load(const AOption: string; AW, AH: Integer);
const
  cTypes: array[0..5] of string = ('highlight', 'downplay', 'select', 'unselect',
    'selectchanged', 'click');
var i: Integer;
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
  FChart.SetBounds(0, 0, AW, AH);
  { a test's chart starts with nothing held }
  FChart.ClearKeyboardItem;
  FChart.Option := AOption;
  for i := 0 to High(cTypes) do FChart.ChartOn(cTypes[i], @FLog.Handle);
  Frame;
end;

procedure TAdvChartKeyboardTest.Frame;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
end;

procedure TAdvChartKeyboardTest.Logged;
begin
  FLog.Lines.Clear;
end;

function TAdvChartKeyboardTest.Item: string;
var d: TTyChartDatumRef;
begin
  d := FChart.KeyboardItem;
  if not TyChartDatumValid(d) then Exit('none');
  Result := Format('%d:%d', [d.SeriesIndex, d.DataIndex]);
end;

{ the pure move rule: series without rows are skipped, the row is clamped
  across series, nothing wraps }
procedure TAdvChartKeyboardTest.TestTheMoveTable;
var
  s: TTyKbSeriesArray;
  p, r: Integer;
begin
  SetLength(s, 3);
  s[0].SeriesIndex := 0; s[0].Count := 4;
  s[1].SeriesIndex := 3; s[1].Count := 0;
  s[2].SeriesIndex := 5; s[2].Count := 2;
  p := -1; r := -1;
  AssertTrue(TyKbMove(s, kbcNext, p, r));
  AssertEquals('from nothing: the first item', 0, p);
  AssertEquals(0, r);
  p := -1; r := -1;
  AssertTrue(TyKbMove(s, kbcLast, p, r));
  AssertEquals('End from nothing: the first series'' last', 3, r);
  AssertFalse('no wrap at the end', TyKbMove(s, kbcNext, p, r));
  AssertTrue(TyKbMove(s, kbcNextSeries, p, r));
  AssertEquals('the empty series is skipped', 2, p);
  AssertEquals('the row is clamped', 1, r);
  AssertFalse('no series after the last', TyKbMove(s, kbcNextSeries, p, r));
  AssertTrue(TyKbMove(s, kbcPrevSeries, p, r));
  AssertEquals(0, p);
  AssertEquals('the row goes back as it was clamped', 1, r);
  AssertTrue(TyKbMove(s, kbcFirst, p, r));
  AssertEquals(0, r);
  AssertFalse('no wrap at the start', TyKbMove(s, kbcPrev, p, r));
  AssertFalse('not a move', TyKbMove(s, kbcActivate, p, r));
  SetLength(s, 1);
  s[0].Count := 0;
  p := -1; r := -1;
  AssertFalse('nothing to land on', TyKbMove(s, kbcNext, p, r));
  AssertEquals(-1, p);
  { the commands }
  AssertTrue(TyKbCommandOf(VK_RIGHT, []) = kbcNext);
  AssertTrue(TyKbCommandOf(VK_LEFT, []) = kbcPrev);
  AssertTrue(TyKbCommandOf(VK_DOWN, []) = kbcNextSeries);
  AssertTrue(TyKbCommandOf(VK_UP, []) = kbcPrevSeries);
  AssertTrue(TyKbCommandOf(VK_NEXT, []) = kbcPageNext);
  AssertTrue(TyKbCommandOf(VK_PRIOR, []) = kbcPagePrev);
  AssertTrue(TyKbCommandOf(VK_SPACE, []) = kbcActivate);
  AssertTrue(TyKbCommandOf(VK_RETURN, []) = kbcActivate);
  AssertTrue(TyKbCommandOf(VK_ESCAPE, []) = kbcClear);
  AssertTrue('Tab is not the chart''s', TyKbCommandOf(VK_TAB, []) = kbcNone);
  AssertTrue('Shift+Tab neither', TyKbCommandOf(VK_TAB, [ssShift]) = kbcNone);
  AssertTrue('a modifier makes it not the chart''s', TyKbCommandOf(VK_RIGHT, [ssCtrl]) = kbcNone);
  AssertTrue(TyKbCommandOf(VK_RIGHT, [ssAlt]) = kbcNone);
end;

procedure TAdvChartKeyboardTest.TestTheKeysWalkTheItems;
begin
  Load(cBars);
  Logged;
  AssertEquals('none', Item);
  AssertEquals(0, FChart.Key(VK_RIGHT));
  AssertEquals('from nothing, the first item', '0:0', Item);
  AssertEquals('the highlight action''s event',
    'highlight {"type":"highlight","seriesIndex":0,"dataIndex":0}', FLog.Text);
  Logged;
  FChart.Key(VK_RIGHT);
  AssertEquals('0:1', Item);
  AssertEquals('downplay the old, highlight the new',
    'downplay {"type":"downplay","seriesIndex":0,"dataIndex":0} | '
    + 'highlight {"type":"highlight","seriesIndex":0,"dataIndex":1}', FLog.Text);
  FChart.Key(VK_END);
  AssertEquals('0:3', Item);
  Logged;
  AssertEquals('taken even at the end', 0, FChart.Key(VK_RIGHT));
  AssertEquals('0:3', Item);
  AssertEquals('nothing dispatched at the end', '', FLog.Text);
  FChart.Key(VK_DOWN);
  AssertEquals('the line has three rows: clamped', '1:2', Item);
  FChart.Key(VK_DOWN);
  AssertEquals('the scatter has two', '2:1', Item);
  Logged;
  FChart.Key(VK_DOWN);
  AssertEquals('no series after the last', '2:1', Item);
  AssertEquals('', FLog.Text);
  FChart.Key(VK_UP);
  AssertEquals('1:1', Item);
  FChart.Key(VK_HOME);
  AssertEquals('1:0', Item);
  FChart.Key(VK_NEXT);
  AssertEquals('a page of three rows is one', '1:1', Item);
  FChart.Key(VK_LEFT);
  FChart.Key(VK_LEFT);
  AssertEquals('1:0', Item);
  AssertEquals('the raw row', 0, FChart.KeyboardItem.RawDataIndex);
end;

procedure TAdvChartKeyboardTest.TestAPageIsATenth;
var
  s: string;
  i: Integer;
begin
  AssertEquals(1, TyKbPageStep(1));
  AssertEquals(1, TyKbPageStep(10));
  AssertEquals(2, TyKbPageStep(11));
  AssertEquals(3, TyKbPageStep(25));
  AssertEquals('never zero', 1, TyKbPageStep(0));
  s := '';
  for i := 0 to 24 do
  begin
    if i > 0 then s := s + ',';
    s := s + IntToStr(i);
  end;
  Load('{"animation":false,"xAxis":{"type":"category"},"yAxis":{},'
    + '"series":[{"type":"bar","data":[' + s + ']}]}');
  FChart.Key(VK_HOME);
  FChart.Key(VK_NEXT);
  AssertEquals('25 rows: a page of three', '0:3', Item);
  FChart.Key(VK_END);
  FChart.Key(VK_PRIOR);
  AssertEquals('0:21', Item);
  FChart.Key(VK_HOME);
  FChart.Key(VK_PRIOR);
  AssertEquals('clamped at the start', '0:0', Item);
end;

procedure TAdvChartKeyboardTest.TestTheMovingKeysAreAlwaysTakenAndTabIsNot;
var r: LRESULT;
begin
  Load('{"animation":false,"series":[]}');
  AssertEquals('an empty chart takes the arrows all the same', 0, FChart.Key(VK_RIGHT));
  AssertEquals(0, FChart.Key(VK_DOWN));
  AssertEquals(0, FChart.Key(VK_HOME));
  AssertEquals('none', Item);
  AssertEquals('Tab leaves', VK_TAB, FChart.Key(VK_TAB));
  AssertEquals('Shift+Tab leaves', VK_TAB, FChart.Key(VK_TAB, [ssShift]));
  AssertEquals('Enter with no item is the form''s', VK_RETURN, FChart.Key(VK_RETURN));
  AssertEquals('Escape with no item is the form''s', VK_ESCAPE, FChart.Key(VK_ESCAPE));
  AssertEquals('a modified arrow is not the chart''s', VK_RIGHT, FChart.Key(VK_RIGHT, [ssCtrl]));
  { THROUGH LCL'S OWN PATH: CN_KEYDOWN runs KeyDown before the interface, and
    a key it takes never reaches WMKeyDown -- where DoArrowKey would hand the
    focus to a sibling }
  Load(cBars);
  r := FChart.Perform(CN_KEYDOWN, VK_RIGHT, 0);
  AssertEquals('the arrow is taken before the interface', 1, r);
  AssertEquals('0:0', Item);
  r := FChart.Perform(CN_KEYDOWN, VK_TAB, 0);
  AssertEquals('Tab is not', 0, r);
end;

type
  TKbTaker = class
    procedure Take(Sender: TObject; var Key: Word; Shift: TShiftState);
  end;

procedure TKbTaker.Take(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RIGHT then Key := 0;
end;

procedure TAdvChartKeyboardTest.TestOnKeyDownMayTakeTheKey;
var t: TKbTaker;
begin
  t := TKbTaker.Create;
  try
    Load(cBars);
    FChart.OnKeyDown := @t.Take;
    FChart.Key(VK_RIGHT);
    AssertEquals('the host''s handler took it first', 'none', Item);
    FChart.Key(VK_END);
    AssertEquals('other keys still reach the chart', '0:3', Item);
    FChart.OnKeyDown := nil;
  finally
    t.Free;
  end;
end;

procedure TAdvChartKeyboardTest.TestEscapeClearsAndAnExitKeepsThePlace;
begin
  Load(cBars);
  FChart.Key(VK_RIGHT);
  FChart.Key(VK_RIGHT);
  Logged;
  AssertEquals('Escape is taken while an item is held', 0, FChart.Key(VK_ESCAPE));
  AssertEquals('none', Item);
  AssertEquals('downplay {"type":"downplay","seriesIndex":0,"dataIndex":1}', FLog.Text);
  FChart.Key(VK_RIGHT);
  AssertEquals('after Escape the walk starts again', '0:0', Item);
  FChart.Key(VK_RIGHT);
  FChart.Key(VK_RIGHT);
  Logged;
  FChart.LeaveFocus;
  AssertEquals('an exit lets go', 'none', Item);
  AssertEquals('downplay {"type":"downplay","seriesIndex":0,"dataIndex":2}', FLog.Text);
  Logged;
  FChart.Key(VK_RIGHT);
  AssertEquals('the first key after it takes up the same item', '0:2', Item);
  AssertEquals('highlight {"type":"highlight","seriesIndex":0,"dataIndex":2}', FLog.Text);
  Logged;
  FChart.LeaveFocus;
  FChart.LeaveFocus;
  AssertEquals('a second exit dispatches nothing more', 1, FLog.Lines.Count);
  FChart.ClearKeyboardItem;
  FChart.Key(VK_RIGHT);
  AssertEquals('ClearKeyboardItem forgets the place', '0:0', Item);
end;

procedure TAdvChartKeyboardTest.TestTheDataIndexIsRawUnderAFilter;
begin
  Load('{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d","e","f"]},'
    + '"yAxis":{},"dataZoom":[{"type":"inside","startValue":2,"endValue":4}],'
    + '"series":[{"type":"bar","data":[1,2,3,4,5,6]}]}');
  Logged;
  FChart.Key(VK_RIGHT);
  AssertEquals('the view''s first row', '0:0', Item);
  AssertEquals('is the raw row 2', 2, FChart.KeyboardItem.RawDataIndex);
  AssertEquals('the payload names the raw row, as a page''s would',
    'highlight {"type":"highlight","seriesIndex":0,"dataIndex":2}', FLog.Text);
  FChart.Key(VK_END);
  AssertEquals('the view has three rows', 4, FChart.KeyboardItem.RawDataIndex);
  AssertTrue('by raw index', FChart.SetKeyboardItem(0, 3));
  AssertEquals('0:1', Item);
  AssertFalse('a row the view filtered out', FChart.SetKeyboardItem(0, 0));
  AssertFalse('no such series', FChart.SetKeyboardItem(7, 0));
end;

procedure TAdvChartKeyboardTest.TestHiddenAndChangedSeries;
begin
  Load('{"animation":false,"legend":{},"xAxis":{"type":"category","data":["a","b","c","d"]},'
    + '"yAxis":{},"series":[{"type":"bar","name":"A","data":[1,2,3,4]},'
    + '{"type":"bar","name":"B","data":[2,3,1,2]},{"type":"bar","name":"C","data":[4,1,2,2]}]}');
  FChart.Key(VK_RIGHT);
  FChart.Key(VK_RIGHT);
  AssertTrue(FChart.DispatchAction('{"type":"legendToggleSelect","name":"B"}'));
  Frame;
  FChart.Key(VK_DOWN);
  AssertEquals('the series the legend hid is not walked', '2:1', Item);
  AssertTrue(FChart.DispatchAction('{"type":"legendToggleSelect","name":"C"}'));
  Frame;
  AssertEquals('the item went with its series', 'none', Item);
  FChart.Key(VK_RIGHT);
  AssertEquals('so the walk starts again', '0:0', Item);
  { a notMerge with fewer rows: the item no longer exists }
  FChart.Key(VK_END);
  FChart.SetOption('{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{},"series":[{"type":"bar","data":[1,2]}]}', True);
  Frame;
  AssertEquals('none', Item);
  Logged;
  FChart.Key(VK_RIGHT);
  AssertEquals('0:0', Item);
  AssertEquals('nothing to downplay: the old item is gone',
    'highlight {"type":"highlight","seriesIndex":0,"dataIndex":0}', FLog.Text);
  { an empty option }
  FChart.SetOption('{"series":[]}', True);
  Frame;
  AssertEquals('none', Item);
  AssertEquals(0, FChart.Key(VK_RIGHT));
  AssertEquals('none', Item);
end;

procedure TAdvChartKeyboardTest.TestSeveralSeriesTypes;
var
  idx: Integer;
  b: TTyRectF;
begin
  Load('{"animation":false,"tooltip":{},"grid":{"right":"55%"},'
    + '"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{},'
    + '"series":[{"type":"bar","data":[1,2,3]},'
    + '{"type":"pie","center":["75%","50%"],"radius":"30%",'
    + '"data":[{"name":"x","value":1},{"name":"y","value":2}]}]}');
  FChart.TooltipNow := 1000;
  FChart.Key(VK_RIGHT);
  FChart.Key(VK_DOWN);
  AssertEquals('down to the pie, row clamped', '1:0', Item);
  Logged;
  FChart.Key(VK_RIGHT);
  AssertEquals('1:1', Item);
  AssertEquals('downplay {"type":"downplay","seriesIndex":1,"dataIndex":0} | '
    + 'highlight {"type":"highlight","seriesIndex":1,"dataIndex":1}', FLog.Text);
  AssertEquals('the slice''s tooltip', 'item:1:1', FChart.TooltipShownWhich);
  { the tooltip is placed from the slice's centre }
  idx := FChart.List.IndexOfDatumInk(1, 1);
  AssertTrue('the slice', idx >= 0);
  b := TyShapeBounds(FChart.List.Element(idx).Shape);
  AssertEquals(Round((b.Left + b.Right) / 2), FChart.TooltipAnchor.X);
  AssertEquals(Round((b.Top + b.Bottom) / 2), FChart.TooltipAnchor.Y);
end;

procedure TAdvChartKeyboardTest.TestEnterNeedsASelectedMode;
begin
  Load('{"animation":false,"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{},"series":[{"type":"bar","selectedMode":"multiple","data":[1,2,3]},'
    + '{"type":"bar","data":[3,2,1]}]}');
  FChart.Key(VK_RIGHT);
  FChart.Key(VK_RIGHT);
  Logged;
  AssertEquals('Enter is taken', 0, FChart.Key(VK_RETURN));
  AssertEquals('select and selectchanged', 2, FLog.Lines.Count);
  AssertEquals('the click''s select',
    'select {"type":"select","dataIndexInside":1,"seriesIndex":0,"isFromClick":true}',
    FLog.Lines[0]);
  AssertEquals('selectchanged', Copy(FLog.Lines[1], 1, 13));
  AssertEquals('no click event', 0, Pos('click ', FLog.Text));
  Logged;
  AssertEquals('Space is the same key', 0, FChart.Key(VK_SPACE));
  AssertEquals('selected: the click''s unselect', 'unselect', Copy(FLog.Lines[0], 1, 8));
  FChart.Key(VK_DOWN);
  Logged;
  AssertEquals('no selectedMode: Enter is the form''s', VK_RETURN, FChart.Key(VK_RETURN));
  AssertEquals('', FLog.Text);
end;

procedure TAdvChartKeyboardTest.TestTheTooltipIsShowTipAtTheItem;
var
  mouse: TKbProbe;
  idx: Integer;
  b: TTyRectF;
begin
  Load('{"animation":false,"tooltip":{},"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{},"series":[{"type":"bar","data":[1,2,3]}]}');
  FChart.TooltipNow := 1000;
  FChart.Key(VK_RIGHT);
  FChart.Key(VK_RIGHT);
  AssertTrue('shown', FChart.TooltipShown);
  AssertEquals('the item''s', 'item:0:1', FChart.TooltipShownWhich);
  idx := FChart.List.IndexOfDatumInk(0, 1);
  b := TyShapeBounds(FChart.List.Element(idx).Shape);
  { the mouse over the item shows the same item; the keyboard's box is
    showTip's -- at findPointFromSeries, the bar's dataToPoint: the
    category's centre and the value's top, not the element's centre
    [Batch 153] }
  mouse := TKbProbe.Create(FForm);
  try
    mouse.Parent := FForm;
    mouse.Controller := FCtl;
    mouse.SetBounds(0, 0, 600, 400);
    mouse.Option := FChart.Option;
    mouse.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
    mouse.TooltipNow := 1000;
    mouse.Hover(Round((b.Left + b.Right) / 2), Round((b.Top + b.Bottom) / 2));
    AssertEquals('the mouse there', mouse.TooltipShownWhich, FChart.TooltipShownWhich);
    AssertEquals(mouse.TooltipAnchor.X, FChart.TooltipAnchor.X);
    AssertEquals('the value''s top', b.Top, FChart.TooltipAnchorF.Y, 1e-9);
  finally
    mouse.Free;
  end;
  { Escape hides it, after hideDelay as any hide }
  FChart.Key(VK_ESCAPE);
  FChart.TooltipTick(2000);
  AssertFalse('hidden', FChart.TooltipShown);
  { an axis trigger: the axis' tooltip at the item's category }
  Load('{"animation":false,"tooltip":{"trigger":"axis"},'
    + '"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{},'
    + '"series":[{"type":"bar","data":[1,2,3]},{"type":"line","data":[3,2,1]}]}');
  FChart.TooltipNow := 1000;
  FChart.Key(VK_END);
  AssertEquals('the axis tooltip', 'axis:c', FChart.TooltipShownWhich);
  { showTip does not ask triggerOn: 'none' still shows for the keyboard }
  Load('{"animation":false,"tooltip":{"triggerOn":"none"},'
    + '"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{},'
    + '"series":[{"type":"bar","data":[1,2,3]}]}');
  FChart.TooltipNow := 1000;
  FChart.Key(VK_RIGHT);
  AssertEquals('triggerOn none', 'item:0:0', FChart.TooltipShownWhich);
  { trigger 'none': showTip shows nothing for an item }
  Load('{"animation":false,"tooltip":{"trigger":"none"},'
    + '"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{},'
    + '"series":[{"type":"bar","data":[1,2,3]}]}');
  FChart.TooltipNow := 1000;
  FChart.Key(VK_RIGHT);
  AssertFalse('trigger none', FChart.TooltipShown);
  { no tooltip component: none }
  Load(cBars);
  FChart.Key(VK_RIGHT);
  AssertFalse('no component, no box', FChart.TooltipShown);
end;

procedure TAdvChartKeyboardTest.TestTheRingIsTheThemesOutline;
var
  st: TTyStyleSet;
  ring: TBGRAPixel;
  idx, n0, n1: Integer;
  b: TTyRectF;

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

begin
  st := FCtl.Model.ResolveStyle('TyAdvChartFocusItem', '', []);
  AssertTrue('the theme has the key', tpOutline in st.Present);
  AssertEquals('two pixels wide', 2, st.OutlineWidth);
  AssertEquals('set off the mark', -3, st.OutlineOffset);
  ring := ColorToBGRA(TyColorToLCL(st.OutlineColor));
  Load('{"animation":false,"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{},"series":[{"type":"bar","data":[1,2,3]}]}');
  idx := FChart.List.IndexOfDatumInk(0, 1);
  b := TyShapeBounds(FChart.List.Element(idx).Shape);
  n0 := CountRing;
  AssertEquals('no ring without the keyboard', 0, n0);
  FChart.Key(VK_RIGHT);
  FChart.Key(VK_RIGHT);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  Frame;
  n1 := CountRing;
  { the ring's four sides, two pixels each, around a bar of b }
  AssertTrue(Format('the ring is drawn (%d px)', [n1]),
    n1 >= 2 * Round((b.Right - b.Left) + (b.Bottom - b.Top)));
  { THE WINDOW'S PATH: a ring with no tooltip and no hover is still
    something for the dynamic layer }
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.RenderLayered(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
  AssertEquals('the cached path draws it too', n1, CountRing);
  FChart.Key(VK_ESCAPE);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  Frame;
  AssertEquals('Escape takes it away', 0, CountRing);
end;

procedure TAdvChartKeyboardTest.TestTheTabStopStaysFalse;
var
  c: TTyAdvanceChart;
  pi: PPropInfo;
begin
  c := TTyAdvanceChart.Create(nil);
  try
    AssertFalse('constructed no tab stop: an existing form keeps its focus', c.TabStop);
    pi := GetPropInfo(c, 'TabStop');
    AssertTrue(pi <> nil);
    AssertEquals('declared default False, so the .lfm streams a True', 0, pi^.Default);
    c.TabStop := True;
    AssertTrue('the host opts in', c.TabStop);
  finally
    c.Free;
  end;
end;

procedure TAdvChartKeyboardTest.TestTheTreeFollowsTheChart;
var
  root: TLazAccessibleObject;
  ser, items: TTyAccObjectArray;
  withAria: string;
  idx: Integer;
  b: TTyRectF;
begin
  Load(cBars);
  FChart.AccessibleSync;
  root := FChart.GetAccessibleObject;
  AssertEquals('a chart', Ord(larChart), Ord(root.AccessibleRole));
  AssertEquals('no title: the word', 'Chart', root.AccessibleName);
  { no aria in the option: the sentence aria would write all the same }
  withAria := FChart.AriaDescription;
  AssertEquals('aria off: no aria description', '', withAria);
  AssertTrue('a description all the same', root.AccessibleDescription <> '');
  ser := TyAccChildren(root);
  AssertEquals('one list per series', 3, Length(ser));
  AssertEquals(' The 0 series is a Bar chart.', ' ' + ser[0].AccessibleName);
  items := TyAccChildren(ser[0]);
  AssertEquals('one item per row', 4, Length(items));
  AssertEquals('the data for a is 0, 1', items[0].AccessibleName);
  AssertEquals('the data for d is 3, 4', items[3].AccessibleName);
  AssertEquals('the line', 3, Length(TyAccChildren(ser[1])));
  AssertTrue('in the description', Pos(items[2].AccessibleName, root.AccessibleDescription) > 0);
  { placed over the bar }
  idx := FChart.List.IndexOfDatumInk(0, 2);
  b := TyShapeBounds(FChart.List.Element(idx).Shape);
  AssertEquals(Floor(b.Left), items[2].Position.X);
  AssertEquals(Floor(b.Top), items[2].Position.Y);
  AssertEquals(Ceil(b.Right) - Floor(b.Left), items[2].Size.cx);
  { the same sentence the option's aria writes }
  FChart.SetOption(Copy(cBars, 1, Length(cBars) - 1) + ',"aria":{"enabled":true}}', True);
  Frame;
  FChart.AccessibleSync;
  AssertEquals('with aria on, the aria description itself',
    FChart.AriaDescription, root.AccessibleDescription);
  AssertTrue(FChart.AriaDescription <> '');
  { a title names it; a legend toggle rebuilds the tree; nothing is rebuilt
    without a new layout }
  Load('{"animation":false,"title":{"text":"Sales"},"legend":{},'
    + '"xAxis":{"type":"category","data":["a","b"]},"yAxis":{},'
    + '"series":[{"type":"bar","name":"A","data":[1,2]},{"type":"bar","name":"B","data":[2,1]}]}');
  FChart.AccessibleSync;
  AssertEquals('the title', 'Sales', root.AccessibleName);
  AssertEquals(2, root.GetChildAccessibleObjectsCount);
  items := TyAccChildren(TyAccChildren(root)[1]);
  FChart.AccessibleSync;
  AssertTrue('the same objects without a new layout',
    TyAccChildren(TyAccChildren(root)[1])[0] = items[0]);
  AssertTrue(FChart.DispatchAction('{"type":"legendToggleSelect","name":"A"}'));
  Frame;
  FChart.AccessibleSync;
  AssertEquals('the legend hid one', 1, root.GetChildAccessibleObjectsCount);
  AssertEquals('The 1 series is a Bar chart representing B.', TyAccChildren(root)[0].AccessibleName);
  { an empty chart: the word, no description, no children }
  Load('{"series":[]}');
  FChart.AccessibleSync;
  AssertEquals('Chart', root.AccessibleName);
  AssertEquals('', root.AccessibleDescription);
  AssertEquals(0, root.GetChildAccessibleObjectsCount);
end;

procedure TAdvChartKeyboardTest.TestTheTreeIsCappedAndTheKeysAreNot;
var
  s: string;
  i: Integer;
begin
  s := '';
  for i := 0 to 1199 do
  begin
    if i > 0 then s := s + ',';
    s := s + IntToStr(i mod 7);
  end;
  Load('{"animation":false,"xAxis":{"type":"category"},"yAxis":{},'
    + '"series":[{"type":"bar","data":[' + s + ']}]}');
  FChart.AccessibleSync;
  AssertEquals('a thousand items at most', 1000,
    TyAccChildren(FChart.GetAccessibleObject)[0].GetChildAccessibleObjectsCount);
  FChart.Key(VK_END);
  AssertEquals('the keys walk every row', '0:1199', Item);
  AssertTrue('past the cap there is no item object', FChart.AccessibleFocusedChild = nil);
  FChart.Key(VK_HOME);
  AssertTrue('within it there is', FChart.AccessibleFocusedChild = FChart.AccessibleItem(0, 0));
end;

procedure TAdvChartKeyboardTest.TestTheTreeAnswersTheHost;
var it1, it2: TLazAccessibleObject;
begin
  Load('{"animation":false,"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{},"series":[{"type":"bar","selectedMode":"single","data":[1,2,3]}]}');
  FChart.AccessibleSync;
  it1 := FChart.AccessibleItem(0, 1);
  it2 := FChart.AccessibleItem(0, 2);
  AssertTrue(it1 <> nil);
  AssertTrue('nothing focused', FChart.AccessibleFocusedChild = nil);
  FChart.Key(VK_RIGHT);
  FChart.Key(VK_RIGHT);
  AssertTrue('the keyboard''s item', FChart.AccessibleFocusedChild = it1);
  AssertFalse(FChart.AccessibleSelected(it1));
  FChart.Key(VK_RETURN);
  AssertTrue('selected by Enter', FChart.AccessibleSelected(it1));
  AssertFalse(FChart.AccessibleSelected(it2));
  Logged;
  AssertTrue('the platform may move the focus', FChart.AccessibleTakeFocus(it2));
  AssertEquals('0:2', Item);
  AssertEquals('as a key would', 'downplay {"type":"downplay","seriesIndex":0,"dataIndex":1} | '
    + 'highlight {"type":"highlight","seriesIndex":0,"dataIndex":2}', FLog.Text);
  AssertFalse('the root is no item', FChart.AccessibleTakeFocus(FChart.GetAccessibleObject));
  FChart.Key(VK_ESCAPE);
  AssertTrue('Escape: nothing focused', FChart.AccessibleFocusedChild = nil);
end;

procedure TAdvChartKeyboardTest.TestTheOrderedChildren;
var
  root: TLazAccessibleObject;
  kids, back: TTyAccObjectArray;
  i: Integer;
begin
  root := TLazAccessibleObject.Create(FChart);
  try
    kids := TyAccAddChildren(root, 40);
    for i := 0 to High(kids) do kids[i].AccessibleName := IntToStr(i);
    back := TyAccChildren(root);
    AssertEquals(40, Length(back));
    for i := 0 to High(back) do
      AssertEquals('LCL lists them in the order they were filled', IntToStr(i), back[i].AccessibleName);
    { LCL's own indexed walk agrees, read in order }
    for i := 0 to 39 do
      AssertEquals(IntToStr(i), root.GetChildAccessibleObject(i).AccessibleName);
    AssertEquals('pre-order', 7, TyAccPreorderIndex(root, kids[7]));
    AssertTrue(TyAccByPreorder(root, 7) = kids[7]);
    AssertTrue(TyAccByPreorder(root, 40) = nil);
    AssertEquals(-1, TyAccPreorderIndex(root, root));
  finally
    root.Free;
  end;
end;

{$IFDEF WINDOWS}

function NameOf(const A: IAccessible; AChild: LongInt): string;
var p: PWideChar;
begin
  p := nil;
  A.get_accName(TyAccChild(AChild), @p);
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

function VarDispatch(var V: TTyAccVariant): IAccessible;
var d: IDispatch;
begin
  Result := nil;
  if V.VType <> TyAccVtDispatch then Exit;
  Pointer(d) := V.PVal;
  V := Default(TTyAccVariant);
  Result := d as IAccessible;
end;

procedure TAdvChartKeyboardTest.TestTheMsaaTree;
var
  root, s0, it, nx: IAccessible;
  n, x, y, w, h, rx, ry, rw, rh: LongInt;
  v: TTyAccVariant;
  p: PWideChar;
  itemObj: TLazAccessibleObject;
begin
  AssertEquals('a VARIANT''s size', 8 + 2 * SizeOf(Pointer), SizeOf(TTyAccVariant));
  Load('{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d"]},'
    + '"yAxis":{},"series":[{"type":"bar","selectedMode":"single","data":[1,2,3,4]},'
    + '{"type":"line","data":[2,3,1]}]}');
  root := FChart.AccessibleLink.Root as IAccessible;
  AssertEquals(S_OK, root.get_accChildCount(@n));
  AssertEquals('two series', 2, n);
  AssertEquals('Chart', NameOf(root, TyAccChildSelf));
  v := Default(TTyAccVariant);
  AssertEquals(S_OK, root.get_accRole(TyAccChild(TyAccChildSelf), @v));
  AssertEquals('ROLE_SYSTEM_CHART', $11, v.LVal);
  p := nil;
  root.get_accDescription(TyAccChild(TyAccChildSelf), @p);
  AssertEquals('the description', FChart.GetAccessibleObject.AccessibleDescription, TyAccTakeBstr(p));
  AssertEquals('a child by id', 'The 0 series is a Bar chart.', NameOf(root, 1));
  s0 := ChildOf(root, 1);
  AssertTrue(s0 <> nil);
  AssertEquals(S_OK, s0.get_accChildCount(@n));
  AssertEquals(4, n);
  s0.get_accRole(TyAccChild(TyAccChildSelf), @v);
  AssertEquals('ROLE_SYSTEM_LIST', $21, v.LVal);
  it := ChildOf(s0, 2);
  AssertEquals('the data for b is 1, 2', NameOf(it, TyAccChildSelf));
  it.get_accRole(TyAccChild(TyAccChildSelf), @v);
  AssertEquals('ROLE_SYSTEM_LISTITEM', $22, v.LVal);
  { where it is: the item's place in the control, on the screen }
  itemObj := FChart.AccessibleItem(0, 1);
  AssertEquals(S_OK, root.accLocation(@rx, @ry, @rw, @rh, TyAccChild(TyAccChildSelf)));
  AssertEquals(S_OK, it.accLocation(@x, @y, @w, @h, TyAccChild(TyAccChildSelf)));
  AssertEquals(itemObj.Position.X, x - rx);
  AssertEquals(itemObj.Position.Y, y - ry);
  AssertEquals(itemObj.Size.cx, w);
  AssertEquals('the root is the client area', FChart.ClientWidth, rw);
  { a descendant by the events' id: -(1 + its pre-order index) }
  AssertEquals('series 0 is 0, its rows 1..4', 'the data for b is 1, 2', NameOf(root, -3));
  AssertEquals('the line''s first row', 'the data for a is 0, 2', NameOf(root, -7));
  { navigation }
  v := Default(TTyAccVariant);
  AssertEquals(S_OK, it.accNavigate(TyAccNavNext, TyAccChild(TyAccChildSelf), @v));
  nx := VarDispatch(v);
  AssertEquals('the next row', 'the data for c is 2, 3', NameOf(nx, TyAccChildSelf));
  AssertEquals('no sibling past the last', S_FALSE,
    ChildOf(s0, 4).accNavigate(TyAccNavNext, TyAccChild(TyAccChildSelf), @v));
  AssertEquals(S_OK, s0.accNavigate(TyAccNavFirstChild, TyAccChild(TyAccChildSelf), @v));
  AssertEquals('the data for a is 0, 1', NameOf(VarDispatch(v), TyAccChildSelf));
  { state, and the focus taken through MSAA }
  it.get_accState(TyAccChild(TyAccChildSelf), @v);
  AssertTrue('selectable', (v.LVal and TyAccStateSelectable) <> 0);
  AssertTrue('not selected', (v.LVal and TyAccStateSelected) = 0);
  AssertEquals(S_OK, it.accSelect(TyAccSelTakeFocus, TyAccChild(TyAccChildSelf)));
  AssertEquals('accSelect moved the keyboard', '0:1', Item);
  FChart.Key(VK_RETURN);
  it.get_accState(TyAccChild(TyAccChildSelf), @v);
  AssertTrue('selected', (v.LVal and TyAccStateSelected) <> 0);
  root.get_accState(TyAccChild(TyAccChildSelf), @v);
  AssertTrue('no tab stop: not focusable', (v.LVal and TyAccStateFocusable) = 0);
  FChart.TabStop := True;
  root.get_accState(TyAccChild(TyAccChildSelf), @v);
  AssertTrue('a tab stop: focusable', (v.LVal and TyAccStateFocusable) <> 0);
  { the parent of a row is its series }
  AssertEquals('a bad child id', E_INVALIDARG, root.get_accName(TyAccChild(9), @p));
end;

procedure TAdvChartKeyboardTest.TestTheMsaaNodesOutliveNothing;
var
  root, line: IAccessible;
  n: LongInt;
  c: TKbProbe;
begin
  Load(cBars);
  root := FChart.AccessibleLink.Root as IAccessible;
  line := ChildOf(ChildOf(root, 3), 1);
  AssertTrue('the scatter''s first row', NameOf(line, TyAccChildSelf) <> '');
  { the tree is rebuilt: a node is a path, read against the new one }
  FChart.SetOption('{"animation":false,"xAxis":{"type":"category","data":["a"]},'
    + '"yAxis":{},"series":[{"type":"bar","data":[5]}]}', True);
  Frame;
  AssertEquals('the series it named is gone', TyAccDisconnected,
    line.get_accChildCount(@n));
  AssertEquals(S_OK, root.get_accChildCount(@n));
  AssertEquals(1, n);
  { the control is gone: every node a client holds says so }
  c := FChart;
  FChart := nil;
  c.Free;
  AssertEquals('disconnected', TyAccDisconnected, root.get_accChildCount(@n));
  root := nil;
  line := nil;
  FChart := TKbProbe.Create(FForm);
end;

type
  TObjectFromLresult = function(lResult: LRESULT; riid: PGUID; wParam: WPARAM;
    ppvObject: PPointer): HResult; stdcall;

{ [Milestone D9-D14] what a screen reader hears: an out-of-context WinEvent
  hook on this process, its callbacks run while the thread pumps messages }
var
  GFocusWnd: HWND;
  GFocusChild: LongInt;
  GFocusCount: Integer;

procedure FocusEventProc(AHook: THandle; AEvent: DWORD; AWnd: HWND;
  AObject, AChild: LongInt; AThread, ATime: DWORD); stdcall;
begin
  if (AEvent = $8005) and (AWnd = GFocusWnd) and (AObject = TyAccObjIdClient) then
  begin
    GFocusChild := AChild;
    Inc(GFocusCount);
  end;
end;

function TySetWinEventHook(AMin, AMax: DWORD; AMod: HMODULE; AProc: Pointer;
  AProcess, AThread, AFlags: DWORD): THandle; stdcall;
  external 'user32.dll' name 'SetWinEventHook';
function TyUnhookWinEvent(AHook: THandle): BOOL; stdcall;
  external 'user32.dll' name 'UnhookWinEvent';

procedure TAdvChartKeyboardTest.TestTheWindowAnswersGetObject;
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
  { A WINDOW NEEDS THE WIDGETSET, and initialising it here would move every
    later suite's text onto the real fonts (suite-order-widgetset-init):
    this runs when something before it initialised the widgetset, or when
    TY_KEYBOARD_WINDOW=1 asks for it in a run of its own }
  if not (AppInitialized in Application.Flags) then
  begin
    if SysUtils.GetEnvironmentVariable('TY_KEYBOARD_WINDOW') = '1' then Application.Initialize
    else Ignore('needs an initialised widgetset (TY_KEYBOARD_WINDOW=1)');
  end;
  Load(cBars);
  FForm.HandleNeeded;
  FChart.HandleNeeded;
  AssertTrue('a handle', FChart.HandleAllocated);
  AssertFalse('nobody has asked yet', FChart.AccessibleLink.InUse);
  lres := SendMessage(FChart.Handle, $003D, 0, LPARAM(LongInt(TyAccObjIdClient)));
  AssertTrue('WM_GETOBJECT answered', lres > 0);
  AssertTrue('a client asked', FChart.AccessibleLink.InUse);
  lib := LoadLibrary('oleacc.dll');
  AssertTrue(lib <> 0);
  Pointer(fromLresult) := GetProcAddress(lib, 'ObjectFromLresult');
  p := nil;
  AssertEquals(S_OK, fromLresult(lres, @IID_IAccessible, 0, @p));
  Pointer(acc) := p;
  AssertEquals('Chart', NameOf(acc, TyAccChildSelf));
  AssertEquals('the scatter', 'The 2 series is a Scatter plot.', NameOf(acc, 3));
  { A FOCUS MOVE IS ANNOUNCED [Milestone D9-D14]: EVENT_OBJECT_FOCUS on the
    client object, the child a descendant's id -(1 + its pre-order index),
    which the root's own get_accName answers }
  GFocusWnd := FChart.Handle;
  GFocusChild := 0;
  GFocusCount := 0;
  hook := TySetWinEventHook($8005, $8005, 0, @FocusEventProc, GetCurrentProcessId, 0, 0);
  AssertTrue('a WinEvent hook', hook <> 0);
  try
    FChart.Key(VK_RIGHT);
    Application.ProcessMessages;
  finally
    TyUnhookWinEvent(hook);
  end;
  AssertTrue('the focus was announced', GFocusCount > 0);
  AssertTrue('as a descendant: a negative child id', GFocusChild < 0);
  AssertEquals('the root names that descendant (the first bar)',
    'the data for a is 0, 1', NameOf(acc, GFocusChild));
  acc := nil;
  FChart.DestroyHandle;
  AssertFalse('unhooked with the window', FChart.AccessibleLink.InUse);
end;
{$ENDIF}

initialization
  RegisterTest(TAdvChartKeyboardOracleTest);
  RegisterTest(TAdvChartKeyboardTest);
end.
