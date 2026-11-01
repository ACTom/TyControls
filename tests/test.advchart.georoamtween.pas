unit test.advchart.georoamtween;
{$mode objfpc}{$H+}
{ A GEO VIEW'S ROAM TWEEN AND WHAT RIDES IT, HELD TO UPSTREAM [R6-B].

  tools/advchart-oracle/geo-roam-tween.js runs the real ECharts 6.1 build in
  node and samples, on the animation clock, MapDraw's transform group and
  every displayable under it that draws a stroke, a text or an image: its
  global transform, its stroke and dash as the screen sees them (zrender's
  strokeNoScale over getLineScale), its points' box, a text's font, an
  image's box. What it pins:

    - the roam group only ever moves and scales (no turn, no skew): an SVG
      map's own turns and skews are its content's;
    - an SVG map never tweens (MapDraw's isFirstDraw: its regions group is
      empty), a GeoJSON one does, and so does the merge that switches a
      GeoJSON map to an SVG one (the old regions are still in the group);
    - a GeoJSON region and a named SVG shape keep their screen width
      through a tween (strokeNoScale); an unnamed SVG shape's stroke and
      dash, a text and an image grow and shrink with the group.

  This replays every case through the control and compares the 'geoView'
  proxy bit for bit and every element of the frame (1e-6 px; a font size to
  its encoding's hundredth of a pixel). }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.FontUnits,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Anim,
     tyControls.AdvanceChart.AnimView, tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Geo,
     tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax,
     test.advchart.graphic;
type
  TGrtProbe = class(TGfxProbe)
  public
    function Frame: TTyPaintList;
  end;

  TAdvChartGeoRoamTweenOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGrtProbe;
    FRoot: TJSONData;
    FBad, FCompared, FSamples, FEls: Integer;
    FWhere, FReport: string;
    procedure Bad(const AWhat: string);
    procedure SameNum(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure NearVal(const AWhat: string; AGot, AWant, ATol: Double);
    procedure NewChart(AW, AH: Integer);
    procedure RenderNow;
    function Drawn: TTyPaintList;
    procedure CheckGroup(const AName: string; AKey: Integer; AGroup: TJSONObject);
    procedure CheckRegions(const AName: string; AKey: Integer; AEls: TJSONArray);
    procedure CheckEl(const AName: string; AKey: Integer; AEl: TJSONObject);
    procedure CheckSample(ARec: TJSONObject);
    procedure RunCase(ACase: TJSONObject);
    procedure RunCases(const AIds: array of string; AMin: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAnSvgMapIsSetAtOnce;
    procedure TestAGeoJsonRegionKeepsItsScreenWidthThroughTheTween;
    procedure TestTheSvgContentRidesTheTweenOfASwitchedMap;
    procedure TestAViewMadeAnewIsSetAtOnce;
  end;

  { [R6-B] what the oracle cannot say: the same at another density }
  TAdvChartGeoRoamTweenTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGrtProbe;
    procedure RenderAt(APPI: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAnImageRidesTheTweenAtAnyDensity;
  end;

implementation

function TGrtProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function HexOf(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function Txt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function SameBits(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := (HexOf(A) = HexOf(B)) or ((A = 0) and (B = 0));
end;

function IsNull(AData: TJSONData): Boolean;
begin
  Result := (AData = nil) or (AData.JSONType = jtNull);
end;

function WantNum(AData: TJSONData): Double;
begin
  if IsNull(AData) then Result := NaN else Result := FromHex(AData.AsString);
end;

{ a map view's key (TyGeoViewKey): a geo component's index + 1, a map
  series' own -(its index + 1) }
function ViewKeyOf(const AName: string; out AKey: Integer): Boolean;
begin
  Result := True;
  if Copy(AName, 1, 3) = 'geo' then AKey := StrToInt(Copy(AName, 4, MaxInt)) + 1
  else if Copy(AName, 1, 3) = 'map' then AKey := -(StrToInt(Copy(AName, 4, MaxInt)) + 1)
  else Result := False;
end;

function IsPathShape(const AEl: TTyChartElement): Boolean;
begin
  Result := (AEl.Shape.Kind in [cskPolygon, cskPolyline, cskPath])
    and (AEl.Caption.FontSizeLogical <= 0) and not AEl.Style.FillPattern.Present;
end;

{ ==================== the oracle ==================== }

procedure TAdvChartGeoRoamTweenOracleTest.SetUp;
var
  sl: TStringList;
  maps: TJSONArray;
  i: Integer;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-geo-roam-tween.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-geo-roam-tween.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  { an SVG map registers as its markup, a GeoJSON one as its text }
  maps := TJSONObject(FRoot).Arrays['maps'];
  for i := 0 to maps.Count - 1 do
    AssertTrue('the map registers', TyChartRegisterMap(maps.Objects[i].Strings['name'],
      maps.Objects[i].Strings['text']));
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FSamples := 0;
  FEls := 0;
  FReport := '';
end;

procedure TAdvChartGeoRoamTweenOracleTest.TearDown;
var
  maps: TJSONArray;
  i: Integer;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  if FRoot <> nil then
  begin
    maps := TJSONObject(FRoot).Arrays['maps'];
    for i := 0 to maps.Count - 1 do TyChartUnregisterMap(maps.Objects[i].Strings['name']);
  end;
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartGeoRoamTweenOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartGeoRoamTweenOracleTest.SameNum(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  want := WantNum(AWant);
  if not SameBits(AGot, want) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(want)]));
end;

procedure TAdvChartGeoRoamTweenOracleTest.NearVal(const AWhat: string; AGot, AWant,
  ATol: Double);
begin
  Inc(FCompared);
  if IsNan(AWant) or IsNan(AGot) then
  begin
    if not (IsNan(AWant) and IsNan(AGot)) then
      Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(AWant)]));
    Exit;
  end;
  if Abs(AGot - AWant) > ATol then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(AWant)]));
