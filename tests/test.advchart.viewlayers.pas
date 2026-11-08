unit test.advchart.viewlayers;

{ Round 7 R7-AH (spec section 288): THE ROOT'S VIEWS AND THE LAYERS.

  The fixture (tools/advchart-oracle/view-layers.js, the real ECharts 6.1
  dist) records, per case and step, the zrender root's views in order
  (prepareView: a componentsMap key new to the model goes in after every one
  there is, in topological order; a merge's, a timeline frame's, a media
  switch's new models after every view; a replaceMerge's model mapped by
  index brand new), every model's zlevel as allocateZlevels left it (a lines
  series with a trail, a scatter of more rows than its progressiveThreshold:
  a level of its own, what follows it one up -- and written into the
  models, so it stays when the key goes), the painter's layers and their
  motion blur, and the display list as runs of [view, zlevel, z, z2].

  Beside the fixture: a trail under the axes stays under them while it
  plays, a series before the trail's in (zlevel, z) is under the trail, and
  at another PPI the axes' transition frames and the break areas are
  snapped on the css px grid (the 144 PPI ones 1.5 times the 96 PPI ones,
  as a canvas scaled by devicePixelRatio 1.5 draws them), the tooltip's
  position handler is handed css px. }

{$mode objfpc}{$H+}

interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Layout, tyControls.AdvanceChart.Builder,
     tyControls.AdvanceChart.Anim, tyControls.AdvanceChart.AnimView,
     tyControls.AdvanceChart.Handlers, tyControls.AdvanceChart.Geo,
     tyControls.AdvanceChart;
type
  TVlProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Views: TTyStringArray;
    function ZLevelOf(const AKey: string): Integer;
    function ViewOf(const AEl: TTyChartElement): string;
    function Trail(ASeries: Integer): Double;
    function List: TTyPaintList;
    function Titles: TTyOverlayShapeArray;
  end;

  TAdvChartViewLayersOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TVlProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport: string;
    FArgs: array of TTyChartTooltipPosArgs;
    procedure Miss(const AWhat: string);
    procedure NewChart(AW, AH: Integer);
    procedure Paint(APPI: Integer);
    { the case's steps, each record compared by ACheck }
    procedure Replay(const APrefix: string; AWhat: Integer);
    procedure CheckRoots(const AWhere: string; ARec: TJSONObject);
    procedure CheckLevels(const AWhere: string; ARec: TJSONObject);
    procedure CheckOrder(const AWhere: string; ARec: TJSONObject);
    function PosArgs(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheRootsViewsAsUpstream;
    procedure TestTheZLevelsAndTrailLayersAsUpstream;
    procedure TestTheViewsAtOneZAndZ2AsUpstream;
    procedure TestATrailUnderTheAxesStaysUnderThem;
    procedure TestASeriesBeforeTheTrailIsUnderIt;
    procedure TestTheAxesTransitionAtAnotherPPIOnTheCssGrid;
    procedure TestTheBreaksAtAnotherPPIOnTheCssGrid;
    procedure TestThePositionHandlerIsHandedCssPx;
    procedure TestLinesGraphEdgesAndTitleFramesOnTheCssGrid;
    procedure TestAViewWrittenIntoAnElementMovesIt;
  end;

implementation

const
  cT0 = 1700000000000;

function HexD(const S: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + S);
  Move(q, Result, SizeOf(Result));
end;

procedure PinClocks(AChart: TTyCustomAdvanceChart; AAt: Double);
begin
  AChart.AnimNow := AAt;
  AChart.TooltipNow := AAt;
  AChart.DataZoomNow := AAt;
  AChart.BrushNow := AAt;
  AChart.ParallelExpandNow := AAt;
  AChart.TimelineNow := AAt;
end;

procedure TVlProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TVlProbe.Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

function TVlProbe.Views: TTyStringArray;
begin
  Result := ViewOrderNames;
end;

function TVlProbe.ZLevelOf(const AKey: string): Integer;
begin
  Result := ZLevelOfModel(AKey);
end;

function TVlProbe.ViewOf(const AEl: TTyChartElement): string;
begin
  Result := ViewNameOfEl(AEl);
end;

function TVlProbe.Trail(ASeries: Integer): Double;
begin
  Result := TrailAlphaOf(ASeries);
end;

function TVlProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TVlProbe.Titles: TTyOverlayShapeArray;
begin
  Result := TitleFramesDrawn;
end;

procedure TAdvChartViewLayersOracleTest.SetUp;
var sl: TStringList; mp: TJSONArray; k: Integer;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + 'advchart-view-layers.json');
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  mp := TJSONObject(FRoot).Arrays['maps'];
  for k := 0 to mp.Count - 1 do
    TyChartRegisterMap(mp.Objects[k].Strings['name'], mp.Objects[k].Strings['text']);
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartViewLayersOracleTest.TearDown;
begin
  TyChartClearPositionHandlers;
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartViewLayersOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 6000 then FReport := FReport + LineEnding + AWhat;
end;

procedure TAdvChartViewLayersOracleTest.NewChart(AW, AH: Integer);
begin
  FreeAndNil(FChart);
  FreeAndNil(FBmp);
  FChart := TVlProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, AW, AH);
  PinClocks(FChart, cT0);
  FBmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
