unit test.advchart.decalseries;
{$mode objfpc}{$H+}
{ DECALS ON THE REST OF THE SERIES, held to what ECharts 6.1 does [F4a]:
  every element the radar (area and points), the sunburst, the treemap (the
  trees' aria decals by their depth-1 ancestors), the candlestick, the
  boxplot, the heatmap, the pictorial bar, the sankey and the chord (nodes,
  and edges coloured by a node), the themeRiver, the gauge (pointer and
  progress), a custom series' paths and the large bar's batch draw a decal
  on, with the pattern it draws; the graph draws none; a line's own legend
  icon and an empty icon wear theirs. The decal symbols batch 131 left out --
  empty, path:// and image:// -- against the tile upstream brushed.

  tools/advchart-oracle/decal-series.js records them under the real dist;
  each case is replayed here. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.Types, tyControls.StyleModel,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Color, tyControls.AdvChart.Render, tyControls.AdvChart.Custom,
     tyControls.AdvChart.Legend, tyControls.AdvChart.Decal,
     tyControls.AdvChart.Geo, tyControls.AdvChart.Images, ImgList,
     tyControls.AdvanceChart;
type
  TDsProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TDsRenders = class
  public
    function DecalBar(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function DecalLit(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
  end;

  TAdvChartDecalSeriesOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TDsProbe;
    FRoot: TJSONObject;
    FBmp: TBGRABitmap;
    FSkin: TTyChartColor;
    FBad, FCompared: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Done(const ATitle: string);
    function SameTile(const A: TTyChartDecal; ATile: TJSONObject; AReport: Boolean;
      const AWhat: string): Boolean;
    function PatternOf(const A: TTyChartDecal; APats: TJSONArray): Integer;
    procedure Step(AStep: TJSONObject);
    procedure CheckSeries(ARec: TJSONObject);
    procedure CheckLegend(ARec: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheNewSymbolsAsUpstream;
    procedure TestTheSeriesAsUpstream;
  end;

  TAdvChartDecalSeriesTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TDsProbe;
    FBmp: TBGRABitmap;
    procedure Load(const AOption: string; AW, AH, APPI: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheLightSkinsDecalIsUpstreams;
    procedure TestEveryProgressiveChunkWearsTheDecal;
    procedure TestALargeBarPaintsItsDecal;
    procedure TestAnImageSymbolPaintsTheImage;
    procedure TestTheApiVisualIsTheItemsDecal;
    procedure TestAHollowsGroundIsTheSkins;
    procedure TestAMapRegionPaintsItsDecal;
    procedure TestAListPictureInATileFollowsTheList;
    procedure TestAReplacedListPictureIsFollowed;
  end;

implementation

const
  cUpstreamDefault = 'rgba(0, 0, 0, 0.2)';
  { a 2 x 1 PNG: red then blue -- decal-series.js' PNG }
  { [R2-F] the map of decal-series.js' 'map' scenario: three squares }
  cDecalMap = '{"type":"FeatureCollection","features":['
    + '{"type":"Feature","properties":{"name":"A"},"geometry":{"type":"Polygon","coordinates":[[[0,0],[8,0],[8,8],[0,8],[0,0]]]}},'
    + '{"type":"Feature","properties":{"name":"B"},"geometry":{"type":"Polygon","coordinates":[[[10,0],[18,0],[18,8],[10,8],[10,0]]]}},'
    + '{"type":"Feature","properties":{"name":"C"},"geometry":{"type":"Polygon","coordinates":[[[20,0],[28,0],[28,8],[20,8],[20,0]]]}}]}';
  cPng = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8AAQv8BD/kD/YURmXYAAAAASUVORK5CYII=';

var
  GRenders: TDsRenders = nil;

procedure TDsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TDsProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

{ RENDER.decalBar: a bar from the axis to the value, the item's decal on it }
function TDsRenders.DecalBar(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  base, top: TTyDoubleArray;
  st: TJSONObject;
  dec: TJSONData;
begin
  base := AApi.Coord([AApi.Value(0), 0]);
  top := AApi.Coord([AApi.Value(0), AApi.Value(1)]);
  st := TJSONObject.Create(['fill', AApi.Visual('color')]);
  dec := AApi.Visual('decal');
  if dec <> nil then st.Add('decal', dec);
  Result := TJSONObject.Create(['type', 'rect',
    'shape', TJSONObject.Create(['x', base[0] - 15, 'y', top[1], 'width', 30,
      'height', base[1] - top[1]]),
    'style', st]);
end;

{ RENDER.decalLit: a circle with a decal written here, a text and a polyline
  that cannot take one }
function TDsRenders.DecalLit(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  p: TTyDoubleArray;
  kids, pts: TJSONArray;
begin
  p := AApi.Coord([AApi.Value(0), AApi.Value(1)]);
  kids := TJSONArray.Create;
  kids.Add(TJSONObject.Create(['type', 'circle',
    'shape', TJSONObject.Create(['cx', p[0], 'cy', p[1], 'r', 18]),
    'style', TJSONObject.Create(['fill', '#91cc75',
      'decal', TJSONObject.Create(['symbol', 'circle', 'dashArrayX', 4, 'dashArrayY', 4,
        'color', 'red'])])]));
  kids.Add(TJSONObject.Create(['type', 'text', 'x', p[0] + 20, 'y', p[1],
    'style', TJSONObject.Create(['text', 'T', 'fill', '#333',
      'decal', TJSONObject.Create(['symbol', 'rect'])])]));
  pts := TJSONArray.Create;
  pts.Add(TJSONArray.Create([p[0] - 20, p[1] + 25]));
  pts.Add(TJSONArray.Create([p[0] + 20, p[1] + 25]));
  kids.Add(TJSONObject.Create(['type', 'polyline',
    'shape', TJSONObject.Create(['points', pts]),
    'style', TJSONObject.Create(['stroke', '#333', 'fill', TJSONNull.Create,
      'decal', TJSONObject.Create(['symbol', 'rect'])])]));
  Result := TJSONObject.Create(['type', 'group', 'children', kids]);
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-decal-series.json';
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Bits(A: Double): QWord;
begin
  Move(A, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
begin
  if IsNan(A) then Exit('NaN');
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function SameNum(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := Bits(A) = Bits(B);
end;

function IsNull(A: TJSONData): Boolean;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

function ColourOf(const AText: string): TTyChartColor;
begin
  if not TyTryParseChartColor(AText, Result) then Result := 0;
end;

{ ==================== the replay ==================== }

procedure TAdvChartDecalSeriesOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TDsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, 600, 400);
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  FSkin := TTyChartColor(FCtl.Model.ResolveStyle(TyDecalSkin, '', []).TextColor);
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := TJSONObject(GetJSON(sl.Text));
  finally
    sl.Free;
  end;
  if GRenders = nil then GRenders := TDsRenders.Create;
  TyChartRegisterRenderItem('decalBar', @GRenders.DecalBar);
  TyChartRegisterRenderItem('decalLit', @GRenders.DecalLit);
  AssertTrue('the map registers', TyChartRegisterMap('decalSquares', cDecalMap));
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartDecalSeriesOracleTest.TearDown;
begin
  TyChartUnregisterRenderItem('decalBar');
  TyChartUnregisterRenderItem('decalLit');
  FRoot.Free;
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartDecalSeriesOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartDecalSeriesOracleTest.Done(const ATitle: string);
begin
  if GetEnvironmentVariable('TY_DECALSERIES_COUNTS') = '1' then
    WriteLn(ATitle, ': ', FCompared, ' compared');
  AssertEquals(ATitle + ' (' + IntToStr(FCompared) + ' compared):' + FReport, 0, FBad);
end;

{ A PORT DECAL AGAINST AN UPSTREAM TILE: the size and the rotation, every
  symbol's name, emptiness, box (bit for bit) and pens -- the colour the
  symbol's own fill or stroke carries -- and a path's or an image's bounds }
function TAdvChartDecalSeriesOracleTest.SameTile(const A: TTyChartDecal;
  ATile: TJSONObject; AReport: Boolean; const AWhat: string): Boolean;
var
  t: TTyDecalTile;
  marks: TTyDecalMarkArray;
  syms: TJSONArray;
  s: TJSONObject;
  i: Integer;
  ok: Boolean;
  bb: TJSONArray;

  procedure Bad(const AMsg: string);
  begin
    Result := False;
    if AReport then Miss(AWhat + ': ' + AMsg);
  end;

  function Pen(const AKey: string): TTyChartColor;
  begin
    if IsNull(s.Find(AKey)) then Result := 0 else Result := ColourOf(s.Strings[AKey]);
  end;

begin
  Result := True;
  if not A.Present then
  begin
    Bad('no decal here');
    Exit;
  end;
  t := TyDecalTile(A);
  if AReport then Inc(FCompared, 3);
  if not SameNum(t.W, ATile.Floats['w']) or not SameNum(t.H, ATile.Floats['h']) then
    Bad(Format('the tile is %s x %s upstream, %s x %s here', [Fmt(ATile.Floats['w']),
      Fmt(ATile.Floats['h']), Fmt(t.W), Fmt(t.H)]));
  if not SameNum(A.Rotation, FromHex(ATile.Strings['rotation'])) then
    Bad('the rotation');
  syms := ATile.Arrays['symbols'];
  marks := TyDecalTileMarks(A, 1);
  if (Length(marks) <> syms.Count) or (Length(t.Symbols) <> syms.Count) then
  begin
    Bad(Format('%d symbols upstream, %d here', [syms.Count, Length(marks)]));
    Exit;
  end;
  for i := 0 to syms.Count - 1 do
  begin
    s := syms.Objects[i];
    if AReport then Inc(FCompared, 4);
    if marks[i].Name <> s.Strings['type'] then
      Bad(Format('symbol %d is %s upstream, %s here', [i, s.Strings['type'], marks[i].Name]));
    if marks[i].Empty <> s.Booleans['empty'] then
      Bad(Format('symbol %d: empty', [i]));
    if not IsNull(s.Find('x')) then
    begin
      ok := SameNum(t.Symbols[i].X, FromHex(s.Strings['x']))
        and SameNum(t.Symbols[i].Y, FromHex(s.Strings['y']))
        and SameNum(t.Symbols[i].W, FromHex(s.Strings['w']))
        and SameNum(t.Symbols[i].H, FromHex(s.Strings['h']));
      if not ok then
        Bad(Format('symbol %d at (%s, %s, %s, %s) upstream, (%s, %s, %s, %s) here',
          [i, Fmt(FromHex(s.Strings['x'])), Fmt(FromHex(s.Strings['y'])),
           Fmt(FromHex(s.Strings['w'])), Fmt(FromHex(s.Strings['h'])),
           Fmt(t.Symbols[i].X), Fmt(t.Symbols[i].Y), Fmt(t.Symbols[i].W), Fmt(t.Symbols[i].H)]));
    end;
    if s.Find('bbox') is TJSONArray then
    begin
      bb := s.Arrays['bbox'];
      ok := SameNum(marks[i].BBox.X, FromHex(bb.Strings[0]))
        and SameNum(marks[i].BBox.Y, FromHex(bb.Strings[1]))
        and SameNum(marks[i].BBox.W, FromHex(bb.Strings[2]))
        and SameNum(marks[i].BBox.H, FromHex(bb.Strings[3]));
      if not ok then
        Bad(Format('symbol %d bounds (%s, %s, %s, %s) upstream, (%s, %s, %s, %s) here',
          [i, Fmt(FromHex(bb.Strings[0])), Fmt(FromHex(bb.Strings[1])),
           Fmt(FromHex(bb.Strings[2])), Fmt(FromHex(bb.Strings[3])),
           Fmt(marks[i].BBox.X), Fmt(marks[i].BBox.Y), Fmt(marks[i].BBox.W), Fmt(marks[i].BBox.H)]));
    end;
    if marks[i].IsImage then Continue;
    { the pens: an empty symbol filled white and stroked 2 wide in the
      colour, a line stroked, anything else filled }
    if s.Booleans['empty'] then
    begin
      if not (marks[i].HasFill and (marks[i].Fill = Pen('fill')) and marks[i].HasStroke
        and (marks[i].Stroke = Pen('stroke'))
        and SameNum(marks[i].LineWidth, FromHex(s.Strings['lineWidth']))) then
        Bad(Format('symbol %d: the empty symbol''s pens', [i]));
    end
    else if s.Strings['type'] = 'line' then
    begin
      if not (marks[i].HasStroke and (marks[i].Stroke = Pen('stroke'))
        and SameNum(marks[i].LineWidth, FromHex(s.Strings['lineWidth']))) then
        Bad(Format('symbol %d: the line''s pen', [i]));
    end
    else if not (marks[i].HasFill and (marks[i].Fill = Pen('fill'))) then
      Bad(Format('symbol %d: filled $%.8x upstream, $%.8x here', [i, Pen('fill'), marks[i].Fill]));
  end;
end;

function TAdvChartDecalSeriesOracleTest.PatternOf(const A: TTyChartDecal;
  APats: TJSONArray): Integer;
var j: Integer;
begin
  for j := 0 to APats.Count - 1 do
    if SameTile(A, APats.Objects[j], False, '') then Exit(j);
  Result := -1;
end;

procedure TAdvChartDecalSeriesOracleTest.Step(AStep: TJSONObject);
var opt: TJSONObject;
begin
  opt := TJSONObject(AStep.Objects['option'].Clone);
  try
    if AStep.Booleans['merge'] then
      FChart.SetOption(opt.AsJSON, False)
    else
    begin
      opt.Add('animation', False);
      FChart.SetOption(opt.AsJSON, True);
    end;
  finally
    opt.Free;
  end;
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 600, 400), 96);
end;

{ EVERY ELEMENT THAT DRAWS A DECAL, per series: upstream's (dataType,
  dataIndex, pattern) multiset against the port's -- a node of a sankey, a
  chord or a graph is upstream's 'node', an edge its 'edge'; the pattern by
  its tile }
procedure TAdvChartDecalSeriesOracleTest.CheckSeries(ARec: TJSONObject);
var
  pats, series, drawn: TJSONArray;
  s, d: TJSONObject;
  i, k, si, p, j: Integer;
  typ, t: string;
  want, got: TStringList;
  e: TTyChartElement;
begin
  pats := ARec.Arrays['patterns'];
  series := ARec.Arrays['series'];
  want := TStringList.Create;
  got := TStringList.Create;
  try
    for i := 0 to series.Count - 1 do
    begin
      s := series.Objects[i];
      si := s.Integers['index'];
      typ := s.Strings['type'];
      want.Clear;
      got.Clear;
      drawn := s.Arrays['drawn'];
      for k := 0 to drawn.Count - 1 do
      begin
        d := drawn.Objects[k];
        want.Add(Format('%s:%d:%d', [d.Strings['t'], d.Integers['i'], d.Integers['p']]));
      end;
      for k := 0 to FChart.List.Count - 1 do
      begin
        e := FChart.List.Element(k);
        if e.Ignore or e.ProgHidden or (e.Datum.Kind <> ctkSeries) then Continue;
        if e.Datum.SeriesIndex <> si then Continue;
        if not (e.Style.Decal.Present and e.Style.HasFill) then Continue;
        if e.Datum.IsEdge then t := 'edge'
        else if (typ = 'sankey') or (typ = 'chord') or (typ = 'graph') then t := 'node'
        else t := '';
        p := PatternOf(e.Style.Decal, pats);
        if (p < 0) and (GetEnvironmentVariable('TY_DECALSERIES_DEBUG') = '1') then
          for j := 0 to pats.Count - 1 do
            SameTile(e.Style.Decal, pats.Objects[j], True, Format('dbg s%d i%d vs %d',
              [si, e.Datum.DataIndex, j]));
        got.Add(Format('%s:%d:%d', [t, Max(-1, e.Datum.DataIndex), p]));
      end;
      want.Sort;
      got.Sort;
      Inc(FCompared, want.Count + 1);
      if want.Text <> got.Text then
        Miss(Format('series %d (%s): upstream [%s], here [%s]', [si, typ,
          StringReplace(Trim(want.Text), LineEnding, ' ', [rfReplaceAll]),
          StringReplace(Trim(got.Text), LineEnding, ' ', [rfReplaceAll])]));
    end;
  finally
    want.Free;
    got.Free;
  end;
end;

{ THE LEGEND'S ICONS: per item, the patterns of the displayables in its
  icon box that draw a decal }
procedure TAdvChartDecalSeriesOracleTest.CheckLegend(ARec: TJSONObject);
var
  pats, legend, els: TJSONArray;
  it: TJSONObject;
  lay: TTyLegendLayout;
  i, j, k: Integer;
  want, got: TStringList;
  e: TTyChartElement;
  b, box: TTyRectF;
begin
  pats := ARec.Arrays['patterns'];
  legend := ARec.Arrays['legend'];
  if legend.Count = 0 then Exit;
  lay := FChart.LegendLayout(0);
  want := TStringList.Create;
  got := TStringList.Create;
  try
    for i := 0 to legend.Count - 1 do
    begin
      it := legend.Objects[i];
      want.Clear;
      got.Clear;
      els := it.Arrays['els'];
      for k := 0 to els.Count - 1 do want.Add(IntToStr(els.Objects[k].Integers['p']));
      box := TyInvalidRectF;
      for j := 0 to High(lay.Items) do
        if lay.Items[j].Name = it.Strings['name'] then box := lay.Items[j].IconBox;
      Inc(FCompared);
      if not TyRectFIsValid(box) then
      begin
        Miss('legend ' + it.Strings['name'] + ': no item');
        Continue;
      end;
      for k := 0 to FChart.List.Count - 1 do
      begin
        e := FChart.List.Element(k);
        if e.Ignore or (e.Datum.SeriesIndex >= 0) then Continue;
        if not (e.Style.Decal.Present and e.Style.HasFill) then Continue;
        b := TyShapeBounds(e.Shape);
        if (b.Left < box.Left - 1) or (b.Right > box.Right + 1)
          or (b.Top < box.Top - 1) or (b.Bottom > box.Bottom + 1) then Continue;
        got.Add(IntToStr(PatternOf(e.Style.Decal, pats)));
      end;
      want.Sort;
      got.Sort;
      Inc(FCompared, want.Count);
      if want.Text <> got.Text then
        Miss(Format('legend %s: upstream [%s], here [%s]', [it.Strings['name'],
          StringReplace(Trim(want.Text), LineEnding, ' ', [rfReplaceAll]),
          StringReplace(Trim(got.Text), LineEnding, ' ', [rfReplaceAll])]));
    end;
  finally
    want.Free;
    got.Free;
  end;
end;

procedure TAdvChartDecalSeriesOracleTest.TestTheNewSymbolsAsUpstream;
var
  tiles: TJSONArray;
  t: TJSONObject;
  i: Integer;
  dec: TTyChartDecal;
begin
  tiles := FRoot.Arrays['tiles'];
  AssertTrue('the fixture has tiles', tiles.Count >= 9);
  for i := 0 to tiles.Count - 1 do
  begin
    t := tiles.Objects[i];
    FName := 'tile ' + t.Strings['id'];
    { the option as written, read by the port: an unwritten colour is the
      light skin's, which is upstream's }
    { [R2-F] through the skin's ground, as the chart resolves one: on the
      light skin it is upstream's neutral00 }
    dec := TyDecalResolve(TyDecalRawOf(t.Objects['decal']), FSkin,
      TTyChartColor(FCtl.Model.ResolveStyle(TyDecalSkin, '', []).Background.Color));
    SameTile(dec, t.Objects['tile'], True, 'tile');
  end;
  Done('tiles');
end;

procedure TAdvChartDecalSeriesOracleTest.TestTheSeriesAsUpstream;
var
  scs, steps: TJSONArray;
  sc, st, rec: TJSONObject;
  i, j: Integer;
begin
  scs := FRoot.Arrays['scenarios'];
  AssertTrue('the fixture has scenarios', scs.Count >= 14);
  for i := 0 to scs.Count - 1 do
  begin
    sc := scs.Objects[i];
    steps := sc.Arrays['steps'];
    for j := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[j];
      FName := sc.Strings['id'] + '#' + IntToStr(j);
      Step(st);
      rec := st.Objects['record'];
      if not IsNull(rec.Find('error')) then Continue;
      CheckSeries(rec);
      CheckLegend(rec);
    end;
  end;
  Done('series');
end;

{ ==================== the hand-written ones ==================== }

procedure TAdvChartDecalSeriesTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TDsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := nil;
  if GRenders = nil then GRenders := TDsRenders.Create;
  TyChartRegisterRenderItem('decalBar', @GRenders.DecalBar);
end;

procedure TAdvChartDecalSeriesTest.TearDown;
begin
  TyChartUnregisterRenderItem('decalBar');
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartDecalSeriesTest.Load(const AOption: string; AW, AH, APPI: Integer);
var dw, dh: Integer;
begin
  dw := AW * APPI div 96;
  dh := AH * APPI div 96;
  FBmp.Free;
  FBmp := TBGRABitmap.Create(dw, dh, BGRA(255, 255, 255, 255));
  FChart.Option := '{}';
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, AW, AH);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, dw, dh), APPI);
end;

{ THE THEME TOKEN, NOT A LITERAL -- but on the light skin it is upstream's
  rgba(0, 0, 0, 0.2) to the bit, and on the dark one white at 20% }
procedure TAdvChartDecalSeriesTest.TestTheLightSkinsDecalIsUpstreams;
var
  skin: TTyChartColor;
  m: TTyStyleModel;
begin
  skin := TTyChartColor(FCtl.Model.ResolveStyle(TyDecalSkin, '', []).TextColor);
  AssertEquals('light: upstream''s colour', Int64(ColourOf(cUpstreamDefault)), Int64(skin));
  { the dual-mode theme: its light mode the same, its dark mode's surface
    takes white ink }
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes'
      + PathDelim + 'auto.tycss');
    m.SetMode('light');
    skin := TTyChartColor(m.ResolveStyle(TyDecalSkin, '', []).TextColor);
    AssertEquals('auto light: upstream''s colour', Int64(ColourOf(cUpstreamDefault)), Int64(skin));
    m.SetMode('dark');
    skin := TTyChartColor(m.ResolveStyle(TyDecalSkin, '', []).TextColor);
    AssertEquals('auto dark: white at 20%', Int64(ColourOf('rgba(255, 255, 255, 0.2)')),
      Int64(skin));
  finally
    m.Free;
  end;
end;

{ A PROGRESSIVE LARGE BAR: every chunk's batch is a LargePath of its own,
  useStyle(data.getVisual('style')) -- the series' decal on each }
procedure TAdvChartDecalSeriesTest.TestEveryProgressiveChunkWearsTheDecal;
var
  k, chunks, worn: Integer;
  e: TTyChartElement;
  data: string;
begin
  data := '';
  for k := 0 to 59 do
  begin
    if k > 0 then data := data + ',';
    data := data + IntToStr(1 + k mod 7);
  end;
  Load('{"animation":false,"xAxis":{"type":"category"},"yAxis":{},'
    + '"series":[{"type":"bar","large":true,"largeThreshold":10,"progressive":20,'
    + '"progressiveThreshold":30,"itemStyle":{"decal":{"symbol":"circle"}},'
    + '"data":[' + data + ']}]}', 600, 400, 96);
  chunks := 0;
  worn := 0;
  for k := 0 to FChart.List.Count - 1 do
  begin
    e := FChart.List.Element(k);
    if (e.Shape.Kind <> cskLarge) or not e.Style.HasFill or e.Silent then Continue;
    Inc(chunks);
    if e.Style.Decal.Present and (e.Style.Decal.Symbols[0][0] = 'circle') then Inc(worn);
  end;
  AssertTrue('more than one chunk', chunks > 1);
  AssertEquals('every chunk wears the decal', chunks, worn);
end;

{ THE BATCH PATH REALLY DRAWS IT: a black decal of 4 x 4 squares every 8 px
  over red bars -- black pixels inside the bars, and none without it }
procedure TAdvChartDecalSeriesTest.TestALargeBarPaintsItsDecal;
const
  cOpt = '{"animation":false,"grid":{"left":0,"right":0,"top":0,"bottom":0},'
    + '"xAxis":{"type":"category","show":false},"yAxis":{"show":false,"max":1},'
    + '"series":[{"type":"bar","large":true,"largeThreshold":5,"barCategoryGap":0,'
    + '"itemStyle":{"color":"#ff0000"%s},"data":[1,1,1,1,1,1,1,1,1,1]}]}';
var
  x, y, black, red: Integer;
  px: TBGRAPixel;
begin
  Load(Format(cOpt, [',"decal":{"color":"#000","dashArrayX":[4,4],"dashArrayY":[4,4]}']),
    200, 100, 96);
  black := 0;
  red := 0;
  for y := 10 to 89 do
    for x := 10 to 189 do
    begin
      px := FBmp.GetPixel(x, y);
      if (px.red < 40) and (px.green < 40) and (px.blue < 40) then Inc(black)
      else if (px.red > 200) and (px.green < 60) then Inc(red);
    end;
  AssertTrue(Format('black squares over the batch (%d black, %d red)', [black, red]),
    (black > 2000) and (red > 2000));
  Load(Format(cOpt, ['']), 200, 100, 96);
  black := 0;
  for y := 10 to 89 do
    for x := 10 to 189 do
    begin
      px := FBmp.GetPixel(x, y);
      if (px.red < 40) and (px.green < 40) and (px.blue < 40) then Inc(black);
    end;
  AssertEquals('none without a decal', 0, black);
end;

{ AN image:// SYMBOL: its source stretched over its box in the tile
  (keepAspect false) -- red over the left half, blue over the right }
procedure TAdvChartDecalSeriesTest.TestAnImageSymbolPaintsTheImage;
var
  d: TJSONData;
  dec: TTyChartDecal;
  tile: TBGRABitmap;
  l, r: TBGRAPixel;
begin
  d := GetJSON('{"symbol":"image://' + cPng + '","symbolKeepAspect":false,'
    + '"dashArrayX":[8,8],"dashArrayY":[8,8]}');
  try
    dec := TyDecalResolve(TyDecalRawOf(d), 0);
  finally
    d.Free;
  end;
  tile := TyDecalTileImage(dec, 1);
  AssertTrue('a tile', tile <> nil);
  AssertEquals('16 wide', 16, tile.Width);
  { the first row of symbols is the second dash row: y 0 .. 8, x 0 .. 8 }
  l := tile.GetPixel(1, 4);
  r := tile.GetPixel(6, 4);
  AssertTrue(Format('red on the left (%d, %d, %d, %d)', [l.red, l.green, l.blue, l.alpha]),
    (l.red > 200) and (l.blue < 60) and (l.alpha > 200));
  AssertTrue(Format('blue on the right (%d, %d, %d, %d)', [r.red, r.green, r.blue, r.alpha]),
    (r.blue > 200) and (r.red < 60) and (r.alpha > 200));
  AssertTrue('and nothing in the gap', tile.GetPixel(12, 4).alpha = 0);
end;

{ [R2-F] AN empty* SYMBOL'S GROUND IS THE SKIN'S: the TyAdvChartDecal
  background -- upstream's neutral00 white on the light skin, the dark
  surface on a dark one, where it was a literal white everywhere }
procedure TAdvChartDecalSeriesTest.TestAHollowsGroundIsTheSkins;
var
  m: TTyStyleModel;
  ink, ground: TTyChartColor;
  d: TJSONData;
  dec: TTyChartDecal;
  tile: TBGRABitmap;
  p: TBGRAPixel;
  k, i: Integer;
  e: TTyChartElement;
begin
  AssertEquals('light: upstream''s white', Int64($FFFFFFFF),
    Int64(TTyChartColor(FCtl.Model.ResolveStyle(TyDecalSkin, '', []).Background.Color)));
  { the chart hands it to the decals it resolves }
  Load('{"animation":false,"xAxis":{"data":["a"]},"yAxis":{},"series":[{"type":"bar",'
    + '"itemStyle":{"decal":{"symbol":"emptyCircle"}},"data":[1]}]}', 300, 200, 96);
  k := 0;
  for i := 0 to FChart.List.Count - 1 do
  begin
    e := FChart.List.Element(i);
    if not e.Style.Decal.Present then Continue;
    Inc(k);
    AssertEquals('the chart''s decal takes the skin''s ground', Int64($FFFFFFFF),
      Int64(e.Style.Decal.EmptyFill));
  end;
  AssertTrue('a decal', k > 0);
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes'
      + PathDelim + 'auto.tycss');
    m.SetMode('dark');
    ink := TTyChartColor(m.ResolveStyle(TyDecalSkin, '', []).TextColor);
    ground := TTyChartColor(m.ResolveStyle(TyDecalSkin, '', []).Background.Color);
    AssertTrue(Format('dark: no white hole ($%.8x)', [ground]), ground <> $FFFFFFFF);
    AssertTrue(Format('dark: a dark ground ($%.8x)', [ground]),
      ((ground shr 16) and $FF) + ((ground shr 8) and $FF) + (ground and $FF) < 3 * 100);
  finally
    m.Free;
  end;
  d := GetJSON('{"symbol":"emptyCircle","symbolSize":1,"dashArrayX":[20,0],"dashArrayY":[20,0]}');
  try
    { the same decal on white first: a tile of its own, not the dark one's }
    dec := TyDecalResolve(TyDecalRawOf(d), ink, TTyChartColor($FFFFFFFF));
    tile := TyDecalTileImage(dec, 1);
    AssertTrue('a white-ground tile', tile <> nil);
    p := tile.GetPixel(tile.Width div 2, tile.Height div 2);
    AssertTrue('its hollow white', (p.red > 250) and (p.green > 250) and (p.blue > 250));
    dec := TyDecalResolve(TyDecalRawOf(d), ink, ground);
  finally
    d.Free;
  end;
  tile := TyDecalTileImage(dec, 1);
  AssertTrue('a tile', tile <> nil);
  { the hollow's middle: the ground, not white }
  p := tile.GetPixel(tile.Width div 2, tile.Height div 2);
  AssertTrue(Format('the hollow is the ground: (%d, %d, %d) against $%.8x',
    [p.red, p.green, p.blue, ground]),
    (Abs(p.red - Integer((ground shr 16) and $FF)) <= 2)
    and (Abs(p.green - Integer((ground shr 8) and $FF)) <= 2)
    and (Abs(p.blue - Integer(ground and $FF)) <= 2));
end;

{ [R2-F] A MAP REGION WEARS ITS DECAL (MapDraw's applyOptionStyleForRegion):
  black 4 x 4 squares over red regions -- black inside, and none without it }
procedure TAdvChartDecalSeriesTest.TestAMapRegionPaintsItsDecal;
const
  cOpt = '{"animation":false,"series":[{"type":"map","map":"decalSquares","left":0,"right":0,'
    + '"top":0,"bottom":0,"itemStyle":{"areaColor":"#ff0000","borderWidth":0%s},'
    + '"data":[{"name":"A","value":1},{"name":"B","value":2}]}]}';
var
  x, y, black, red: Integer;
  px: TBGRAPixel;
begin
  AssertTrue('the map registers', TyChartRegisterMap('decalSquares', cDecalMap));
  Load(Format(cOpt, [',"decal":{"color":"#000","dashArrayX":[4,4],"dashArrayY":[4,4]}']),
    300, 100, 96);
  black := 0;
  red := 0;
  for y := 0 to 99 do
    for x := 0 to 299 do
    begin
      px := FBmp.GetPixel(x, y);
      if (px.red < 40) and (px.green < 40) and (px.blue < 40) then Inc(black)
      else if (px.red > 200) and (px.green < 60) then Inc(red);
    end;
  AssertTrue(Format('black squares over the regions (%d black, %d red)', [black, red]),
    (black > 500) and (red > 500));
  Load(Format(cOpt, ['']), 300, 100, 96);
  black := 0;
  for y := 0 to 99 do
    for x := 0 to 299 do
    begin
      px := FBmp.GetPixel(x, y);
      if (px.red < 40) and (px.green < 40) and (px.blue < 40) then Inc(black);
    end;
  AssertEquals('none without a decal', 0, black);
end;

{ [R2-F] A TILE WITH AN IMAGE LIST'S PICTURE is the list's picture now: the
  tile used to be kept by the decal alone and stayed what the list held
  when it was first drawn, until 64 other tiles cleared the cache }
procedure TAdvChartDecalSeriesTest.TestAListPictureInATileFollowsTheList;
var
  lst: TImageList;
  bmp: TBitmap;
  d: TJSONData;
  dec: TTyChartDecal;
  tile: TBGRABitmap;
  p: TBGRAPixel;

  procedure Paint(AColor: TColor);
  begin
    bmp.Canvas.Brush.Color := AColor;
    bmp.Canvas.FillRect(0, 0, 4, 4);
  end;

begin
  lst := TImageList.Create(nil);
  bmp := TBitmap.Create;
  try
    lst.Width := 4;
    lst.Height := 4;
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(4, 4);
    Paint(clRed);
    lst.Add(bmp, nil);
    TyChartRegisterImageList('decalTileList', lst);
    d := GetJSON('{"symbol":"image://decalTileList/0","symbolKeepAspect":false,'
      + '"dashArrayX":[8,8],"dashArrayY":[8,8]}');
    try
      dec := TyDecalResolve(TyDecalRawOf(d), 0);
    finally
      d.Free;
    end;
    tile := TyDecalTileImage(dec, 1);
    AssertTrue('a tile', tile <> nil);
    p := tile.GetPixel(3, 4);
    AssertTrue(Format('red first (%d, %d, %d)', [p.red, p.green, p.blue]), (p.red > 200) and (p.blue < 60));
    { a change the list announces (LCL's Replace announces none) }
    Paint(clBlue);
    lst.Clear;
    lst.Add(bmp, nil);
    tile := TyDecalTileImage(dec, 1);
    AssertTrue('a tile again', tile <> nil);
    p := tile.GetPixel(3, 4);
    AssertTrue(Format('blue once the list holds blue (%d, %d, %d)', [p.red, p.green, p.blue]),
      (p.blue > 200) and (p.red < 60));
  finally
    TyChartUnregisterImageList('decalTileList');
    bmp.Free;
    lst.Free;
  end;
end;

{ [R2-I2] LCL'S Replace ANNOUNCES NOTHING (InternalReplace calls no Change):
  the list's picture and a decal's tile over it follow it all the same, by
  the picture's content }
procedure TAdvChartDecalSeriesTest.TestAReplacedListPictureIsFollowed;
var
  lst: TImageList;
  bmp: TBitmap;
  d: TJSONData;
  dec: TTyChartDecal;
  tile, pic: TBGRABitmap;
  p: TBGRAPixel;
  nw, nh: Double;
  s0, s1: string;

  procedure Paint(AColor: TColor);
  begin
    bmp.Canvas.Brush.Color := AColor;
    bmp.Canvas.FillRect(0, 0, 4, 4);
  end;

begin
  lst := TImageList.Create(nil);
  bmp := TBitmap.Create;
  try
    lst.Width := 4;
    lst.Height := 4;
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(4, 4);
    Paint(clRed);
    lst.Add(bmp, nil);
    Paint(clLime);
    lst.Add(bmp, nil);
    TyChartRegisterImageList('replacedList', lst);
    d := GetJSON('{"symbol":"image://replacedList/0","symbolKeepAspect":false,'
      + '"dashArrayX":[8,8],"dashArrayY":[8,8]}');
    try
      dec := TyDecalResolve(TyDecalRawOf(d), 0);
    finally
      d.Free;
    end;
    tile := TyDecalTileImage(dec, 1);
    AssertTrue('a tile', tile <> nil);
    p := tile.GetPixel(3, 4);
    AssertTrue(Format('red first (%d, %d, %d)', [p.red, p.green, p.blue]), (p.red > 200) and (p.blue < 60));
    pic := TyChartImage('image://replacedList/0', 4, nw, nh);
    AssertTrue('the picture', pic <> nil);
    p := pic.GetPixel(1, 1);
    AssertTrue(Format('the picture red (%d, %d, %d)', [p.red, p.green, p.blue]), (p.red > 200) and (p.blue < 60));
    s0 := TyChartImageStamp('replacedList/0');
    AssertEquals('the stamp holds while nothing changes', s0, TyChartImageStamp('replacedList/0'));
    { Replace: no change announced }
    Paint(clBlue);
    lst.Replace(0, bmp, nil);
    s1 := TyChartImageStamp('replacedList/0');
    AssertTrue('the stamp moves with the content', s0 <> s1);
    pic := TyChartImage('image://replacedList/0', 4, nw, nh);
    AssertTrue('the picture again', pic <> nil);
    p := pic.GetPixel(1, 1);
    AssertTrue(Format('the picture blue (%d, %d, %d)', [p.red, p.green, p.blue]), (p.blue > 200) and (p.red < 60));
    tile := TyDecalTileImage(dec, 1);
    AssertTrue('a tile again', tile <> nil);
    p := tile.GetPixel(3, 4);
    AssertTrue(Format('the tile blue (%d, %d, %d)', [p.red, p.green, p.blue]), (p.blue > 200) and (p.red < 60));
    { the other slot's picture is its own }
    pic := TyChartImage('image://replacedList/1', 4, nw, nh);
    p := pic.GetPixel(1, 1);
    AssertTrue(Format('the other still green (%d, %d, %d)', [p.red, p.green, p.blue]), (p.green > 200) and (p.blue < 60));
  finally
    TyChartUnregisterImageList('replacedList');
    bmp.Free;
    lst.Free;
  end;
end;

{ api.visual('decal') is the item's decal visual -- its own over the
  series', the palette's under both with aria -- and a renderItem that hands
  it back gets that pattern on its path }
procedure TAdvChartDecalSeriesTest.TestTheApiVisualIsTheItemsDecal;
var
  k, n: Integer;
  e: TTyChartElement;
begin
  Load('{"animation":false,"xAxis":{"data":["a","b","c"]},"yAxis":{},'
    + '"series":[{"type":"custom","renderItem":"@decalBar",'
    + '"itemStyle":{"decal":{"symbol":"triangle"}},'
    + '"data":[[0,2],{"value":[1,4],"itemStyle":{"decal":{"symbol":"circle"}}},[2,3]]}]}',
    600, 400, 96);
  n := 0;
  for k := 0 to FChart.List.Count - 1 do
  begin
    e := FChart.List.Element(k);
    if (e.Datum.SeriesIndex <> 0) or not e.Style.Decal.Present then Continue;
    Inc(n);
    if e.Datum.DataIndex = 1 then
      AssertEquals('the item''s own', 'circle', e.Style.Decal.Symbols[0][0])
    else
      AssertEquals('the series''', 'triangle', e.Style.Decal.Symbols[0][0]);
  end;
  AssertEquals('three bars wear one', 3, n);
end;

initialization
  RegisterTest(TAdvChartDecalSeriesOracleTest);
  RegisterTest(TAdvChartDecalSeriesTest);
finalization
  FreeAndNil(GRenders);
end.
