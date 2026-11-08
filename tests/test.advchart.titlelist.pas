unit test.advchart.titlelist;

{ Round 7 R7-AJ (spec section 290): THE TITLE IN THE LIST.

  Upstream's TitleView adds the text and the subtext (z2 10) and the
  background Rect (z2 0) to its group, every one at the title's z and
  zlevel (updateZ): zrender sorts them with every other displayable by
  zlevel, z, z2 and the root's order. The port drew the title after the
  whole list, the break areas and the parallel axes, whatever its z -- so a
  thumbnail (z 10), a brush's cover (z 10000), a toolbox icon at the title's
  z (its view after the title's: over the frame, under the text), a title of
  z -1 under the axes, all drew the other way round.

  The fixture (tools/advchart-oracle/view-layers.js, the `vo-title-` cases,
  the real ECharts 6.1 dist) records the display list as runs of [view,
  zlevel, z, z2]: the title's runs are compared with every other run there,
  in order. Beside it, the pixels: what lies over the title is drawn over
  it, and the title is drawn once on every path (the static layer, a frame
  in motion, the continuous phase, the dirty rects, an export). }

{$mode objfpc}{$H+}

interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser, base64,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Geo,
     tyControls.AdvanceChart;
type
  TTlProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function ViewOf(const AEl: TTyChartElement): string;
    function List: TTyPaintList;
    function Titles: TTyOverlayShapeArray;
    procedure Hover(AX, AY: Integer);
  end;

  TAdvChartTitleListTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTlProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport: string;
    procedure Miss(const AWhat: string);
    procedure NewChart(AW, AH: Integer);
    procedure Paint;
    procedure CheckRuns(const AWhere: string; ARec: TJSONObject);
    function Px(AX, AY: Integer): TBGRAPixel;
    procedure Save(const AName: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheTitleAmongTheListAsUpstream;
    procedure TestAThumbnailIsOverTheTitle;
    procedure TestABrushCoverIsOverTheTitle;
    procedure TestAToolboxIconIsBetweenTheFrameAndTheText;
    procedure TestATitleUnderTheAxesIsUnderTheirLines;
    procedure TestATitleOnALowerZLevelIsUnderTheAxes;
    procedure TestATitleOfAHigherZIsOverALegend;
    procedure TestTheTitleIsDrawnOnceOnEveryPath;
    procedure TestTheTitleAloneAsBefore;
    procedure TestSeveralLinesAlignedAsBefore;
    procedure TestARefusedBoxFillIsWhatTheListHandsIt;
  end;

implementation

const
  cT0 = 1700000000000;

procedure PinClocks(AChart: TTyCustomAdvanceChart; AAt: Double);
begin
  AChart.AnimNow := AAt;
  AChart.TooltipNow := AAt;
  AChart.DataZoomNow := AAt;
  AChart.BrushNow := AAt;
  AChart.ParallelExpandNow := AAt;
  AChart.TimelineNow := AAt;
end;

procedure TTlProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTlProbe.Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

function TTlProbe.ViewOf(const AEl: TTyChartElement): string;
begin
  Result := ViewNameOfEl(AEl);
end;

function TTlProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TTlProbe.Titles: TTyOverlayShapeArray;
begin
  Result := TitleFramesDrawn;
end;

procedure TTlProbe.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TAdvChartTitleListTest.SetUp;
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

procedure TAdvChartTitleListTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartTitleListTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 6000 then FReport := FReport + LineEnding + AWhat;
end;

procedure TAdvChartTitleListTest.NewChart(AW, AH: Integer);
begin
  FreeAndNil(FChart);
  FreeAndNil(FBmp);
  FChart := TTlProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, AW, AH);
  PinClocks(FChart, cT0);
  FBmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
end;

procedure TAdvChartTitleListTest.Paint;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
end;

function TAdvChartTitleListTest.Px(AX, AY: Integer): TBGRAPixel;
begin
  Result := FBmp.GetPixel(AX, AY);
end;

procedure TAdvChartTitleListTest.Save(const AName: string);
begin
  if GetEnvironmentVariable('TY_TL_SAVE') <> '' then
    FBmp.SaveToFile(GetEnvironmentVariable('TY_TL_SAVE') + AName + '.png');
end;

{ EVERY TWO RUNS OF THE DISPLAY LIST, ONE OF THEM THE TITLE'S: of the two the
  list both draw (a view's elements at one zlevel, z and z2), the one upstream
  draws first is first here -- and every run of the title's is in the list }
procedure TAdvChartTitleListTest.CheckRuns(const AWhere: string; ARec: TJSONObject);
var
  dl: TJSONArray;
  keys: TStringList;
  first: array of Integer;
  i, a, b, k: Integer;
  el: TTyChartElement;
  L: TTyPaintList;
  v, key: string;

  function KeyOf(R: TJSONArray): string;
  begin
    Result := Format('%s/%d/%d/%d', [R.Strings[0], R.Integers[1], R.Integers[2], R.Integers[3]]);
  end;

  function IsTitle(R: TJSONArray): Boolean;
  begin
    Result := Copy(R.Strings[0], 1, 5) = 'title';
  end;

begin
  dl := ARec.Arrays['dl'];
  L := FChart.List;
  keys := TStringList.Create;
  try
    { the port's runs: each view's elements at a key, where the first stands
      in the paint order }
    if L <> nil then
      for i := 0 to L.Count - 1 do
      begin
        el := L.Element(L.PaintOrder(i));
        if el.Ignore then Continue;
        v := FChart.ViewOf(el);
        if v = '' then Continue;
        key := Format('%s/%d/%d/%d', [v, el.ZLevel, el.Z, el.Z2]);
        if keys.IndexOf(key) < 0 then
        begin
          keys.Add(key);
          SetLength(first, keys.Count);
          first[keys.Count - 1] := i;
        end;
      end;
    for a := 0 to dl.Count - 1 do
    begin
      if not IsTitle(dl.Arrays[a]) then Continue;
      Inc(FCompared);
      if keys.IndexOf(KeyOf(dl.Arrays[a])) < 0 then
        Miss(Format('%s: no %s in the list', [AWhere, KeyOf(dl.Arrays[a])]));
    end;
    for a := 0 to dl.Count - 1 do
      for b := a + 1 to dl.Count - 1 do
      begin
        if not (IsTitle(dl.Arrays[a]) or IsTitle(dl.Arrays[b])) then Continue;
        if dl.Arrays[a].Strings[0] = dl.Arrays[b].Strings[0] then Continue;
        i := keys.IndexOf(KeyOf(dl.Arrays[a]));
        k := keys.IndexOf(KeyOf(dl.Arrays[b]));
        if (i < 0) or (k < 0) then Continue;
        Inc(FCompared);
        if first[i] > first[k] then
          Miss(Format('%s: %s drawn after %s, upstream before it', [AWhere,
            KeyOf(dl.Arrays[a]), KeyOf(dl.Arrays[b])]));
      end;
  finally
    keys.Free;
  end;
end;

procedure TAdvChartTitleListTest.TestTheTitleAmongTheListAsUpstream;
var
  cs, steps, recs: TJSONArray;
  c, s: TJSONObject;
  i, j: Integer;
  id: string;
begin
  cs := TJSONObject(FRoot).Arrays['charts'];
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    if (Copy(id, 1, 8) <> 'vo-title') and (id <> 'vo-z4') then Continue;
    NewChart(c.Get('w', 400), c.Get('h', 300));
    FChart.AnimationMode := camOff;
    FChart.SetOption(c.Objects['option'].AsJSON, True);
    AssertEquals(id + ' parses', '', FChart.OptionError);
    Paint;
    steps := c.Arrays['steps'];
    recs := c.Arrays['recs'];
    for j := 0 to recs.Count - 1 do
    begin
      if j > 0 then
      begin
        s := steps.Objects[j - 1];
        if s.Find('act') <> nil then FChart.DispatchAction(s.Objects['act'].AsJSON);
        if s.Find('set') <> nil then
          AssertTrue(id + ' merges', FChart.SetOption(s.Objects['set'].AsJSON, '{}'));
        Paint;
      end;
      CheckRuns(Format('%s %d', [id, j]), recs.Objects[j]);
    end;
  end;
  AssertTrue(Format('compared %d', [FCompared]), FCompared >= 40);
  AssertEquals(Format('%d mismatches over %d:%s', [FBad, FCompared, FReport]), 0, FBad);
end;

{ the title's red box at the top left, a thumbnail's green box over it }
procedure TAdvChartTitleListTest.TestAThumbnailIsOverTheTitle;
var p: TBGRAPixel;
begin
  NewChart(400, 300);
  FChart.SetOption('{"animation":false,"title":{"text":"T","left":0,"top":0,"padding":40,'
    + '"backgroundColor":"#ff0000"},"thumbnail":{"left":0,"top":0,"width":120,"height":80,'
    + '"itemStyle":{"color":"#00ff00","borderWidth":0}},"series":[{"type":"graph","layout":"none",'
    + '"roam":true,"data":[{"x":0,"y":0},{"x":100,"y":50}],"links":[{"source":0,"target":1}]}]}', True);
  AssertEquals('parses', '', FChart.OptionError);
  Paint;
  Save('thumb');
  { (the thumbnail's box half covers what is under it: the red through it,
    lighter) }
  p := Px(10, 70);
  AssertTrue(Format('the thumbnail over the title''s box: (%d,%d,%d)', [p.red, p.green, p.blue]),
    (p.green > 200) and (p.red < 160));
end;

{ a brush cover (z 10000) over the title's box in the plot's middle }
procedure TAdvChartTitleListTest.TestABrushCoverIsOverTheTitle;
var p: TBGRAPixel;
begin
  NewChart(400, 300);
  FChart.SetOption('{"animation":false,"grid":{"left":40,"right":40,"top":40,"bottom":40},'
    + '"xAxis":{"type":"value","min":0,"max":10},"yAxis":{"type":"value","min":0,"max":10},'
    + '"title":{"text":"T","left":"center","top":"middle","padding":40,"backgroundColor":"#ff0000"},'
    + '"brush":{"xAxisIndex":0,"brushStyle":{"color":"#0000ff","borderWidth":0}},'
    + '"series":[{"type":"scatter","data":[[1,1]]}]}', True);
  AssertEquals('parses', '', FChart.OptionError);
  Paint;
  FChart.DispatchAction('{"type":"brush","areas":[{"brushType":"lineX","coordRange":[2,8],"xAxisIndex":0}]}');
  Paint;
  Save('brush');
  p := Px(200, 150);
  AssertTrue(Format('the cover over the title''s box: (%d,%d,%d)', [p.red, p.green, p.blue]),
    (p.blue > 200) and (p.red < 60));
end;

{ the toolbox's icons over the title's box (z 6 z2 0, the title's view
  first), its text over them (z2 10) }
procedure TAdvChartTitleListTest.TestAToolboxIconIsBetweenTheFrameAndTheText;
var
  x, y, iconOnBox: Integer;
  p: TBGRAPixel;
begin
  NewChart(400, 300);
  FChart.SetOption('{"animation":false,"title":{"text":"T","left":0,"top":0,"padding":[30,120,30,0],'
    + '"backgroundColor":"#ff0000","textStyle":{"color":"#ff0000"}},"toolbox":{"left":0,"top":10,"itemSize":30,'
    + '"iconStyle":{"borderColor":"#0000ff","borderWidth":3},"feature":{"restore":{}}},'
    + '"series":[{"type":"scatter","data":[[1,1]]}]}', True);
  AssertEquals('parses', '', FChart.OptionError);
  Paint;
  Save('toolbox');
  { the icon's blue strokes inside the red box }
  iconOnBox := 0;
  for y := 12 to 48 do
    for x := 2 to 44 do
    begin
      p := Px(x, y);
      if (p.blue > 200) and (p.red < 80) then Inc(iconOnBox);
    end;
  AssertTrue(Format('the icon drawn over the box: %d blue px', [iconOnBox]), iconOnBox > 20);
end;

{ a title of z -1 under the axes: a split line over its box }
procedure TAdvChartTitleListTest.TestATitleUnderTheAxesIsUnderTheirLines;
var p, q: TBGRAPixel;
begin
  NewChart(400, 300);
  FChart.SetOption('{"animation":false,"grid":{"left":40,"right":40,"top":40,"bottom":40},'
    + '"xAxis":{"type":"value","min":0,"max":10,"show":false},'
    + '"yAxis":{"type":"value","min":0,"max":10,"interval":5,"axisLabel":{"show":false},'
    + '"axisLine":{"show":false},"axisTick":{"show":false},'
    + '"splitLine":{"lineStyle":{"color":"#0000ff","width":3}}},'
    + '"title":{"text":"T","left":"center","top":"middle","z":-1,"padding":40,"backgroundColor":"#ff0000",'
    + '"textStyle":{"color":"#ff0000"}},'
    + '"series":[{"type":"scatter","data":[[1,1]]}]}', True);
  AssertEquals('parses', '', FChart.OptionError);
  Paint;
  Save('under');
  p := Px(200, 150);
  q := Px(200, 160);
  AssertTrue(Format('the split line over the title''s box: (%d,%d,%d)', [p.red, p.green, p.blue]),
    (p.blue > 200) and (p.red < 60));
  AssertTrue(Format('the box beside it: (%d,%d,%d)', [q.red, q.green, q.blue]),
    (q.red > 200) and (q.blue < 60));
end;

{ a title on zlevel -1, the axes on 0: the axes' canvas over the title's --
  the list has an element under the components' zlevel, drawn level by
  level }
procedure TAdvChartTitleListTest.TestATitleOnALowerZLevelIsUnderTheAxes;
var p, q: TBGRAPixel;
begin
  NewChart(400, 300);
  FChart.SetOption('{"animation":false,"grid":{"left":40,"right":40,"top":40,"bottom":40},'
    + '"xAxis":{"type":"value","min":0,"max":10,"show":false},'
    + '"yAxis":{"type":"value","min":0,"max":10,"interval":5,"axisLabel":{"show":false},'
    + '"axisLine":{"show":false},"axisTick":{"show":false},'
    + '"splitLine":{"lineStyle":{"color":"#0000ff","width":3}}},'
    + '"title":{"text":"T","left":"center","top":"middle","zlevel":-1,"z":20,"padding":40,'
    + '"backgroundColor":"#ff0000","textStyle":{"color":"#ff0000"}},'
    + '"series":[{"type":"scatter","data":[[1,1]]}]}', True);
  AssertEquals('parses', '', FChart.OptionError);
  Paint;
  Save('zlunder');
  AssertTrue('the title noted (the levels drawn one by one)', Length(FChart.Titles) > 0);
  p := Px(200, 150);
  q := Px(200, 160);
  AssertTrue(Format('the split line over the title''s box: (%d,%d,%d)', [p.red, p.green, p.blue]),
    (p.blue > 200) and (p.red < 60));
  AssertTrue(Format('the box beside it: (%d,%d,%d)', [q.red, q.green, q.blue]),
    (q.red > 200) and (q.blue < 60));
end;

{ a title of z 20 over a legend's (z 4) icon, under a slider of z 30 }
procedure TAdvChartTitleListTest.TestATitleOfAHigherZIsOverALegend;
var p, q: TBGRAPixel;
begin
  NewChart(400, 300);
  FChart.SetOption('{"animation":false,"grid":{"left":40,"right":40,"top":60,"bottom":60},'
    + '"xAxis":{"type":"value","min":0,"max":10},"yAxis":{"type":"value","min":0,"max":10},'
    + '"legend":{"left":0,"top":0,"itemWidth":60,"itemHeight":30,"itemStyle":{"color":"#00ff00"}},'
    + '"dataZoom":[{"type":"slider","left":80,"top":0,"width":200,"height":30,"z":30,'
    + '"backgroundColor":"#0000ff","fillerColor":"#0000ff","borderColor":"#0000ff","showDetail":false}],'
    + '"title":{"text":"T","left":0,"top":0,"z":20,"padding":[20,200,20,20],"backgroundColor":"#ff0000",'
    + '"textStyle":{"color":"#ff0000"}},'
    + '"series":[{"type":"scatter","name":"A","symbol":"rect","itemStyle":{"color":"#00ff00"},"data":[[1,1]]}]}', True);
  AssertEquals('parses', '', FChart.OptionError);
  Paint;
  Save('z20');
  p := Px(20, 20);
  AssertTrue(Format('the title''s box over the legend''s icon: (%d,%d,%d)', [p.red, p.green, p.blue]),
    (p.red > 200) and (p.green < 60));
  q := Px(150, 15);
  AssertTrue(Format('the slider over the title''s box: (%d,%d,%d)', [q.red, q.green, q.blue]),
    (q.blue > 200) and (q.red < 60));
end;

{ A HALF-TRANSPARENT BOX, DRAWN ONCE: over white, a box of rgba(255, 0, 0,
  0.5) drawn twice is the box once drawn again over itself -- its green and
  blue the square of once's (as fractions of 255). The static layer and the
  dynamic one each blend it their own way: each path's box is its layer's
  box drawn once (RenderTo's for the static layer, a moving frame's for the
  dynamic one), and that is no box drawn twice }
procedure TAdvChartTitleListTest.TestTheTitleIsDrawnOnceOnEveryPath;
const
  cTitle = '"title":{"text":"T","left":20,"top":20,"padding":30,"backgroundColor":"rgba(255,0,0,0.5)"}';
  cAxes = '"grid":{"left":40,"right":40,"top":100,"bottom":40},'
    + '"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{"type":"value","min":0,"max":10},';
var
  stat, dyn: Integer;

  function Green: Integer;
  begin
    Result := Px(40, 40).green;
  end;

  procedure Like(const AWhere: string; ARef: Integer);
  var g: Integer;
  begin
    g := Green;
    Inc(FCompared);
    if (Abs(g - ARef) > 12) or (Px(40, 40).red < 240) then
      Miss(Format('%s: the box (%d,%d,%d), drawn once is (255,%d,%d)', [AWhere, Px(40, 40).red, g,
        Px(40, 40).blue, ARef, ARef]));
  end;

  procedure Layered(AClear: Boolean);
  begin
    if AClear then FBmp.Fill(BGRA(255, 255, 255, 255));
    FChart.Layered(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
  end;

var
  t: Integer;
  url, raw: string;
  ss: TStringStream;
  img: TBGRABitmap;
begin
  { the static layer, through RenderTo and the cached layers }
  NewChart(400, 300);
  FChart.SetOption('{"animation":false,' + cAxes + cTitle + ',"series":[{"type":"bar","data":[1,2,3]}]}', True);
  AssertEquals('parses', '', FChart.OptionError);
  Paint;
  stat := Green;
  { (drawn twice it would be at most 255 * (169/255)^2 = 112) }
  AssertTrue(Format('RenderTo: the box (255,%d,%d) is a box drawn once', [stat, stat]),
    (stat > 120) and (stat < 200));
  Layered(True);
  Like('RenderCached', stat);
  { a frame in motion: the bars entering -- the title in the dynamic layer }
  NewChart(400, 300);
  FChart.AnimationMode := camAlways;
  FChart.SetOption('{"animation":true,"animationDuration":1000,"animationDurationUpdate":1000,'
    + '"animationEasing":"linear",' + cAxes + cTitle + ',"series":[{"type":"bar","data":[1,2,3]}]}', True);
  Layered(True);
  PinClocks(FChart, cT0 + 400);
  FChart.AnimTick(cT0 + 400);
  Layered(True);
  dyn := Green;
  AssertTrue(Format('in motion: the box (255,%d,%d) is a box drawn once', [dyn, dyn]),
    (dyn > 100) and (dyn < 200));
  PinClocks(FChart, cT0 + 5000);
  FChart.AnimTick(cT0 + 5000);
  Layered(True);
  Like('the enter at rest', stat);
  { the continuous phase: an effect scatter's ripples under the title }
  NewChart(400, 300);
  FChart.AnimationMode := camAlways;
  FChart.SetOption('{"animation":true,"animationDuration":0,' + cAxes + cTitle
    + ',"series":[{"type":"effectScatter","data":[1,2,3]}]}', True);
  Layered(True);
  for t := 1 to 5 do
  begin
    PinClocks(FChart, cT0 + t * 100);
    FChart.AnimTick(cT0 + t * 100);
    Layered(True);
  end;
  Like('the ripples', dyn);
  { the dirty rects: each frame onto the last, a hover and back }
  NewChart(400, 300);
  FChart.UseDirtyRect := True;
  FChart.SetOption('{"animation":false,' + cAxes + cTitle + ',"series":[{"type":"bar","data":[1,2,3]}]}', True);
  Layered(True);
  Like('the first dirty-rect frame', stat);
  FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":1}');
  Layered(False);
  Like('a dirty-rect frame', stat);
  FChart.DispatchAction('{"type":"downplay","seriesIndex":0,"dataIndex":1}');
  Layered(False);
  Like('the next dirty-rect frame', stat);
  { an export }
  NewChart(400, 300);
  FChart.SetOption('{"animation":false,"backgroundColor":"#ffffff",' + cAxes + cTitle
    + ',"series":[{"type":"bar","data":[1,2,3]}]}', True);
  Paint;
  url := FChart.GetDataURL('{"type":"png"}');
  AssertTrue('a png', Pos('base64,', url) > 0);
  raw := DecodeStringBase64(Copy(url, Pos('base64,', url) + 7, MaxInt));
  ss := TStringStream.Create(raw);
  try
    img := TBGRABitmap.Create(ss);
    try
      FBmp.PutImage(0, 0, img, dmSet);
    finally
      img.Free;
    end;
  finally
    ss.Free;
  end;
  Like('the export', stat);
  AssertEquals(Format('%d mismatches over %d:%s', [FBad, FCompared, FReport]), 0, FBad);
end;

{ A TITLE WITH NOTHING OVER IT, as it was drawn: its words, its subtext, a
  rich block, its frame, at 96 and 144 PPI -- the list draws them as
  PaintTitles drew them. Saved (TY_TL_SAVE) for the comparison with the
  build before; here: ink where the words are, the frame's colour }
procedure TAdvChartTitleListTest.TestTheTitleAloneAsBefore;
const
  cOpts: array[0..3] of string = (
    '{"animation":false,"title":{"text":"Title text","subtext":"the sub\ntwo lines","left":"center","top":10,'
      + '"backgroundColor":"#ffeeaa","borderWidth":2,"borderColor":"#333333","borderRadius":6,'
      + '"shadowBlur":4,"shadowColor":"rgba(0,0,0,0.4)"}}',
    '{"animation":false,"title":{"text":"{a|Rich} {b|text}","left":"right","top":"bottom",'
      + '"textStyle":{"rich":{"a":{"color":"#ff0000","fontSize":20},"b":{"backgroundColor":"#ccccff","padding":4}}}}}',
    '{"animation":false,"title":[{"text":"One","left":10,"top":10},{"text":"Two","subtext":"s",'
      + '"left":"center","top":"middle","textAlign":"center"}],"series":[]}',
    '{"animation":false,"grid":{"left":40,"right":40,"top":60,"bottom":40},"xAxis":{},"yAxis":{},'
      + '"title":{"text":"Over a plot","left":60,"top":20},"series":[{"type":"line","data":[[1,1],[5,3]]}]}');
var
  k, ppi, x, y, ink: Integer;
  p: TBGRAPixel;
begin
  for k := 0 to High(cOpts) do
    for ppi := 0 to 1 do
    begin
      if ppi = 0 then NewChart(400, 300) else NewChart(600, 450);
      FChart.SetOption(cOpts[k], True);
      AssertEquals(Format('%d parses', [k]), '', FChart.OptionError);
      FBmp.Fill(BGRA(255, 255, 255, 255));
      FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96 + 48 * ppi);
      Save(Format('alone%d_%d', [k, 96 + 48 * ppi]));
      ink := 0;
      for y := 0 to FBmp.Height - 1 do
        for x := 0 to FBmp.Width - 1 do
        begin
          p := FBmp.GetPixel(x, y);
          if (p.red < 200) or (p.green < 200) or (p.blue < 200) then Inc(ink);
        end;
      AssertTrue(Format('%d at %d PPI: something drawn (%d px)', [k, 96 + 48 * ppi, ink]), ink > 30);
      AssertTrue(Format('%d: a title frame noted', [k]), Length(FChart.Titles) > 0);
    end;
  { A BOX OF NO FILL AND NO PEN CASTS NO SHADOW: the Rect is in the list
    (it hands the canvas its fill), its fill transparent -- nothing drawn,
    the words white on white }
  NewChart(400, 300);
  FChart.SetOption('{"animation":false,"title":{"text":"White","left":40,"top":40,"padding":20,'
    + '"shadowBlur":12,"shadowColor":"#000000","shadowOffsetX":6,"shadowOffsetY":6,'
    + '"textStyle":{"color":"#ffffff"}}}', True);
  AssertEquals('parses', '', FChart.OptionError);
  Paint;
  Save('noshadow');
  { (inside the control's own border) }
  ink := 0;
  for y := 10 to FBmp.Height - 11 do
    for x := 10 to FBmp.Width - 11 do
    begin
      p := FBmp.GetPixel(x, y);
      if (p.red < 250) or (p.green < 250) or (p.blue < 250) then Inc(ink);
    end;
  AssertEquals('nothing drawn of an unfilled, unstroked box', 0, ink);
end;

{ SEVERAL LINES, EACH ALIGNED IN THE BOX as the title's alignment says: a
  centred title's short second line under the middle of its first, a right
  one's at its right -- the list's caption draws them as PaintTitles did }
procedure TAdvChartTitleListTest.TestSeveralLinesAlignedAsBefore;
var
  k, x, y, top, bottom, l1, r1, l2, r2, mid: Integer;
  p: TBGRAPixel;
begin
  for k := 0 to 1 do
  begin
    NewChart(400, 300);
    if k = 0 then
      FChart.SetOption('{"animation":false,"title":{"text":"WWWWWWWW\ni","left":"center","top":20,'
        + '"textStyle":{"fontSize":20,"color":"#000000"}}}', True)
    else
      FChart.SetOption('{"animation":false,"title":{"text":"WWWWWWWW\ni","left":"right","top":20,'
        + '"textStyle":{"fontSize":20,"color":"#000000"}}}', True);
    AssertEquals('parses', '', FChart.OptionError);
    Paint;
    Save(Format('lines%d', [k]));
    { the ink's rows, inside the control's border }
    top := MaxInt;
    bottom := -1;
    for y := 10 to FBmp.Height - 11 do
      for x := 10 to FBmp.Width - 11 do
      begin
        p := Px(x, y);
        if p.green < 128 then
        begin
          if y < top then top := y;
          if y > bottom then bottom := y;
        end;
      end;
    AssertTrue('ink', bottom > top);
    mid := (top + bottom) div 2;
    l1 := MaxInt; r1 := -1; l2 := MaxInt; r2 := -1;
    for y := top to bottom do
      for x := 10 to FBmp.Width - 11 do
      begin
        p := Px(x, y);
        if p.green >= 128 then Continue;
        if y < mid - 2 then
        begin
          if x < l1 then l1 := x;
          if x > r1 then r1 := x;
        end
        else if y > mid + 2 then
        begin
          if x < l2 then l2 := x;
          if x > r2 then r2 := x;
        end;
      end;
    AssertTrue(Format('%d: two lines (%d..%d, %d..%d)', [k, l1, r1, l2, r2]), (r1 > l1 + 60) and (r2 >= l2) and (r2 - l2 < 15));
    if k = 0 then
      AssertTrue(Format('the short line under the middle of the long: %d..%d under %d..%d', [l2, r2, l1, r1]),
        Abs((l2 + r2) - (l1 + r1)) <= 8)
    else
      AssertTrue(Format('the short line at the long one''s right: %d..%d under %d..%d', [l2, r2, l1, r1]),
        Abs(r2 - r1) <= 5);
  end;
end;

{ A BOX FILL THE CANVAS REFUSES IS THE FILL THE CANVAS HAD: what the element
  drawn before the title's box left (its fill, a text's ink) -- the list's
  run as it stands after a hover's state patch and after the visual map's
  tail is built again (the indicator), as after the build }
procedure TAdvChartTitleListTest.TestARefusedBoxFillIsWhatTheListHandsIt;
var
  t: TTyOverlayShapeArray;
  before, lit: TTyChartColor;
  k, cx, cy: Integer;
  el: TTyChartElement;

  { the fill the list's last element before the title's box hands on }
  function Handed: TTyChartColor;
  var i: Integer; e: TTyChartElement; L: TTyPaintList;
  begin
    Result := 0;
    L := FChart.List;
    for i := 0 to L.Count - 1 do
    begin
      e := L.Element(L.PaintOrder(i));
      if FChart.ViewOf(e) = 'title0' then Break;
      if e.Ignore or e.GfxUnder or (e.ZLevel <> 0) or (e.Style.Alpha = 0) then Continue;
      if (e.Caption.FontSizeLogical <> 0) and (e.Caption.Text <> '') then Result := e.Caption.Colour
      else if e.Style.HasFill then Result := e.Style.FillColor;
    end;
  end;

  function BoxFill: TTyChartColor;
  begin
    t := FChart.Titles;
    AssertTrue('a title box', Length(t) > 0);
    Result := t[0].El.Style.FillColor;
  end;

begin
  { a scatter's symbol before the box; highlighted, its emphasis' fill }
  NewChart(400, 300);
  FChart.SetOption('{"animation":false,"xAxis":{"show":false,"min":0,"max":10},'
    + '"yAxis":{"show":false,"min":0,"max":10},'
    + '"title":{"text":"T","left":20,"top":20,"padding":20,"backgroundColor":"nope"},'
    + '"series":[{"type":"scatter","symbolSize":20,"itemStyle":{"color":"#ff0000"},'
    + '"emphasis":{"itemStyle":{"color":"#00ff00"}},"data":[[5,5]]}]}', True);
  AssertEquals('parses', '', FChart.OptionError);
  Paint;
  before := BoxFill;
  AssertEquals('built: the symbol''s fill', Handed, before);
  FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":0}');
  Paint;
  lit := BoxFill;
  AssertEquals('highlighted: the emphasis'' fill', Handed, lit);
  AssertTrue('the highlight changed what is handed on', lit <> before);
  FChart.DispatchAction('{"type":"downplay","seriesIndex":0,"dataIndex":0}');
  Paint;
  AssertEquals('let go: the symbol''s fill again', before, BoxFill);
  { a visual map's tail before the box: the indicator a hover on the
    series shows (hoverLink) }
  NewChart(400, 300);
  FChart.SetOption('{"animation":false,"grid":{"left":40,"right":40,"top":80,"bottom":40},'
    + '"xAxis":{"show":false,"min":0,"max":10},"yAxis":{"show":false,"min":0,"max":10},'
    + '"visualMap":{"min":0,"max":10,"dimension":1,"calculable":false,"orient":"horizontal","left":"center","top":0},'
    + '"title":{"text":"T","left":20,"top":20,"padding":20,"backgroundColor":"nope"},'
    + '"series":[{"type":"scatter","symbolSize":20,"data":[[5,5]]}]}', True);
  AssertEquals('parses', '', FChart.OptionError);
  Paint;
  before := BoxFill;
  AssertEquals('built: the tail''s fill', Handed, before);
  cx := -1;
  cy := -1;
  for k := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(k);
    if (el.Datum.Kind = ctkSeries) and (el.Datum.SeriesIndex = 0) and (el.Caption.FontSizeLogical = 0)
      and TyRectFIsValid(TyShapeBounds(el.Shape)) and (cx < 0) then
    begin
      cx := Round((TyShapeBounds(el.Shape).Left + TyShapeBounds(el.Shape).Right) / 2);
      cy := Round((TyShapeBounds(el.Shape).Top + TyShapeBounds(el.Shape).Bottom) / 2);
    end;
  end;
  AssertTrue('the symbol', cx >= 0);
  FChart.Hover(cx, cy);
  Paint;
  lit := BoxFill;
  AssertEquals('the indicator shown: what the tail hands on', Handed, lit);
  AssertTrue(Format('the indicator changed what is handed on (%x, %x)', [before, lit]), lit <> before);
end;

initialization
  RegisterTest(TAdvChartTitleListTest);
end.