end;

procedure TAdvChartViewLayersOracleTest.Paint(APPI: Integer);
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), APPI);
end;

procedure TAdvChartViewLayersOracleTest.Replay(const APrefix: string; AWhat: Integer);
var
  cs, steps, recs: TJSONArray;
  c, s: TJSONObject;
  i, j, w, h: Integer;
  id: string;
begin
  cs := TJSONObject(FRoot).Arrays['charts'];
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    if (APrefix <> '') and (Copy(id, 1, Length(APrefix)) <> APrefix) then Continue;
    w := c.Get('w', 400);
    h := c.Get('h', 300);
    NewChart(w, h);
    if c.Get('anim', False) then FChart.AnimationMode := camAlways else FChart.AnimationMode := camOff;
    FChart.SetOption(c.Objects['option'].AsJSON, True);
    AssertEquals(id + ' parses', '', FChart.OptionError);
    Paint(96);
    steps := c.Arrays['steps'];
    recs := c.Arrays['recs'];
    for j := 0 to recs.Count - 1 do
    begin
      if j > 0 then
      begin
        s := steps.Objects[j - 1];
        if s.Find('set') <> nil then
        begin
          if s.Find('opts') <> nil then
            AssertTrue(id + ' sets', FChart.SetOption(s.Objects['set'].AsJSON, s.Objects['opts'].AsJSON))
          else
            AssertTrue(id + ' merges', FChart.SetOption(s.Objects['set'].AsJSON, '{}'));
        end;
        if s.Find('act') <> nil then FChart.DispatchAction(s.Objects['act'].AsJSON);
        if s.Find('size') <> nil then
        begin
          FChart.SetBounds(0, 0, s.Arrays['size'].Integers[0], s.Arrays['size'].Integers[1]);
          FBmp.SetSize(s.Arrays['size'].Integers[0], s.Arrays['size'].Integers[1]);
        end;
        if s.Find('t') <> nil then
        begin
          PinClocks(FChart, cT0 + s.Floats['t']);
          FChart.AnimTick(cT0 + s.Floats['t']);
        end;
        Paint(96);
      end;
      case AWhat of
        0: CheckRoots(Format('%s %d', [id, j]), recs.Objects[j]);
        1: CheckLevels(Format('%s %d', [id, j]), recs.Objects[j]);
      else
        CheckOrder(Format('%s %d', [id, j]), recs.Objects[j]);
      end;
    end;
  end;
end;

procedure TAdvChartViewLayersOracleTest.CheckRoots(const AWhere: string; ARec: TJSONObject);
var
  up: TJSONArray;
  mine: TTyStringArray;
  a, b: TStringList;
  i, k: Integer;
  ga, gb: string;
begin
  up := ARec.Arrays['roots'];
  mine := FChart.Views;
  a := TStringList.Create;
  b := TStringList.Create;
  try
    { the views both have, each list in its own order }
    for i := 0 to up.Count - 1 do
      for k := 0 to High(mine) do
        if mine[k] = up.Strings[i] then a.Add(up.Strings[i]);
    for k := 0 to High(mine) do
      for i := 0 to up.Count - 1 do
        if mine[k] = up.Strings[i] then b.Add(mine[k]);
    Inc(FCompared);
    ga := StringReplace(a.Text, LineEnding, ' ', [rfReplaceAll]);
    gb := StringReplace(b.Text, LineEnding, ' ', [rfReplaceAll]);
    if (a.Count < 2) or (ga <> gb) then
      Miss(Format('%s: the views %s, upstream %s', [AWhere, gb, ga]));
    { every view upstream made is one here (but the preprocessors' axis
      pointer and a grid no option writes, which draw nothing) }
    for i := 0 to up.Count - 1 do
    begin
      if (Copy(up.Strings[i], 1, 11) = 'axisPointer') or (Copy(up.Strings[i], 1, 4) = 'grid') then Continue;
      if a.IndexOf(up.Strings[i]) < 0 then
        Miss(Format('%s: no view %s', [AWhere, up.Strings[i]]));
    end;
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TAdvChartViewLayersOracleTest.CheckLevels(const AWhere: string; ARec: TJSONObject);
const
  cKinds: array[0..13] of string = ('S', 'xAxis', 'yAxis', 'legend', 'title', 'markPoint',
    'markLine', 'markArea', 'timeline', 'visualMap', 'dataZoom', 'toolbox', 'graphic', 'calendar');
