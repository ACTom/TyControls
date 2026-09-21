unit test.advchart.graphlegend;
{$mode objfpc}{$H+}
{ A graph's categories in the legend, held to upstream's own output.

  tools/advchart-oracle/graph-legend.js runs the real ECharts 6.1 build over
  the cases below and records, for every graph series, which nodes the legend
  kept (by the row they were written at), where they went, what colour each
  node and each category is, which edges survived and how they bend -- and
  what the legend offers and has switched on. The first test puts each case
  through the CONTROL, the way a host does, and reads back what it laid out;
  the filter, the available names, the shared category palette and the chip
  colours all live in the control, and this is the only path that sees them
  all at once.

  Every case declares a palette, so every colour is the author's and none is a
  theme's -- which is what lets a colour here be compared with a colour there. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Data, tyControls.AdvChart.Color,
     tyControls.AdvChart.Paint,
     tyControls.AdvChart.Legend, tyControls.AdvChart.Graph,
     tyControls.AdvanceChart, test.advancechart;
type
  TAdvChartGraphLegendOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(AW, AH: Integer);
  published
    procedure TestEveryCaseMatchesUpstream;
  end;

  TAdvChartGraphLegendTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    FOpt: TTyChartOption;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(AW, AH: Integer);
  published
    procedure TestAGraphSwitchedOffByItsNameGreysItsCategoryChips;
    procedure TestANodeIsTheSeriesColourThenItsCategoryThenItsOwn;
    procedure TestAnEdgeTakesTheCategoryColourNotTheNodesOwn;
    procedure TestIsSelectedAnswersForNamesTheLegendDoesNotList;
    procedure TestAGraphNamedByItsSeriesIsDrawnAsItsSymbol;
    procedure TestNoLegendFiltersNothing;
    procedure TestAnInfiniteCategoryIsAnIndexNobodyHas;
    procedure TestANameSwitchedOffInSelectedGoesEvenUnlisted;
  end;

implementation

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-graph-legend.json';
end;

function ColourOf(AData: TJSONData; out AColour: TTyChartColor): Boolean;
begin
  AColour := 0;
  Result := False;
  if (AData = nil) or (AData.JSONType <> jtString) then Exit;
  Result := TyTryParseChartColor(AData.AsString, AColour);
end;

{ WHAT THE PORT PAINTS FOR A FILL UPSTREAM WROTE DOWN. A colour is itself and
  'none' -- or no fill at all -- is nothing. Any other word is one upstream
  hands the canvas and the canvas ignores; the port keeps the series colour
  there instead, deliberately, and says so in TTyGraphCatColours. }
function PaintedFill(AData: TJSONData; const ASeriesFill: TJSONData): TTyChartColor;
begin
  if ColourOf(AData, Result) then Exit;
  Result := 0;
  if (AData = nil) or (AData.JSONType <> jtString) then Exit;
  if AData.AsString = 'none' then Exit;
  if not ColourOf(ASeriesFill, Result) then Result := 0;
end;

function Near(AExpected, AActual: Double): Boolean;
begin
  if IsNan(AActual) or IsInfinite(AActual) then Exit(False);
  Result := Abs(AExpected - AActual) <= 1e-6 * Max(Double(1), Abs(AExpected));
end;

{ ==================== the oracle ==================== }

procedure TAdvChartGraphLegendOracleTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TChartProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
end;

procedure TAdvChartGraphLegendOracleTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartGraphLegendOracleTest.Draw(AW, AH: Integer);
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

procedure TAdvChartGraphLegendOracleTest.TestEveryCaseMatchesUpstream;
var
  sl: TStringList;
  root: TJSONData;
  cases, graphs, arr, wantNames, wantSel: TJSONArray;
  cs, g, it, phase: TJSONObject;
  c, p, gi, i, k, compared, bad, si: Integer;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  fills: TTyChartColorArray;
  want: TTyChartColor;
  lay: TTyLegendLayout;
  report, nm, bend, symWant, symGot: string;
  phases: array of TJSONObject;
  catColour: TTyChartColor;
  catFound: Boolean;
  ink: TTyGraphInk;
  spec: TTyGraphSpec;
  sopt: TJSONObject;
  arrows, ends, strokeWritten: Boolean;
  seen: array of Boolean;
  d: TJSONData;

  procedure Miss(const AWhat: string);
  begin
    Inc(bad);
    if bad <= 14 then
      report := report + LineEnding + '  ' + cs.Strings['name'] + ': ' + AWhat;
  end;

  { The colour of the chip upstream draws for a name: the first category of
    that name, in series order, and the first series with it. }
  function CategoryColour(AGraphs: TJSONArray; const AName: string;
    out AColour: TTyChartColor): Boolean;
  var a, b: Integer; cats: TJSONArray; one: TJSONObject;
  begin
    Result := False;
    AColour := 0;
    for a := 0 to AGraphs.Count - 1 do
    begin
      cats := AGraphs.Objects[a].Arrays['cats'];
      for b := 0 to cats.Count - 1 do
      begin
        one := cats.Objects[b];
        if one.Strings['name'] = AName then
        begin
          Result := True;
          AColour := PaintedFill(one.Find('fill'),
            AGraphs.Objects[a].Find('seriesFill'));
          Exit;
        end;
      end;
    end;
  end;

  { series[AIndex] of the case's option. }
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
    AssertTrue('the fixture carries its cases', cases.Count >= 40);
    compared := 0;
    bad := 0;
    report := '';
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      FChart.Option := cs.Objects['option'].AsJSON;
      AssertEquals(cs.Strings['name'] + ' parses', '', FChart.OptionError);
      { THE FIRST PASS TWICE: a second layout at the same size REUSES the
        force layout's answer rather than running it again, and must show
        exactly what the first one showed -- stale control points included.
        It has to be ASKED for: a render at an unchanged size lays nothing out
        again, and without the invalidate below this second pass compared the
        first pass's edges with themselves (the replay's mutants lived). }
      SetLength(phases, 2);
      phases[0] := cs;
      phases[1] := cs;
      if cs.Find('resized') is TJSONObject then
      begin
        SetLength(phases, 3);
        phases[2] := cs.Objects['resized'];
      end;
      for p := 0 to High(phases) do
      begin
        phase := phases[p];
        if p = 1 then FChart.Invalidate;
        Draw(phase.Integers['width'], phase.Integers['height']);

        graphs := phase.Arrays['graphs'];
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
          { THE STROKE IS COMPARED ONLY WHERE THE AUTHOR WROTE ONE: the default
            line colour is the theme's here and a fixed grey upstream. }
          strokeWritten := (sopt <> nil) and (sopt.Find('lineStyle') is TJSONObject)
            and (TJSONObject(sopt.Find('lineStyle')).Find('color') <> nil);
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
            if it.Find('px').JSONType = jtNull then
            begin
              if not IsNan(nodes[i].PX) then
                Miss(Format('node %d is nowhere upstream', [i]));
            end
            else if not (Near(it.Floats['px'], nodes[i].PX)
              and Near(it.Floats['py'], nodes[i].PY)) then
              Miss(Format('node %d wants (%.6g, %.6g) got (%.6g, %.6g)',
                [i, it.Floats['px'], it.Floats['py'], nodes[i].PX, nodes[i].PY]));
            if cs.Booleans['colours'] then
            begin
              Inc(compared);
              want := PaintedFill(it.Find('fill'), g.Find('seriesFill'));
              if (i > High(fills)) or (fills[i] <> want) then
                Miss(Format('node %d is %.8x upstream, %.8x here',
                  [i, LongWord(want), LongWord(fills[Min(i, High(fills))])]));
            end;
            { THE SYMBOL: its own, else its category's, else the series'. }
            Inc(compared);
            symWant := it.Get('symbol', '');
            symGot := nodes[i].SymbolName;
            if symGot = '' then
            begin
              symGot := 'circle';
              if (sopt <> nil) and (sopt.Find('symbol') <> nil)
                and (sopt.Find('symbol').JSONType = jtString) then
                symGot := sopt.Strings['symbol'];
            end;
            if symGot <> symWant then
              Miss(Format('node %d is a %s upstream, a %s here',
                [i, symWant, symGot]));
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
            { FOUR WAYS AN EDGE CAN READ, and the port must pick the same one:
              no third point, a third point with a not-a-number half (drawn
              straight), one that is not finite (not drawn), and a curve. }
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
              Miss(Format('edge %d is %s upstream, curved=%s hidden=%s nan=%s here',
                [i, bend, BoolToStr(edges[i].Curved, True),
                 BoolToStr(edges[i].Hidden, True),
                 BoolToStr(edges[i].NaNCurve, True)]));
            { AND WHETHER ITS ENDS SURVIVE: adjustEdge cuts a broken curve into
              not-a-number wherever an end carries a symbol. }
            Inc(compared);
            ends := (edges[i].Source >= 0) and (edges[i].Source <= High(nodes))
              and (edges[i].Target >= 0) and (edges[i].Target <= High(nodes))
              and not IsNan(nodes[edges[i].Source].PX)
              and not IsNan(nodes[edges[i].Target].PX)
              and not (edges[i].NaNCurve and arrows);
            if ends <> it.Booleans['ends'] then
              Miss(Format('edge %d has ends upstream: %s',
                [i, BoolToStr(it.Booleans['ends'], True)]));
            if strokeWritten then
            begin
              Inc(compared);
              if not ColourOf(it.Find('stroke'), want) then want := 0;
              if TyGraphEdgeStroke(spec, edges, ink, i) <> want then
                Miss(Format('edge %d is stroked %.8x upstream, %.8x here',
                  [i, LongWord(want),
                   LongWord(TyGraphEdgeStroke(spec, edges, ink, i))]));
            end;
          end;

        end;
      end;

      { THE LEGEND, as the first phase left it. }
      arr := cs.Arrays['legends'];
      Inc(compared);
      if arr.Count <> FChart.LegendLayoutCount then
      begin
        Miss(Format('%d legends, not %d', [FChart.LegendLayoutCount, arr.Count]));
        Continue;
      end;
      Draw(cs.Integers['width'], cs.Integers['height']);
      for k := 0 to arr.Count - 1 do
      begin
        lay := FChart.LegendLayout(k);
        { A LEGEND THAT IS NOT SHOWN IS NOT PLACED here, so it has no items to
          compare -- it still filters, and the nodes above say so. }
        if (Length(lay.Items) = 0) and (Pos('"show" : false',
          cs.Objects['option'].AsJSON) > 0) then Continue;
        wantNames := arr.Objects[k].Arrays['names'];
        wantSel := arr.Objects[k].Arrays['selected'];
        Inc(compared);
        if wantNames.Count <> Length(lay.Items) then
        begin
          Miss(Format('legend %d offers %d items, not %d',
            [k, Length(lay.Items), wantNames.Count]));
          Continue;
        end;
        for i := 0 to wantNames.Count - 1 do
        begin
          nm := wantNames.Items[i].AsString;
          Inc(compared);
          if lay.Items[i].Name <> nm then
            Miss(Format('legend item %d is %s, not %s', [i, nm, lay.Items[i].Name]));
          if nm = '' then Continue;
          if lay.Items[i].Selected <> wantSel.Items[i].AsBoolean then
            Miss(Format('legend item %s selected is %s upstream',
              [nm, BoolToStr(wantSel.Items[i].AsBoolean, True)]));
          { A CATEGORY CHIP IS ITS CATEGORY'S COLOUR. }
          catFound := CategoryColour(TJSONArray(cs.Arrays['graphs']), nm, catColour);
          if catFound and cs.Booleans['colours'] and lay.Items[i].Selected then
          begin
            Inc(compared);
            if lay.Items[i].Colour <> catColour then
              Miss(Format('the chip for %s is %.8x upstream, %.8x here',
                [nm, LongWord(catColour), LongWord(lay.Items[i].Colour)]));
            if lay.Items[i].Icon <> 'roundRect' then
              Miss(Format('the chip for %s is a %s, not a roundRect',
                [nm, lay.Items[i].Icon]));
          end;
        end;
      end;
    end;
    AssertTrue('a great deal of it was compared (' + IntToStr(compared) + ')',
      compared > 2000);
    AssertEquals(IntToStr(bad) + ' of ' + IntToStr(compared)
      + ' disagree with upstream:' + report, 0, bad);
  finally
    root.Free;
    sl.Free;
  end;
end;

{ ==================== the rules ==================== }

procedure TAdvChartGraphLegendTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TChartProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
end;

procedure TAdvChartGraphLegendTest.TearDown;
begin
  FreeAndNil(FOpt);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartGraphLegendTest.Draw(AW, AH: Integer);
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

procedure TAdvChartGraphLegendTest.TestAGraphSwitchedOffByItsNameGreysItsCategoryChips;
var
  lay: TTyLegendLayout;
  i: Integer;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  fills: TTyChartColorArray;
begin
  { UPSTREAM THROWS HERE. The graph is switched off by its series name, so its
    categories are never coloured -- and the legend, which still draws them,
    dereferences a colour that does not exist. Its own comment says a name
    missing from the filtered data "will display as gray", so the chips come
    out greyed rather than taking the host down. The render must RETURN. }
  FChart.Option := '{"color":["#111111","#222222"],'
    + '"legend":{"data":["G","X","Y"],"selected":{"G":false}},'
    + '"series":[{"type":"graph","name":"G","layout":"none",'
    + '"categories":[{"name":"X"},{"name":"Y"}],'
    + '"data":[{"name":"a","x":0,"y":0,"category":0},'
    + '{"name":"b","x":1,"y":1,"category":1}]}]}';
  Draw(400, 300);
  lay := FChart.LegendLayout(0);
  AssertEquals(3, Length(lay.Items));
  for i := 1 to 2 do
    AssertFalse('the category chip ' + lay.Items[i].Name + ' is grey',
      lay.Items[i].Selected);
  AssertFalse('and the graph itself is not drawn',
    FChart.GraphLayout(0, nodes, edges, fills) and (Length(nodes) > 0));
end;

procedure TAdvChartGraphLegendTest.TestANodeIsTheSeriesColourThenItsCategoryThenItsOwn;
var
  st: TTyDataStore;
  cats: TTyGraphCategoryArray;
  nodes: TTyGraphNodeArray;
  cols: TTyGraphCatColours;
  edgeEnd, f: TTyChartColor;
begin
  FOpt := TTyChartOption.Create;
  AssertTrue(FOpt.SetOptionText('{"series":[{"type":"graph",'
    + '"categories":[{"name":"X"},{"name":"Y"}],'
    + '"data":[{"name":"a","category":0},{"name":"b","category":1,'
    + '"itemStyle":{"color":"#ff0000"}},{"name":"c"},{"name":"d","category":7}]}]}'));
  st := TTyDataStore.Create;
  try
    TyGraphFillStore(FOpt, 0, st);
    cats := TyGraphCategoriesOf(FOpt, 0);
    nodes := TyGraphNodesOf(st, cats);
    SetLength(cols.Known, 2);
    SetLength(cols.Colours, 2);
    cols.Known[0] := True;
    cols.Colours[0] := TTyChartColor($FF00AA00);
    cols.Known[1] := True;
    cols.Colours[1] := TTyChartColor($FF0000AA);
    f := TyGraphNodeFill(nodes[0], cols, 2, TTyChartColor($FF777777), st, edgeEnd);
    AssertEquals('its category''s', LongWord($FF00AA00), LongWord(f));
    f := TyGraphNodeFill(nodes[1], cols, 2, TTyChartColor($FF777777), st, edgeEnd);
    AssertEquals('its own, last', LongWord($FFFF0000), LongWord(f));
    AssertEquals('and an edge takes the category''s, from before its own',
      LongWord($FF0000AA), LongWord(edgeEnd));
    f := TyGraphNodeFill(nodes[2], cols, 2, TTyChartColor($FF777777), st, edgeEnd);
    AssertEquals('no category: the series''', LongWord($FF777777), LongWord(f));
    f := TyGraphNodeFill(nodes[3], cols, 2, TTyChartColor($FF777777), st, edgeEnd);
    AssertEquals('an index past the end: the series''', LongWord($FF777777),
      LongWord(f));
    { A SERIES WITH NO CATEGORIES AT ALL never reaches for one. }
    f := TyGraphNodeFill(nodes[0], cols, 0, TTyChartColor($FF777777), st, edgeEnd);
    AssertEquals(LongWord($FF777777), LongWord(f));
    { AND A CATEGORY THAT FOUND NO COLOUR GIVES NONE -- upstream lays an
      undefined fill over the series'. }
    cols.Known[0] := False;
    f := TyGraphNodeFill(nodes[0], cols, 2, TTyChartColor($FF777777), st, edgeEnd);
    AssertEquals(LongWord(0), LongWord(f));
  finally
    st.Free;
  end;
end;

procedure TAdvChartGraphLegendTest.TestAnEdgeTakesTheCategoryColourNotTheNodesOwn;
var
  view: TTyGraphView;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  ink: TTyGraphInk;
  list: TTyPaintList;
  s: TTyGraphSpec;
begin
  { `lineStyle.color: 'source'` IS RESOLVED BEFORE THE NODE'S OWN COLOUR -- so
    an edge leaving a node that painted itself red takes the node's CATEGORY
    colour. The builder reads EdgeEndFills for that. }
  s := TyGraphSpecDefault;
  s.ColourBy := gecSource;
  SetLength(nodes, 2);
  nodes[0] := Default(TTyGraphNode);
  nodes[1] := Default(TTyGraphNode);
  nodes[0].PX := 10; nodes[0].PY := 10;
  nodes[1].PX := 90; nodes[1].PY := 10;
  SetLength(edges, 1);
  edges[0] := Default(TTyGraphEdge);
  edges[0].Target := 1;
  ink := Default(TTyGraphInk);
  SetLength(ink.NodeFills, 2);
  SetLength(ink.EdgeEndFills, 2);
  ink.NodeFills[0] := TTyChartColor($FFFF0000);
  ink.EdgeEndFills[0] := TTyChartColor($FF00AA00);
  view := TTyGraphView.Create(TyRectF(0, 0, 100, 100), TyRectF(0, 0, 100, 100));
  list := TTyPaintList.Create;
  try
    TyBuildGraphMarks(0, view, s, nodes, edges, ink, nil, list);
    AssertEquals(LongWord($FF00AA00), LongWord(list.Element(0).Style.StrokeColor));
  finally
    list.Free;
    view.Free;
  end;
end;

procedure TAdvChartGraphLegendTest.TestIsSelectedAnswersForNamesTheLegendDoesNotList;
var
  entries: TTyLegendEntryArray;
  flags: TTyLegendFlags;
  avail: array of string;
begin
  FOpt := TTyChartOption.Create;
  AssertTrue(FOpt.SetOptionText(
    '{"legend":{"data":["Y"],"selected":{"X":false,"Z":0}},"series":[]}'));
  SetLength(avail, 3);
  avail[0] := 'X';
  avail[1] := 'Y';
  avail[2] := 'Z';
  entries := TyLegendEntries(FOpt, 0, avail);
  flags := TyLegendSelected(FOpt, 0, entries, avail, tlsMultiple);
  AssertTrue('a listed name answers with its flag',
    TyLegendNameSelected(FOpt, 0, entries, flags, avail, 'Y'));
  AssertFalse('an unlisted name switched off is off',
    TyLegendNameSelected(FOpt, 0, entries, flags, avail, 'X'));
  AssertFalse('by any falsy word',
    TyLegendNameSelected(FOpt, 0, entries, flags, avail, 'Z'));
  AssertFalse('and a name the chart does not offer is never selected',
    TyLegendNameSelected(FOpt, 0, entries, flags, avail, 'Nope'));
  { THE LIST-ONLY TyLegendHides says nothing about a name the legend does not
    list -- but the whole rule, the one the control asks, reads `selected`
    too: upstream's isSelected finds 'X' switched off there, and every series
    name is available, so a series called X goes. A name the map does not
    mention stays, and so does the empty one. }
  AssertFalse('the listed-only answer', TyLegendHides(entries, flags, 'X'));
  AssertTrue('the whole rule', TyLegendHides(FOpt, 0, entries, flags, 'X'));
  AssertTrue('by any falsy word', TyLegendHides(FOpt, 0, entries, flags, 'Z'));
  AssertFalse('a listed name on', TyLegendHides(FOpt, 0, entries, flags, 'Y'));
  AssertFalse('an unmentioned name',
    TyLegendHides(FOpt, 0, entries, flags, 'Nope'));
  AssertFalse('the empty name', TyLegendHides(FOpt, 0, entries, flags, ''));

  { EVEN WHEN THE MAP SWITCHES '' OFF: here the empty name is every unnamed
    series, which upstream calls something unique and never finds there. }
  AssertTrue(FOpt.SetOptionText('{"legend":{"data":["Y"],"selected":{"":false}},'
    + '"series":[]}'));
  entries := TyLegendEntries(FOpt, 0, avail);
  flags := TyLegendSelected(FOpt, 0, entries, avail, tlsMultiple);
  AssertFalse('an unnamed series survives a map that names nothing',
    TyLegendHides(FOpt, 0, entries, flags, ''));

  { A LISTED NAME ANSWERS WITH ITS FLAG, which carries single mode's rewrite:
    the map says nothing about 'Y', and 'Y' is off all the same. }
  AssertTrue(FOpt.SetOptionText('{"legend":{"data":["X","Y"],'
    + '"selectedMode":"single"},"series":[]}'));
  entries := TyLegendEntries(FOpt, 0, avail);
  flags := TyLegendSelected(FOpt, 0, entries, avail, tlsSingle);
  AssertFalse('single mode keeps the first', TyLegendHides(FOpt, 0, entries, flags, 'X'));
  AssertTrue('and switches the rest off', TyLegendHides(FOpt, 0, entries, flags, 'Y'));
end;


procedure TAdvChartGraphLegendTest.TestAGraphNamedByItsSeriesIsDrawnAsItsSymbol;
begin
  AssertEquals('a circle by default', 'circle', TyLegendDefaultIcon('graph', ''));
  AssertEquals('or the symbol it names', 'rect', TyLegendDefaultIcon('graph', 'rect'));
end;

procedure TAdvChartGraphLegendTest.TestNoLegendFiltersNothing;
var
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  fills: TTyChartColorArray;
  lay: TTyLegendLayout;
begin

  { WITHOUT A LEGEND, a node whose category the chart cannot offer is KEPT, in
    the series colour -- the same node a legend would remove. }
  FChart.Option := '{"series":[{"type":"graph","layout":"none",'
    + '"categories":[{"name":"X"}],"data":[{"name":"a","x":0,"y":0,"category":5},'
    + '{"name":"b","x":1,"y":1,"category":"Nope"}]}]}';
  Draw(400, 300);
  AssertTrue(FChart.GraphLayout(0, nodes, edges, fills));
  AssertEquals('both kept', 2, Length(nodes));
  FChart.Option := '{"legend":{},"series":[{"type":"graph","layout":"none",'
    + '"categories":[{"name":"X"}],"data":[{"name":"a","x":0,"y":0,"category":5},'
    + '{"name":"b","x":1,"y":1,"category":"Nope"}]}]}';
  Draw(400, 300);
  AssertTrue(FChart.GraphLayout(0, nodes, edges, fills));
  AssertEquals('and with a legend, both gone', 0, Length(nodes));
  { AND WHAT THE LEGEND LAYOUT HANDS OUT IS A COPY: writing into it must not
    write into the control. }
  lay := FChart.LegendLayout(0);
  AssertTrue('the legend has an item', Length(lay.Items) > 0);
  lay.Items[0].Name := 'scribbled';
  AssertEquals('X', FChart.LegendLayout(0).Items[0].Name);
end;

procedure TAdvChartGraphLegendTest.TestAnInfiniteCategoryIsAnIndexNobodyHas;
var
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  fills: TTyChartColorArray;
begin
  { `1e999` PARSES AS AN INFINITY, and the filter tested it for a whole
    number before it tested the range -- Frac of an infinity raises. Upstream
    indexes the category names with it, finds undefined, and the legend
    never selects undefined: the node goes. Written on the node and, through
    the model chain, on the series. }
  FChart.Option := '{"legend":{},"series":[{"type":"graph","layout":"none",'
    + '"categories":[{"name":"X"}],"data":[{"name":"a","x":0,"y":0,"category":1e999},'
    + '{"name":"b","x":1,"y":1,"category":-1e999},{"name":"c","x":2,"y":2,"category":0}]}]}';
  AssertEquals('it parses', '', FChart.OptionError);
  Draw(400, 300);
  AssertTrue(FChart.GraphLayout(0, nodes, edges, fills));
  AssertEquals('only the node with a real index stays', 1, Length(nodes));
  AssertEquals(2, nodes[0].RawRow);
  FChart.Option := '{"legend":{},"series":[{"type":"graph","layout":"none",'
    + '"category":1e999,"categories":[{"name":"X"}],'
    + '"data":[{"name":"a","x":0,"y":0},{"name":"c","x":2,"y":2,"category":0}]}]}';
  Draw(400, 300);
  AssertTrue(FChart.GraphLayout(0, nodes, edges, fills));
  AssertEquals('and the series'' own goes the same way', 1, Length(nodes));
  AssertEquals(1, nodes[0].RawRow);
end;

procedure TAdvChartGraphLegendTest.TestANameSwitchedOffInSelectedGoesEvenUnlisted;
var
  bmp: TBGRABitmap;

  function Count(ARed: Boolean): Integer;
  var x, y: Integer; p: TBGRAPixel;
  begin
    Result := 0;
    for y := 0 to bmp.Height - 1 do
      for x := 0 to bmp.Width - 1 do
      begin
        p := bmp.GetPixel(x, y);
        if ARed and (p.red > 200) and (p.green < 60) and (p.blue < 60) then
          Inc(Result);
        if (not ARed) and (p.blue > 200) and (p.red < 60) and (p.green < 60) then
          Inc(Result);
      end;
  end;

  procedure Paint;
  begin
    FChart.SetBounds(0, 0, 400, 300);
    bmp.Fill(BGRA(255, 255, 255, 255));
    FChart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
  end;

begin
  { UPSTREAM READS `selected` BEFORE IT READS THE LIST. A series name is
    always available, so `selected: { L: false }` switches series L off
    whether `legend.data` names it or not -- and the same for a pie slice,
    whose name is available while its pie is drawn. Before this the control
    only let a LISTED name switch anything off. }
  bmp := TBGRABitmap.Create(400, 300);
  try
    FChart.Option := '{"color":["#ff0000","#0000ff"],"legend":{"data":["Other"]},'
      + '"xAxis":{"type":"category","data":["a","b"]},"yAxis":{},'
      + '"series":[{"type":"bar","name":"L","data":[5,3]},'
      + '{"type":"bar","name":"M","data":[4,2]}]}';
    Paint;
    AssertTrue('both bars are drawn', (Count(True) > 200) and (Count(False) > 200));
    FChart.Option := '{"color":["#ff0000","#0000ff"],'
      + '"legend":{"data":["Other"],"selected":{"L":false}},'
      + '"xAxis":{"type":"category","data":["a","b"]},"yAxis":{},'
      + '"series":[{"type":"bar","name":"L","data":[5,3]},'
      + '{"type":"bar","name":"M","data":[4,2]}]}';
    Paint;
    AssertEquals('the series switched off by name is gone', 0, Count(True));
    AssertTrue('and the other is not', Count(False) > 200);

    FChart.Option := '{"legend":{"data":["Other"],"selected":{"s1":false}},'
      + '"series":[{"type":"pie","data":[{"name":"s1","value":1,'
      + '"itemStyle":{"color":"#ff0000"}},{"name":"s2","value":1,'
      + '"itemStyle":{"color":"#0000ff"}}]}]}';
    Paint;
    AssertEquals('a slice switched off by name is gone', 0, Count(True));
    AssertTrue('and the other slice is the whole pie', Count(False) > 2000);
  finally
    bmp.Free;
  end;
end;


initialization
  RegisterTest(TAdvChartGraphLegendOracleTest);
  RegisterTest(TAdvChartGraphLegendTest);
end.