end;

procedure TAdvChartGeoRoamTweenOracleTest.NewChart(AW, AH: Integer);
var m: TJSONObject;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TGrtProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(
    TZrSsrMeasurer.Create(m.Arrays['ratio'], m.Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, AW, AH);
end;

procedure TAdvChartGeoRoamTweenOracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

{ what the canvas shows now: the frame while one is drawn, else the list }
function TAdvChartGeoRoamTweenOracleTest.Drawn: TTyPaintList;
begin
  Result := FChart.Frame;
  if (Result = nil) or (Result.Count = 0) then Result := FChart.List;
end;

{ THE TRANSFORM GROUP: tweening (a clip on it) the proxy is upstream's
  group now; at rest a proxy left over must be at upstream's place too
  (a port tweening where upstream sets the group at once is caught here
  and by every element below) }
procedure TAdvChartGeoRoamTweenOracleTest.CheckGroup(const AName: string; AKey: Integer;
  AGroup: TJSONObject);
const
  cKeys: array[0..3] of string = ('x', 'y', 'scaleX', 'scaleY');
var
  p: TTyChartAnimProxy;
  v: TTyAnimValue;
  k: Integer;
begin
  p := FChart.AnimFindProxy(-1, AKey, 'geoView');
  if p = nil then
  begin
    Inc(FCompared);
    if AGroup.Integers['n'] > 0 then Bad(AName + ': upstream tweens the transform group, the port has no proxy');
    Exit;
  end;
  for k := 0 to High(cKeys) do
  begin
    v := p.GetAnimProp(cKeys[k]);
    if v.Kind <> avkNumber then
    begin
      Inc(FCompared);
      Bad(Format('%s: the proxy has no %s', [AName, cKeys[k]]));
      Continue;
    end;
    SameNum(AName + '.' + cKeys[k], v.Num, AGroup.Find(cKeys[k]));
  end;
end;

{ A GEOJSON MAP'S REGIONS: the region paths the port draws for the view, in
  its order -- the regions group's (a region's group per name, in the order
  of first appearance, its compound paths in order) -- against upstream's
  in its preorder: each one's box, stroke and dash }
procedure TAdvChartGeoRoamTweenOracleTest.CheckRegions(const AName: string; AKey: Integer;
  AEls: TJSONArray);
var
  l: TTyPaintList;
  i, k, n: Integer;
  e: TTyChartElement;
  r: TJSONObject;
  b: TTyRectF;
  ups: array of TJSONObject;
  els: array of TTyChartElement;
  bb, dash: TJSONArray;
  what: string;
begin
  ups := nil;
  for i := 0 to AEls.Count - 1 do
  begin
    r := AEls.Objects[i];
    if (Copy(r.Strings['key'], 1, 2) <> 'r:') or r.Get('stale', False) then Continue;
    SetLength(ups, Length(ups) + 1);
    ups[High(ups)] := r;
  end;
  if Length(ups) = 0 then Exit;
  l := Drawn;
  els := nil;
  for i := 0 to l.Count - 1 do
  begin
    e := l.Element(i);
    if (e.Anim.GeoView <> AKey) or (e.ZrHit.SvgNode <> 0) or not IsPathShape(e) then Continue;
    SetLength(els, Length(els) + 1);
    els[High(els)] := e;
  end;
  Inc(FCompared);
  if Length(els) <> Length(ups) then
  begin
    Bad(Format('%s: the port draws %d region paths, upstream %d', [AName, Length(els), Length(ups)]));
    Exit;
  end;
  n := Length(els);
  Inc(FEls, n);
  for i := 0 to n - 1 do
  begin
    e := els[i];
    r := ups[i];
    what := AName + ' ' + r.Strings['key'];
    b := TyShapeBounds(e.Shape);
    if not IsNull(r.Find('bb')) then
    begin
      bb := r.Arrays['bb'];
      NearVal(what + ' left', b.Left, WantNum(bb.Items[0]), 1e-6);
      NearVal(what + ' top', b.Top, WantNum(bb.Items[1]), 1e-6);
      NearVal(what + ' right', b.Right, WantNum(bb.Items[2]), 1e-6);
      NearVal(what + ' bottom', b.Bottom, WantNum(bb.Items[3]), 1e-6);
    end;
    if IsNull(r.Find('sw')) then Continue;
    NearVal(what + ' stroke', e.Style.StrokeWidthLogical, WantNum(r.Find('sw')), 1e-9);
    if IsNull(r.Find('dash')) then Continue;
    dash := r.Arrays['dash'];
    Inc(FCompared);
    if Length(e.Style.DashLogical) <> dash.Count then
      Bad(Format('%s: %d dash numbers, upstream %d', [what, Length(e.Style.DashLogical), dash.Count]))
    else
      for k := 0 to dash.Count - 1 do
        NearVal(Format('%s dash[%d]', [what, k]), e.Style.DashLogical[k], WantNum(dash.Items[k]), 1e-9);
  end;
end;

{ AN SVG ELEMENT, found by its stroke (a shape), its fill (a text) or its
  pattern (the image) }
procedure TAdvChartGeoRoamTweenOracleTest.CheckEl(const AName: string; AKey: Integer;
  AEl: TJSONObject);
var
  key, what: string;
  l: TTyPaintList;
  i, k: Integer;
  e, hit: TTyChartElement;
  found: Boolean;
  col: TTyChartColor;
  gm, bb, dash, img: TJSONArray;
  b: TTyRectF;
  g: array[0..5] of Double;
  px, det: Double;
begin
  key := AEl.Strings['key'];
  what := AName + ' ' + key;
  if AEl.Get('stale', False) or (Copy(key, 1, 2) = 'r:') then Exit;
  gm := AEl.Arrays['gm'];
  for k := 0 to 5 do g[k] := WantNum(gm.Items[k]);
  col := 0;
  if (Copy(key, 1, 2) = 's:') or (Copy(key, 1, 2) = 't:') then
    AssertTrue('a colour key', TyTryParseChartColor(Copy(key, 3, MaxInt), col));
  l := Drawn;
  found := False;
  hit := Default(TTyChartElement);
  for i := 0 to l.Count - 1 do
  begin
    e := l.Element(i);
    if e.ZrHit.SvgNode <= 0 then Continue;
    if Copy(key, 1, 2) = 's:' then
      found := IsPathShape(e) and (e.Style.StrokeColor = col)
    else if Copy(key, 1, 2) = 't:' then
      found := (e.Caption.FontSizeLogical > 0) and (e.Caption.Colour = col)
    else if key = 'img' then
      found := e.Style.FillPattern.Present and e.Style.FillPattern.HasMatrix;
    if found then
    begin
      hit := e;
      Break;
    end;
  end;
  Inc(FCompared);
  if not found then
  begin
    { what it does draw, to say what it is missing }
    what := what + ': the port draws no such element (its SVG paths:';
    for i := 0 to l.Count - 1 do
    begin
      e := l.Element(i);
      if (e.ZrHit.SvgNode > 0) and IsPathShape(e) then
        what := what + ' ' + IntToHex(e.Style.StrokeColor, 8) + '/' + Txt(e.Style.StrokeWidthLogical);
    end;
    Bad(what + ')');
    Exit;
  end;
  Inc(FEls);
  e := hit;
  if Copy(key, 1, 2) = 's:' then
  begin
    b := TyShapeBounds(e.Shape);
    bb := AEl.Arrays['bb'];
    NearVal(what + ' left', b.Left, WantNum(bb.Items[0]), 1e-6);
    NearVal(what + ' top', b.Top, WantNum(bb.Items[1]), 1e-6);
    NearVal(what + ' right', b.Right, WantNum(bb.Items[2]), 1e-6);
    NearVal(what + ' bottom', b.Bottom, WantNum(bb.Items[3]), 1e-6);
    NearVal(what + ' stroke', e.Style.StrokeWidthLogical, WantNum(AEl.Find('sw')), 1e-9);
    if not IsNull(AEl.Find('dash')) then
    begin
      dash := AEl.Arrays['dash'];
      Inc(FCompared);
      if Length(e.Style.DashLogical) <> dash.Count then
        Bad(Format('%s: %d dash numbers, upstream %d', [what, Length(e.Style.DashLogical), dash.Count]))
      else
        for k := 0 to dash.Count - 1 do
          NearVal(Format('%s dash[%d]', [what, k]), e.Style.DashLogical[k], WantNum(dash.Items[k]), 1e-9);
      NearVal(what + ' dash offset', e.Style.DashOffsetLogical, WantNum(AEl.Find('doff')), 1e-9);
    end;
  end
  else if Copy(key, 1, 2) = 't:' then
  begin
    { the glyphs as the screen sees them: through the whole map, or turned
      at a size }
    px := TyFontPxOf(e.Caption.FontSizeLogical);
    if e.Caption.HasAffine then
    begin
      det := Sqrt(Abs(e.Caption.Affine[0] * e.Caption.Affine[3] - e.Caption.Affine[2] * e.Caption.Affine[1]));
      NearVal(what + ' font px', px * det, WantNum(AEl.Find('fs')), 0.01 * det);
      for k := 0 to 5 do
        NearVal(Format('%s map[%d]', [what, k]), e.Caption.Affine[k], g[k], 1e-6);
      if not IsNull(AEl.Find('sw')) then
        NearVal(what + ' stroke', e.Caption.StrokeWidthLogical * det, WantNum(AEl.Find('sw')), 1e-9);
    end
    else
    begin
      NearVal(what + ' font px', px, WantNum(AEl.Find('fs')), 0.0051);
      NearVal(what + ' x', e.Caption.X, g[4], 1e-6);
      NearVal(what + ' y', e.Caption.Y, g[5], 1e-6);
      if not IsNull(AEl.Find('sw')) then
        NearVal(what + ' stroke', e.Caption.StrokeWidthLogical, WantNum(AEl.Find('sw')), 1e-9);
    end;
  end
  else
  begin
    { the image's unit square to the canvas: its box through gm }
    img := AEl.Arrays['img'];
    NearVal(what + ' m0', e.Style.FillPattern.Matrix[0], g[0] * WantNum(img.Items[2]), 1e-6);
    NearVal(what + ' m1', e.Style.FillPattern.Matrix[1], g[1] * WantNum(img.Items[2]), 1e-6);
    NearVal(what + ' m2', e.Style.FillPattern.Matrix[2], g[2] * WantNum(img.Items[3]), 1e-6);
    NearVal(what + ' m3', e.Style.FillPattern.Matrix[3], g[3] * WantNum(img.Items[3]), 1e-6);
    NearVal(what + ' m4', e.Style.FillPattern.Matrix[4],
      g[0] * WantNum(img.Items[0]) + g[2] * WantNum(img.Items[1]) + g[4], 1e-6);
    NearVal(what + ' m5', e.Style.FillPattern.Matrix[5],
      g[1] * WantNum(img.Items[0]) + g[3] * WantNum(img.Items[1]) + g[5], 1e-6);
  end;
end;

procedure TAdvChartGeoRoamTweenOracleTest.CheckSample(ARec: TJSONObject);
var
  i, j, key: Integer;
  name, view: string;
  els: TJSONArray;
begin
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    view := Copy(name, 1, Pos('/', name) - 1);
    if not ViewKeyOf(view, key) then Continue;
    if Copy(name, Pos('/', name) + 1, MaxInt) = 'group' then
      CheckGroup(name, key, TJSONObject(ARec.Items[i]))
    else
    begin
      els := TJSONArray(ARec.Items[i]);
      CheckRegions(view, key, els);
      for j := 0 to els.Count - 1 do CheckEl(view, key, els.Objects[j]);
    end;
  end;
end;

procedure TAdvChartGeoRoamTweenOracleTest.RunCase(ACase: TJSONObject);
var
  events: TJSONArray;
  ev: TJSONObject;
  j: Integer;
  t0, now_: Double;
  act: string;
begin
  FWhere := ACase.Strings['id'];
  NewChart(ACase.Integers['W'], ACase.Integers['H']);
  t0 := TJSONObject(FRoot).Objects['clock'].Floats['T0'];
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := t0;
  FChart.SetOption(ACase.Objects['option'].AsJSON, True);
  RenderNow;
  events := ACase.Arrays['events'];
  for j := 0 to events.Count - 1 do
  begin
    ev := events.Objects[j];
    now_ := t0 + ev.Floats['t'];
    act := ev.Strings['do'];
    FWhere := Format('%s t=%s %s', [ACase.Strings['id'], Txt(ev.Floats['t']), act]);
    FChart.AnimNow := now_;
    if act = 'sample' then
    begin
      FChart.AnimTick(now_);
      RenderNow;
      Inc(FSamples);
      CheckSample(ev.Objects['rec']);
    end
    else if act = 'merge' then
    begin
      FChart.SetOption(ev.Objects['option'].AsJSON, False);
      RenderNow;
    end
    else if act = 'action' then
      { no paint: what an action changes is drawn by the next frame }
      FChart.DispatchAction(ev.Objects['action'].AsJSON)
    else
      Bad('an event it does not know: ' + act);
  end;
  FChart.Measurer := nil;
  FreeAndNil(FChart);
end;

procedure TAdvChartGeoRoamTweenOracleTest.RunCases(const AIds: array of string; AMin: Integer);
var
  cases: TJSONArray;
  i, k, n: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  n := 0;
  for k := 0 to High(AIds) do
    for i := 0 to cases.Count - 1 do
      if cases.Objects[i].Strings['id'] = AIds[k] then
      begin
        try
          RunCase(cases.Objects[i]);
        except
          on E: Exception do
          begin
            Bad(E.ClassName + ': ' + E.Message);
            if FChart <> nil then FChart.Measurer := nil;
            FreeAndNil(FChart);
          end;
        end;
        Inc(n);
      end;
  AssertEquals('cases run', Length(AIds), n);
  if FBad > 0 then
    Fail(Format('%d of %d comparisons differ from upstream:%s', [FBad, FCompared, FReport]));
  AssertTrue(Format('comparisons made (%d)', [FCompared]), FCompared >= AMin);
  AssertTrue(Format('elements compared (%d)', [FEls]), FEls > 0);
end;

procedure TAdvChartGeoRoamTweenOracleTest.TestAnSvgMapIsSetAtOnce;
begin
  RunCases(['svg-geo-zoom', 'svg-map-out', 'svg-to-gj'], 200);
end;

procedure TAdvChartGeoRoamTweenOracleTest.TestAGeoJsonRegionKeepsItsScreenWidthThroughTheTween;
begin
  RunCases(['gj-geo-zoom'], 150);
end;

procedure TAdvChartGeoRoamTweenOracleTest.TestTheSvgContentRidesTheTweenOfASwitchedMap;
begin
  RunCases(['gj-to-svg', 'gj-to-svg-midway'], 600);
end;

procedure TAdvChartGeoRoamTweenOracleTest.TestAViewMadeAnewIsSetAtOnce;
begin
  RunCases(['gj-hide-svg', 'map-legend-gone'], 150);
end;

{ ==================== by hand ==================== }

const
  cGrtGeoJson = '{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"name":"A"},' +
    '"geometry":{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}}]}';
  { a 1 x 1 picture, turned and skewed by its own transform }
  cGrtSvg = '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" ' +
    'width="200" height="100" viewBox="0 0 200 100"><g transform="rotate(20 100 50) skewX(15)">' +
    '<rect x="20" y="20" width="40" height="30" fill="#ddeeff"/>' +
    '<image x="5" y="5" width="16" height="12" xlink:href="data:image/png;base64,' +
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="/>' +
    '</g></svg>';

procedure TAdvChartGeoRoamTweenTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the GeoJSON map registers', TyChartRegisterMap('r6hGj', cGrtGeoJson));
  AssertTrue('the SVG map registers', TyChartRegisterMap('r6hSvg', cGrtSvg));
  FChart := TGrtProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, 400, 300);
end;

procedure TAdvChartGeoRoamTweenTest.TearDown;
begin
  FreeAndNil(FChart);
  TyChartUnregisterMap('r6hGj');
  TyChartUnregisterMap('r6hSvg');
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartGeoRoamTweenTest.RenderAt(APPI: Integer);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width * APPI div 96, FChart.Height * APPI div 96,
    BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height), APPI);
  finally
    bmp.Free;
  end;