var
  zl: TJSONObject;
  lay, l, dl: TJSONArray;
  i, k, want, s: Integer;
  key, kind, v: string;
  ok, seen: Boolean;
  a: Double;
  plist: TTyPaintList;
  el: TTyChartElement;
begin
  zl := ARec.Objects['zl'];
  for i := 0 to zl.Count - 1 do
  begin
    key := zl.Names[i];
    kind := key;
    while (kind <> '') and (kind[Length(kind)] in ['0'..'9']) do SetLength(kind, Length(kind) - 1);
    ok := False;
    for k := 0 to High(cKinds) do if cKinds[k] = kind then ok := True;
    if not ok then Continue;
    if zl.Items[i].JSONType = jtNull then want := 0 else want := zl.Items[i].AsInteger;
    Inc(FCompared);
    if FChart.ZLevelOf(key) <> want then
      Miss(Format('%s: %s on zlevel %d, upstream %d', [AWhere, key, FChart.ZLevelOf(key), want]));
  end;
  { every view's displayables on the zlevels upstream's are on (its
    elements, a marker's of the master model's level) }
  dl := ARec.Arrays['dl'];
  plist := FChart.List;
  if plist <> nil then
    for k := 0 to plist.Count - 1 do
    begin
      el := plist.Element(k);
      v := FChart.ViewOf(el);
      if v = '' then Continue;
      seen := False;
      ok := False;
      for i := 0 to dl.Count - 1 do
        if dl.Arrays[i].Strings[0] = v then
        begin
          seen := True;
          if dl.Arrays[i].Integers[1] = el.ZLevel then ok := True;
        end;
      if not seen then Continue;
      Inc(FCompared);
      if not ok then Miss(Format('%s: an element of %s on zlevel %d, upstream not there', [AWhere, v, el.ZLevel]));
    end;
  { every motion-blurred layer: a trail series on it, its lastFrameAlpha }
  lay := ARec.Arrays['layers'];
  for i := 0 to lay.Count - 1 do
  begin
    l := lay.Arrays[i];
    if not l.Booleans[2] then Continue;
    ok := False;
    a := HexD(l.Strings[3]);
    for s := 0 to 9 do
      if (FChart.Trail(s) > 0) and (FChart.ZLevelOf('S' + IntToStr(s)) = l.Integers[0])
        and (Abs(FChart.Trail(s) - a) < 1e-12) then ok := True;
    Inc(FCompared);
    if not ok then Miss(Format('%s: no trail of alpha %g on zlevel %d', [AWhere, a, l.Integers[0]]));
  end;
  { and every trail the port draws on such a layer }
  for s := 0 to 9 do
  begin
    if FChart.Trail(s) <= 0 then Continue;
    ok := False;
    for i := 0 to lay.Count - 1 do
      if lay.Arrays[i].Booleans[2] and (lay.Arrays[i].Integers[0] = FChart.ZLevelOf('S' + IntToStr(s))) then ok := True;
    Inc(FCompared);
    if not ok then Miss(Format('%s: series %d trails on zlevel %d, upstream no motion blur there',
      [AWhere, s, FChart.ZLevelOf('S' + IntToStr(s))]));
  end;
end;

{ AT ONE zlevel, z AND z2 THE VIEWS IN THE ROOT'S ORDER: of every two views
  both lists draw at a key, the one upstream draws first is first here }
procedure TAdvChartViewLayersOracleTest.CheckOrder(const AWhere: string; ARec: TJSONObject);
var
  dl, rn: TJSONArray;
  upKeys, upViews, myKeys, myViews: TStringList;
  i, a, b, ia, ib: Integer;
  el: TTyChartElement;
  key, v: string;
  L: TTyPaintList;

  procedure Put(AKeys, AViews: TStringList; const AKey, AView: string);
  var q: Integer;
  begin
    for q := 0 to AKeys.Count - 1 do
      if (AKeys[q] = AKey) and (AViews[q] = AView) then Exit;
    AKeys.Add(AKey);
    AViews.Add(AView);
  end;

  function At(AKeys, AViews: TStringList; const AKey, AView: string): Integer;
  var q: Integer;
  begin
    for q := 0 to AKeys.Count - 1 do
      if (AKeys[q] = AKey) and (AViews[q] = AView) then Exit(q);
    Result := -1;
  end;

