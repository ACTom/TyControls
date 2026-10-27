unit test.advchart.edgesmisc;
{$mode objfpc}{$H+}
{ THE LAST EDGES OF ROUND FIVE [R5-J, spec 244b].

  tools/advchart-oracle/edges-misc.js records, on ECharts 6.1:

    events   every event type chart.on hears -- the published action events
             (registerAction's publicEventTypeMap), the legacy pie / map
             select events, the render and the mouse events -- and the three
             only connect hears; then charts with three handlers on every
             published type and `updated` (a plain one, 'series.nosuch',
             {seriesIndex: 5}: an action event has no eventInfo, so no query
             filters it) and steps: actions, a tree node's click, drags and
             wheels on a tree, a graph and a sankey, each step's log;
    append   object items appendData pushes carry their own symbol, size,
             rotation, colour and label as the items an option writes.

  The replay holds the control to those: ChartOn takes every published type
  and refuses the rest; an action step's log is upstream's, handler by
  handler, payload by payload; a gesture step's roam and expand events too
  (the pointer's other traffic -- the axis pointer's updateAxisPointer and
  hideTip on every move -- is the tooltip suites'). }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller, tyControls.Painter,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Events, tyControls.AdvanceChart.Measure,
     tyControls.AdvanceChart.ThemeRiver, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart;
type
  TEmProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Move(AX, AY: Integer);
    procedure Down(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
    function Wheel(AX, AY, ADelta: Integer): Boolean;
  end;

  TEmLogger = class
  public
    Id: string;
    Log: TStringList;
    procedure Handle(Sender: TObject; const AEvent: TTyChartEvent);
  end;

  TAdvChartEdgesMiscOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot: TJSONData;
    FLoggers: TList;
    function NewChart(AW, AH: Integer): TEmProbe;
    function Section(const AKey: string): TJSONObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestChartOnTakesEveryTypeUpstreamPublishes;
    procedure TestTheActionEventsReachChartOnAsUpstream;
    procedure TestAnAppendedItemDrawsItsOwnSymbol;
    procedure TestTheDiagnosticsAreTheOptionsAtOnce;
    procedure TestARiverMergedTheSameGapResolvesItAgain;
    procedure TestASplitAreaGradientRampsAsUpstreams;
  end;

{ a payload as text both sides compare: keys sorted, numbers by value, a
  view's uid ('from') and an auto id's NULs (as the fixture writes them,
  '^') normalised }
function EmCanonical(const AJson: string): string;

implementation

procedure TEmProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TEmProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TEmProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TEmProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [ssLeft], AX, AY);
end;

procedure TEmProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

function TEmProbe.Wheel(AX, AY, ADelta: Integer): Boolean;
begin
  Result := DoMouseWheel([], ADelta, Point(AX, AY));
end;

procedure TEmLogger.Handle(Sender: TObject; const AEvent: TTyChartEvent);
begin
  Log.Add(Id + #9 + AEvent.EventType + #9 + EmCanonical(AEvent.Payload));
end;

function CanonOf(AData: TJSONData; const AKey: string): string;
var
  names: TStringList;
  i: Integer;
  o: TJSONObject;
begin
  if AData = nil then Exit('undefined');
  case AData.JSONType of
    jtNull: Result := 'null';
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
    jtNumber: Result := FloatToStr(AData.AsFloat, DefaultFormatSettings);
    jtString:
      if AKey = 'from' then Result := '"<from>"'
      else Result := '"' + StringReplace(AData.AsString, #0, '^', [rfReplaceAll]) + '"';
    jtArray:
      begin
        Result := '[';
        for i := 0 to AData.Count - 1 do
        begin
          if i > 0 then Result := Result + ',';
          Result := Result + CanonOf(AData.Items[i], '');
        end;
        Result := Result + ']';
      end;
    jtObject:
      begin
        o := TJSONObject(AData);
        names := TStringList.Create;
        try
          names.UseLocale := False;
          names.CaseSensitive := True;
          for i := 0 to o.Count - 1 do names.Add(o.Names[i]);
          names.Sort;
          Result := '{';
          for i := 0 to names.Count - 1 do
          begin
            if i > 0 then Result := Result + ',';
            Result := Result + names[i] + ':' + CanonOf(o.Find(names[i]), names[i]);
          end;
          Result := Result + '}';
        finally
          names.Free;
        end;
      end;
  else
    Result := AData.AsJSON;
  end;
end;

function EmCanonical(const AJson: string): string;
var d: TJSONData;
begin
  if AJson = '' then Exit('');
  { the port's own auto ids hold NULs (fpjson would drop the \u0000 the
    fixture never writes): the fixture's '^' }
  try
    d := GetJSON(StringReplace(AJson, '\u0000', '^', [rfReplaceAll]));
  except
    Exit('unparsed ' + AJson);
  end;
  try
    Result := CanonOf(d, '');
  finally
    d.Free;
  end;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-edges-misc.json';
end;

procedure TAdvChartEdgesMiscOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FLoggers := TList.Create;
  FRoot := nil;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure TAdvChartEdgesMiscOracleTest.TearDown;
var i: Integer;
begin
  for i := 0 to FLoggers.Count - 1 do TObject(FLoggers[i]).Free;
  FLoggers.Free;
  FRoot.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

function TAdvChartEdgesMiscOracleTest.NewChart(AW, AH: Integer): TEmProbe;
begin
  Result := TEmProbe.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.AnimationMode := camOff;
  Result.SetBounds(0, 0, AW, AH);
end;

function TAdvChartEdgesMiscOracleTest.Section(const AKey: string): TJSONObject;
var d: TJSONData;
begin
  AssertNotNull('the fixture', FRoot);
  d := TJSONObject(FRoot).Find(AKey);
  AssertTrue('the fixture''s ' + AKey, d is TJSONObject);
  Result := TJSONObject(d);
end;

{ EVERY TYPE chart.on HEARS IS ONE ChartOn TAKES, and the three only connect
  hears are refused [was: datazoom, restore, magictypechanged,
  dataviewchanged, showtip, hidetip, updateaxispointer and fifteen more
  answered -1] }
procedure TAdvChartEdgesMiscOracleTest.TestChartOnTakesEveryTypeUpstreamPublishes;
const
  cLists: array[0..3] of string = ('public', 'legacy', 'rendering', 'mouse');
var
  ev: TJSONObject;
  arr: TJSONArray;
  chart: TEmProbe;
  lg: TEmLogger;
  i, k, id: Integer;
  t: string;
begin
  ev := Section('events');
  chart := NewChart(600, 400);
  lg := TEmLogger.Create;
  FLoggers.Add(lg);
  for k := 0 to High(cLists) do
  begin
    arr := ev.Arrays[cLists[k]];
    AssertTrue(cLists[k] + ' listed', arr.Count > 0);
    for i := 0 to arr.Count - 1 do
    begin
      t := arr.Strings[i];
      AssertEquals(cLists[k] + ' ' + t, t, TyChartEventTypeOf(t));
      id := chart.ChartOn(t, @lg.Handle);
      AssertTrue(cLists[k] + ' ' + t + ' registered', id > 0);
      chart.ChartOff(id);
    end;
  end;
  { as written in an action's camel case: lowercased, as upstream lowercases
    a name it is given }
  AssertEquals('dataZoom', 'datazoom', TyChartEventTypeOf('dataZoom'));
  AssertEquals('updateAxisPointer', 'updateaxispointer', TyChartEventTypeOf('updateAxisPointer'));
  arr := ev.Arrays['connectOnly'];
  AssertEquals('three only connect hears', 3, arr.Count);
  for i := 0 to arr.Count - 1 do
  begin
    AssertEquals(arr.Strings[i] + ' is no chart event', '', TyChartEventTypeOf(arr.Strings[i]));
    AssertEquals(arr.Strings[i] + ' refused', -1, chart.ChartOn(arr.Strings[i], @lg.Handle));
  end;
end;

{ THE ACTION EVENTS THROUGH ChartOn: every case's chart with the oracle's
  three registrations on every published type and `updated`, each step
  replayed and its log compared -- an action step's whole, a gesture step's
  roam and expand events }
procedure TAdvChartEdgesMiscOracleTest.TestTheActionEventsReachChartOnAsUpstream;
const
  cGesture: array[0..3] of string = ('graphroam', 'treeroam', 'sankeyroam',
    'treeexpandandcollapse');
var
  ev, cs, st, q: TJSONObject;
  cases, steps, pub, queries, ulog, row: TJSONArray;
  chart: TEmProbe;
  log, want, got: TStringList;
  c, s, i, k, x, y: Integer;
  lg: TEmLogger;
  types: TStringList;
  qtext, tag, line: string;
  gesture: Boolean;
  bmp: TBitmap;
  bad: Integer;
  report: string;
  d: TJSONData;

  function Kept(const AType: string): Boolean;
  var j: Integer;
  begin
    if not gesture then Exit(True);
    for j := 0 to High(cGesture) do
      if AType = cGesture[j] then Exit(True);
    Result := False;
  end;

  function TypeOf(const ALine: string): string;
  var a, b: Integer;
  begin
    a := Pos(#9, ALine);
    b := Pos(#9, Copy(ALine, a + 1, MaxInt)) + a;
    Result := Copy(ALine, a + 1, b - a - 1);
  end;

begin
  ev := Section('events');
  cases := ev.Arrays['cases'];
  pub := ev.Arrays['public'];
  queries := ev.Arrays['queries'];
  log := TStringList.Create;
  want := TStringList.Create;
  got := TStringList.Create;
  types := TStringList.Create;
  bmp := TBitmap.Create;
  bad := 0;
  report := '';
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(600, 400);
    for i := 0 to pub.Count - 1 do types.Add(pub.Strings[i]);
    types.Add('updated');
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      chart := NewChart(600, 400);
      chart.Option := cs.Objects['option'].AsJSON;
      chart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
      for i := 0 to types.Count - 1 do
        for k := 0 to queries.Count - 1 do
        begin
          q := queries.Objects[k];
          lg := TEmLogger.Create;
          FLoggers.Add(lg);
          lg.Id := q.Strings['h'];
          lg.Log := log;
          d := q.Find('query');
          if (d = nil) or (d.JSONType = jtNull) then qtext := ''
          else if d.JSONType = jtString then qtext := d.AsString
          else qtext := d.AsJSON;
          AssertTrue(cs.Strings['id'] + ' ' + types[i] + ' registered',
            chart.ChartOn(types[i], @lg.Handle, qtext) > 0);
        end;
      steps := cs.Arrays['steps'];
      for s := 0 to steps.Count - 1 do
      begin
        st := steps.Objects[s];
        tag := cs.Strings['id'] + ' step ' + IntToStr(s);
        log.Clear;
        gesture := st.Find('action') = nil;
        if not gesture then
          AssertTrue(tag + ' dispatched', chart.DispatchAction(st.Objects['action'].AsJSON))
        else if st.Find('click') <> nil then
        begin
          x := st.Arrays['at'].Integers[0];
          y := st.Arrays['at'].Integers[1];
          chart.Move(x, y);
          chart.Down(x, y);
          chart.Up(x, y);
        end
        else if st.Find('drag') <> nil then
        begin
          row := st.Arrays['drag'];
          chart.Move(row.Arrays[0].Integers[0], row.Arrays[0].Integers[1]);
          chart.Down(row.Arrays[0].Integers[0], row.Arrays[0].Integers[1]);
          for k := 1 to row.Count - 1 do
            chart.Move(row.Arrays[k].Integers[0], row.Arrays[k].Integers[1]);
          chart.Up(row.Arrays[row.Count - 1].Integers[0], row.Arrays[row.Count - 1].Integers[1]);
        end
        else if st.Find('wheel') <> nil then
        begin
          row := st.Arrays['wheel'];
          chart.Wheel(row.Integers[0], row.Integers[1], row.Integers[2]);
        end;
        chart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
        want.Clear;
        ulog := st.Arrays['log'];
        for k := 0 to ulog.Count - 1 do
          if Kept(ulog.Arrays[k].Strings[1]) then
            want.Add(ulog.Arrays[k].Strings[0] + #9 + ulog.Arrays[k].Strings[1] + #9
              + EmCanonical(ulog.Arrays[k].Strings[2]));
        got.Clear;
        for k := 0 to log.Count - 1 do
        begin
          line := log[k];
          if Kept(TypeOf(line)) then got.Add(line);
        end;
        if gesture then
          AssertTrue(tag + ': upstream published something to compare', want.Count > 0);
        if want.Text <> got.Text then
        begin
          Inc(bad);
          if Length(report) < 9000 then
            report := report + LineEnding + tag + LineEnding + '  upstream:' + LineEnding
              + '    ' + StringReplace(Trim(want.Text), LineEnding, LineEnding + '    ', [rfReplaceAll])
              + LineEnding + '  here:' + LineEnding + '    '
              + StringReplace(Trim(got.Text), LineEnding, LineEnding + '    ', [rfReplaceAll]);
        end;
      end;
      chart.Free;
    end;
    AssertTrue(Format('%d steps differ:%s', [bad, report]), bad = 0);
  finally
    bmp.Free;
    types.Free;
    got.Free;
    want.Free;
    log.Free;
  end;
end;

{ what a symbol element is: every element of the datum (its symbol, its
  label), then the one that carries the ink -- kind, path, box, centre,
  radius, fill, turn, points }
function SymSig(AList: TTyPaintList; ASeries, ARow: Integer): string;
var k, i, j: Integer; e: TTyChartElement;
begin
  if AList = nil then Exit('no list');
  Result := '';
  for j := 0 to AList.Count - 1 do
  begin
    e := AList.Element(j);
    if (e.Datum.Kind <> ctkSeries) or (e.Datum.SeriesIndex <> ASeries)
      or (e.Datum.DataIndex <> ARow) then Continue;
    Result := Result + ' [' + e.Caption.Text + '|' + IntToStr(Ord(e.Style.HasFill)) + ']';
  end;
  k := AList.IndexOfDatumInk(ASeries, ARow);
  if k < 0 then Exit('none' + Result);
  e := AList.Element(k);
  Result := Result + IntToStr(Ord(e.Shape.Kind)) + ':' + e.Shape.PathData + ':'
    + FloatToStr(e.Shape.Bounds.Left) + ',' + FloatToStr(e.Shape.Bounds.Top) + ','
    + FloatToStr(e.Shape.Bounds.Right) + ',' + FloatToStr(e.Shape.Bounds.Bottom) + ':'
    + FloatToStr(e.Shape.CX) + ',' + FloatToStr(e.Shape.CY) + ','
    + FloatToStr(e.Shape.R1) + ':' + IntToHex(e.Style.FillColor, 8) + ':'
    + FloatToStr(e.Style.Alpha) + ':' + FloatToStr(e.Shape.RotationRad);
  for i := 0 to High(e.Shape.Points) do
    Result := Result + ';' + FloatToStr(e.Shape.Points[i].X) + ','
      + FloatToStr(e.Shape.Points[i].Y);
end;

{ AN OBJECT ITEM APPENDED DRAWS AS ONE WRITTEN: its own symbol, size,
  rotation, offset, colour, opacity and label, in the frame that takes it in
  and after a full update -- as upstream's getItemModel reads the appended
  raw item (the oracle: every appended row's symbol is the written one's).
  [The R5-G note that the symbol was not drawn read the label's element:
  IndexOfDatum answers the topmost, the label.] }
procedure TAdvChartEdgesMiscOracleTest.TestAnAppendedItemDrawsItsOwnSymbol;
var
  ap: TJSONObject;
  a, b: TEmProbe;
  bmp: TBitmap;
  head, tail: string;
  k, n: Integer;
  w: TJSONArray;
begin
  ap := Section('append');
  w := ap.Arrays['written'];
  AssertEquals('the oracle''s triangle', 'triangle', w.Objects[4].Strings['symbol']);
  head := ap.Arrays['head'].AsJSON;
  tail := ap.Arrays['tail'].AsJSON;
  n := w.Count;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(400, 300);
    a := NewChart(400, 300);
    a.Option := '{"animation":false,"xAxis":{"min":0,"max":30},"yAxis":{"min":0,"max":12},'
      + '"series":[{"type":"scatter","symbolSize":8,"data":'
      + Copy(head, 1, Length(head) - 1) + ',' + Copy(tail, 2, MaxInt) + '}]}';
    a.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    b := NewChart(400, 300);
    b.Option := '{"animation":false,"xAxis":{"min":0,"max":30},"yAxis":{"min":0,"max":12},'
      + '"series":[{"type":"scatter","symbolSize":8,"data":' + head + '}]}';
    b.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    AssertTrue('appended', b.AppendData(0, tail));
    b.ProgressTick;
    b.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    for k := 0 to n - 1 do
      AssertEquals('row ' + IntToStr(k) + ' in the frame', SymSig(a.List, 0, k),
        SymSig(b.List, 0, k));
    { the label of the appended triangle, its fill the item's red }
    AssertTrue('the appended label', Pos('[M|', SymSig(b.List, 0, 4)) > 0);
    AssertTrue('the appended red', Pos('FFFF0000', SymSig(b.List, 0, 4)) > 0);
    { a full update of the same tree }
    b.MergeOption('{}');
    b.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    for k := 0 to n - 1 do
      AssertEquals('row ' + IntToStr(k) + ' after an update', SymSig(a.List, 0, k),
        SymSig(b.List, 0, k));
  finally
    bmp.Free;
  end;
end;

{ THE DIAGNOSTICS ARE THE OPTION'S AS SOON AS IT IS SET: before the first
  paint (laid out where that paint will lay it out, which then finds it
  done and draws the same), and after a new option on a painted chart --
  not the previous option's. A control of no size has nothing to answer
  from. [Was: empty until a paint, the previous option's after one.] }
procedure TAdvChartEdgesMiscOracleTest.TestTheDiagnosticsAreTheOptionsAtOnce;
const
  cBad = '{"animation":false,"xAxis":{},"yAxis":{},"series":[{"type":"bard","data":[1]}]}';
  cGood = '{"animation":false,"xAxis":{"type":"category","data":["a"]},"yAxis":{},'
    + '"series":[{"type":"bar","data":[1]}]}';
var
  chart, ref: TEmProbe;
  bmp, bmp2: TBGRABitmap;
  n, k: Integer;
  first: string;
begin
  bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  bmp2 := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  try
    chart := NewChart(400, 300);
    chart.Option := cBad;
    n := chart.DiagnosticCount;
    AssertTrue('before the first paint', n > 0);
    first := chart.Diagnostic(0);
    AssertTrue('a sentence', first <> '');
    { the paint finds the layout done: the same diagnostics, the same
      picture as a chart that was never asked }
    chart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    AssertEquals('after the paint', n, chart.DiagnosticCount);
    AssertEquals('the same sentence', first, chart.Diagnostic(0));
    ref := NewChart(400, 300);
    ref.Option := cBad;
    ref.Render(bmp2.Canvas, Rect(0, 0, 400, 300), 96);
    for k := 0 to 400 * 300 - 1 do
      if bmp.GetPixel(k mod 400, k div 400) <> bmp2.GetPixel(k mod 400, k div 400) then
        Fail('the picture after an early read differs at ' + IntToStr(k));
    { a new option on the painted chart: its own diagnostics at once }
    chart.Option := cGood;
    AssertEquals('the good option has none', 0, chart.DiagnosticCount);
    chart.Option := cBad;
    AssertEquals('and the bad one its own again', n, chart.DiagnosticCount);
    { no size, no layout }
    ref := NewChart(0, 0);
    ref.Option := cBad;
    AssertEquals('no size: nothing to answer from', 0, ref.DiagnosticCount);
  finally
    bmp.Free;
    bmp2.Free;
  end;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function SameBits(A, B: Double): Boolean;
begin
  Result := CompareMem(@A, @B, SizeOf(Double));
end;

{ A MERGE THAT WRITES boundaryGap -- the same text too -- has the river
  resolve it again at the size it has then: upstream's merge replaces the
  model's array the layout wrote its px into. One that writes none keeps
  the px. [Was: the px kept while the text was the same.] }
procedure TAdvChartEdgesMiscOracleTest.TestARiverMergedTheSameGapResolvesItAgain;
var
  river, st, op: TJSONObject;
  steps: TJSONArray;
  chart: TEmProbe;
  bmp: TBGRABitmap;
  k, w, h: Integer;
  lay: TTyThemeRiverLayout;
  report: string;
begin
  river := Section('river');
  steps := river.Arrays['steps'];
  chart := NewChart(600, 400);
  chart.Option := river.Objects['option'].AsJSON;
  w := 600;
  h := 400;
  report := '';
  for k := 0 to steps.Count - 1 do
  begin
    st := steps.Objects[k];
    if st.Find('op') is TJSONObject then
    begin
      op := st.Objects['op'];
      if op.Find('resize') <> nil then
      begin
        w := op.Arrays['resize'].Integers[0];
        h := op.Arrays['resize'].Integers[1];
        chart.SetBounds(0, 0, w, h);
      end
      else
        AssertTrue('merged', chart.MergeOption(op.Objects['merge'].AsJSON));
    end;
    bmp := TBGRABitmap.Create(w, h, BGRA(255, 255, 255, 255));
    try
      chart.Render(bmp.Canvas, Rect(0, 0, w, h), 96);
    finally
      bmp.Free;
    end;
    lay := chart.RiverLayoutOf(0);
    if not (SameBits(lay.Rect.H, FromHex(st.Strings['rectH']))
      and SameBits(lay.Gap[0], FromHex(st.Arrays['gap'].Strings[0]))
      and SameBits(lay.Gap[1], FromHex(st.Arrays['gap'].Strings[1]))) then
      report := report + LineEnding + Format('%s: %g %g over %g here, %g %g over %g upstream',
        [st.Strings['what'], lay.Gap[0], lay.Gap[1], lay.Rect.H,
         FromHex(st.Arrays['gap'].Strings[0]), FromHex(st.Arrays['gap'].Strings[1]),
         FromHex(st.Strings['rectH'])]);
  end;
  AssertEquals('the river''s gaps step by step', '', report);
end;

{ the linear ramp's colour at (AX, AY): the stops over (X1, Y1)-(X2, Y2) }
function RampAt(AStops: TJSONArray; X1, Y1, X2, Y2, AX, AY: Double): TBGRAPixel;
var
  dx, dy, t, len2, u: Double;
  k: Integer;
  c0, c1: TTyChartColor;
  o0, o1: Double;
begin
  dx := X2 - X1;
  dy := Y2 - Y1;
  len2 := dx * dx + dy * dy;
  if len2 = 0 then t := 0
  else t := ((AX - X1) * dx + (AY - Y1) * dy) / len2;
  if t < 0 then t := 0;
  if t > 1 then t := 1;
  k := 0;
  while (k < AStops.Count - 2) and (t > AStops.Arrays[k + 1].Floats[0]) do Inc(k);
  o0 := AStops.Arrays[k].Floats[0];
  o1 := AStops.Arrays[k + 1].Floats[0];
  TyTryParseChartColor(AStops.Arrays[k].Strings[1], c0);
  TyTryParseChartColor(AStops.Arrays[k + 1].Strings[1], c1);
  if o1 > o0 then u := (t - o0) / (o1 - o0) else u := 0;
  if u < 0 then u := 0;
  if u > 1 then u := 1;
  Result.red := Round(((c0 shr 16) and $FF) * (1 - u) + ((c1 shr 16) and $FF) * u);
  Result.green := Round(((c0 shr 8) and $FF) * (1 - u) + ((c1 shr 8) and $FF) * u);
  Result.blue := Round((c0 and $FF) * (1 - u) + (c1 and $FF) * u);
  Result.alpha := 255;
end;

function Within(AGot, A, B: Integer): Boolean;
begin
  Result := (AGot >= Min(A, B) - 12) and (AGot <= Max(A, B) + 12);
end;

{ A GRADIENT WRITTEN AS A SPLIT AREA'S COLOUR RAMPS AS THE CANVAS RAMPS IT:
  over each band's own rect on a cartesian and a single axis (a Rect per
  band), over the merged bands' box on a polar axis (mergePath) -- the
  oracle's pixels, which only that area covers, against the ramp across
  each pixel, 12 levels either side. [Was: every band in the first stop.] }
procedure TAdvChartEdgesMiscOracleTest.TestASplitAreaGradientRampsAsUpstreams;
var
  cases, els, samples: TJSONArray;
  cs, e: TJSONObject;
  c, k, q, px, py, bad, n: Integer;
  chart: TEmProbe;
  bmp: TBGRABitmap;
  gx1, gy1, gx2, gy2: Double;
  want, lo, hi, got: TBGRAPixel;
  report: string;
begin
  cases := TJSONObject(FRoot).Arrays['splitArea'];
  bad := 0;
  n := 0;
  report := '';
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    chart := NewChart(600, 400);
    chart.Option := '{"animation":false,' + Copy(cs.Objects['option'].AsJSON, 2, MaxInt);
    bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
    try
      chart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
      els := cs.Arrays['elements'];
      for k := 0 to els.Count - 1 do
      begin
        e := els.Objects[k];
        gx1 := FromHex(e.Arrays['gradient'].Strings[0]);
        gy1 := FromHex(e.Arrays['gradient'].Strings[1]);
        gx2 := FromHex(e.Arrays['gradient'].Strings[2]);
        gy2 := FromHex(e.Arrays['gradient'].Strings[3]);
        samples := e.Arrays['samples'];
        for q := 0 to samples.Count - 1 do
        begin
          px := samples.Arrays[q].Integers[0];
          py := samples.Arrays[q].Integers[1];
          want := RampAt(e.Arrays['stops'], gx1, gy1, gx2, gy2, px + 0.5, py + 0.5);
          lo := RampAt(e.Arrays['stops'], gx1, gy1, gx2, gy2, px, py);
          hi := RampAt(e.Arrays['stops'], gx1, gy1, gx2, gy2, px + 1, py + 1);
          got := bmp.GetPixel(px, py);
          Inc(n);
          if not (Within(got.red, lo.red, hi.red) and Within(got.green, lo.green, hi.green)
            and Within(got.blue, lo.blue, hi.blue)) then
          begin
            Inc(bad);
            if Length(report) < 3000 then
              report := report + LineEnding + Format('%s element %d at %d,%d: %d %d %d upstream, %d %d %d here',
                [cs.Strings['id'], k, px, py, want.red, want.green, want.blue, got.red, got.green, got.blue]);
          end;
        end;
      end;
    finally
      bmp.Free;
    end;
    chart.Free;
  end;
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(n) + ' pixels off the ramp:' + report, 0, bad);
  AssertTrue(Format('enough sampled (%d)', [n]), n >= 200);
end;

initialization
  RegisterTest(TAdvChartEdgesMiscOracleTest);
end.