end;

{ AN SVG MAP'S IMAGE IN FLIGHT (a GeoJSON map switched to the SVG one: the
  group tweens): its pattern's map -- logical, the painter's PPI over it --
  takes the unit square onto the image's own corners as the frame draws
  them, at 144 dpi as at 96 }
procedure TAdvChartGeoRoamTweenTest.TestAnImageRidesTheTweenAtAnyDensity;
var
  ppi, i, k, found: Integer;
  l: TTyPaintList;
  e: TTyChartElement;
  s, ux, uy: Double;
  pts: TTyPointFArray;
  m: TTyMat2D;
begin
  for ppi in [96, 144] do
  begin
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := 1000;
    FChart.SetOption('{"animation":true,"animationDurationUpdate":1000,"animationEasingUpdate":"linear",' +
      '"geo":{"map":"r6hGj","roam":true}}', True);
    RenderAt(ppi);
    FChart.AnimNow := 2000;
    FChart.SetOption('{"geo":{"map":"r6hSvg","zoom":2,"center":[100,50]}}', False);
    RenderAt(ppi);
    FChart.AnimNow := 2400;
    FChart.AnimTick(2400);
    RenderAt(ppi);
    AssertTrue('the group tweens', FChart.AnimFindProxy(-1, 1, 'geoView') <> nil);
    l := FChart.Frame;
    AssertTrue('a frame is drawn', (l <> nil) and (l.Count > 0));
    s := ppi / 96;
    found := 0;
    for i := 0 to l.Count - 1 do
    begin
      e := l.Element(i);
      if not (e.Style.FillPattern.Present and e.Style.FillPattern.HasMatrix) then Continue;
      Inc(found);
      pts := e.Shape.Points;
      AssertEquals('four corners', 4, Length(pts));
      m := e.Style.FillPattern.Matrix;
      for k := 0 to 3 do
      begin
        if (k = 1) or (k = 2) then ux := 1 else ux := 0;
        if k >= 2 then uy := 1 else uy := 0;
        AssertEquals(Format('%d dpi: corner %d x', [ppi, k]), pts[k].X,
          (m[0] * ux + m[2] * uy + m[4]) * s, 1e-6);
        AssertEquals(Format('%d dpi: corner %d y', [ppi, k]), pts[k].Y,
          (m[1] * ux + m[3] * uy + m[5]) * s, 1e-6);
      end;
    end;
    AssertEquals(Format('%d dpi: the image is drawn once', [ppi]), 1, found);
  end;
end;

initialization
  RegisterTest(TAdvChartGeoRoamTweenOracleTest);
  RegisterTest(TAdvChartGeoRoamTweenTest);
end.