begin
  upKeys := TStringList.Create;
  upViews := TStringList.Create;
  myKeys := TStringList.Create;
  myViews := TStringList.Create;
  try
    dl := ARec.Arrays['dl'];
    for i := 0 to dl.Count - 1 do
    begin
      rn := dl.Arrays[i];
      Put(upKeys, upViews, Format('%d/%d/%d', [rn.Integers[1], rn.Integers[2], rn.Integers[3]]), rn.Strings[0]);
    end;
    L := FChart.List;
    if L <> nil then
      for i := 0 to L.Count - 1 do
      begin
        el := L.Element(L.PaintOrder(i));
        v := FChart.ViewOf(el);
        if v = '' then Continue;
        Put(myKeys, myViews, Format('%d/%d/%d', [el.ZLevel, el.Z, el.Z2]), v);
      end;
    for a := 0 to upKeys.Count - 1 do
      for b := a + 1 to upKeys.Count - 1 do
      begin
        if upKeys[a] <> upKeys[b] then Continue;
        key := upKeys[a];
        ia := At(myKeys, myViews, key, upViews[a]);
        ib := At(myKeys, myViews, key, upViews[b]);
        if (ia < 0) or (ib < 0) then Continue;
        Inc(FCompared);
        if ia > ib then
          Miss(Format('%s: at %s %s is drawn after %s, upstream before it', [AWhere, key, upViews[a], upViews[b]]));
      end;
  finally
    upKeys.Free;
    upViews.Free;
    myKeys.Free;
    myViews.Free;
  end;
end;

