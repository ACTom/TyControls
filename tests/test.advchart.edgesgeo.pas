unit test.advchart.edgesgeo;
{$mode objfpc}{$H+}
{ R5-G EDGES, THE GEO AND MERGE SIDE [spec 244].

  tools/advchart-oracle/edges-geo.js records, on ECharts 6.1, what an export
  with `excludeComponents: ['geo']` hides: the geo components' views (their
  regions and labels, a map series' data drawn on one with them), never a
  map series' own geo nor the series on a geo. tools/advchart-oracle/
  edges-merge.js records the markPoint / markLine / markArea models the
  marker preprocessors make for an option whose series write one -- their
  ids and names after each setOption, merge, notMerge, timeline frame and
  media unit.

  By hand: an SVG map's <image> of any source draws through the chart's
  image resolver (OnResolveImage), not only a data: URI. The map series'
  symbol labels and the echartsStyle of several regions of one name are in
  the geo-series fixture (TAdvChartGeoSeriesOracleTest). }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Export, tyControls.AdvanceChart.Geo,
     tyControls.AdvanceChart;
type
  TEgProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Views: TTyChartViews;
    function List: TTyPaintList;
    procedure Resolve(Sender: TObject; const AUrl: string; var AImage: TBGRABitmap);
  end;

  TAdvChartEdgesGeoOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TEgProbe;
    FBad, FCompared: Integer;
    FReport: string;
    procedure Bad(const AWhat: string);
    procedure NewChart(AW, AH: Integer);
    function Fixture(const AName: string): TJSONData;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestExcludingGeoHidesItsViewsAsUpstream;
    procedure TestTheMarkerModelsAreUpstreams;
  end;

  TAdvChartEdgesGeoTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TEgProbe;
    function RedPixels(AOption: string): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAnSvgImageDrawsThroughTheResolver;
    procedure TestExcludingGeoTakesItsPixelsOnly;
    procedure TestASymbolLabelHangsByItsPosition;
  end;

implementation

const
  cSvgImage = '<svg width="200" height="100">'
    + '<rect name="A" x="0" y="0" width="200" height="100" fill="#ffffff"/>'
    + '<image href="x://pic" x="20" y="20" width="60" height="40"/></svg>';
  cSvgUnknown = '<svg width="200" height="100">'
    + '<rect name="A" x="0" y="0" width="200" height="100" fill="#ffffff"/>'
    + '<image href="x://nobody" x="20" y="20" width="60" height="40"/></svg>';

procedure TEgProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TEgProbe.Views: TTyChartViews;
begin
  Result := LastViewsDrawn;
end;

function TEgProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TEgProbe.Resolve(Sender: TObject; const AUrl: string; var AImage: TBGRABitmap);
begin
  if AUrl = 'x://pic' then AImage := TBGRABitmap.Create(6, 4, BGRA(255, 0, 0, 255));
end;

function LoadText(const APath: string): string;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(APath);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

{ ==================== the oracle ==================== }

procedure TAdvChartEdgesGeoOracleTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartEdgesGeoOracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartEdgesGeoOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then FReport := FReport + LineEnding + '  ' + AWhat;
end;

procedure TAdvChartEdgesGeoOracleTest.NewChart(AW, AH: Integer);
begin
  FreeAndNil(FChart);
  FChart := TEgProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, AW, AH);
end;

function TAdvChartEdgesGeoOracleTest.Fixture(const AName: string): TJSONData;
var fn: string;
begin
  fn := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
  AssertTrue('the fixture is where the suite expects it: ' + AName, FileExists(fn));
  Result := GetJSON(LoadText(fn));
end;

