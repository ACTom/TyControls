unit test.advchart.handlerwiring;
{$mode objfpc}{$H+}
{ A NAMED HANDLER AT EVERY FORMATTER SITE, held to upstream.

  tools/advchart-oracle/handlers.js runs the real ECharts 6.1 build with every
  '@Name' formatter string replaced by a JavaScript function that prints the
  arguments it was called with; the handlers registered below print the same
  encoding from the params record the port hands them. What is compared is
  the multiset of texts the chart puts up that carry one of the encodings --
  so a site that passes the filtered index where upstream passes the raw one,
  a category's ordinal where upstream passes its name, or that never calls
  the handler at all, shows up as a text that differs. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StrConsts,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Scale, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Layout,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Tooltip,
     tyControls.AdvChart.Legend, tyControls.AdvChart.VisualMapView,
     tyControls.AdvChart.DataZoomView, tyControls.AdvChart.JsMath,
     tyControls.AdvanceChart;
type
  THwProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function ItemContent(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
    function Pointers(AX, AY: Integer): TTyAxisHitArray;
    function AxisContent(const AHits: TTyAxisHitArray;
      const ASpec: TTyTooltipSpec): TTyTooltipBlock;
    function PointerText(const AHit: TTyAxisHit): string;
  end;

  { the handlers: each prints what it was given, as handlers.js does }
  THwHandlers = class
  public
    function L(const P: TTyChartParams): string;
    function AX(const P: TTyChartParams): string;
    function TT(const P: TTyChartParams): string;
    function LG(const P: TTyChartParams): string;
    function VF(const P: TTyChartParams): string;
    function AP(const P: TTyChartParams): string;
    function VM(const P: TTyChartParams): string;
    function DZ(const P: TTyChartParams): string;
    function GD(const P: TTyChartParams): string;
    function GA(const P: TTyChartParams): string;
    function RN(const P: TTyChartParams): string;
    function CM(const P: TTyChartParams): string;
  end;

  TAdvChartHandlerWiringOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: THwProbe;
    FHandlers: THwHandlers;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport: string;
    FSavedSource: TTyDateTimeNameSource;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(ACase: TJSONObject);
    procedure SceneTexts(AOut: TStrings);
    procedure TipTexts(ACase: TJSONObject; ATip, AAfter: TStrings);
    procedure Compare(ACase: TJSONObject; const AWhat: string;
      AWant: TJSONData; AGot: TStrings);
    procedure Run(const APrefix: string; AMinimum: Integer);
  published
    procedure TestSeriesAndMarkerLabelsAsUpstream;
    procedure TestAxisLabelsAsUpstream;
    procedure TestLegendAsUpstream;
    procedure TestTooltipValueFormatterAsUpstream;
    procedure TestAxisPointerLabelAsUpstream;
    procedure TestVisualMapAsUpstream;
    procedure TestDataZoomAsUpstream;
    procedure TestGaugeRadarCalendarAsUpstream;
    procedure TestAnUnregisteredNameSaysSo;
  end;

implementation

{ Cases whose sites the port does not draw yet; the upstream answer stays in
  the fixture for the batch that does. }
const
  cDeferred: array[0..2] of string = (
    'label radar: one call per indicator',  // radar series labels: not ported (batch 35)
    { a treemap truncates its words to the box by their measured width, and
      this harness measures with the real font where upstream's node run
      estimates -- test.advchart.treemap holds the words with zrender's own
      SSR measure }
    'label treemap',
    { axisPointer.status / value on the option: not ported -- batch B5 }
    'axisPointer status show with a value, no tooltip trigger'
  );

{ ==================== the probe ==================== }

procedure THwProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function THwProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function THwProbe.ItemContent(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
begin
  Result := TooltipContent(ADatum, TooltipSpecFor(ADatum));
end;

function THwProbe.Pointers(AX, AY: Integer): TTyAxisHitArray;
begin
  Result := ResolveAxisPointers(AX, AY);
end;

function THwProbe.AxisContent(const AHits: TTyAxisHitArray;
  const ASpec: TTyTooltipSpec): TTyTooltipBlock;
begin
  Result := AxisTooltipContent(AHits, ASpec);
end;

function THwProbe.PointerText(const AHit: TTyAxisHit): string;
begin
  Result := PointerLabelText(AHit, PointerValue(AHit));
end;

{ ==================== the handlers ==================== }

function Num(AValue: Double): string;
begin
  Result := TyJsNumberToString(AValue);
end;

function IdxText(AIndex: Integer): string;
begin
  if AIndex < 0 then Result := 'undefined' else Result := IntToStr(AIndex);
end;

function THwHandlers.L(const P: TTyChartParams): string;
var pct, dt: string;
begin
  if P[0].HasPercent then pct := Num(P[0].Percent) else pct := '-';
  if P[0].DataType = '' then dt := '-' else dt := P[0].DataType;
  Result := 'L:' + P[0].ComponentType + '|' + P[0].SeriesType + '|'
    + IntToStr(P[0].SeriesIndex) + '|' + P[0].SeriesName + '|' + P[0].Name + '|'
    + IdxText(P[0].RawDataIndex) + '|' + P[0].ValueText + '|' + pct + '|' + dt;
end;

function LevelText(const P: TTyChartCallbackParams): string;
begin
  if P.HasLevel then Result := 'L' + IntToStr(P.Level) else Result := 'null';
end;

function THwHandlers.AX(const P: TTyChartParams): string;
begin
  Result := 'A:' + P[0].ValueText + '|' + IdxText(P[0].DataIndex) + '|'
    + LevelText(P[0]);
end;

function THwHandlers.TT(const P: TTyChartParams): string;
begin
  { a template: the chart runs it through the time format }
  Result := '{yyyy}/{M}/{d} ' + LevelText(P[0]);
end;

function THwHandlers.LG(const P: TTyChartParams): string;
begin
  Result := 'G:' + P[0].Name;
end;

function THwHandlers.VF(const P: TTyChartParams): string;
begin
  Result := 'V:' + P[0].ValueText + '|' + IdxText(P[0].RawDataIndex);
end;

function THwHandlers.AP(const P: TTyChartParams): string;
var k: Integer; s: string;
begin
  s := '';
  for k := 1 to High(P) do
  begin
    if k > 1 then s := s + ',';
    s := s + IntToStr(P[k].SeriesIndex) + ':' + IdxText(P[k].RawDataIndex);
  end;
  Result := 'P:' + P[0].AxisDimension + '|' + IntToStr(P[0].AxisIndex) + '|'
    + P[0].ValueText + '|' + IntToStr(High(P)) + '|' + s;
end;

function THwHandlers.VM(const P: TTyChartParams): string;
var v1, v2: string;
begin
  if Length(P[0].Values) = 0 then v1 := P[0].ValueText
  else v1 := Num(P[0].Values[0]);
  if Length(P[0].Values) > 1 then v2 := Num(P[0].Values[1])
  else v2 := 'undefined';
  Result := 'M:' + v1 + '|' + v2;
end;

function THwHandlers.DZ(const P: TTyChartParams): string;
begin
  Result := 'Z:' + P[0].ValueText + '|' + P[0].DefaultText;
end;

function THwHandlers.GD(const P: TTyChartParams): string;
begin
  Result := 'D:' + P[0].ValueText;
end;

function THwHandlers.GA(const P: TTyChartParams): string;
begin
  Result := 'GA:' + P[0].ValueText;
end;

function THwHandlers.RN(const P: TTyChartParams): string;
begin
  Result := 'R:' + P[0].Name + '|' + P[0].ValueText;
end;

function THwHandlers.CM(const P: TTyChartParams): string;
begin
  if P[0].Extra = 'month' then
    Result := 'C:' + P[0].Name + '|' + Num(P[0].Values[0]) + '|'
      + Num(P[0].Values[1]) + '|undefined'
  else
    Result := 'C:' + P[0].Name + '|undefined|undefined|undefined';
end;

{ ==================== plumbing ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-handlers.json';
end;

function Ours(const AText: string): Boolean;
const
  cPrefixes: array[0..10] of string = ('L:', 'A:', 'G:', 'V:', 'P:', 'M:',
    'Z:', 'D:', 'GA:', 'R:', 'C:');
var i, slash: Integer;
begin
  for i := 0 to High(cPrefixes) do
    if Copy(AText, 1, Length(cPrefixes[i])) = cPrefixes[i] then Exit(True);
  { the @TT template's answer: yyyy/M/d and a space }
  Result := False;
  if (Length(AText) < 10) or not (AText[1] in ['0'..'9']) then Exit;
  if AText[5] <> '/' then Exit;
  slash := Pos('/', Copy(AText, 6, MaxInt));
  Result := (slash > 0) and (Pos(' ', AText) > 0);
end;

procedure Flatten(ABlock: TTyTooltipBlock; AOut: TStrings);
var i: Integer;
begin
  if ABlock = nil then Exit;
  if ABlock.IsSection then
  begin
    if not ABlock.NoHeader and Ours(ABlock.Header) then AOut.Add(ABlock.Header);
    for i := 0 to ABlock.BlockCount - 1 do Flatten(ABlock.Blocks[i], AOut);
    Exit;
  end;
  if not ABlock.NoName and Ours(ABlock.Name) then AOut.Add(ABlock.Name);
  if not ABlock.NoValue and Ours(ABlock.Value) then AOut.Add(ABlock.Value);
end;

procedure TAdvChartHandlerWiringOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := THwProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  FHandlers := THwHandlers.Create;
  TyChartRegisterFormatter('L', @FHandlers.L);
  TyChartRegisterFormatter('AX', @FHandlers.AX);
  TyChartRegisterFormatter('TT', @FHandlers.TT);
  TyChartRegisterFormatter('LG', @FHandlers.LG);
  TyChartRegisterFormatter('VF', @FHandlers.VF);
  TyChartRegisterFormatter('AP', @FHandlers.AP);
  TyChartRegisterFormatter('VM', @FHandlers.VM);
  TyChartRegisterFormatter('DZ', @FHandlers.DZ);
  TyChartRegisterFormatter('GD', @FHandlers.GD);
  TyChartRegisterFormatter('GA', @FHandlers.GA);
  TyChartRegisterFormatter('RN', @FHandlers.RN);
  TyChartRegisterFormatter('CM', @FHandlers.CM);
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  { month names are the library's, English under node: pinned so this
    reads the same on every machine }
  FSavedSource := TyDateTimeNameSource;
  TyDateTimeNameSource := dnTranslation;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartHandlerWiringOracleTest.TearDown;
begin
  TyDateTimeNameSource := FSavedSource;
  TyChartClearFormatters;
  FHandlers.Free;
  FRoot.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartHandlerWiringOracleTest.Draw(ACase: TJSONObject);
begin
  FChart.Option := ACase.Objects['option'].AsJSON;
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
end;

{ every text the chart puts up that carries an encoding: the display list's
  captions -- the series', the markers', the legends', the visualMaps', the
  sliders' -- and the axes' shown labels. A caption with no size is the host
  of a label expanded into an element of its own, and is not drawn. }
procedure TAdvChartHandlerWiringOracleTest.SceneTexts(AOut: TStrings);
var
  lst: TTyPaintList;
  i, g, a: Integer;
  gb: TTyGridBuild;
  spec: PTyAxisLayoutSpec;

  procedure Take(const S: string);
  begin
    { fpjson drops a   from what it parses, so the fixture's
      'series 1' reads 'series1': the port's NUL goes the same way }
    if Ours(S) then AOut.Add(StringReplace(S, #0, '', [rfReplaceAll]));
  end;

  procedure Axis(AAxis: TTyAxis);
  var q: Integer;
  begin
    spec := gb.SpecFor(AAxis);
    if spec = nil then Exit;
    for q := 0 to High(spec^.Placements) do
      if spec^.Placements[q].Shown then Take(spec^.Placements[q].Text);
  end;

begin
  lst := FChart.List;
  if lst <> nil then
    for i := 0 to lst.Count - 1 do
      if lst.Element(i).Caption.FontSizeLogical > 0 then
        Take(lst.Element(i).Caption.Text);
  if FChart.Build <> nil then
    for g := 0 to FChart.Build.GridCount - 1 do
    begin
      gb := FChart.Build.Grid(g);
      for a := 0 to gb.XAxisCount - 1 do Axis(gb.XAxis(a));
      for a := 0 to gb.YAxisCount - 1 do Axis(gb.YAxis(a));
    end;
end;

procedure TAdvChartHandlerWiringOracleTest.TipTexts(ACase: TJSONObject;
  ATip, AAfter: TStrings);
var
  tip: TJSONObject;
  hits: TTyAxisHitArray;
  block: TTyTooltipBlock;
  lst: TTyPaintList;
  e: TTyChartElement;
  datum: TTyChartDatumRef;
  i, si, raw: Integer;
  found: Boolean;
  opt: TTyChartOption;
begin
  tip := ACase.Objects['tooltip'];
  block := nil;
  if tip.Strings['trigger'] = 'axis' then
  begin
    hits := FChart.Pointers(Round(tip.Floats['x']), Round(tip.Floats['y']));
    opt := TTyChartOption.Create;
    try
      opt.SetOptionText(ACase.Objects['option'].AsJSON);
      block := FChart.AxisContent(hits, TyTooltipSpecOf(opt, -1, -1));
    finally
      opt.Free;
    end;
    { the pointers' own labels, each shown arm -- the cross' second arm too }
    for i := 0 to High(hits) do
      if hits[i].Spec.LabelSpec.Show then
        if Ours(FChart.PointerText(hits[i])) then
          AAfter.Add(FChart.PointerText(hits[i]));
  end
  else
  begin
    found := False;
    datum := Default(TTyChartDatumRef);
    si := tip.Integers['seriesIndex'];
    raw := tip.Integers['dataIndex'];
    lst := FChart.List;
    for i := 0 to lst.Count - 1 do
    begin
      e := lst.Element(i);
      if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si)
        or (e.Datum.RawDataIndex <> raw) or (e.Datum.DataIndex < 0) then Continue;
      datum := e.Datum;
      found := True;
      Break;
    end;
    if found then block := FChart.ItemContent(datum);
  end;
  try
    Flatten(block, ATip);
  finally
    block.Free;
  end;
end;

procedure TAdvChartHandlerWiringOracleTest.Compare(ACase: TJSONObject;
  const AWhat: string; AWant: TJSONData; AGot: TStrings);
var
  want: TStringList;
  i: Integer;
begin
  want := TStringList.Create;
  try
    if AWant is TJSONArray then
      for i := 0 to TJSONArray(AWant).Count - 1 do
        { A LINK'S LABEL IS NOT DRAWN: graph and sankey edge labels are not
          ported (batches 46 and 79) }
        if Copy(TJSONArray(AWant).Strings[i],
          Length(TJSONArray(AWant).Strings[i]) - 4, 5) <> '|edge' then
          want.Add(TJSONArray(AWant).Strings[i]);
    want.Sort;
    TStringList(AGot).Sort;
    Inc(FCompared);
    if want.Text <> AGot.Text then
    begin
      Inc(FBad);
      if Length(FReport) < 6000 then
        FReport := FReport + LineEnding + ACase.Strings['name'] + ' [' + AWhat
          + ']' + LineEnding + '  upstream: ' + StringReplace(want.Text,
          LineEnding, ' ; ', [rfReplaceAll]) + LineEnding + '  here:     '
          + StringReplace(AGot.Text, LineEnding, ' ; ', [rfReplaceAll]);
    end;
  finally
    want.Free;
  end;
end;

procedure TAdvChartHandlerWiringOracleTest.Run(const APrefix: string;
  AMinimum: Integer);
var
  cases: TJSONArray;
  cs: TJSONObject;
  c, k: Integer;
  skip: Boolean;
  got, tip, after: TStringList;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  got := TStringList.Create;
  tip := TStringList.Create;
  after := TStringList.Create;
  try
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      if Copy(cs.Strings['name'], 1, Length(APrefix)) <> APrefix then Continue;
      skip := False;
      for k := 0 to High(cDeferred) do
        if cs.Strings['name'] = cDeferred[k] then skip := True;
      if skip then Continue;
      Draw(cs);
      got.Clear;
      SceneTexts(got);
      Compare(cs, 'scene', cs.Find('texts'), got);
      if cs.Find('tooltip') is TJSONObject then
      begin
        tip.Clear;
        after.Clear;
        TipTexts(cs, tip, after);
        Compare(cs, 'tooltip', cs.Find('tipTexts'), tip);
        Compare(cs, 'pointer', cs.Find('afterTexts'), after);
      end;
    end;
  finally
    got.Free;
    tip.Free;
    after.Free;
  end;
  AssertTrue(Format('%d of %d differ:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('only %d compared', [FCompared]), FCompared >= AMinimum);
end;

{ ==================== the tests ==================== }

procedure TAdvChartHandlerWiringOracleTest.TestSeriesAndMarkerLabelsAsUpstream;
begin
  Run('label ', 22);
end;

procedure TAdvChartHandlerWiringOracleTest.TestAxisLabelsAsUpstream;
begin
  Run('axisLabel ', 10);
end;

procedure TAdvChartHandlerWiringOracleTest.TestLegendAsUpstream;
begin
  Run('legend ', 2);
end;

procedure TAdvChartHandlerWiringOracleTest.TestTooltipValueFormatterAsUpstream;
begin
  Run('tooltip ', 27);
end;

procedure TAdvChartHandlerWiringOracleTest.TestAxisPointerLabelAsUpstream;
begin
  Run('axisPointer ', 6);
end;

procedure TAdvChartHandlerWiringOracleTest.TestVisualMapAsUpstream;
begin
  Run('visualMap ', 6);
end;

procedure TAdvChartHandlerWiringOracleTest.TestDataZoomAsUpstream;
begin
  Run('dataZoom ', 4);
end;

procedure TAdvChartHandlerWiringOracleTest.TestGaugeRadarCalendarAsUpstream;
begin
  Run('gauge ', 2);
  Run('radar ', 3);
  Run('calendar ', 5);
end;

{ A NAME NOBODY REGISTERED IS SAID, NOT SWALLOWED: the label reads the
  message rather than coming out blank or as the literal '@Name'. }
procedure TAdvChartHandlerWiringOracleTest.TestAnUnregisteredNameSaysSo;
var
  lst: TTyPaintList;
  i, n: Integer;
begin
  FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[1,2],'
    + '"label":{"show":true,"formatter":"@NobodyRegisteredThis"}}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  lst := FChart.List;
  n := 0;
  for i := 0 to lst.Count - 1 do
    if (lst.Element(i).Caption.FontSizeLogical > 0)
      and (Pos('NobodyRegisteredThis', lst.Element(i).Caption.Text) > 0) then
    begin
      Inc(n);
      AssertTrue('not the literal name', lst.Element(i).Caption.Text <> '@NobodyRegisteredThis');
    end;
  AssertEquals('each bar says the name is missing', 2, n);
end;

initialization
  RegisterTest(TAdvChartHandlerWiringOracleTest);
end.