procedure TAdvChartViewLayersOracleTest.TestTheRootsViewsAsUpstream;
begin
  Replay('', 0);
  AssertTrue(Format('compared %d', [FCompared]), FCompared >= 40);
  AssertEquals(Format('%d mismatches over %d:%s', [FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartViewLayersOracleTest.TestTheZLevelsAndTrailLayersAsUpstream;
begin
  Replay('zl-', 1);
  AssertTrue(Format('compared %d', [FCompared]), FCompared >= 60);
  AssertEquals(Format('%d mismatches over %d:%s', [FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartViewLayersOracleTest.TestTheViewsAtOneZAndZ2AsUpstream;
begin
  Replay('vo-', 2);
  AssertTrue(Format('compared %d', [FCompared]), FCompared >= 6);
  AssertEquals(Format('%d mismatches over %d:%s', [FBad, FCompared, FReport]), 0, FBad);
end;

const
  { a trail of lines along y 5, a split line there (interval 5) }
  cTrail = '{"animation":true,"animationDuration":0,"animationDurationUpdate":0,'
    + '"grid":{"left":40,"right":40,"top":40,"bottom":40},'
    + '"xAxis":{"type":"value","min":0,"max":10,"show":false},'
    + '"yAxis":{"type":"value","min":0,"max":10,"interval":5,"axisLabel":{"show":false},'
    + '"axisLine":{"show":false},"axisTick":{"show":false},"splitLine":{"lineStyle":{"color":"#0000ff","width":3}}},'
    + '"series":[%s{"type":"lines","coordinateSystem":"cartesian2d","z":%d,"lineStyle":{"color":"#ff0000","width":1,"opacity":1},'
    + '"effect":{"show":true,"trailLength":0.4,"period":1,"symbol":"circle","symbolSize":12,"delay":0,"color":"#ff0000"},'
    + '"data":[{"coords":[[1,5],[9,5]]}]}]}';

{ A TRAIL UNDER THE AXES: allocateZlevels puts the lines of z -1 on zlevel 0
  and the axes on 1 -- the faded trail is on its own layer under them, the
  split line drawn over it every frame [was: the trail over the axes] }
procedure TAdvChartViewLayersOracleTest.TestATrailUnderTheAxesStaysUnderThem;
var t: Integer; px, off, old, once: TBGRAPixel;
begin
  NewChart(400, 300);
  FChart.AnimationMode := camAlways;
  { (the y axis' line half transparent: drawn once a frame) }
  FChart.SetOption(StringReplace(Format(cTrail, ['', -1]), '"axisLine":{"show":false}',
    '"axisLine":{"show":true,"lineStyle":{"color":"#0000ff","width":3,"opacity":0.5}}', []), True);
  AssertEquals('parses', '', FChart.OptionError);
  FChart.Layered(FBmp.Canvas, Rect(0, 0, 400, 300), 96);
  for t := 1 to 30 do
  begin
    PinClocks(FChart, cT0 + t * 16);
    FChart.AnimTick(cT0 + t * 16);
    FChart.Layered(FBmp.Canvas, Rect(0, 0, 400, 300), 96);
  end;
  if GetEnvironmentVariable('TY_VL_SAVE') <> '' then
    FBmp.SaveToFile(GetEnvironmentVariable('TY_VL_SAVE') + 'trail-under.png');
  { the symbol (from x 72 px at 256 px a second) has passed x 104 px by
    480 ms: on the split line there blue, the trail red beside it }
  px := FBmp.GetPixel(104, 150);
  off := FBmp.GetPixel(104, 150 - 4);
  AssertTrue(Format('the split line over the trail: (%d,%d,%d)', [px.red, px.green, px.blue]),
    (px.blue > 200) and (px.red < 60));
  AssertTrue(Format('the trail beside it: (%d,%d,%d)', [off.red, off.green, off.blue]),
    (off.red > 200) and (off.red - off.blue > 40));
  { the trail's layer fades frame by frame: the newer, nearer the symbol
    (x 180 px, a few frames ago), redder than the older }
  old := FBmp.GetPixel(180, 150 - 4);
  AssertTrue(Format('the older trail lighter: (%d,%d,%d) against the newer (%d,%d,%d)', [off.red, off.green, off.blue,
    old.red, old.green, old.blue]), off.blue > old.blue + 60);
  { the axis line, at half its opacity over white: once }
  once := FBmp.GetPixel(40, 100);
  AssertTrue(Format('the axis line drawn once: (%d,%d,%d)', [once.red, once.green, once.blue]),
    (once.red > 100) and (once.red < 160) and (once.blue > 240));
  AssertEquals('the lines on zlevel 0', 0, FChart.ZLevelOf('S0'));
  AssertEquals('the axes on zlevel 1', 1, FChart.ZLevelOf('yAxis0'));
end;

{ A SERIES BEFORE THE TRAIL'S IN (zlevel, z): its own zlevel under the trail's
  -- the effect symbol passing over its symbol is drawn over it [was: the
  scatter's symbol (z2 100, after the lines' line) over the trail layer] }
procedure TAdvChartViewLayersOracleTest.TestASeriesBeforeTheTrailIsUnderIt;
var t: Integer; px: TBGRAPixel;
begin
  NewChart(400, 300);
  FChart.AnimationMode := camAlways;
  FChart.SetOption(Format(cTrail, ['{"type":"scatter","symbolSize":30,"itemStyle":{"color":"#00ff00"},"data":[[5,6]]},', 2]), True);
  AssertEquals('parses', '', FChart.OptionError);
  FChart.Layered(FBmp.Canvas, Rect(0, 0, 400, 300), 96);
  { the symbol at x 5 (200 px) at 500 ms, over the scatter's at (200, 138) }
  for t := 1 to 31 do
  begin
    PinClocks(FChart, cT0 + t * 16);
    FChart.AnimTick(cT0 + t * 16);
    FChart.Layered(FBmp.Canvas, Rect(0, 0, 400, 300), 96);
  end;
  px := FBmp.GetPixel(200, 146);
  AssertTrue(Format('the trail over the scatter: (%d,%d,%d)', [px.red, px.green, px.blue]),
    (px.red > 120) and (px.green < 200));
  AssertEquals('the scatter on zlevel 0', 0, FChart.ZLevelOf('S0'));
  AssertEquals('the lines on zlevel 1', 1, FChart.ZLevelOf('S1'));
end;

{ THE AXES' groupTransition AT 144 PPI: every leaf's frame 1.5 times the one
  at 96, its ends snapped on the css px grid [was: the device px grid] }
procedure TAdvChartViewLayersOracleTest.TestTheAxesTransitionAtAnotherPPIOnTheCssGrid;
const
  cOpt = '{"animation":true,"animationDurationUpdate":1000,"animationEasingUpdate":"linear",'
    + '"grid":{"left":43.3,"right":40,"top":41.7,"bottom":40},'
    + '"xAxis":{"type":"value","min":0,"max":%d,"interval":2.5},'
    + '"yAxis":{"type":"value","min":0,"max":%d,"interval":2.5},'
    + '"series":[{"type":"scatter","data":[[1,1]]}]}';
  cAnids: array[0..7] of string = ('line', 'ticks_0', 'ticks_2.5', 'ticks_5', 'line_0', 'line_2.5', 'line_5',
    'line_7.5');
  cProps: array[0..3] of string = ('shape.x1', 'shape.y1', 'shape.x2', 'shape.y2');
var
  vals: array[0..1] of array of Double;
  ppi, a, k, n, q: Integer;
  p: TTyChartAnimProxy;
  v: TTyAnimValue;
  ax: string;
  worst: Double;
  s: string;
begin
  for ppi := 0 to 1 do
  begin
    if ppi = 0 then NewChart(400, 300) else NewChart(600, 450);
    FChart.AnimationMode := camAlways;
    FChart.SetOption(Format(cOpt, [10, 10]), True);
    if ppi = 0 then FChart.Render(FBmp.Canvas, Rect(0, 0, 400, 300), 96)
    else FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 450), 144);
    PinClocks(FChart, cT0 + 5000);
    FChart.AnimTick(cT0 + 5000);
    FChart.SetOption(Format(cOpt, [15, 15]), False);
    if ppi = 0 then FChart.Render(FBmp.Canvas, Rect(0, 0, 400, 300), 96)
    else FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 450), 144);
    PinClocks(FChart, cT0 + 5400);
    FChart.AnimTick(cT0 + 5400);
    if ppi = 0 then FChart.Render(FBmp.Canvas, Rect(0, 0, 400, 300), 96)
    else FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 450), 144);
    vals[ppi] := nil;
    n := 0;
    for a := 0 to 1 do
    begin
      if a = 0 then ax := 'xAxis0' else ax := 'yAxis0';
      for k := 0 to High(cAnids) do
      begin
        p := FChart.AnimAxisProxy(ax, cAnids[k]);
        AssertTrue(Format('%d PPI %s %s: a proxy', [96 + 48 * ppi, ax, cAnids[k]]), p <> nil);
        for q := 0 to High(cProps) do
        begin
          v := p.GetAnimProp(cProps[q]);
          AssertTrue(Format('%s %s %s: a number', [ax, cAnids[k], cProps[q]]), v.Kind = avkNumber);
          SetLength(vals[ppi], n + 1);
          vals[ppi][n] := v.Num;
          Inc(n);
        end;
      end;
    end;
  end;
  worst := 0;
  s := '';
  for k := 0 to High(vals[0]) do
    if Abs(vals[1][k] - 1.5 * vals[0][k]) > worst then
    begin
      worst := Abs(vals[1][k] - 1.5 * vals[0][k]);
      s := Format(' (%s %s: %g at 144, %g at 96)', [cAnids[(k div 4) mod Length(cAnids)],
        cProps[k mod 4], vals[1][k], vals[0][k]]);
    end;
  AssertTrue('the transition at 144 PPI is the one at 96 times 1.5, off by ' + FloatToStr(worst) + s,
    worst < 1e-9);
end;

{ THE BREAK AREAS AND THE CUT AXIS LINE AT 144 PPI: 1.5 times the ones at 96
  -- the zigzag's amplitude and spans in css px, its ends and the line's on
  the css px grid [was: device px] }
procedure TAdvChartViewLayersOracleTest.TestTheBreaksAtAnotherPPIOnTheCssGrid;
const
  cOpt = '{"animation":false,"grid":{"left":43.3,"right":40,"top":41.7,"bottom":40},'
    + '"xAxis":{"type":"category","data":["a","b","c","d","e"]},'
    + '"yAxis":{"type":"value","breaks":[{"start":30,"end":800,"gap":"7%"}]},'
    + '"series":[{"type":"bar","data":[10,20,900,950,1000]}]}';
var
  pts: array[0..1] of array of Double;
  ppi, k, q, n: Integer;
  spec: PTyAxisLayoutSpec;
  worst: Double;

  procedure Add(V: Double);
  begin
    SetLength(pts[ppi], n + 1);
    pts[ppi][n] := V;
    Inc(n);
  end;

begin
  for ppi := 0 to 1 do
  begin
    if ppi = 0 then NewChart(400, 300) else NewChart(600, 450);
    FChart.SetOption(cOpt, True);
    AssertEquals('parses', '', FChart.OptionError);
    if ppi = 0 then FChart.Render(FBmp.Canvas, Rect(0, 0, 400, 300), 96)
    else FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 450), 144);
    spec := FChart.Build.Grid(0).SpecFor(FChart.Build.Grid(0).YAxis(0));
    AssertTrue('a spec', spec <> nil);
    AssertTrue('a break area', Length(spec^.BreakAreas) > 0);
    AssertTrue('a cut line', Length(spec^.BreakLineSegs) > 1);
    pts[ppi] := nil;
    n := 0;
    for k := 0 to High(spec^.BreakAreas) do
    begin
      for q := 0 to High(spec^.BreakAreas[k].A) do
      begin
        Add(spec^.BreakAreas[k].A[q].X);
        Add(spec^.BreakAreas[k].A[q].Y);
      end;
      for q := 0 to High(spec^.BreakAreas[k].B) do
      begin
        Add(spec^.BreakAreas[k].B[q].X);
        Add(spec^.BreakAreas[k].B[q].Y);
      end;
    end;
    for k := 0 to High(spec^.BreakLineSegs) do
    begin
      Add(spec^.BreakLineSegs[k].X1);
      Add(spec^.BreakLineSegs[k].Y1);
      Add(spec^.BreakLineSegs[k].X2);
      Add(spec^.BreakLineSegs[k].Y2);
    end;
  end;
  AssertEquals('as many points', Length(pts[0]), Length(pts[1]));
  worst := 0;
  for k := 0 to High(pts[0]) do worst := Max(worst, Abs(pts[1][k] - 1.5 * pts[0][k]));
  AssertTrue('the breaks at 144 PPI are the ones at 96 times 1.5, off by ' + FloatToStr(worst), worst < 1e-9);
