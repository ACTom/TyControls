unit test.advchart.backwardcompat;
{$mode objfpc}{$H+}
{ THE OLD OPTION SPELLINGS, rewritten as ECharts 6.1 rewrites them [R3-A]:
  backwardCompat (compatStyle's normal / emphasis, ec2's itemStyle.normal.
  label, a label's textStyle, the series' and components' old keys,
  dataRange), the radar's ec2 polar and the candlestick's 'k', over every
  option the manager preprocesses -- the base, the frames, a query unit, a
  merge -- and never the media default.

  tools/advchart-oracle/backward-compat.js runs each case three times on
  the real dist -- in the old spelling, in today's, and without what the
  old one says -- and guards that the first two draw the same display list
  at every step and that the first draws something the third does not. Here
  the same three run on the port: the legacy option tree after every step
  is upstream's raw merge layer (GetOptionJson, structurally), the legacy
  bitmaps are the modern ones pixel for pixel, and some legacy bitmap
  differs from the plain one.

  TAdvChartBackwardCompatTest holds the rewrite itself where no picture can
  show it -- the copies of one object in two places, where upstream throws,
  the media default -- and the diagnostics: an old spelling where upstream
  reads it is no unknown option, the same key anywhere else still is. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Option,
     tyControls.AdvanceChart.Geo, tyControls.AdvanceChart.Complete,
     tyControls.AdvanceChart.Diagnose, tyControls.AdvanceChart.BackwardCompat,
     tyControls.AdvanceChart.OptionMerge,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;

type
  TBcProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
  end;

  TBcBitmaps = array of TBGRABitmap;

  TAdvChartBackwardCompatOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot: TJSONObject;
    FW, FH: Integer;
    FBad, FCompared: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    function NewChart: TBcProbe;
    { the steps on a chart of their own: a bitmap after each (the caller
      frees them); the option tree held to ATrees[k] after step k when
      ATrees is given }
    function RunSteps(ASteps: TJSONArray; ATrees: TJSONArray): TBcBitmaps;
    procedure FreeAll(var A: TBcBitmaps);
    function Diff(A, B: TBGRABitmap; out AWhere: string): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheTreesAsUpstream;
    procedure TestTheOldSpellingsDrawAsTheNew;
    procedure TestTheOldSpellingsDrawSomething;
  end;

  TAdvChartBackwardCompatTest = class(TTestCase)
  private
    function Compat(const AText: string): TJSONObject;
    function Unknown(const AText: string): string;
  published
    procedure TestAnEmphasisOnlyStyleStandsInTwoPlaces;
    procedure TestTheControlStyleKeepsItsOwnKeys;
    procedure TestEc2StylesMergeIntoTheOnesWritten;
    procedure TestWhereUpstreamThrowsTheRestGoesOn;
    procedure TestTheSeriesKeysByType;
    procedure TestPolarsWithAnIndicatorAreRadars;
    procedure TestEveryOptionTheManagerPreprocesses;
    procedure TestTheLegacyKeysAreNoUnknownOptions;
    procedure TestTheSameKeysElsewhereStillAre;
  end;

implementation

{ ==================== the probe ==================== }

function TBcProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Exit(Measurer);
  Result := inherited NewTextMeasurer(APPI);
end;

procedure TBcProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TBcProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-backward-compat.json';
end;

function SameNum(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := A = B;
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
    Result := SameNum(A.AsFloat, B.AsFloat);
    if not Result then AWhere := APath + ' ' + A.AsJSON + ' here, ' + B.AsJSON + ' upstream';
    Exit;
  end;
  if A.JSONType <> B.JSONType then
  begin
    AWhere := APath + ' ' + A.AsJSON + ' here, ' + B.AsJSON + ' upstream';
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
          AWhere := APath + Format(' %d items here, %d upstream', [A.Count, B.Count]);
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
  if not Result and (AWhere = APath) then AWhere := APath + ' ' + A.AsJSON + ' here, ' + B.AsJSON + ' upstream';
end;

{ ==================== the oracle ==================== }

procedure TAdvChartBackwardCompatOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := TJSONObject(GetJSON(sl.Text));
  finally
    sl.Free;
  end;
  FW := FRoot.Integers['W'];
  FH := FRoot.Integers['H'];
  AssertTrue('the map', TyChartRegisterMap('sq', FRoot.Objects['maps'].Strings['sq']));
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartBackwardCompatOracleTest.TearDown;
begin
  TyChartUnregisterMap('sq');
  FRoot.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartBackwardCompatOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

function TAdvChartBackwardCompatOracleTest.NewChart: TBcProbe;
var m: TJSONObject;
begin
  Result := TBcProbe.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  m := FRoot.Objects['measure'];
  Result.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(m.Arrays['ratio'],
    m.Integers['firstCode']));
  Result.AnimationMode := camOff;
  Result.SetBounds(0, 0, FW, FH);
end;

function TAdvChartBackwardCompatOracleTest.RunSteps(ASteps: TJSONArray;
  ATrees: TJSONArray): TBcBitmaps;
var
  chart: TBcProbe;
  st: TJSONObject;
  k: Integer;
  kind, where: string;
  got: TJSONData;
begin
  Result := nil;
  chart := NewChart;
  try
    SetLength(Result, ASteps.Count);
    for k := 0 to ASteps.Count - 1 do
    begin
      st := ASteps.Objects[k];
      kind := st.Strings['kind'];
      if kind = 'set' then
      begin
        if st.Find('opts') is TJSONObject then
          chart.SetOption(st.Objects['option'].AsJSON, st.Objects['opts'].AsJSON)
        else
          chart.SetOption(st.Objects['option'].AsJSON);
      end
      else if kind = 'action' then
        chart.DispatchAction(st.Objects['payload'].AsJSON)
      else if kind = 'hover' then
        chart.Move(st.Integers['x'], st.Integers['y'])
      else
        Fail(FName + ': a step of no kind ' + kind);
      Result[k] := TBGRABitmap.Create(FW, FH, BGRA(255, 255, 255, 255));
      chart.Render(Result[k].Canvas, Classes.Rect(0, 0, FW, FH), 96);
      if ATrees <> nil then
      begin
        Inc(FCompared);
        got := GetJSON(chart.GetOptionJson);
        try
          if not SameJson(got, ATrees.Items[k], Format('step %d: tree', [k]), where) then Miss(where);
        finally
          got.Free;
        end;
      end;
    end;
  finally
    chart.Free;
  end;
end;

procedure TAdvChartBackwardCompatOracleTest.FreeAll(var A: TBcBitmaps);
var i: Integer;
begin
  for i := 0 to High(A) do A[i].Free;
  A := nil;
end;

function TAdvChartBackwardCompatOracleTest.Diff(A, B: TBGRABitmap; out AWhere: string): Integer;
var
  x, y: Integer;
  pa, pb: PBGRAPixel;
begin
  Result := 0;
  AWhere := '';
  for y := 0 to A.Height - 1 do
  begin
    pa := A.ScanLine[y];
    pb := B.ScanLine[y];
    for x := 0 to A.Width - 1 do
    begin
      if (pa^.red <> pb^.red) or (pa^.green <> pb^.green) or (pa^.blue <> pb^.blue)
        or (pa^.alpha <> pb^.alpha) then
      begin
        if Result = 0 then AWhere := Format('(%d, %d)', [x, y]);
        Inc(Result);
      end;
      Inc(pa);
      Inc(pb);
    end;
  end;
end;

procedure TAdvChartBackwardCompatOracleTest.TestTheTreesAsUpstream;
var
  cases: TJSONArray;
  c: TJSONObject;
  i: Integer;
  bm: TBcBitmaps;
begin
  cases := FRoot.Arrays['cases'];
  AssertTrue('cases', cases.Count >= 25);
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    FName := c.Strings['id'];
    bm := RunSteps(c.Arrays['legacy'], c.Arrays['trees']);
    FreeAll(bm);
  end;
  AssertTrue(Format('%d of %d trees differ from upstream:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue('trees compared', FCompared >= 40);
end;

procedure TAdvChartBackwardCompatOracleTest.TestTheOldSpellingsDrawAsTheNew;
var
  cases: TJSONArray;
  c: TJSONObject;
  i, k, n: Integer;
  bl, bm: TBcBitmaps;
  where: string;
begin
  cases := FRoot.Arrays['cases'];
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    FName := c.Strings['id'];
    bl := RunSteps(c.Arrays['legacy'], nil);
    bm := RunSteps(c.Arrays['modern'], nil);
    try
      for k := 0 to High(bl) do
      begin
        Inc(FCompared);
        n := Diff(bl[k], bm[k], where);
        if n > 0 then Miss(Format('step %d: %d pixels differ from the modern spelling, the first at %s',
          [k, n, where]));
      end;
    finally
      FreeAll(bl);
      FreeAll(bm);
    end;
  end;
  AssertTrue(Format('%d of %d steps draw otherwise than the modern spelling:%s',
    [FBad, FCompared, FReport]), FBad = 0);
end;

procedure TAdvChartBackwardCompatOracleTest.TestTheOldSpellingsDrawSomething;
var
  cases: TJSONArray;
  c: TJSONObject;
  i, k, n, cmp: Integer;
  bl, bp: TBcBitmaps;
  where: string;
  any: Boolean;
begin
  cases := FRoot.Arrays['cases'];
  cmp := 0;
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    if not (c.Find('plain') is TJSONArray) then Continue;
    FName := c.Strings['id'];
    Inc(cmp);
    bl := RunSteps(c.Arrays['legacy'], nil);
    bp := RunSteps(c.Arrays['plain'], nil);
    try
      any := False;
      for k := 0 to High(bl) do
      begin
        n := Diff(bl[k], bp[k], where);
        if n > 0 then any := True;
      end;
      if not any then Miss('the old spelling draws as the chart without it at every step');
    finally
      FreeAll(bl);
      FreeAll(bp);
    end;
  end;
  AssertTrue(Format('%d of %d cases draw nothing of their old spelling:%s', [FBad, cmp, FReport]), FBad = 0);
  AssertTrue('cases with a plain run', cmp >= 20);
end;

{ ==================== the rewrite itself ==================== }

function TAdvChartBackwardCompatTest.Compat(const AText: string): TJSONObject;
begin
  Result := TJSONObject(GetJSON(AText));
  TyLegacyPreprocess(Result);
end;

{ every unknown option the diagnostics report, as 'path;path;' }
function TAdvChartBackwardCompatTest.Unknown(const AText: string): string;
var
  d: TTyOptDiagArray;
  i: Integer;
begin
  Result := '';
  d := TyOptDiagnose(AText);
  for i := 0 to High(d) do
    if d[i].Kind = odkUnknownOption then Result := Result + d[i].Path + ';';
end;

procedure TAdvChartBackwardCompatTest.TestAnEmphasisOnlyStyleStandsInTwoPlaces;
var o, s: TJSONObject;
begin
  o := Compat('{"series": [{"type": "scatter", "label": {"emphasis": {"show": true,'
    + ' "textStyle": {"color": "#f00"}}}, "itemStyle": {"emphasis": {"color": "#0f0",'
    + ' "focus": "self"}}}]}');
  try
    s := o.Arrays['series'].Objects[0];
    AssertEquals('the emphasis label', '#f00', s.Objects['emphasis'].Objects['label'].Strings['color']);
    AssertEquals('the copy left in the label takes the text style too', '#f00',
      s.Objects['label'].Objects['emphasis'].Strings['color']);
    AssertEquals('the item style''s emphasis, in both places', '#0f0',
      s.Objects['itemStyle'].Objects['emphasis'].Strings['color']);
    AssertEquals('its focus lifted', 'self', s.Objects['emphasis'].Strings['focus']);
  finally
    o.Free;
  end;
  { the timeline preprocessor's move of the label out of an itemStyle.emphasis
    is done to the other copy as well }
  o := Compat('{"timeline": {"data": [1], "itemStyle": {"emphasis": {"color": "#f00",'
    + ' "label": {"color": "#00f"}}}}}');
  try
    s := o.Objects['timeline'];
    AssertTrue('the copy loses the label', s.Objects['emphasis'].Objects['itemStyle'].Find('label') = nil);
    AssertTrue('the original keeps it until the timeline preprocessor',
      s.Objects['itemStyle'].Objects['emphasis'].Find('label') <> nil);
  finally
    o.Free;
  end;
end;

procedure TAdvChartBackwardCompatTest.TestTheControlStyleKeepsItsOwnKeys;
var o, cs: TJSONObject;
begin
  o := Compat('{"timeline": {"data": [1], "controlStyle": {"normal": {"color": "#111",'
    + ' "showPlayBtn": true, "normal": 7}, "emphasis": {"color": "#222"}, "showPlayBtn": false,'
    + ' "color": null}}}');
  try
    cs := o.Objects['timeline'].Objects['controlStyle'];
    { nulled, then filled like any other null key: the normal's own `normal`
      comes in (upstream: controlStyle.normal is 7) }
    AssertEquals('normal nulled, then the normal''s own', 7, cs.Integers['normal']);
    AssertTrue('emphasis is null', cs.Find('emphasis').JSONType = jtNull);
    AssertEquals('a key it holds as null takes the normal''s', '#111', cs.Strings['color']);
    AssertFalse('a key it has keeps its own', cs.Booleans['showPlayBtn']);
    AssertEquals('the emphasis moved', '#222', o.Objects['timeline'].Objects['emphasis']
      .Objects['controlStyle'].Strings['color']);
  finally
    o.Free;
  end;
end;

procedure TAdvChartBackwardCompatTest.TestEc2StylesMergeIntoTheOnesWritten;
var o, s: TJSONObject;
begin
  o := Compat('{"series": [{"type": "line", "lineStyle": {"normal": {"width": 1, "type": "dashed"}},'
    + ' "itemStyle": {"normal": {"color": "#123", "lineStyle": {"width": 5, "color": "#f00",'
    + ' "shadow": {"a": 1}}, "nodeStyle": {"x": 1}}}}]}');
  try
    s := o.Arrays['series'].Objects[0];
    AssertEquals('the written width stays (merge, no overwrite)', 1, s.Objects['lineStyle'].Integers['width']);
    AssertEquals('the ec2 colour fills in', '#f00', s.Objects['lineStyle'].Strings['color']);
    AssertEquals('the written type', 'dashed', s.Objects['lineStyle'].Strings['type']);
    AssertTrue('null left in the item style', s.Objects['itemStyle'].Find('lineStyle').JSONType = jtNull);
    AssertEquals('the item style is its normal', '#123', s.Objects['itemStyle'].Strings['color']);
    AssertTrue('ec2''s nodeStyle moves, and nothing rewrites it further',
      s.Objects['nodeStyle'].Objects['normal'].Integers['x'] = 1);
  finally
    o.Free;
  end;
end;

procedure TAdvChartBackwardCompatTest.TestWhereUpstreamThrowsTheRestGoesOn;
var o, s: TJSONObject;
begin
  { a truthy primitive where an object is set into: upstream throws in strict
    mode; here the step is skipped and the rest is rewritten }
  o := Compat('{"series": [{"type": "pie", "emphasis": true, "hoverAnimation": false,'
    + ' "itemStyle": {"normal": {"color": "#f00", "label": {"show": true}}}, "label": 5,'
    + ' "clockWise": false}], "grid": [5, {"x": 3}], "radar": [null, {"name": "n"}],'
    + ' "timeline": [null], "toolbox": null, "polar": [null]}');
  try
    s := o.Arrays['series'].Objects[0];
    AssertTrue('emphasis stays as written', s.Booleans['emphasis']);
    AssertEquals('the label stays 5', 5, s.Integers['label']);
    AssertTrue('the ec2 label not moved (upstream throws there)',
      s.Objects['itemStyle'].Objects['label'].Booleans['show']);
    AssertFalse('clockwise still rewritten', s.Booleans['clockwise']);
    AssertEquals('the second grid''s x is its left', 3, o.Arrays['grid'].Objects[1].Integers['left']);
    AssertEquals('the second radar''s name is its axisName', 'n', o.Arrays['radar'].Objects[1].Strings['axisName']);
    AssertEquals('a null polar kept', 1, o.Arrays['polar'].Count);
  finally
    o.Free;
  end;
end;

procedure TAdvChartBackwardCompatTest.TestTheSeriesKeysByType;
var o: TJSONObject;
begin
  o := Compat('{"series": [{"type": "bar", "clipOverflow": false, "clockWise": true,'
    + ' "hoverOffset": 3, "focusNodeAdjacency": true, "mapType": "m", "x": 5, "left": 9},'
    + ' {"type": "line", "clipOverflow": false},'
    + ' {"type": "gauge", "pointer": {"color": "#f00"}, "hoverOffset": 4},'
    + ' {"type": "sankey", "focusNodeAdjacency": false, "emphasis": {"focus": "self"}},'
    + ' {"type": "sunburst", "highlightPolicy": "descendant", "data": [{"downplay": 1,'
    + ' "children": [{"downplay": 2, "blur": 3}]}]},'
    + ' {"type": "map", "mapType": "a", "map": "b", "mapLocation": {"x": 1, "y": null, "left": 4}, "y": 7},'
    + ' {"type": "pie", "data": [{"value": 1, "alignTo": "edge", "margin": 3, "label": {"alignTo": "edge",'
    + ' "margin": 4}}]},'
    + ' {"type": "graph", "data": [{"name": "a", "label": {"normal": {"show": true}}}],'
    + ' "nodes": [{"name": "b", "label": {"normal": {"show": true}}}]}],'
    + ' "dataRange": {"x": "right"}, "visualMap": {"min": 3}}');
  try
    with o.Arrays['series'].Objects[0] do
    begin
      AssertTrue('a bar has no clip', Find('clip') = nil);
      AssertTrue('a bar has no clockwise', Find('clockwise') = nil);
      AssertTrue('a bar has no emphasis from hoverOffset or focusNodeAdjacency', Find('emphasis') = nil);
      AssertTrue('a bar has no map', Find('map') = nil);
      AssertEquals('x does not overwrite left', 9, Integers['left']);
    end;
    AssertFalse('a line''s clip', o.Arrays['series'].Objects[1].Booleans['clip']);
    with o.Arrays['series'].Objects[2] do
    begin
      AssertTrue('a gauge''s pointer colour is never moved', Find('itemStyle') = nil);
      AssertTrue('a gauge''s hoverOffset writes the scale size null',
        Objects['emphasis'].Find('scaleSize').JSONType = jtNull);
    end;
    AssertEquals('a written focus stays', 'self', o.Arrays['series'].Objects[3].Objects['emphasis'].Strings['focus']);
    with o.Arrays['series'].Objects[4] do
    begin
      AssertEquals('highlightPolicy', 'descendant', Objects['emphasis'].Strings['focus']);
      AssertEquals('a node''s downplay', 1, Arrays['data'].Objects[0].Integers['blur']);
      AssertEquals('a blur written stays', 3, Arrays['data'].Objects[0].Arrays['children'].Objects[0].Integers['blur']);
    end;
    with o.Arrays['series'].Objects[5] do
    begin
      AssertEquals('a map written stays', 'b', Strings['map']);
      AssertEquals('mapLocation fills what is missing', 1, Integers['x']);
      AssertEquals('a key written stays (defaults)', 7, Integers['y']);
      AssertEquals('x as left: the location''s left was there first', 4, Integers['left']);
      AssertEquals('y as top', 7, Integers['top']);
    end;
    with o.Arrays['series'].Objects[6].Arrays['data'].Objects[0] do
    begin
      { compatPieLabel is called on the data item itself, not on its label }
      AssertEquals('the item''s own margin', 3, Integers['edgeDistance']);
      AssertTrue('its label untouched', Objects['label'].Find('edgeDistance') = nil);
    end;
    with o.Arrays['series'].Objects[7] do
    begin
      AssertTrue('a graph''s data rewritten', Arrays['data'].Objects[0].Objects['label'].Booleans['show']);
      AssertTrue('its nodes not, when it has data',
        Arrays['nodes'].Objects[0].Objects['label'].Find('normal') <> nil);
    end;
    AssertEquals('dataRange replaces the visualMap', 'right', o.Objects['visualMap'].Strings['left']);
    AssertTrue('the visualMap written is gone', o.Objects['visualMap'].Find('min') = nil);
  finally
    o.Free;
  end;
end;

procedure TAdvChartBackwardCompatTest.TestPolarsWithAnIndicatorAreRadars;
var o: TJSONObject;
begin
  o := Compat('{"polar": {"indicator": [{"name": "a"}], "type": "circle", "shape": ""},'
    + ' "radar": {"name": "keep"}, "series": [{"type": "radar", "polarIndex": 1},'
    + ' {"type": "radar", "polarIndex": 0}, {"type": "k"}]}');
  try
    AssertEquals('the polar list is left empty', 0, o.Arrays['polar'].Count);
    AssertEquals('the radar wrapped and the polar appended', 2, o.Arrays['radar'].Count);
    AssertEquals('the radar written first, its name moved by compatStyle before', 'keep',
      o.Arrays['radar'].Objects[0].Strings['axisName']);
    AssertEquals('type as the shape (a falsy shape)', 'circle', o.Arrays['radar'].Objects[1].Strings['shape']);
    AssertEquals('polarIndex as radarIndex', 1, o.Arrays['series'].Objects[0].Integers['radarIndex']);
    AssertTrue('polarIndex 0 is falsy', o.Arrays['series'].Objects[1].Find('radarIndex') = nil);
    AssertEquals('k', 'candlestick', o.Arrays['series'].Objects[2].Strings['type']);
  finally
    o.Free;
  end;
  { a polar without an indicator is kept, as a list }
  o := Compat('{"polar": {"radius": 3}}');
  try
    AssertEquals('kept', 3, o.Arrays['polar'].Objects[0].Integers['radius']);
    AssertTrue('no radar', o.Find('radar') = nil);
  finally
    o.Free;
  end;
end;

procedure TAdvChartBackwardCompatTest.TestEveryOptionTheManagerPreprocesses;
var
  opt: TTyChartOption;
  r: TJSONObject;
  rep: TTyMergeReport;
begin
  opt := TTyChartOption.Create;
  try
    AssertTrue(opt.SetOptionText('{"baseOption": {"series": [{"type": "bar",'
      + ' "itemStyle": {"normal": {"color": "#111"}}}], "timeline": {"data": [1, 2]}},'
      + ' "options": [{"series": [{"label": {"normal": {"show": true}}}]},'
      + ' {"series": [{"label": {"normal": {"show": false}}}]}],'
      + ' "media": [{"query": {"minWidth": 1}, "option": {"title": {"x": 5}}},'
      + ' {"option": {"legend": {"x": 6}}}]}'));
    r := TJSONObject(opt.Root);
    AssertEquals('the base', '#111', r.Arrays['series'].Objects[0].Objects['itemStyle'].Strings['color']);
    AssertTrue('the first frame, merged', r.Arrays['series'].Objects[0].Objects['label'].Booleans['show']);
    AssertTrue('the second frame preprocessed too',
      opt.Media.Frame(1).Arrays['series'].Objects[0].Objects['label'].Find('normal') = nil);
    AssertEquals('a query unit', 5, opt.Media.UnitOption(0).Objects['title'].Integers['left']);
    { a merge }
    AssertTrue(opt.MergeOptionText('{"series": [{"itemStyle": {"normal": {"color": "#222"}}}]}', nil, rep));
    r := TJSONObject(opt.Root);
    AssertEquals('a merge', '#222', r.Arrays['series'].Objects[0].Objects['itemStyle'].Strings['color']);
  finally
    opt.Free;
  end;
end;

procedure TAdvChartBackwardCompatTest.TestTheLegacyKeysAreNoUnknownOptions;
var s: string;
begin
  s := Unknown('{"series": [{"type": "pie", "clockWise": false, "hoverOffset": 3,'
    + ' "hoverAnimation": false, "x": 1, "label": {"textStyle": {"fontSize": 3}, "alignTo": "edge",'
    + ' "margin": 4, "emphasis": {"show": true}}, "itemStyle": {"emphasis": {"color": "#f00"}},'
    + ' "data": [{"value": 1, "label": {"emphasis": {"show": true}}}]},'
    + ' {"type": "bar", "data": [1], "itemStyle": {"normal": {"barBorderRadius": 3,'
    + ' "label": {"show": true}}}, "emphasis": {"itemStyle": {"barBorderWidth": 2}},'
    + ' "markPoint": {"data": [{"type": "max", "label": {"textStyle": {"color": "#f00"}}}]}},'
    + ' {"type": "graph", "focusNodeAdjacency": true, "nodes": [{"name": "a",'
    + ' "label": {"emphasis": {"show": true}}}], "links": []},'
    + ' {"type": "sunburst", "highlightPolicy": "ancestor", "downplay": {},'
    + ' "data": [{"name": "a", "value": 1, "children": [{"name": "b", "value": 1, "downplay": {}}]}]},'
    + ' {"type": "map", "mapType": "x", "mapLocation": {"x": 1}},'
    + ' {"type": "line", "clipOverflow": true, "data": [1]}, {"type": "radar", "polarIndex": 1,'
    + ' "data": []}, {"type": "gauge", "title": {"textStyle": {"color": "#f00"}}}],'
    + ' "xAxis": {"axisLabel": {"textStyle": {"color": "#f00"}}}, "yAxis": {},'
    + ' "grid": {"x": 3, "y2": 4}, "legend": {"x": "left"}, "title": {"y": 3},'
    + ' "dataRange": {"min": 0, "max": 1}, "timeline": {"data": [1], "x": 5,'
    + ' "label": {"emphasis": {"color": "#f00"}}, "controlStyle": {"normal": {"color": "#f00"}}},'
    + ' "toolbox": {"feature": {"saveAsImage": {"iconStyle": {"emphasis": {"color": "#f00"}}}}},'
    + ' "calendar": {"dayLabel": {"textStyle": {"color": "#f00"}}}, "radar": {"indicator": [],'
    + ' "name": {"textStyle": {"color": "#f00"}}}, "tooltip": {"axisPointer": {"label":'
    + ' {"textStyle": {"color": "#f00"}}}}}');
  AssertEquals('nothing unknown', '', s);
end;

procedure TAdvChartBackwardCompatTest.TestTheSameKeysElsewhereStillAre;
var s: string;
begin
  s := Unknown('{"series": [{"type": "bar", "data": [1], "clockWise": false,'
    + ' "focusNodeAdjacency": true, "mapType": "x", "polarIndex": 1, "highlightPolicy": "a",'
    + ' "label": {"margin": 3}},'
    + ' {"type": "pie", "data": [1], "label": {"margin": 3}, "barBorderRadius": 2},'
    + ' {"type": "treemap", "data": [], "levels": [{"label": {"textStyle": {}}}]},'
    + ' {"type": "graph", "data": [{"name": "a"}], "links": [],'
    + ' "categories": [{"name": "c", "label": {"textStyle": {}, "emphasis": {}}}]}],'
    + ' "xAxis": {"textStyle": {}}, "yAxis": {}, "tooltip": {"x": 3},'
    + ' "axisPointer": [{}, {"label": {"textStyle": {}}}], "legend": {"textStyle": {"normal": 1}}}');
  AssertTrue('a bar''s clockWise: ' + s, Pos('series[0].clockWise;', s) > 0);
  AssertTrue('a bar''s focusNodeAdjacency', Pos('series[0].focusNodeAdjacency;', s) > 0);
  AssertTrue('a bar''s mapType', Pos('series[0].mapType;', s) > 0);
  AssertTrue('a bar''s highlightPolicy', Pos('series[0].highlightPolicy;', s) > 0);
  AssertTrue('a bar label''s margin', Pos('series[0].label.margin;', s) > 0);
  AssertTrue('a pie label''s margin without alignTo edge', Pos('series[1].label.margin;', s) > 0);
  AssertTrue('a pie''s barBorderRadius', Pos('series[1].barBorderRadius;', s) > 0);
  AssertTrue('a treemap level label''s textStyle (removeEC3NormalStatus only)',
    Pos('series[2].levels[0].label.textStyle;', s) > 0);
  AssertTrue('an axis'' own textStyle', Pos('xAxis.textStyle;', s) > 0);
  AssertTrue('a tooltip''s x', Pos('tooltip.x;', s) > 0);
  AssertTrue('the second axisPointer''s label textStyle (toObj takes the first)',
    Pos('axisPointer[1].label.textStyle;', s) > 0);
  AssertTrue('a legend textStyle''s normal', Pos('legend.textStyle.normal;', s) > 0);
  AssertTrue('a graph category label''s textStyle (removeEC3NormalStatus only)',
    Pos('series[3].categories[0].label.textStyle;', s) > 0);
  AssertTrue('while its emphasis is the ec3 one', Pos('series[3].categories[0].label.emphasis;', s) = 0);
end;

initialization
  RegisterTest(TAdvChartBackwardCompatOracleTest);
  RegisterTest(TAdvChartBackwardCompatTest);
end.
