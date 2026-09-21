unit test.advchart.graphcartesian;
{$mode objfpc}{$H+}
{ A graph on a cartesian grid, held to upstream's own output.

  tools/advchart-oracle/graph-cartesian.js runs the real ECharts 6.1 build over
  the cases in tests/fixtures/advchart-graph-cartesian.json and records, for
  every graph series upstream kept, where each node landed IN PIXELS -- on
  axes upstream's layout is dataToPoint and nothing maps it again -- what each
  node and each link is called, how each link bends, and the plot rectangle.
  Every case pins the grid in pixels, so the rectangle is the same here and
  there whatever font an axis label is drawn in, and a position that differs
  is a position that differs.

  The rest are the rules the oracle cannot name. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Data, tyControls.AdvChart.Builder,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Handlers,
     tyControls.AdvChart.Color, tyControls.AdvChart.Labels,
     tyControls.AdvChart.LabelOpt, tyControls.AdvChart.Tooltip,
     tyControls.AdvChart.Graph,
     tyControls.AdvanceChart, test.advancechart;
type
  { The protected doors this suite needs: what a tooltip would say about a
    datum, and which spec it would say it under. }
  TCartProbe = class(TChartProbe)
  public
    function ParamsFor(const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
    function ContentFor(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
    function SpecFor(const ADatum: TTyChartDatumRef): TTyTooltipSpec;
  end;

  TAdvChartGraphCartesianOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCartProbe;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(AW, AH: Integer);
  published
    procedure TestEveryCaseMatchesUpstream;
  end;

  TAdvChartGraphCartesianTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCartProbe;
    FOpt: TTyChartOption;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(AW, AH: Integer);
  published
    procedure TestTheSolverPlacesByTheColumnsAndIgnoresTheLayout;
    procedure TestALinkIsNotTheNodeThatSharesItsRow;
    procedure TestTheItemNameFallsBackToTheFirstCategory;
    procedure TestALinksTooltipIsOneBareRowUnderTheSeriesSpec;
    procedure TestAGraphOnAxesIsDrawnAndItsLinksAnswerAsLinks;
  end;

implementation

const
  cGraphGrid = '{"animation":false,"tooltip":{},'
    + '"grid":{"left":60,"right":40,"top":40,"bottom":40},'
    + '"xAxis":{"type":"category","boundaryGap":false,'
    + '"data":["Mon","Tue","Wed","Thu"]},"yAxis":{"type":"value"},'
    + '"series":[{"type":"graph","coordinateSystem":"cartesian2d",'
    + '"lineStyle":{"color":"#2f4554"},'
    + '"data":[{"value":842,"tooltip":{"show":false}},1276,2288,393],'
    + '"links":[{"source":0,"target":1},{"source":1,"target":2,"value":7},'
    + '{"source":2,"target":3}]}]}';

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-graph-cartesian.json';
end;

function ColourOf(AData: TJSONData; out AColour: TTyChartColor): Boolean;
begin
  AColour := 0;
  Result := False;
  if (AData = nil) or (AData.JSONType <> jtString) then Exit;
  Result := TyTryParseChartColor(AData.AsString, AColour);
end;

function Near(AExpected, AActual: Double): Boolean;
begin
  if IsNan(AActual) or IsInfinite(AActual) then Exit(False);
  Result := Abs(AExpected - AActual) <= 1e-6 * Max(Double(1), Abs(AExpected));
end;

{ ==================== the probe ==================== }

function TCartProbe.ParamsFor(
  const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
begin
  Result := TooltipParams(ADatum);
end;

function TCartProbe.ContentFor(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
begin
  Result := TooltipContent(ADatum, TooltipSpecFor(ADatum));
end;

function TCartProbe.SpecFor(const ADatum: TTyChartDatumRef): TTyTooltipSpec;
begin
  Result := TooltipSpecFor(ADatum);
end;

{ ==================== the oracle ==================== }

procedure TAdvChartGraphCartesianOracleTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TCartProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
end;

procedure TAdvChartGraphCartesianOracleTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartGraphCartesianOracleTest.Draw(AW, AH: Integer);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(AW, AH, BGRA(255, 0, 255, 255));
  try
    FChart.SetBounds(0, 0, AW, AH);
    FChart.Render(bmp.Canvas, Rect(0, 0, AW, AH), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartGraphCartesianOracleTest.TestEveryCaseMatchesUpstream;
var
  sl: TStringList;
  root, d: TJSONData;
  cases, graphs, arr, area: TJSONArray;
  cs, g, it, sopt: TJSONObject;
  c, gi, i, compared, bad, si: Integer;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  fills: TTyChartColorArray;
  ink: TTyGraphInk;
  spec: TTyGraphSpec;
  p: TTyChartCallbackParams;
  plot: TTyRectF;
  want: TTyChartColor;
  report, bend: string;
  seen: array of Boolean;
  arrows, ends, strokeWritten: Boolean;

  procedure Miss(const AWhat: string);
  begin
    Inc(bad);
    if bad <= 14 then
      report := report + LineEnding + '  ' + cs.Strings['name'] + ': ' + AWhat;
  end;

  function SeriesOpt(AIndex: Integer): TJSONObject;
  var s: TJSONData;
  begin
    Result := nil;
    s := cs.Objects['option'].Find('series');
    if (s is TJSONArray) and (AIndex < TJSONArray(s).Count)
      and (TJSONArray(s).Items[AIndex] is TJSONObject) then
      Result := TJSONObject(TJSONArray(s).Items[AIndex]);
  end;

begin
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  root := nil;
  try
    sl.LoadFromFile(FixturePath);
    root := GetJSON(sl.Text);
    cases := TJSONObject(root).Arrays['cases'];
    AssertTrue('the fixture carries its cases', cases.Count >= 20);
    compared := 0;
    bad := 0;
    report := '';
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      FChart.Option := cs.Objects['option'].AsJSON;
      AssertEquals(cs.Strings['name'] + ' parses', '', FChart.OptionError);
      Draw(cs.Integers['width'], cs.Integers['height']);
      graphs := cs.Arrays['graphs'];

      { A GRAPH UPSTREAM FILTERED AWAY is not in the fixture at all, so the
        port must not lay it out either. }
      d := cs.Objects['option'].Find('series');
      if d is TJSONArray then
      begin
        SetLength(seen, TJSONArray(d).Count);
        for i := 0 to High(seen) do seen[i] := False;
        for gi := 0 to graphs.Count - 1 do
          if graphs.Objects[gi].Integers['index'] <= High(seen) then
            seen[graphs.Objects[gi].Integers['index']] := True;
        for i := 0 to High(seen) do
        begin
          sopt := SeriesOpt(i);
          if (sopt = nil) or (sopt.Get('type', '') <> 'graph') then Continue;
          Inc(compared);
          if FChart.GraphLayout(i, nodes, edges, fills) <> seen[i] then
            Miss(Format('series %d is laid out %s upstream',
              [i, BoolToStr(seen[i], 'as', 'not')]));
        end;
      end;

      for gi := 0 to graphs.Count - 1 do
      begin
        g := graphs.Objects[gi];
        si := g.Integers['index'];
        if not (FChart.GraphLayout(si, nodes, edges, fills)
          and FChart.GraphInkOf(si, ink, spec)) then
        begin
          Miss(Format('series %d was not laid out', [si]));
          Continue;
        end;
        sopt := SeriesOpt(si);
        arrows := ((spec.EdgeSymbolFrom <> '') and (spec.EdgeSymbolFrom <> 'none'))
          or ((spec.EdgeSymbolTo <> '') and (spec.EdgeSymbolTo <> 'none'));
        strokeWritten := (sopt <> nil) and (sopt.Find('lineStyle') is TJSONObject)
          and (TJSONObject(sopt.Find('lineStyle')).Find('color') <> nil);

        { THE PLOT RECTANGLE, which every position below is made from. A
          miss here explains every miss after it. }
        area := g.Arrays['area'];
        plot := FChart.Build.Grid(0).PlotRect;
        Inc(compared);
        if not (Near(area.Floats[0], plot.Left) and Near(area.Floats[1], plot.Top)
          and Near(area.Floats[2], plot.Right - plot.Left)
          and Near(area.Floats[3], plot.Bottom - plot.Top)) then
          Miss(Format('the plot is (%g %g %g %g) upstream, (%g %g %g %g) here',
            [area.Floats[0], area.Floats[1], area.Floats[2], area.Floats[3],
             plot.Left, plot.Top, plot.Right - plot.Left, plot.Bottom - plot.Top]));

        arr := g.Arrays['nodes'];
        Inc(compared);
        if arr.Count <> Length(nodes) then
        begin
          Miss(Format('series %d keeps %d nodes, not %d',
            [si, arr.Count, Length(nodes)]));
          Continue;
        end;
        for i := 0 to arr.Count - 1 do
        begin
          it := arr.Objects[i];
          Inc(compared);
          if it.Integers['raw'] <> nodes[i].RawRow then
            Miss(Format('node %d is row %d upstream, %d here',
              [i, it.Integers['raw'], nodes[i].RawRow]));
          if not it.Booleans['placed'] then
          begin
            if not (IsNan(nodes[i].PX) and IsNan(nodes[i].PY)) then
              Miss(Format('node %d is nowhere upstream', [i]));
          end
          else if not (Near(it.Floats['px'], nodes[i].PX)
            and Near(it.Floats['py'], nodes[i].PY)) then
            Miss(Format('node %d wants (%.6g, %.6g) got (%.6g, %.6g)',
              [i, it.Floats['px'], it.Floats['py'], nodes[i].PX, nodes[i].PY]));
          { WHAT IT IS CALLED -- the name a label's b placeholder and the
            tooltip both say, category text included. }
          Inc(compared);
          p := FChart.ParamsFor(TyChartDatum(si, nodes[i].Row, nodes[i].RawRow));
          if p.Name <> it.Strings['name'] then
            Miss(Format('node %d is called "%s" upstream, "%s" here',
              [i, it.Strings['name'], p.Name]));
        end;

        arr := g.Arrays['edges'];
        Inc(compared);
        if arr.Count <> Length(edges) then
        begin
          Miss(Format('series %d keeps %d edges, not %d',
            [si, arr.Count, Length(edges)]));
          Continue;
        end;
        for i := 0 to arr.Count - 1 do
        begin
          it := arr.Objects[i];
          Inc(compared);
          if it.Integers['raw'] <> edges[i].RawIndex then
            Miss(Format('edge %d is edge %d upstream, %d here',
              [i, it.Integers['raw'], edges[i].RawIndex]));
          bend := it.Strings['bend'];
          if bend = 'curve' then
          begin
            if not edges[i].Curved or edges[i].Hidden then
              Miss(Format('edge %d is curved upstream, not here', [i]))
            else if not (Near(it.Floats['cpx'], edges[i].CPX)
              and Near(it.Floats['cpy'], edges[i].CPY)) then
              Miss(Format('edge %d bends through (%.6g, %.6g), not (%.6g, %.6g)',
                [i, it.Floats['cpx'], it.Floats['cpy'], edges[i].CPX, edges[i].CPY]));
          end
          else if bend = 'hidden' then
          begin
            if not edges[i].Hidden then
              Miss(Format('edge %d is refused by the canvas upstream', [i]));
          end
          else if (edges[i].Curved or edges[i].Hidden
            or (edges[i].NaNCurve <> (bend = 'nancurve'))) then
            Miss(Format('edge %d is %s upstream', [i, bend]));
          Inc(compared);
          ends := (edges[i].Source >= 0) and (edges[i].Source <= High(nodes))
            and (edges[i].Target >= 0) and (edges[i].Target <= High(nodes))
            and not IsNan(nodes[edges[i].Source].PX)
            and not IsNan(nodes[edges[i].Target].PX)
            and not (edges[i].NaNCurve and arrows);
          if ends <> it.Booleans['ends'] then
            Miss(Format('edge %d has ends upstream: %s',
              [i, BoolToStr(it.Booleans['ends'], True)]));
          { THE LINK'S TOOLTIP: its two ends' names, and its own value. }
          Inc(compared);
          p := FChart.ParamsFor(TyChartEdgeDatum(si, edges[i].Row));
          if p.Name <> it.Strings['tipName'] then
            Miss(Format('edge %d is called "%s" upstream, "%s" here',
              [i, it.Strings['tipName'], p.Name]));
          if it.Find('tipValue').JSONType = jtNull then
          begin
            if Length(p.Values) > 0 then
              Miss(Format('edge %d has no value upstream', [i]));
          end
          else if (Length(p.Values) <> 1)
            or not Near(it.Floats['tipValue'], p.Values[0]) then
            Miss(Format('edge %d has the value %g upstream', [i, it.Floats['tipValue']]));
          if strokeWritten then
          begin
            Inc(compared);
            if not ColourOf(it.Find('stroke'), want) then want := 0;
            if TyGraphEdgeStroke(spec, edges, ink, i) <> want then
              Miss(Format('edge %d is stroked %.8x upstream, %.8x here',
                [i, LongWord(want), LongWord(TyGraphEdgeStroke(spec, edges, ink, i))]));
          end;
        end;
      end;
    end;
    AssertTrue('a great deal of it was compared (' + IntToStr(compared) + ')',
      compared > 250);
    AssertEquals(IntToStr(bad) + ' of ' + IntToStr(compared)
      + ' disagree with upstream:' + report, 0, bad);
  finally
    root.Free;
    sl.Free;
  end;
end;

{ ==================== the rules ==================== }

procedure TAdvChartGraphCartesianTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TCartProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
end;

procedure TAdvChartGraphCartesianTest.TearDown;
begin
  FreeAndNil(FOpt);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartGraphCartesianTest.Draw(AW, AH: Integer);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(AW, AH, BGRA(255, 0, 255, 255));
  try
    FChart.SetBounds(0, 0, AW, AH);
    FChart.Render(bmp.Canvas, Rect(0, 0, AW, AH), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartGraphCartesianTest.TestTheSolverPlacesByTheColumnsAndIgnoresTheLayout;
var
  st: TTyDataStore;
  dims: TTySeriesDimArray;
  view: TTyGraphView;
  solved: TTyGraphSolved;
begin
  { A GRAPH ON AXES IS PLACED BY ITS TWO COLUMNS AND BY NOTHING ELSE. The
    option asks for a force layout and writes x and y on an item; upstream
    runs neither on anything that is not a view. The coordinate system here is
    a view standing in for a grid -- any ITyCoordSys will do -- with its two
    scales different, ten pixels a unit across and five down, so a control
    point made in data space and then mapped would land somewhere else than
    one made from the two pixel positions. }
  FOpt := TTyChartOption.Create;
  AssertTrue(FOpt.SetOptionText('{"series":[{"type":"graph","layout":"force",'
    + '"coordinateSystem":"cartesian2d","data":[{"value":[1,2],"x":500,"y":600},'
    + '[4,6],[9,9],["-",5],"-",[1,1e12]],"links":[{"source":0,"target":1,'
    + '"lineStyle":{"curveness":0.5}},{"source":1,"target":2}]}]}'));
  st := TTyDataStore.Create;
  view := TTyGraphView.Create(TyRectF(0, 0, 10, 10), TyRectF(0, 0, 100, 50));
  try
    st.AddDimension('x', ddtFloat);
    st.AddDimension('y', ddtFloat);
    SetLength(dims, 2);
    dims[0] := Default(TTySeriesDim);
    dims[0].Name := 'x';
    dims[0].Kind := ddtFloat;
    dims[1] := Default(TTySeriesDim);
    dims[1].Name := 'y';
    dims[1].Kind := ddtFloat;
    TyGraphFillNodes(FOpt, 0, dims, st);
    AssertEquals('six rows', 6, st.Count);
    solved := TyGraphSolveOnCoordSys(FOpt, 0, st, view, 0, 1);
    AssertTrue('no view is made', solved.View = nil);
    AssertEquals(6, Length(solved.Nodes));
    AssertEquals('by the columns, not the item''s x', 10.0, solved.Nodes[0].PX, 1e-9);
    AssertEquals(10.0, solved.Nodes[0].PY, 1e-9);
    AssertEquals('and X is the column', 1.0, solved.Nodes[0].X, 1e-9);
    AssertEquals('no force moved it', 40.0, solved.Nodes[1].PX, 1e-9);
    AssertEquals(30.0, solved.Nodes[1].PY, 1e-9);
    AssertEquals(90.0, solved.Nodes[2].PX, 1e-9);
    AssertEquals(45.0, solved.Nodes[2].PY, 1e-9);
    AssertTrue('half a position is none', IsNan(solved.Nodes[3].PX)
      and IsNan(solved.Nodes[3].PY));
    AssertTrue('and so is no position', IsNan(solved.Nodes[4].PX));
    { AND A THOUSAND SCREENS OFF IS GONE, the same rule a view graph keeps:
      five trillion pixels down is not a place anything downstream can
      square. }
    AssertTrue('a node a thousand screens off is unplaced',
      IsNan(solved.Nodes[5].PX) and IsNan(solved.Nodes[5].PY));
    { THE CONTROL POINT FROM THE PIXELS: midpoint (25, 20), perpendicular
      offset by the pixel run. Made in data space it would be (45, 12.5). }
    AssertTrue('the first link curves', solved.Edges[0].Curved);
    AssertEquals(35.0, solved.Edges[0].CPX, 1e-9);
    AssertEquals(5.0, solved.Edges[0].CPY, 1e-9);
    AssertFalse('and the second does not', solved.Edges[1].Curved);
    { NO VIEW, NO RING. The ring's control point is pulled towards a centre
      only a view has; asked for it without one, the edge takes the plain
      perpendicular rather than a point made of nothing. }
    TyGraphEdgeGeometry(solved.Edges, solved.Nodes, nil, True);
    AssertTrue('asked for the ring without a view', solved.Edges[0].Curved);
    AssertEquals('it bends the plain way', 35.0, solved.Edges[0].CPX, 1e-9);
  finally
    view.Free;
    st.Free;
  end;
end;

procedure TAdvChartGraphCartesianTest.TestALinkIsNotTheNodeThatSharesItsRow;
var
  list: TTyPaintList;
  el: TTyChartElement;
  p: TTyChartCallbackParams;
begin
  { LINK 0 AND NODE 0 ARE BOTH ROW 0. A lookup by row is a lookup for a
    datum, and must find the node however the two were stacked. }
  list := TTyPaintList.Create;
  try
    el := TyChartElement(TyShapeRect(TyRectF(0, 0, 10, 10)));
    el.Silent := False;
    el.Datum := TyChartDatum(0, 0);
    el.Style.HasFill := True;
    el.Style.FillColor := TTyChartColor($FF112233);
    el.Z2 := 0;
    list.Add(el);
    el := TyChartElement(TyShapeRect(TyRectF(0, 0, 10, 10)));
    el.Silent := False;
    el.Datum := TyChartEdgeDatum(0, 0);
    el.Style.HasFill := True;
    el.Style.FillColor := TTyChartColor($FF445566);
    el.Z2 := 5;
    list.Add(el);
    AssertEquals('the node, not the link above it', 0, list.IndexOfDatum(0, 0));
    AssertEquals('and its ink, not the link''s', 0, list.IndexOfDatumInk(0, 0));
  finally
    list.Free;
  end;
  AssertTrue('a link says so', TyChartEdgeDatum(0, 3).IsEdge);
  AssertFalse('a datum does not', TyChartDatum(0, 3).IsEdge);
  AssertFalse('nor does nothing', TyChartNoDatum.IsEdge);

  { AND THE CONTROL ASKS WHICH IT IS. Link 1 of this chart joins 'Tue' to
    'Wed' and carries a value of 7; node 1 is 'Tue' at 1276. }
  FChart.Option := cGraphGrid;
  Draw(600, 400);
  p := FChart.ParamsFor(TyChartEdgeDatum(0, 1));
  AssertEquals('the link is named by its ends', 'Tue > Wed', p.Name);
  AssertEquals('it is a link', 'edge', p.DataType);
  AssertEquals('with its own value', 1, Length(p.Values));
  AssertEquals(7.0, p.Values[0], 1e-9);
  AssertEquals('and its own colour', LongWord($FF2F4554), LongWord(p.Color));
  p := FChart.ParamsFor(TyChartDatum(0, 1));
  AssertEquals('the node is named by its category', 'Tue', p.Name);
  AssertEquals('it is a node', 'node', p.DataType);
  AssertEquals(1, Length(p.Values));
  AssertEquals(1276.0, p.Values[0], 1e-9);
  p := FChart.ParamsFor(TyChartEdgeDatum(0, 0));
  AssertEquals('a link with no value has none', 0, Length(p.Values));
end;

procedure TAdvChartGraphCartesianTest.TestTheItemNameFallsBackToTheFirstCategory;
var st: TTyDataStore;
begin
  { upstream's getName: the item's own name, else the category of the FIRST
    ordinal dimension, else nothing -- and the label's b placeholder is it. }
  st := TTyDataStore.Create;
  try
    st.AddDimension('y', ddtFloat);
    st.AddDimension('x', ddtOrdinal);
    st.AddDimension('z', ddtOrdinal);
    st.AppendRow([TyDataNum(5), TyDataText('Mon'), TyDataText('other')]);
    st.AppendRow([TyDataNum(6), TyDataText('Tue'), TyDataText('more')]);
    st.SetName(1, 'own');
    AssertEquals('no name of its own: the first category', 'Mon',
      st.GetItemName(0));
    AssertEquals('a name of its own wins', 'own', st.GetItemName(1));
    AssertEquals('while the raw name stays empty', '', st.GetName(0));
    AssertEquals('and b says the same', 'Mon',
      TyLabelText('{b}', tldValue, st, 0, '', 0, 0, False));
    AssertEquals('as the default name text does', 'Mon',
      TyLabelText('', tldName, st, 0, '', 0, 0, False));
  finally
    st.Free;
  end;
  st := TTyDataStore.Create;
  try
    st.AddDimension('x', ddtFloat);
    st.AppendRow([TyDataNum(5)]);
    AssertEquals('no category, no name', '', st.GetItemName(0));
  finally
    st.Free;
  end;
end;

procedure TAdvChartGraphCartesianTest.TestALinksTooltipIsOneBareRowUnderTheSeriesSpec;
var block, row: TTyTooltipBlock;
begin
  { upstream's formatTooltip for a link: one nameValue, no marker, no
    section header even for a named series -- and the tooltip spec is the
    series', because the link's row names a NODE's item in the option. Node 0
    switched its own tooltip off; link 0 still has one. }
  FChart.Option := cGraphGrid;
  Draw(600, 400);
  AssertFalse('node 0 wrote show: false', FChart.SpecFor(TyChartDatum(0, 0)).Show);
  AssertTrue('link 0 did not', FChart.SpecFor(TyChartEdgeDatum(0, 0)).Show);
  block := FChart.ContentFor(TyChartEdgeDatum(0, 1));
  try
    AssertTrue('there is something to say', block <> nil);
    AssertEquals('one row', 1, block.BlockCount);
    AssertTrue('under no header', block.NoHeader);
    row := block.Blocks[0];
    AssertTrue('with no marker', row.Marker = ttmNone);
    AssertEquals('Tue > Wed', row.Name);
    AssertEquals('7', row.Value);
  finally
    block.Free;
  end;
end;

procedure TAdvChartGraphCartesianTest.TestAGraphOnAxesIsDrawnAndItsLinksAnswerAsLinks;
var
  bmp: TBGRABitmap;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  fills: TTyChartColorArray;
  ink: TTyGraphInk;
  spec: TTyGraphSpec;
  d: TTyChartDatumRef;
  x, y, red: Integer;
  p: TBGRAPixel;
begin
  { LAID OUT IS NOT DRAWN. The oracle reads the layout; this looks at the
    pixels, and at what the pointer finds on a link -- the builder has to put
    the LINK's datum on it, not a row a node shares. }
  FChart.Option := StringReplace(cGraphGrid, '"lineStyle"',
    '"itemStyle":{"color":"#ff0000"},"symbolSize":20,"lineStyle"', []);
  bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  try
    FChart.SetBounds(0, 0, 600, 400);
    FChart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
    red := 0;
    for y := 0 to bmp.Height - 1 do
      for x := 0 to bmp.Width - 1 do
      begin
        p := bmp.GetPixel(x, y);
        if (p.red > 200) and (p.green < 60) and (p.blue < 60) then Inc(red);
      end;
    AssertTrue(Format('the nodes are drawn (%d px)', [red]), red > 400);
  finally
    bmp.Free;
  end;
  AssertTrue(FChart.GraphLayout(0, nodes, edges, fills));
  AssertTrue(Length(edges) = 3);
  d := FChart.HitTestAt(
    Round((nodes[edges[0].Source].PX + nodes[edges[0].Target].PX) / 2),
    Round((nodes[edges[0].Source].PY + nodes[edges[0].Target].PY) / 2));
  AssertTrue('the pointer finds a link', d.IsEdge);
  AssertEquals('the first one', edges[0].Row, d.DataIndex);
  { AND THE c PLACEHOLDER READS THE VALUE AXIS' COLUMN -- there is no column
    called value on axes. x is column 0, y column 1. }
  AssertTrue(FChart.GraphInkOf(0, ink, spec));
  AssertEquals('the label value is y', 1, ink.LabelValueDim);
end;

initialization
  RegisterTest(TAdvChartGraphCartesianOracleTest);
  RegisterTest(TAdvChartGraphCartesianTest);
end.