end;

function TAdvChartViewLayersOracleTest.PosArgs(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
begin
  SetLength(FArgs, Length(FArgs) + 1);
  FArgs[High(FArgs)] := AArgs;
  Result := Default(TTyChartTooltipPos);
  Result.Kind := ctpPoint;
  Result.X := TyChartPosNum(100);
  Result.Y := TyChartPosNum(60);
end;

{ THE POSITION HANDLER'S ARGUMENTS AT 144 PPI: the point, the element's
  rect, the view's and the content's sizes in css px, as at 96 [R7-AG made
  them so; no test held it] }
procedure TAdvChartViewLayersOracleTest.TestThePositionHandlerIsHandedCssPx;
const
  cOpt = '{"animation":false,"grid":{"left":40,"right":40,"top":40,"bottom":40},'
    + '"xAxis":{"type":"value","min":0,"max":10},"yAxis":{"type":"value","min":0,"max":10},'
    + '"tooltip":{"renderMode":"richText","showDelay":0,"transitionDuration":0,"position":"@vlPos"},'
    + '"series":[{"type":"scatter","name":"S","symbolSize":20,"data":[[3,7]]}]}';
var
  ppi: Integer;
  got: array[0..1] of TTyChartTooltipPosArgs;
begin
  TyChartRegisterPositionHandler('vlPos', @PosArgs);
  for ppi := 0 to 1 do
  begin
    FArgs := nil;
    if ppi = 0 then NewChart(400, 300) else NewChart(600, 450);
    FChart.SetOption(cOpt, True);
    AssertEquals('parses', '', FChart.OptionError);
    if ppi = 0 then FChart.Render(FBmp.Canvas, Rect(0, 0, 400, 300), 96)
    else FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 450), 144);
    FChart.DispatchAction('{"type":"showTip","seriesIndex":0,"dataIndex":0}');
    if ppi = 0 then FChart.Render(FBmp.Canvas, Rect(0, 0, 400, 300), 96)
    else FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 450), 144);
    AssertTrue(Format('%d PPI: the handler called', [96 + 48 * ppi]), Length(FArgs) > 0);
    got[ppi] := FArgs[High(FArgs)];
  end;
  AssertEquals('the point x', got[0].PointX, got[1].PointX, 0.01);
  AssertEquals('the point y', got[0].PointY, got[1].PointY, 0.01);
  AssertTrue('a rect at both', got[0].HasRect and got[1].HasRect);
  AssertEquals('the rect x', got[0].RectX, got[1].RectX, 0.01);
  AssertEquals('the rect y', got[0].RectY, got[1].RectY, 0.01);
  AssertEquals('the rect width', got[0].RectW, got[1].RectW, 0.01);
  AssertEquals('the rect height', got[0].RectH, got[1].RectH, 0.01);
  AssertEquals('the view width', got[0].ViewW, got[1].ViewW, 0.01);
  AssertEquals('the view height', got[0].ViewH, got[1].ViewH, 0.01);
  AssertEquals('the view in css px', 400, got[1].ViewW, 0.01);
  { (the content measured in each PPI's fonts: to a pixel and a half) }
  AssertEquals('the content width', got[0].ContentW, got[1].ContentW, 1.5);
  AssertEquals('the content height', got[0].ContentH, got[1].ContentH, 1.5);
end;

{ A LINES ROW'S STRAIGHT LINE, A GRAPH'S STRAIGHT EDGE ON AXES, A TITLE'S
  FRAME AT 144 PPI: 1.5 times the ones at 96 -- subPixelOptimize on the css
  px grid [was: the device px grid] }
procedure TAdvChartViewLayersOracleTest.TestLinesGraphEdgesAndTitleFramesOnTheCssGrid;
const
  cAxes = '"grid":{"left":43.3,"right":40,"top":41.7,"bottom":40},'
    + '"xAxis":{"type":"value","min":0,"max":10,"show":false},"yAxis":{"type":"value","min":0,"max":10,"show":false},';
var bad: string;

  procedure Render(APPI: Integer; const AOpt: string);
  begin
    if APPI = 96 then NewChart(400, 300) else NewChart(600, 450);
    FChart.SetOption(AOpt, True);
    AssertEquals('parses', '', FChart.OptionError);
    FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), APPI);
  end;

  { every element of the list but a text: 1.5 times }
  procedure One(const AName, AOpt: string);
  var ppi, k, n: Integer; el: TTyChartElement; bb: TTyRectF;
    boxes: array[0..1] of array of TTyRectF; worst: Double;
  begin
    for ppi := 0 to 1 do
    begin
      Render(96 + 48 * ppi, AOpt);
      boxes[ppi] := nil;
      for k := 0 to FChart.List.Count - 1 do
      begin
        el := FChart.List.Element(k);
        if (el.Caption.FontSizeLogical <> 0) or el.Ignore then Continue;
        bb := TyShapeBounds(el.Shape);
        if not TyRectFIsValid(bb) then Continue;
        n := Length(boxes[ppi]);
        SetLength(boxes[ppi], n + 1);
        boxes[ppi][n] := bb;
      end;
    end;
    worst := 0;
    if (Length(boxes[0]) = 0) or (Length(boxes[0]) <> Length(boxes[1])) then worst := 1e9
    else
      for k := 0 to High(boxes[0]) do
      begin
        worst := Max(worst, Abs(boxes[1][k].Left - 1.5 * boxes[0][k].Left));
        worst := Max(worst, Abs(boxes[1][k].Right - 1.5 * boxes[0][k].Right));
        worst := Max(worst, Abs(boxes[1][k].Top - 1.5 * boxes[0][k].Top));
        worst := Max(worst, Abs(boxes[1][k].Bottom - 1.5 * boxes[0][k].Bottom));
      end;
    if worst > 1e-6 then bad := bad + LineEnding + Format('%s: off by %g', [AName, worst]);
  end;