{ the views an export draws with the opts upstream's getDataURL had: the
  main types present (drew and not hidden) as upstream's, sorted }
procedure TAdvChartEdgesGeoOracleTest.TestExcludingGeoHidesItsViewsAsUpstream;
var
  root: TJSONData;
  maps, arr, pres: TJSONArray;
  i, k: Integer;
  c: TJSONObject;
  opts, want, got: string;
  bmp: TBGRABitmap;
begin
  root := Fixture('advchart-edges-geo.json');
  try
    maps := TJSONObject(root).Arrays['maps'];
    for i := 0 to maps.Count - 1 do
      AssertTrue('registered', TyChartRegisterMap(maps.Objects[i].Strings['name'],
        maps.Objects[i].Strings['text']));
    arr := TJSONObject(root).Arrays['exports'];
    AssertTrue('cases', arr.Count >= 5);
    for i := 0 to arr.Count - 1 do
    begin
      c := arr.Objects[i];
      NewChart(c.Integers['W'], c.Integers['H']);
      FChart.Option := c.Objects['option'].AsJSON;
      if c.Find('opts').JSONType = jtNull then opts := '' else opts := c.Objects['opts'].AsJSON;
      pres := c.Arrays['present'];
      { the port's present set: the views it drew, minus the ones whose
        upstream view holds nothing the port draws (axisPointer) }
      want := '';
      for k := 0 to pres.Count - 1 do
      begin
        if want <> '' then want := want + ',';
        want := want + pres.Strings[k];
      end;
      bmp := FChart.RenderToBitmap(opts);
      try
        got := TyChartViewsText(FChart.Views);
      finally
        bmp.Free;
      end;
      Inc(FCompared);
      if got <> want then Bad(c.Strings['id'] + ': drew ' + got + ', upstream ' + want);
    end;
  finally
    root.Free;
  end;
  AssertTrue('compared', FCompared >= 5);
  AssertEquals('excludeComponents geo: ' + IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' differ:' + FReport, 0, FBad);
end;

{ every slot of markPoint, markLine, markArea, grid and axisPointer after
  every step: the model's id, name and subType, '' past the last }
procedure TAdvChartEdgesGeoOracleTest.TestTheMarkerModelsAreUpstreams;
const
  cTypes: array[0..4] of string = ('markPoint', 'markLine', 'markArea', 'grid', 'axisPointer');
var
  root: TJSONData;
  cases, steps, states, slots: TJSONArray;
  ci, si, t, k: Integer;
  c, st, step, m: TJSONObject;
  where: string;

  procedure Same(const AWhat, AGot, AWant: string);
  begin
    Inc(FCompared);
    { fpjson drops a \u0000 as it reads the fixture: both sides without it }
    if StringReplace(AGot, #0, '', [rfReplaceAll]) <> AWant then
      Bad(where + ' ' + AWhat + ': ' + StringReplace(AGot, #0, '~', [rfReplaceAll])
        + ', upstream ' + AWant);
  end;

begin
  root := Fixture('advchart-edges-merge.json');
  try
    cases := TJSONObject(root).Arrays['cases'];
    AssertTrue('cases', cases.Count >= 7);
    for ci := 0 to cases.Count - 1 do
    begin
      c := cases.Objects[ci];
      NewChart(c.Integers['W'], c.Integers['H']);
      steps := c.Arrays['steps'];
      states := c.Arrays['states'];
      for si := 0 to steps.Count - 1 do
      begin
        step := steps.Objects[si];
        where := Format('%s step %d', [c.Strings['id'], si]);
        if step.Find('set') <> nil then
          FChart.SetOption(step.Objects['set'].AsJSON,
            (step.Find('notMerge') <> nil) and step.Booleans['notMerge'])
        else
          FChart.DispatchAction(step.Objects['action'].AsJSON);
        st := states.Objects[si];
        for t := 0 to High(cTypes) do
        begin
          slots := st.Arrays[cTypes[t]];
          for k := 0 to slots.Count - 1 do
          begin
            if slots.Items[k].JSONType = jtNull then
            begin
              Same(Format('%s %d id', [cTypes[t], k]), FChart.ComponentModelId(cTypes[t], k), '');
              Continue;
            end;
            m := slots.Objects[k];
            Same(Format('%s %d id', [cTypes[t], k]), FChart.ComponentModelId(cTypes[t], k), m.Strings['id']);
            Same(Format('%s %d name', [cTypes[t], k]), FChart.ComponentModelName(cTypes[t], k), m.Strings['name']);
            Same(Format('%s %d sub', [cTypes[t], k]), FChart.ComponentModelSubType(cTypes[t], k), m.Strings['sub']);
          end;
          Same(Format('%s %d (past the last)', [cTypes[t], slots.Count]),
            FChart.ComponentModelId(cTypes[t], slots.Count), '');
        end;
      end;
    end;
  finally
    root.Free;
  end;
  AssertTrue('compared', FCompared >= 150);
  AssertEquals('marker models: ' + IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' differ:' + FReport, 0, FBad);
end;

{ ==================== by hand ==================== }

procedure TAdvChartEdgesGeoTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TEgProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, 400, 300);
  FChart.OnResolveImage := @FChart.Resolve;
end;

procedure TAdvChartEdgesGeoTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TAdvChartEdgesGeoTest.RedPixels(AOption: string): Integer;
var
  bmp: TBGRABitmap;
  p: PBGRAPixel;
  i: Integer;
begin
  FChart.Option := AOption;
  bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    Result := 0;
    p := bmp.Data;
    for i := 0 to bmp.NbPixels - 1 do
    begin
      if (p^.red > 200) and (p^.green < 60) and (p^.blue < 60) then Inc(Result);
      Inc(p);
    end;
  finally
    bmp.Free;
  end;
end;

{ an <image> whose href is no data: URI draws what OnResolveImage answers
  for it (upstream's picture once the browser has loaded it); a URL nobody
  answers draws nothing and does not fail }
procedure TAdvChartEdgesGeoTest.TestAnSvgImageDrawsThroughTheResolver;
var n, k: Integer; found: Boolean;
begin
  AssertTrue(TyChartRegisterMap('r5g-img', cSvgImage));
  AssertTrue(TyChartRegisterMap('r5g-noimg', cSvgUnknown));
  n := RedPixels('{"animation":false,"geo":{"map":"r5g-img"}}');
  { the image is 60 x 40 SVG units in a 200 x 100 map laid into 80% of the
    chart: hundreds of pixels }
  AssertTrue('the resolved picture is drawn: ' + IntToStr(n) + ' red pixels', n > 400);
  found := False;
  for k := 0 to FChart.List.Count - 1 do
    if FChart.List.Element(k).Style.FillPattern.Image = 'x://pic' then found := True;
  AssertTrue('the image element carries its source', found);
  n := RedPixels('{"animation":false,"geo":{"map":"r5g-noimg"}}');
  AssertEquals('a source nobody answers draws nothing', 0, n);
end;

{ the export without the geo loses the regions' ink and keeps the scatter's }
procedure TAdvChartEdgesGeoTest.TestExcludingGeoTakesItsPixelsOnly;
const
  cOpt = '{"animation":false,"geo":{"map":"r5g-sq","itemStyle":{"areaColor":"#ff0000"}},'
    + '"series":[{"type":"scatter","coordinateSystem":"geo","symbolSize":30,'
    + '"itemStyle":{"color":"#0000ff","opacity":1},"data":[[5,5]]}]}';
  cSq = '{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"name":"A"},'
    + '"geometry":{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}}]}';

  function Count(ABmp: TBGRABitmap; ARed: Boolean): Integer;
  var p: PBGRAPixel; i: Integer;
  begin
    Result := 0;
    p := ABmp.Data;
    for i := 0 to ABmp.NbPixels - 1 do
    begin
      if ARed and (p^.red > 200) and (p^.green < 60) and (p^.blue < 60) and (p^.alpha > 200) then Inc(Result);
      if (not ARed) and (p^.blue > 200) and (p^.green < 60) and (p^.red < 60) and (p^.alpha > 200) then Inc(Result);
      Inc(p);
    end;
  end;

var a, b: TBGRABitmap;
begin
  AssertTrue(TyChartRegisterMap('r5g-sq', cSq));
  FChart.Option := cOpt;
  a := FChart.RenderToBitmap('');
  b := FChart.RenderToBitmap('{"excludeComponents":["geo"]}');
  try
    AssertTrue('the regions are drawn', Count(a, True) > 1000);
    AssertEquals('excluded, the regions are not', 0, Count(b, True));
    AssertTrue('the scatter is drawn', Count(a, False) > 100);
    AssertEquals('and stays', Count(a, False), Count(b, False));
  finally
    a.Free;
    b.Free;
  end;
end;

{ a map series' symbol label hangs off its anchor as zrender's position
  table pins it: 'top' (and 'outside') by its bottom centre, 'right' by its
  left middle, 'inside' by its centre, no position at 'bottom' by its top
  centre -- the element's box agrees with the caption }
procedure TAdvChartEdgesGeoTest.TestASymbolLabelHangsByItsPosition;
const
  cSq = '{"type":"FeatureCollection","features":['
    + '{"type":"Feature","properties":{"name":"A"},"geometry":{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}},'
    + '{"type":"Feature","properties":{"name":"B"},"geometry":{"type":"Polygon","coordinates":[[[10,0],[20,0],[20,10],[10,10],[10,0]]]}},'
    + '{"type":"Feature","properties":{"name":"C"},"geometry":{"type":"Polygon","coordinates":[[[0,10],[10,10],[10,20],[0,20],[0,10]]]}},'
    + '{"type":"Feature","properties":{"name":"D"},"geometry":{"type":"Polygon","coordinates":[[[10,10],[20,10],[20,20],[10,20],[10,10]]]}}]}';
  cOpt = '{"animation":false,"legend":{},"series":[{"type":"map","map":"r5g-sq4","name":"a",'
    + '"label":{"show":true},"data":[{"name":"A","value":1,"label":{"position":"top"}},'
    + '{"name":"B","value":2,"label":{"position":"right"}},{"name":"C","value":3,"label":{"position":"outside"}},'
    + '{"name":"D","value":4,"label":{"position":"inside"}}]},'
    + '{"type":"map","map":"r5g-sq4","name":"b","label":{"show":true},"data":[{"name":"A","value":5}]}]}';
  cH: array[0..3] of TTyTextAnchorH = (tahCentre, tahLeft, tahCentre, tahCentre);
  cV: array[0..3] of TTyTextAnchorV = (tavBottom, tavMiddle, tavBottom, tavMiddle);
var
  start, count, k, n: Integer;
  el: TTyChartElement;
  bmp: TBGRABitmap;
begin
  AssertTrue(TyChartRegisterMap('r5g-sq4', cSq));
  FChart.Option := cOpt;
  bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
  finally
    bmp.Free;
  end;
  AssertTrue('series a has symbols', FChart.MapSymbolRange(0, start, count));
  n := 0;
  for k := start to start + count - 1 do
  begin
    el := FChart.List.Element(k);
    if el.Caption.FontSizeLogical <= 0 then Continue;
    AssertTrue('four labels', n <= 3);
    AssertEquals(Format('label %d anchor h', [n]), Ord(cH[n]), Ord(el.Caption.AnchorH));
    AssertEquals(Format('label %d anchor v', [n]), Ord(cV[n]), Ord(el.Caption.AnchorV));
    Inc(n);
  end;
  AssertEquals('four labels', 4, n);
end;

initialization
  RegisterTest(TAdvChartEdgesGeoOracleTest);
  RegisterTest(TAdvChartEdgesGeoTest);
end.
