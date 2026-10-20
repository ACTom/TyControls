unit test.advchart.geo;
{$mode objfpc}{$H+}
{ THE GEO FOUNDATION, HELD TO UPSTREAM [Batch 146, D14 GE1].

  tools/advchart-oracle/geo.js runs the real ECharts 6.1 build in node and
  records, per case, the maps it registered (the very text) and, per geo
  component, what the coordinate system made of them -- every region's name,
  centre, rect and points; the view's two rectangles and four matrices, the
  roam transform and the zoom; dataToPoint / pointToData / containPoint
  probes and the chart's convertToPixel / convertFromPixel -- and what the
  geo view drew: one group per region name, each compound path's points
  before the roam, the path a first canvas brush hands the context, its
  style, its stroked rect and its label.

  This registers the same texts, builds the same geos and compares bit for
  bit. The colours upstream takes from its tokens are the skin's here: where
  upstream's style is its default token the port must say "the theme's";
  everywhere else the text the option wrote. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.FontUnits, tyControls.Types, tyControls.StyleModel,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Shape, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Convert,
     tyControls.AdvChart.Data, tyControls.AdvChart.JsMath,
     tyControls.AdvChart.GeoFix, tyControls.AdvChart.Geo,
     tyControls.AdvanceChart, ualbersusa;
type
  TGeoProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  { the oracle's projections, the same arithmetic }
  TGeoProjections = class
  public
    function Sinu(AX, AY: Double; out ARX, ARY: Double): Boolean;
    function SinuInv(AX, AY: Double; out ARX, ARY: Double): Boolean;
    function Lin(AX, AY: Double; out ARX, ARY: Double): Boolean;
    function LinInv(AX, AY: Double; out ARX, ARY: Double): Boolean;
    function Cut(AX, AY: Double; out ARX, ARY: Double): Boolean;
    function CutInv(AX, AY: Double; out ARX, ARY: Double): Boolean;
  end;

  TAdvChartGeoOracleTest = class(TTestCase)
  private
    FRoot: TJSONData;
    FProj: TGeoProjections;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; const AHex: string);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameInt(const AWhat: string; AGot, AWant: Integer);
    procedure Finish(const AWhat: string; AMin: Integer);
    function Cases: TJSONArray;
    procedure RegisterMaps(ACase: TJSONObject);
    function OptionOf(ACase: TJSONObject): TTyChartOption;
    procedure ComparePt(const AWhat: string; AOk: Boolean; AX, AY: Double; AWant: TJSONData);
    procedure CompareRect(const AWhat: string; const R: TTyXYWH; AWant: TJSONData);
    procedure CompareMat(const AWhat: string; const M: TTyMat2D; AWant: TJSONData);
    procedure CompareRing(const AWhat: string; const R: TTyGeoRing; AWant: TJSONData);
    procedure CompareGeo(AGeo: TTyGeo; AWant: TJSONObject);
    procedure CompareDraw(AGeo: TTyGeo; AWant: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTanPiIsV8s;
    procedure TestEveryGeoAsUpstreamBuildsIt;
    procedure TestEveryPictureAsUpstreamDrawsIt;
    procedure TestTheChartConvertsAsUpstream;
    procedure TestWhatThrowsUpstreamDrawsNothing;
  end;

  TAdvChartGeoTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGeoProbe;
    FBmp: TBGRABitmap;
    procedure NewChart(const AOption: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRegisterMapRefusesWhatDoesNotParse;
    procedure TestTheWrapperFormCarriesItsSpecialAreas;
    procedure TestGetMapAnswersWhatWasRegistered;
    procedure TestTheDecoderByHand;
    procedure TestTheChinaTablesAreUpstreams;
    procedure TestAProjectionNobodyRegisteredIsNone;
    procedure TestTheMapIsDrawnInTheSkinsInk;
    procedure TestTheLabelsSitOverEveryRegion;
    procedure TestTheRoamMovesThePictureNotThePoints;
    procedure TestAMapNobodyRegisteredIsNoted;
  end;

implementation

uses tyControls.StrConsts;

const
  cW = 800;
  cH = 600;
  cJsPi: Double = 3.141592653589793;
  { upstream's token values: where the oracle holds one of these the port
    holds the skin's ink }
  cTokenArea = 'rgba(234,237,245,0.5)';
  cTokenBorder = '#b7b9be';
  cTokenLabel = '#6d6e73';

procedure TGeoProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TGeoProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TGeoProjections.Sinu(AX, AY: Double; out ARX, ARY: Double): Boolean;
begin
  ARX := AX * TyJsCos(AY * cJsPi / 180);
  ARY := -AY;
  Result := True;
end;

function TGeoProjections.SinuInv(AX, AY: Double; out ARX, ARY: Double): Boolean;
begin
  ARX := AX / TyJsCos(-AY * cJsPi / 180);
  ARY := -AY;
  Result := True;
end;

function TGeoProjections.Lin(AX, AY: Double; out ARX, ARY: Double): Boolean;
begin
  ARX := AX * 2 + 10;
  ARY := -AY * 3;
  Result := True;
end;

function TGeoProjections.LinInv(AX, AY: Double; out ARX, ARY: Double): Boolean;
begin
  ARX := (AX - 10) / 2;
  ARY := -AY / 3;
  Result := True;
end;

function TGeoProjections.Cut(AX, AY: Double; out ARX, ARY: Double): Boolean;
begin
  ARX := AX;
  ARY := -AY;
  Result := not (AY > 45);
end;

function TGeoProjections.CutInv(AX, AY: Double; out ARX, ARY: Double): Boolean;
begin
  ARX := AX;
  ARY := -AY;
  Result := True;
end;

{ ==================== helpers ==================== }

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
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function SameBits(A, B: Double): Boolean;
begin
  Result := (HexOf(A) = HexOf(B)) or (IsNan(A) and IsNan(B));
end;

function StrOrNull(AData: TJSONData): string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit('<null>');
  if AData.JSONType = jtString then Result := AData.AsString
  else Result := AData.AsJSON;
end;

procedure TAdvChartGeoOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath('advchart-geo.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-geo.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FProj := TGeoProjections.Create;
  TyChartRegisterGeoProjection('sinu', @FProj.Sinu);
  TyChartRegisterGeoProjection('sinuInv', @FProj.SinuInv);
  TyChartRegisterGeoProjection('lin', @FProj.Lin);
  TyChartRegisterGeoProjection('linInv', @FProj.LinInv);
  TyChartRegisterGeoProjection('cut', @FProj.Cut);
  TyChartRegisterGeoProjection('cutInv', @FProj.CutInv);
  { [R2-J2] d3-geo's geoAlbersUsa, the demo's transcription (case
    'albers-usa') }
  TyChartRegisterGeoProjection('albersUsa', @AlbersUsa.Project);
  TyChartRegisterGeoProjection('albersUsaInv', @AlbersUsa.Unproject);
  FBad := 0;
  FCompared := 0;
  FReport := '';
  FWhere := '';
end;

procedure TAdvChartGeoOracleTest.TearDown;
begin
  TyChartClearGeoProjections;
  TyChartClearMaps;
  FProj.Free;
  FRoot.Free;
  inherited TearDown;
end;

procedure TAdvChartGeoOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 12000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartGeoOracleTest.Same(const AWhat: string; AGot: Double; const AHex: string);
begin
  Inc(FCompared);
  if not SameBits(AGot, FromHex(AHex)) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(FromHex(AHex))]));
end;

procedure TAdvChartGeoOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then Bad(Format('%s "%s", upstream "%s"', [AWhat, AGot, AWant]));
end;

procedure TAdvChartGeoOracleTest.SameInt(const AWhat: string; AGot, AWant: Integer);
begin
  Inc(FCompared);
  if AGot <> AWant then Bad(Format('%s %d, upstream %d', [AWhat, AGot, AWant]));
end;

procedure TAdvChartGeoOracleTest.Finish(const AWhat: string; AMin: Integer);
begin
  AssertTrue(Format('%s: only %d compared', [AWhat, FCompared]), FCompared >= AMin);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

function TAdvChartGeoOracleTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

procedure TAdvChartGeoOracleTest.RegisterMaps(ACase: TJSONObject);
var maps: TJSONArray; i: Integer; m: TJSONObject; sp: string;
begin
  TyChartClearMaps;
  maps := ACase.Arrays['maps'];
  for i := 0 to maps.Count - 1 do
  begin
    m := maps.Objects[i];
    sp := '';
    if m.Find('special') is TJSONObject then sp := m.Objects['special'].AsJSON;
    AssertTrue('registered ' + m.Strings['name'],
      TyChartRegisterMap(m.Strings['name'], m.Strings['text'], sp));
  end;
end;

function TAdvChartGeoOracleTest.OptionOf(ACase: TJSONObject): TTyChartOption;
begin
  Result := TTyChartOption.Create;
  Result.SetOptionText(ACase.Objects['option'].AsJSON);
end;

procedure TAdvChartGeoOracleTest.ComparePt(const AWhat: string; AOk: Boolean;
  AX, AY: Double; AWant: TJSONData);
begin
  Inc(FCompared);
  if (AWant = nil) or (AWant.JSONType = jtNull) then
  begin
    if AOk then Bad(AWhat + ': a point, upstream none');
    Exit;
  end;
  if not AOk then
  begin
    Bad(AWhat + ': no point, upstream one');
    Exit;
  end;
  Same(AWhat + '.x', AX, TJSONArray(AWant).Strings[0]);
  Same(AWhat + '.y', AY, TJSONArray(AWant).Strings[1]);
end;

procedure TAdvChartGeoOracleTest.CompareRect(const AWhat: string; const R: TTyXYWH;
  AWant: TJSONData);
var a: TJSONArray;
begin
  a := TJSONArray(AWant);
  Same(AWhat + '.x', R.X, a.Strings[0]);
  Same(AWhat + '.y', R.Y, a.Strings[1]);
  Same(AWhat + '.w', R.W, a.Strings[2]);
  Same(AWhat + '.h', R.H, a.Strings[3]);
end;

procedure TAdvChartGeoOracleTest.CompareMat(const AWhat: string; const M: TTyMat2D;
  AWant: TJSONData);
var k: Integer;
begin
  for k := 0 to 5 do
    Same(Format('%s[%d]', [AWhat, k]), M[k], TJSONArray(AWant).Strings[k]);
end;

procedure TAdvChartGeoOracleTest.CompareRing(const AWhat: string; const R: TTyGeoRing;
  AWant: TJSONData);
var a: TJSONArray; k: Integer;
begin
  a := TJSONArray(AWant);
  SameInt(AWhat + ' points', Length(R), a.Count);
  if Length(R) <> a.Count then Exit;
  for k := 0 to a.Count - 1 do
  begin
    Same(Format('%s[%d].x', [AWhat, k]), R[k].X, a.Arrays[k].Strings[0]);
    Same(Format('%s[%d].y', [AWhat, k]), R[k].Y, a.Arrays[k].Strings[1]);
  end;
end;

procedure TAdvChartGeoOracleTest.CompareGeo(AGeo: TTyGeo; AWant: TJSONObject);
var
  regions, geoms, rings, probes: TJSONArray;
  i, k, r: Integer;
  reg: TTyGeoRegion;
  rw, gw, pw: TJSONObject;
  c: TTyGeoPt;
  px: TTyPointF;
  ok: Boolean;
  roam: TTyGeoTrans;
  d: TJSONData;
begin
  AssertTrue(FWhere + ': the geo is valid', AGeo.Valid);
  Same('aspectScale', AGeo.AspectScale, AWant.Strings['aspectScale']);
  Inc(FCompared);
  if AGeo.InvertY <> AWant.Booleans['invertY'] then Bad('invertY');
  Inc(FCompared);
  if AGeo.Projection.Active <> AWant.Booleans['projection'] then Bad('projection');
  { ---- the regions ---- }
  regions := AWant.Arrays['regions'];
  SameInt('regions', Length(AGeo.Source.Regions), regions.Count);
  if Length(AGeo.Source.Regions) = regions.Count then
    for i := 0 to regions.Count - 1 do
    begin
      reg := AGeo.Source.Regions[i];
      rw := regions.Objects[i];
      SameStr(Format('region %d name', [i]), reg.Name, rw.Strings['name']);
      c := reg.GetCenter;
      ComparePt(reg.Name + ' centre', True, c.X, c.Y, rw.Find('center'));
      CompareRect(reg.Name + ' rect', reg.BoundingRect, rw.Arrays['rect']);
      geoms := rw.Arrays['geoms'];
      SameInt(reg.Name + ' geometries', Length(reg.Geometries), geoms.Count);
      if Length(reg.Geometries) <> geoms.Count then Continue;
      for k := 0 to geoms.Count - 1 do
      begin
        gw := geoms.Objects[k];
        if gw.Strings['t'] = 'polygon' then
        begin
          Inc(FCompared);
          if reg.Geometries[k].Kind <> ggkPolygon then
          begin
            Bad(reg.Name + ' kind');
            Continue;
          end;
          CompareRing(Format('%s g%d ext', [reg.Name, k]), reg.Geometries[k].Exterior, gw.Arrays['ext']);
          rings := gw.Arrays['ints'];
          SameInt(reg.Name + ' holes', Length(reg.Geometries[k].Interiors), rings.Count);
          if Length(reg.Geometries[k].Interiors) = rings.Count then
            for r := 0 to rings.Count - 1 do
              CompareRing(Format('%s g%d int%d', [reg.Name, k, r]),
                reg.Geometries[k].Interiors[r], rings.Arrays[r]);
        end
        else
        begin
          Inc(FCompared);
          if reg.Geometries[k].Kind <> ggkLineString then
          begin
            Bad(reg.Name + ' kind');
            Continue;
          end;
          rings := gw.Arrays['lines'];
          SameInt(reg.Name + ' lines', Length(reg.Geometries[k].Lines), rings.Count);
          if Length(reg.Geometries[k].Lines) = rings.Count then
            for r := 0 to rings.Count - 1 do
              CompareRing(Format('%s g%d line%d', [reg.Name, k, r]),
                reg.Geometries[k].Lines[r], rings.Arrays[r]);
        end;
      end;
    end;
  { ---- the view ---- }
  CompareRect('dataRect', AGeo.DataRect, AWant.Arrays['dataRect']);
  CompareRect('viewRect', AGeo.ViewRect, AWant.Arrays['viewRect']);
  CompareMat('mtRaw', AGeo.MtRaw, AWant.Arrays['mtRaw']);
  CompareMat('mtRawInv', AGeo.MtRawInv, AWant.Arrays['mtRawInv']);
  CompareMat('mtOverall', AGeo.MtOverall, AWant.Arrays['mtOverall']);
  CompareMat('mtOverallInv', AGeo.MtOverallInv, AWant.Arrays['mtOverallInv']);
  roam := AGeo.RoamTrans;
  Same('roam.x', roam.X, AWant.Objects['roam'].Strings['x']);
  Same('roam.y', roam.Y, AWant.Objects['roam'].Strings['y']);
  Same('roam.sx', roam.ScaleX, AWant.Objects['roam'].Strings['sx']);
  Same('roam.sy', roam.ScaleY, AWant.Objects['roam'].Strings['sy']);
  Same('zoom', AGeo.Zoom, AWant.Strings['zoom']);
  { ---- the probes ---- }
  probes := AWant.Arrays['toPoint'];
  for i := 0 to probes.Count - 1 do
  begin
    pw := probes.Objects[i];
    d := pw.Find('data');
    ok := AGeo.ToPixelJson(d, px);
    ComparePt('dataToPoint ' + d.AsJSON, ok, px.X, px.Y, pw.Find('out'));
  end;
  probes := AWant.Arrays['fromPoint'];
  for i := 0 to probes.Count - 1 do
  begin
    pw := probes.Objects[i];
    ok := AGeo.DataOf(pw.Arrays['px'].Floats[0], pw.Arrays['px'].Floats[1], c);
    ComparePt('pointToData ' + pw.Arrays['px'].AsJSON, ok, c.X, c.Y, pw.Find('out'));
  end;
  probes := AWant.Arrays['contain'];
  for i := 0 to probes.Count - 1 do
  begin
    pw := probes.Objects[i];
    Inc(FCompared);
    if AGeo.ContainPoint(TyPointF(pw.Arrays['px'].Floats[0], pw.Arrays['px'].Floats[1]))
      <> pw.Booleans['in'] then
      Bad('containPoint ' + pw.Arrays['px'].AsJSON);
  end;
end;

{ upstream's style string against where the port took the value from }
procedure CheckInk(T: TAdvChartGeoOracleTest; const AWhat: string; ASrc: TTyGeoInkSource;
  const ARaw: string; AWant: TJSONData; const AToken: string);
var want: string;
begin
  want := StrOrNull(AWant);
  if want = '<null>' then
    T.SameStr(AWhat, BoolToStr(ASrc = gisNone, 'none', 'painted'), 'none')
  else if (want = AToken) and (ASrc = gisTheme) then
    T.SameStr(AWhat, 'theme', 'theme')
  else
    T.SameStr(AWhat, ARaw, want);
end;

procedure TAdvChartGeoOracleTest.CompareDraw(AGeo: TTyGeo; AWant: TJSONObject);
var
  ink: TTyGeoInk;
  dr: TTyGeoDraw;
  groups, paths, subs, drawn, cmd: TJSONArray;
  gw, pw, sw, lw: TJSONObject;
  g, k, s, j: Integer;
  p: TTyGeoDrawPath;
  kind: string;
  wantKind: TTyPathCmdKind;
  d: TJSONData;
begin
  ink := Default(TTyGeoInk);
  ink.AreaFill := $FF112233;
  ink.Border := $FF445566;
  ink.LabelColour := $FF778899;
  ink.LabelFontName := '';
  ink.LabelFontSizeLogical := 12;
  ink.LabelFontWeight := 400;
  dr := TyGeoDrawOf(AGeo, ink, 96);
  if AWant.Find('draw').JSONType = jtNull then
  begin
    SameInt('groups of a geo that draws nothing', Length(dr.Groups), 0);
    Exit;
  end;
  AWant := AWant.Objects['draw'];
  Inc(FCompared);
  if dr.HasClip <> (AWant.Find('clip').JSONType <> jtNull) then Bad('clip');
  if dr.HasClip and (AWant.Find('clip').JSONType <> jtNull) then
    CompareRect('clip', dr.Clip, AWant.Arrays['clip']);
  Same('trans.x', TyGeoApply(dr.Trans, 0, 0).X, AWant.Objects['trans'].Strings['x']);
  Same('trans.y', TyGeoApply(dr.Trans, 0, 0).Y, AWant.Objects['trans'].Strings['y']);
  Same('trans.sx', dr.Trans[0], AWant.Objects['trans'].Strings['sx']);
  Same('trans.sy', dr.Trans[3], AWant.Objects['trans'].Strings['sy']);
  groups := AWant.Arrays['groups'];
  SameInt('groups', Length(dr.Groups), groups.Count);
  if Length(dr.Groups) <> groups.Count then Exit;
  for g := 0 to groups.Count - 1 do
  begin
    gw := groups.Objects[g];
    SameStr(Format('group %d', [g]), dr.Groups[g].Name, gw.Strings['name']);
    d := gw.Find('silent');
    { MapDraw sets a group's silent only from the region's own option; an
      unset one reads false through the prototype }
    Inc(FCompared);
    if dr.Groups[g].HasSilent and ((d = nil) or (d.JSONType <> jtBoolean)
      or (dr.Groups[g].Silent <> d.AsBoolean)) then
      Bad(dr.Groups[g].Name + ' silent');
    paths := gw.Arrays['paths'];
    SameInt(dr.Groups[g].Name + ' paths', Length(dr.Groups[g].Paths), paths.Count);
    if Length(dr.Groups[g].Paths) <> paths.Count then Continue;
    for k := 0 to paths.Count - 1 do
    begin
      p := dr.Groups[g].Paths[k];
      pw := paths.Objects[k];
      SameStr(dr.Groups[g].Name + ' kind', BoolToStr(p.IsLine, 'polyline', 'polygon'),
        pw.Strings['kind']);
      subs := pw.Arrays['subs'];
      SameInt(dr.Groups[g].Name + ' subs', Length(p.Subs), subs.Count);
      if Length(p.Subs) = subs.Count then
        for s := 0 to subs.Count - 1 do
          CompareRing(Format('%s sub%d', [dr.Groups[g].Name, s]), p.Subs[s], subs.Arrays[s]);
      { the drawn path }
      drawn := pw.Arrays['drawn'];
      SameInt(dr.Groups[g].Name + ' drawn', Length(p.Drawn), drawn.Count);
      if Length(p.Drawn) = drawn.Count then
        for j := 0 to drawn.Count - 1 do
        begin
          cmd := drawn.Arrays[j];
          kind := cmd.Strings[0];
          if kind = 'M' then wantKind := pckMove
          else if kind = 'L' then wantKind := pckLine
          else wantKind := pckClose;
          Inc(FCompared);
          if p.Drawn[j].Kind <> wantKind then
          begin
            Bad(Format('%s drawn[%d] is not %s', [dr.Groups[g].Name, j, kind]));
            Continue;
          end;
          if wantKind <> pckClose then
          begin
            Same(Format('%s drawn[%d].x', [dr.Groups[g].Name, j]), p.Drawn[j].X, cmd.Strings[1]);
            Same(Format('%s drawn[%d].y', [dr.Groups[g].Name, j]), p.Drawn[j].Y, cmd.Strings[2]);
          end;
        end;
      Same(dr.Groups[g].Name + ' ux', dr.UX, HexOf(Abs(1 / FromHex(pw.Arrays['scale'].Strings[0]))));
      { the style }
      sw := pw.Objects['style'];
      CheckInk(Self, dr.Groups[g].Name + ' fill', p.Paint.FillSrc, p.Paint.FillRaw,
        sw.Find('fill'), cTokenArea);
      CheckInk(Self, dr.Groups[g].Name + ' stroke', p.Paint.StrokeSrc, p.Paint.StrokeRaw,
        sw.Find('stroke'), cTokenBorder);
      if sw.Find('lineWidth').JSONType <> jtNull then
        Same(dr.Groups[g].Name + ' lineWidth', p.Paint.LineWidthLogical, sw.Strings['lineWidth']);
      if p.Paint.HasOpacity then
        Same(dr.Groups[g].Name + ' opacity', p.Paint.Opacity, sw.Strings['opacity'])
      else
        Same(dr.Groups[g].Name + ' opacity', 1, sw.Strings['opacity']);
      SameStr(dr.Groups[g].Name + ' lineDash', p.Paint.DashRaw,
        StringReplace(StrOrNull(sw.Find('lineDash')), '<null>', '', []));
      SameInt(dr.Groups[g].Name + ' z', AGeo.Spec.Z, pw.Integers['z']);
      SameInt(dr.Groups[g].Name + ' z2', 0, pw.Integers['z2']);
      SameInt(dr.Groups[g].Name + ' zlevel', AGeo.Spec.ZLevel, pw.Integers['zlevel']);
      CompareRect(dr.Groups[g].Name + ' rect', p.BoxRect, pw.Arrays['rect']);
      { the label }
      if pw.Find('label').JSONType = jtNull then
      begin
        Inc(FCompared);
        if p.Lbl.Shown then Bad(dr.Groups[g].Name + ' label shown, upstream none');
        Continue;
      end;
      lw := pw.Objects['label'];
      Inc(FCompared);
      if p.Lbl.Shown = lw.Booleans['ignore'] then
        Bad(Format('%s label shown %s, upstream ignore %s', [dr.Groups[g].Name,
          BoolToStr(p.Lbl.Shown, True), BoolToStr(lw.Booleans['ignore'], True)]));
      SameStr(dr.Groups[g].Name + ' label text', p.Lbl.Text, lw.Strings['text']);
      if lw.Strings['fill'] = cTokenLabel then
        SameStr(dr.Groups[g].Name + ' label fill', BoolToStr(p.Lbl.HasColour, 'option', 'theme'), 'theme')
      else
        SameStr(dr.Groups[g].Name + ' label fill', p.Lbl.ColourRaw, lw.Strings['fill']);
      if p.Lbl.HasFontSize then
        Same(dr.Groups[g].Name + ' label size', TyFontPxOf(p.Lbl.FontSizeLogical),
          HexOf(lw.Floats['fontSize']))
      else
        SameInt(dr.Groups[g].Name + ' label size (default)', 12, lw.Integers['fontSize']);
      { [R2-J2] A REGION WITH NO CENTRE -- one a projection answers null for
        (Puerto Rico under albersUsa): no labelXY, so upstream keeps
        textConfig.position 'inside' with no layout rect and no align; the
        port gives the label no position }
      if not (lw.Find('pos') is TJSONArray) then
      begin
        Inc(FCompared);
        if p.Lbl.HasPos then Bad(dr.Groups[g].Name + ' label placed, upstream has no centre');
        Continue;
      end;
      SameStr(dr.Groups[g].Name + ' label align', 'center', lw.Strings['align']);
      SameStr(dr.Groups[g].Name + ' label valign', 'middle', lw.Strings['verticalAlign']);
      SameInt(dr.Groups[g].Name + ' label z2', 2, lw.Integers['z2']);
      Inc(FCompared);
      if not p.Lbl.HasPos then
      begin
        Bad(dr.Groups[g].Name + ' label has no position');
        Continue;
      end;
      Same(dr.Groups[g].Name + ' label pct x', p.Lbl.PctX,
        HexOf(TyJsParseFloat(lw.Arrays['pos'].Strings[0])));
      Same(dr.Groups[g].Name + ' label pct y', p.Lbl.PctY,
        HexOf(TyJsParseFloat(lw.Arrays['pos'].Strings[1])));
      CompareRect(dr.Groups[g].Name + ' label layout', p.Lbl.Layout, lw.Arrays['layout']);
      if not lw.Booleans['ignore'] then
      begin
        Same(dr.Groups[g].Name + ' label x', p.Lbl.AnchorX, lw.Strings['x']);
        Same(dr.Groups[g].Name + ' label y', p.Lbl.AnchorY, lw.Strings['y']);
      end;
    end;
  end;
end;

{ ==================== the oracle suite ==================== }

procedure TAdvChartGeoOracleTest.TestTanPiIsV8s;
begin
  { the skew a flipped view decomposes into: the one Double V8 answers }
  AssertEquals('tan(PI)', TJSONObject(FRoot).Strings['tanPi'], HexOf(TyJsTan(cJsPi)));
  AssertTrue('and not zero', TyJsTan(cJsPi) <> 0);
end;

procedure TAdvChartGeoOracleTest.TestEveryGeoAsUpstreamBuildsIt;
var
  i, k: Integer;
  cs: TJSONObject;
  geos: TJSONArray;
  opt: TTyChartOption;
  geo: TTyGeo;
begin
  for i := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[i];
    if cs.Find('throws') <> nil then Continue;
    RegisterMaps(cs);
    opt := OptionOf(cs);
    try
      geos := cs.Arrays['geos'];
      AssertEquals(cs.Strings['id'] + ': geo count', geos.Count, opt.ComponentCount('geo'));
      for k := 0 to geos.Count - 1 do
      begin
        FWhere := Format('%s geo %d', [cs.Strings['id'], k]);
        geo := TTyGeo.Create(opt, k);
        try
          geo.Resize(TyRectF(0, 0, cs.Integers['W'], cs.Integers['H']), 96);
          CompareGeo(geo, geos.Objects[k]);
        finally
          geo.Free;
        end;
      end;
    finally
      opt.Free;
    end;
  end;
  Finish('geos', 20000);
end;

procedure TAdvChartGeoOracleTest.TestEveryPictureAsUpstreamDrawsIt;
var
  i, k: Integer;
  cs: TJSONObject;
  geos: TJSONArray;
  opt: TTyChartOption;
  geo: TTyGeo;
begin
  for i := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[i];
    if cs.Find('throws') <> nil then Continue;
    RegisterMaps(cs);
    opt := OptionOf(cs);
    try
      geos := cs.Arrays['geos'];
      for k := 0 to geos.Count - 1 do
      begin
        FWhere := Format('%s geo %d', [cs.Strings['id'], k]);
        geo := TTyGeo.Create(opt, k);
        try
          geo.Resize(TyRectF(0, 0, cs.Integers['W'], cs.Integers['H']), 96);
          AssertTrue(FWhere + ': valid', geo.Valid);
          CompareDraw(geo, geos.Objects[k]);
        finally
          geo.Free;
        end;
      end;
    finally
      opt.Free;
    end;
  end;
  Finish('pictures', 20000);
end;

procedure TAdvChartGeoOracleTest.TestTheChartConvertsAsUpstream;
var
  i, k, j: Integer;
  cs, cv: TJSONObject;
  geos, conv: TJSONArray;
  form: TForm;
  ctl: TTyStyleController;
  chart: TGeoProbe;
  bmp: TBGRABitmap;
  r: TTyConvertResult;
  opt: TJSONObject;
  ok: Boolean;
begin
  form := TForm.CreateNew(nil);
  ctl := TTyStyleController.Create(nil);
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  chart := nil;
  try
    ctl.Mode := 'light';
    ctl.ThemeName := 'default';
    for i := 0 to Cases.Count - 1 do
    begin
      cs := Cases.Objects[i];
      if cs.Find('throws') <> nil then Continue;
      RegisterMaps(cs);
      FreeAndNil(chart);
      chart := TGeoProbe.Create(form);
      chart.Parent := form;
      chart.Controller := ctl;
      opt := TJSONObject(cs.Objects['option'].Clone);
      try
        opt.Add('animation', False);
        chart.Option := opt.AsJSON;
      finally
        opt.Free;
      end;
      chart.SetBounds(0, 0, cW, cH);
      chart.Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
      geos := cs.Arrays['geos'];
      SameInt(cs.Strings['id'] + ' geo count', chart.GeoCount, geos.Count);
      for k := 0 to geos.Count - 1 do
      begin
        FWhere := Format('%s geo %d (chart)', [cs.Strings['id'], k]);
        { the control's geo is the suite's geo }
        if chart.GeoLayout(k) <> nil then
          CompareMat('mtOverall', chart.GeoLayout(k).MtOverall, geos.Objects[k].Arrays['mtOverall']);
        conv := geos.Objects[k].Arrays['convert'];
        for j := 0 to conv.Count - 1 do
        begin
          cv := conv.Objects[j];
          if cv.Find('value') <> nil then
          begin
            r := chart.ConvertToPixelData(cv.Objects['finder'], cv.Find('value'));
            ok := r.Kind = cvkArray;
            if ok then
              ComparePt('convertToPixel ' + cv.Find('value').AsJSON, ok, r.Values[0], r.Values[1], cv.Find('to'))
            else
              ComparePt('convertToPixel ' + cv.Find('value').AsJSON, ok, NaN, NaN, cv.Find('to'));
          end
          else
          begin
            r := chart.ConvertFromPixelData(cv.Objects['finder'], cv.Find('pixel'));
            ok := r.Kind = cvkArray;
            if ok then
              ComparePt('convertFromPixel', ok, r.Values[0], r.Values[1], cv.Find('from'))
            else
              ComparePt('convertFromPixel', ok, NaN, NaN, cv.Find('from'));
          end;
        end;
      end;
    end;
  finally
    chart.Free;
    bmp.Free;
    ctl.Free;
    form.Free;
  end;
  Finish('conversions', 300);
end;

procedure TAdvChartGeoOracleTest.TestWhatThrowsUpstreamDrawsNothing;
var
  i, n: Integer;
  cs: TJSONObject;
  opt: TTyChartOption;
  geo: TTyGeo;
  ink: TTyGeoInk;
begin
  n := 0;
  ink := Default(TTyGeoInk);
  for i := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[i];
    if cs.Find('throws') = nil then Continue;
    Inc(n);
    RegisterMaps(cs);
    opt := OptionOf(cs);
    geo := TTyGeo.Create(opt, 0);
    try
      geo.Resize(TyRectF(0, 0, cW, cH), 96);
      { upstream's setOption throws; the port's geo is simply not there }
      AssertFalse(cs.Strings['id'] + ': no geo', geo.Valid);
      AssertEquals(cs.Strings['id'] + ': nothing drawn', 0,
        Length(TyGeoDrawOf(geo, ink, 96).Groups));
    finally
      geo.Free;
      opt.Free;
    end;
  end;
  AssertEquals('both throwing cases', 2, n);
end;

{ ==================== the hand-written suite ==================== }

const
  cSquare = '{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"name":"A"},'
    + '"geometry":{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}},'
    + '{"type":"Feature","properties":{"name":"B"},'
    + '"geometry":{"type":"Polygon","coordinates":[[[20,0],[30,0],[30,10],[20,10],[20,0]]]}}]}';

procedure TAdvChartGeoTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FChart := nil;
  TyChartClearMaps;
end;

procedure TAdvChartGeoTest.TearDown;
begin
  FChart.Free;
  FBmp.Free;
  FCtl.Free;
  FForm.Free;
  TyChartClearMaps;
  TyChartClearGeoProjections;
  inherited TearDown;
end;

procedure TAdvChartGeoTest.NewChart(const AOption: string);
begin
  FChart.Free;
  FChart := TGeoProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartGeoTest.TestAMapNobodyRegisteredIsNoted;
var
  i: Integer;
  s: string;
begin
  { [F1b] an empty geo used to be silent: upstream warns in its console, the
    control said nothing, and 15 gallery charts drew a blank }
  AssertTrue(TyChartRegisterMap('sq', cSquare));
  NewChart('{"animation": false, "geo": [{"map": "sq"}, {"map": "f1bNowhere"}],'
    + ' "series": [{"type": "map", "map": "f1bNowhereToo"}]}');
  s := '';
  for i := 0 to FChart.DiagnosticCount - 1 do
    if Pos('no map is registered', FChart.Diagnostic(i)) > 0 then
      s := s + FChart.Diagnostic(i) + '|';
  AssertEquals(Format(rsTyChartMapNotRegistered, ['geo[1]', 'f1bNowhere']) + '|'
    + Format(rsTyChartMapNotRegistered, ['series[0]', 'f1bNowhereToo']) + '|', s);
end;

procedure TAdvChartGeoTest.TestRegisterMapRefusesWhatDoesNotParse;
var deep: string; i: Integer; js, sp: string;
begin
  AssertTrue('a map', TyChartRegisterMap('m', cSquare));
  { too deep for the option reader's guard: refused before fpjson recurses }
  deep := '';
  for i := 1 to 400 do deep := deep + '[';
  AssertFalse('too deep', TyChartRegisterMap('m', deep));
  AssertFalse('not JSON', TyChartRegisterMap('m', '{"type": '));
  { an SVG map is taken since F6b (registerMap(name, {svg})): under its own
    name, so the GeoJSON one below stands }
  AssertTrue('svg', TyChartRegisterMap('s', '{"svg": "<svg></svg>"}'));
  AssertFalse('special areas that do not parse', TyChartRegisterMap('m', cSquare, '{x'));
  { and the registration before them stands }
  AssertTrue('still registered', TyChartGetMap('m', js, sp));
  AssertTrue('the first text', Pos('"A"', js) > 0);
end;

procedure TAdvChartGeoTest.TestTheWrapperFormCarriesItsSpecialAreas;
var src: TTyGeoSource; r: TTyGeoRegion;
begin
  { the wrapper form, geoJSON with specialAreas: the wrapper's areas win
    over the argument }
  AssertTrue('the wrapper', TyChartRegisterMap('w', '{"geoJSON": ' + cSquare
    + ', "specialAreas": {"B": {"left": 100, "top": 50, "width": 20}}}',
    '{"A": {"left": -50, "top": 0, "width": 5}}'));
  src := TyGeoLoadMap('w', nil, 'name');
  try
    AssertNotNull('loaded', src);
    r := src.RegionByName('B');
    AssertEquals('B moved to its box', 100, r.BoundingRect.X);
    AssertEquals('B''s height from its aspect', 20, r.BoundingRect.H);
    AssertEquals('A not moved: the argument lost', 0, src.RegionByName('A').BoundingRect.X);
  finally
    src.Free;
  end;
  { the GeoJSON as a string inside the wrapper (geoJson, the old spelling) }
  AssertTrue('a string inside the wrapper',
    TyChartRegisterMap('w2', '{"geoJson": "' + StringToJSONString(cSquare) + '"}'));
  src := TyGeoLoadMap('w2', nil, 'name');
  try
    AssertNotNull('loaded from a string', src);
    AssertEquals('two regions', 2, Length(src.Regions));
  finally
    src.Free;
  end;
end;

procedure TAdvChartGeoTest.TestGetMapAnswersWhatWasRegistered;
var js, sp: string;
begin
  AssertFalse('nobody registered it', TyChartGetMap('none', js, sp));
  AssertTrue(TyChartRegisterMap('g', cSquare, '{"A": {"left": 1, "top": 2, "width": 3}}'));
  AssertTrue(TyChartGetMap('g', js, sp));
  AssertTrue('the text', Pos('FeatureCollection', js) > 0);
  AssertTrue('the special areas', Pos('"left"', sp) > 0);
  AssertTrue(TyChartMapRegistered('g'));
  TyChartUnregisterMap('g');
  AssertFalse(TyChartMapRegistered('g'));
end;

procedure TAdvChartGeoTest.TestTheDecoderByHand;
var r: TTyGeoRing;
begin
  { '@' is a delta of nought: the offsets themselves, over the scale }
  r := TyGeoDecodeRing('@@', 10240, 25600, 1024);
  AssertEquals(1, Length(r));
  AssertEquals(10, r[0].X);
  AssertEquals(25, r[0].Y);
  { 'A' is 1, zigzag -1; the y of an odd tail is charCodeAt past the end --
    not a number -- which the bitwise operators read as nought }
  r := TyGeoDecodeRing('@@A', 1024, 2048, 1024);
  AssertEquals(2, Length(r));
  AssertEquals('x', (1024 - 1) / 1024, r[1].X);
  AssertEquals('y', 2, r[1].Y);
  { 'B' is 2, zigzag +1, and the deltas run on }
  r := TyGeoDecodeRing('@@BB', 0, 0, 2);
  AssertEquals(0.5, r[1].X);
  AssertEquals(0.5, r[1].Y);
end;

procedure TAdvChartGeoTest.TestTheChinaTablesAreUpstreams;
var rings: TTyGeoRingArray; dx, dy: Double;
begin
  rings := TyGeoNanhaiRings;
  AssertEquals('twelve rings', 12, Length(rings));
  { [0, 3.5] / 10.5 + 126, 3.5 / (-10.5 / 0.75) + 25 }
  AssertEquals(HexOf(0 / 10.5 + 126), HexOf(rings[0][0].X));
  AssertEquals(HexOf(3.5 / -14.0 + 25), HexOf(rings[0][0].Y));
  AssertEquals('the frame', 9, Length(rings[11]));
  AssertEquals('the island', 5, Length(TyGeoDiaoyuRing));
  AssertTrue(TyGeoTextOffset(TyGeoNanhaiName, dx, dy));
  AssertEquals(32, dx);
  AssertEquals(80, dy);
  AssertFalse('Beijing is commented out upstream', TyGeoTextOffset('X', dx, dy));
end;

procedure TAdvChartGeoTest.TestAProjectionNobodyRegisteredIsNone;
var opt: TTyChartOption; geo: TTyGeo;
begin
  AssertTrue(TyChartRegisterMap('sq', cSquare));
  opt := TTyChartOption.Create;
  try
    opt.SetOptionText('{"geo": {"map": "sq", "projection": {"project": "@nobody", "unproject": "@nobody2"}}}');
    geo := TTyGeo.Create(opt, 0);
    try
      geo.Resize(TyRectF(0, 0, cW, cH), 96);
      AssertTrue(geo.Valid);
      AssertFalse('no projection', geo.Projection.Active);
      { upstream decides the flip on the option before it drops a
        projection that lacks a function: the y axis is NOT inverted }
      AssertFalse('y is not inverted: the option had a projection', geo.InvertY);
      AssertEquals('but the default aspect scale', 0.75, geo.AspectScale);
    finally
      geo.Free;
    end;
  finally
    opt.Free;
  end;
end;

procedure TAdvChartGeoTest.TestTheMapIsDrawnInTheSkinsInk;
var
  list: TTyPaintList;
  i, regions: Integer;
  el: TTyChartElement;
  light: TTyChartColor;
  st: TTyStyleSet;
begin
  AssertTrue(TyChartRegisterMap('sq', cSquare));
  NewChart('{"animation": false, "geo": {"map": "sq"}}');
  list := FChart.List;
  regions := 0;
  light := 0;
  for i := 0 to list.Count - 1 do
  begin
    el := list.Element(i);
    if el.Shape.Kind <> cskPolygon then Continue;
    Inc(regions);
    AssertTrue('filled', el.Style.HasFill);
    AssertTrue('rimmed', el.Style.StrokeWidthLogical > 0);
    AssertEquals('half a pixel', 0.5, el.Style.StrokeWidthLogical);
    AssertEquals('z2 0', 0, el.Z2);
    { [Batch 148: silent until GE2; a region is hit by its own path now] }
    AssertFalse('hit since GE2', el.Silent);
    AssertTrue('by upstream''s Path.contain', el.PathHit.Active);
    AssertTrue('a closed path', Length(el.Shape.Cmds) >= 5);
    light := el.Style.FillColor;
  end;
  AssertEquals('one path a region', 2, regions);
  { the ink is the skin's: the geo area key, not upstream's literal }
  st := FCtl.Model.ResolveStyle('TyAdvChartGeoArea', '', []);
  AssertEquals('the skin''s area fill', HexStr(TTyChartColor(st.Background.Color), 8),
    HexStr(light, 8));
  AssertTrue('mostly surface: a tint, not the accent',
    ((light shr 16) and $FF) + ((light shr 8) and $FF) + (light and $FF) > 600);
  { the option's colour wins }
  NewChart('{"animation": false, "geo": {"map": "sq", "itemStyle": {"areaColor": "#ff0000"}}}');
  for i := 0 to FChart.List.Count - 1 do
    if FChart.List.Element(i).Shape.Kind = cskPolygon then
      AssertEquals('areaColor', HexStr($FFFF0000, 8),
        HexStr(FChart.List.Element(i).Style.FillColor, 8));
end;

procedure TAdvChartGeoTest.TestTheLabelsSitOverEveryRegion;
var
  list: TTyPaintList;
  i, lastRegion, firstLabel: Integer;
  el: TTyChartElement;
  texts: string;
begin
  AssertTrue(TyChartRegisterMap('sq', cSquare));
  NewChart('{"animation": false, "geo": {"map": "sq", "label": {"show": true}}}');
  list := FChart.List;
  lastRegion := -1;
  firstLabel := MaxInt;
  texts := '';
  for i := 0 to list.Count - 1 do
  begin
    el := list.Element(list.PaintOrder(i));
    if el.Shape.Kind = cskPolygon then lastRegion := i;
    if el.Caption.Text <> '' then
    begin
      if i < firstLabel then firstLabel := i;
      texts := texts + el.Caption.Text + ',';
      AssertEquals('z2 2', 2, el.Z2);
      AssertTrue('centred', el.Caption.AnchorH = tahCentre);
    end;
  end;
  AssertEquals('both names', 'A,B,', texts);
  AssertTrue('every label paints after every region', firstLabel > lastRegion);
  { label.show off: none drawn [Batch 148: the text is there, ignored --
    emphasis.label.show is true by default, so a hover shows it] }
  NewChart('{"animation": false, "geo": {"map": "sq"}}');
  for i := 0 to FChart.List.Count - 1 do
    if not FChart.List.Element(i).Ignore then
      AssertEquals('no label', '', FChart.List.Element(i).Caption.Text);
end;

procedure TAdvChartGeoTest.TestTheRoamMovesThePictureNotThePoints;
var
  geo: TTyGeo;
  dr: TTyGeoDraw;
  ink: TTyGeoInk;
  i: Integer;
  el: TTyChartElement;
  m: TTyMat2D;
  q: TTyGeoPt;
  px: TTyPointF;
  found: Boolean;
begin
  AssertTrue(TyChartRegisterMap('sq', cSquare));
  NewChart('{"animation": false, "geo": {"map": "sq", "zoom": 2, "center": [5, 5]}}');
  geo := FChart.GeoLayout(0);
  AssertNotNull(geo);
  AssertTrue('a roam transform', geo.HasRoamTransform);
  ink := Default(TTyGeoInk);
  dr := TyGeoDrawOf(geo, ink, 96);
  m := geo.RoamMatrix;
  { the element's first point is the local first point through the roam }
  found := False;
  for i := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(i);
    if el.Shape.Kind <> cskPolygon then Continue;
    q := TyGeoApply(m, dr.Groups[0].Paths[0].Drawn[0].X, dr.Groups[0].Paths[0].Drawn[0].Y);
    AssertEquals('x', HexOf(q.X), HexOf(el.Shape.Cmds[0].X));
    AssertEquals('y', HexOf(q.Y), HexOf(el.Shape.Cmds[0].Y));
    found := True;
    Break;
  end;
  AssertTrue(found);
  { the threshold shrinks with the zoom: a pixel on the screen }
  AssertEquals('ux', 0.5, dr.UX);
  { and the centre lands in the middle of the view }
  AssertTrue(geo.PointOf(5, 5, px));
  AssertEquals('centre x', geo.ViewRect.X + geo.ViewRect.W / 2, px.X, 1e-9);
  AssertEquals('centre y', geo.ViewRect.Y + geo.ViewRect.H / 2, px.Y, 1e-9);
end;

initialization
  RegisterTest(TAdvChartGeoOracleTest);
  RegisterTest(TAdvChartGeoTest);
end.