var
  ppi: Integer;
  fr: array[0..1] of TTyRectF;
  t: TTyOverlayShapeArray;
begin
  bad := '';
  One('a lines row', '{"animation":false,' + cAxes + '"series":[{"type":"lines","coordinateSystem":"cartesian2d",'
    + '"lineStyle":{"width":1,"color":"#000000","opacity":1},"data":[{"coords":[[1,5.13],[9,5.13]]}]}]}');
  One('a graph edge on axes', '{"animation":false,' + cAxes + '"series":[{"type":"graph","coordinateSystem":"cartesian2d",'
    + '"symbolSize":0,"data":[[1,5.13],[9,5.13]],"links":[{"source":0,"target":1}],"lineStyle":{"width":1,"color":"#000000","opacity":1}}]}');
  for ppi := 0 to 1 do
  begin
    Render(96 + 48 * ppi, '{"animation":false,"title":{"text":"T","left":43.3,"top":41.7,'
      + '"borderWidth":1,"borderColor":"#000000"}}');
    t := FChart.Titles;
    AssertTrue('a title frame', Length(t) > 0);
    fr[ppi] := TyShapeBounds(t[0].El.Shape);
  end;
  if (Abs(fr[1].Left - 1.5 * fr[0].Left) > 1e-6) or (Abs(fr[1].Top - 1.5 * fr[0].Top) > 1e-6) then
    bad := bad + LineEnding + Format('the title frame: (%g, %g) at 144, (%g, %g) at 96',
      [fr[1].Left, fr[1].Top, fr[0].Left, fr[0].Top]);
  AssertEquals('at 144 PPI 1.5 times the 96 PPI ones:' + bad, '', bad);
end;

{ THE VIEW'S PLACE IS A KEY OF THE ORDER: written into an element of a list
  already sorted (SetElement), the order is worked out again }
procedure TAdvChartViewLayersOracleTest.TestAViewWrittenIntoAnElementMovesIt;
var
  L: TTyPaintList;
  el: TTyChartElement;
  i: Integer;
begin
  L := TTyPaintList.Create;
  try
    for i := 0 to 2 do
    begin
      el := Default(TTyChartElement);
      el.Datum := TyChartNoDatum;
      el.Z := 4;
      el.CompView := 3 - i;
      el.ViewKnown := True;
      L.Add(el);
    end;
    AssertEquals('the view first in the root first', 2, L.PaintOrder(0));
    AssertEquals('the view last in the root last', 0, L.PaintOrder(2));
    el := L.Element(0);
    el.CompView := 0;
    L.SetElement(0, el);
    AssertEquals('its view now first: drawn first', 0, L.PaintOrder(0));
    AssertEquals('then the others in their views'' order', 2, L.PaintOrder(1));
  finally
    L.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartViewLayersOracleTest);
end.
