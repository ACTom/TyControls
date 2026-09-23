unit test.advchart.coordaffine;
{$mode objfpc}{$H+}
{ Where a value lands on a cartesian -- held to upstream to the bit.

  tools/advchart-oracle/coord-affine.js runs the real ECharts 6.1 build and
  records, per grid, the rect as upstream holds it (x, y, width, height), the
  affine matrix a value x value or time x value cartesian places its data
  through and its inverse, the clip area, each axis' local pixel extent,
  where its ticks land, the line it sits on and the floor its bars stand on;
  per series item the point dataToPoint gave and by which path, a bar's
  layout and its box after the clip, a pictorial bar's floor, and a line's
  vertices as the Float32Array holds them; and a set of direct probes --
  dataToPoint on finite, infinite, missing and clamped values, pointToData
  through the inverse and per axis, and the pointer's clamped pixel.

  THE RULES IT HOLDS THE PORT TO: an axis maps into its own coordinate first
  -- linearMap over [0, w], which hands an end back verbatim -- and then onto
  the canvas, `c + x` across and `(sum - c) + y` down; a width that was given
  is the width, not an edge less an edge; a time value is rounded to the
  millisecond before it is placed per axis, the matrix's ends included; one
  value that is not finite sends the whole point down the per-axis path; a
  bar is `coord + offset` wide of its point and clipped as x and width; a
  line vertex is a single.

  Everything is compared to the bit, except a pixel taken back to a value on
  a log axis -- a power of the base to a fractional exponent, where FPC's
  Power and V8's Math.pow part by up to twelve units in the last place until
  fdlibm's pow is ported -- and the rects a documentary case measures text
  for. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Builder,
     tyControls.AdvChart.BarLayout, tyControls.AdvChart.Layout,
     tyControls.AdvanceChart;
type
  TCoordAffineProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function Column(ASeriesIndex: Integer): TTyBarColumn;
  end;

  TAdvChartCoordAffineOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCoordAffineProbe;
    FRoot: TJSONData;
    FBad, FCompared, FAffine, FBoxes, FVertices, FLabels: Integer;
    FReport: string;
    FName: string;
    FTol: Double;
    FLogCase: Boolean;
    procedure Miss(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure CheckGrid(ACase, AGrid: TJSONObject; AGridIndex: Integer);
    procedure CheckAxis(AGrid: TTyGridBuild; AAxis: TJSONObject);
    procedure CheckSeries(ACart: TTyCartesian2D; ASeries: TJSONObject);
    procedure CheckProbe(ACart: TTyCartesian2D; AProbe: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryCoordinateLandsWhereUpstreamPutsIt;
  end;

implementation

procedure TCoordAffineProbe.Render(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TCoordAffineProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TCoordAffineProbe.Column(ASeriesIndex: Integer): TTyBarColumn;
begin
  Result := BarColumnOf(ASeriesIndex);
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-coord-affine.json';
end;

{ A recorded number: 16 hex digits, or the name of a non-finite value, or
  null, which is read as not-a-number. }
function NumOf(AData: TJSONData): Double;
var
  q: QWord;
  s: string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  s := AData.AsString;
  if s = 'NaN' then Exit(NaN);
  if s = 'Infinity' then Exit(Infinity);
  if s = '-Infinity' then Exit(NegInfinity);
  Result := 0;
  q := StrToQWord('$' + s);
  Move(q, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function Ulp(A: Double): Double;
var e: Integer;
begin
  A := Abs(A);
  if A < 1e-300 then Exit(4.9406564584124654e-324);
  e := Floor(Log2(A));
  Result := Power(2, e - 52);
end;

procedure TAdvChartCoordAffineOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TCoordAffineProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FAffine := 0;
  FBoxes := 0;
  FVertices := 0;
  FLabels := 0;
  FReport := '';
end;

procedure TAdvChartCoordAffineOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartCoordAffineOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

{ Exact -- or within FTol units in the last place on a case that allows it;
  a non-finite value by kind; -0 as 0. }
procedure TAdvChartCoordAffineOracleTest.Same(const AWhat: string;
  AGot: Double; AWant: TJSONData);
var
  want, d: Double;
  ok: Boolean;
begin
  Inc(FCompared);
  want := NumOf(AWant);
  if IsNan(want) or IsNan(AGot) then ok := IsNan(want) and IsNan(AGot)
  else if IsInfinite(want) or IsInfinite(AGot) then ok := AGot = want
  else if AGot = want then ok := True
  else
  begin
    d := Abs(AGot - want) / Ulp(Max(Abs(AGot), Abs(want)));
    ok := d <= FTol;
  end;
  if not ok then
    Miss(Format('%s is %s upstream, %s here (%s ulps)', [AWhat, Fmt(want),
      Fmt(AGot), FloatToStrF(Abs(AGot - want) / Ulp(Max(Abs(AGot), Abs(want))),
      ffFixed, 15, 1)]));
end;

function AxisOf(AGrid: TTyGridBuild; const ADim: string;
  AIndex: Integer): TTyAxis;
var i: Integer;
begin
  Result := nil;
  if ADim = 'x' then
  begin
    for i := 0 to AGrid.XAxisCount - 1 do
      if AGrid.XAxis(i).ComponentIndex = AIndex then Exit(AGrid.XAxis(i));
  end
  else
    for i := 0 to AGrid.YAxisCount - 1 do
      if AGrid.YAxis(i).ComponentIndex = AIndex then Exit(AGrid.YAxis(i));
end;

function AnchorHName(A: TTyTextAnchorH): string;
begin
  case A of
    tahLeft: Result := 'left';
    tahRight: Result := 'right';
  else
    Result := 'center';
  end;
end;

function AnchorVName(A: TTyTextAnchorV): string;
begin
  case A of
    tavTop: Result := 'top';
    tavBottom: Result := 'bottom';
  else
    Result := 'middle';
  end;
end;

procedure TAdvChartCoordAffineOracleTest.CheckAxis(AGrid: TTyGridBuild;
  AAxis: TJSONObject);
var
  ax: TTyAxis;
  tag: string;
  a, b, tickV: Double;
  e: TTyRange;
  arr, coords: TJSONArray;
  i, k, p, built: Integer;
  spec: PTyAxisLayoutSpec;
  lab: TJSONObject;
  hidden: Boolean;
begin
  tag := AAxis.Strings['dim'] + IntToStr(AAxis.Integers['index']);
  ax := AxisOf(AGrid, AAxis.Strings['dim'], AAxis.Integers['index']);
  if ax = nil then
  begin
    Miss(tag + ': no such axis here');
    Exit;
  end;
  { ITS OWN PIXEL EXTENT, [0, w] or [w, 0] }
  ax.LocalExtent(a, b);
  arr := AAxis.Arrays['extent'];
  Same(tag + ' extent start', a, arr.Items[0]);
  Same(tag + ' extent stop', b, arr.Items[1]);
  e := ax.Scale.GetExtent;
  arr := AAxis.Arrays['effective'];
  Same(tag + ' effective start', e.Start, arr.Items[0]);
  Same(tag + ' effective stop', e.Stop, arr.Items[1]);
  if AAxis.Find('mapping') is TJSONArray then
  begin
    e := ax.Scale.GetExtent2(sekMapping);
    arr := AAxis.Arrays['mapping'];
    Same(tag + ' mapping start', e.Start, arr.Items[0]);
    Same(tag + ' mapping stop', e.Stop, arr.Items[1]);
  end;
  { WHERE THE TICKS LAND -- as the furniture draws them: one per tick, or
    on a banded axis the band edges, shifted half a band and closed at the
    far end (on an inverse one, upstream's duplicate and all) }
  spec := AGrid.SpecFor(ax);
  coords := AAxis.Arrays['tickCoords'];
  { A BLANK AXIS draws no ticks and no split lines upstream, whatever
    getTicksCoords answers for it; here it has none to draw }
  if ax.Scale.Blank then
  begin
    if Length(spec^.TickMarks) + Length(spec^.SplitLineMarks) > 0 then
      Miss(tag + ': a blank axis with marks here');
  end
  else if Length(spec^.TickMarks) <> coords.Count then
    Miss(Format('%s: %d ticks upstream, %d here', [tag, coords.Count,
      Length(spec^.TickMarks)]))
  else
    for i := 0 to coords.Count - 1 do
      Same(Format('%s tick %d', [tag, i]), spec^.TickMarks[i].Coord,
        coords.Items[i]);
  { and the split lines, which read their own alignWithLabel }
  if (not ax.Scale.Blank) and (AAxis.Find('splitLineCoords') is TJSONArray) then
  begin
    coords := AAxis.Arrays['splitLineCoords'];
    if Length(spec^.SplitLineMarks) <> coords.Count then
      Miss(Format('%s: %d split lines upstream, %d here', [tag, coords.Count,
        Length(spec^.SplitLineMarks)]))
    else
      for i := 0 to coords.Count - 1 do
        Same(Format('%s split line %d', [tag, i]), spec^.SplitLineMarks[i].Coord,
          coords.Items[i]);
  end;

  { THE LABELS: every one upstream built, where its anchor is and whether
    the overlap rules kept it, matched to the port's by tick value }
  arr := AAxis.Arrays['labels'];
  built := 0;
  for i := 0 to High(spec^.Placements) do
    if spec^.Placements[i].Built then Inc(built);
  if built <> arr.Count then
    Miss(Format('%s: %d labels built upstream, %d here', [tag, arr.Count, built]));
  for k := 0 to arr.Count - 1 do
  begin
    lab := arr.Objects[k];
    tickV := NumOf(lab.Find('tick'));
    p := -1;
    for i := 0 to High(spec^.TickValues) do
      if spec^.TickValues[i] = tickV then
      begin
        p := i;
        Break;
      end;
    Inc(FLabels);
    if (p < 0) or (p > High(spec^.Placements)) then
    begin
      Miss(Format('%s: no label for tick %s here', [tag, Fmt(tickV)]));
      Continue;
    end;
    Same(Format('%s label %s x', [tag, Fmt(tickV)]), spec^.Placements[p].X,
      lab.Find('x'));
    Same(Format('%s label %s y', [tag, Fmt(tickV)]), spec^.Placements[p].Y,
      lab.Find('y'));
    hidden := (lab.Find('hidden') <> nil) and lab.Booleans['hidden'];
    if spec^.Placements[p].Shown = hidden then
      Miss(Format('%s label %s: hidden %s upstream', [tag, Fmt(tickV),
        BoolToStr(hidden, True)]));
  end;
  { which way they turn and where they hang from them -- the sign of a top
    axis' turn among it }
  if (arr.Count > 0) and (AAxis.Find('labelRotation') <> nil)
    and (AAxis.Find('labelRotation').JSONType = jtString) then
  begin
    Inc(FCompared);
    if Abs(spec^.RotationRad - NumOf(AAxis.Find('labelRotation'))) > 1e-9 then
      Miss(Format('%s: labels turned %s upstream, %s here', [tag,
        Fmt(NumOf(AAxis.Find('labelRotation'))), Fmt(spec^.RotationRad)]));
    if (Length(spec^.Placements) > 0) then
    begin
      Inc(FCompared);
      if AnchorHName(spec^.Placements[0].AnchorH) <> AAxis.Strings['align'] then
        Miss(Format('%s: aligned %s upstream, %s here', [tag,
          AAxis.Strings['align'], AnchorHName(spec^.Placements[0].AnchorH)]));
      if AnchorVName(spec^.Placements[0].AnchorV) <> AAxis.Strings['verticalAlign'] then
        Miss(Format('%s: vertically %s upstream, %s here', [tag,
          AAxis.Strings['verticalAlign'], AnchorVName(spec^.Placements[0].AnchorV)]));
    end;
  end;
  { THE LINE IT SITS ON, and the floor its bars stand on }
  if (AAxis.Find('onZeroOf') <> nil) and (AAxis.Find('onZeroOf').JSONType = jtString) then
    Same(tag + ' on the other''s zero', AGrid.AxisLineCoord(ax, 96),
      AAxis.Find('onZeroCoord'));
  if (AAxis.Find('valueAxisStart') <> nil)
    and (AAxis.Find('valueAxisStart').JSONType = jtString) then
    Same(tag + ' value axis start', ax.DataToCoord(TyValueAxisStart(ax)),
      AAxis.Find('valueAxisStart'));
end;

function IsGap(APts: TJSONArray; AIndex: Integer): Boolean;
begin
  Result := (AIndex < 0) or (AIndex >= APts.Count)
    or IsNan(NumOf(TJSONArray(APts.Items[AIndex]).Items[0]))
    or IsNan(NumOf(TJSONArray(APts.Items[AIndex]).Items[1]));
end;

{ The vertices a stroke is drawn through: a gap -- a NaN pair -- breaks the
  line, and a point alone between two breaks is no stroke at all. The caller
  frees the copy. }
function Solid(APts: TJSONArray): TJSONArray;
var k: Integer;
begin
  Result := TJSONArray.Create;
  for k := 0 to APts.Count - 1 do
    if not IsGap(APts, k) and not (IsGap(APts, k - 1) and IsGap(APts, k + 1)) then
      Result.Add(APts.Items[k].Clone);
end;

function HasGap(APts: TJSONArray): Boolean;
var k: Integer;
begin
  Result := False;
  for k := 0 to APts.Count - 1 do
    if IsNan(NumOf(TJSONArray(APts.Items[k]).Items[0]))
      or IsNan(NumOf(TJSONArray(APts.Items[k]).Items[1])) then Exit(True);
end;

procedure TAdvChartCoordAffineOracleTest.CheckSeries(ACart: TTyCartesian2D;
  ASeries: TJSONObject);
var
  si, k, i, n, marks: Integer;
  typ, cls: string;
  items, arr, pts: TJSONArray;
  item: TJSONObject;
  p: TTyPointF;
  lst: TTyPaintList;
  e, mark: TTyChartElement;
  b: TTyRectF;
  vertical: Boolean;
  floor, e0: Double;
  ring: TTyPointFArray;
  d: TJSONData;
  col: TTyBarColumn;
begin
  si := ASeries.Integers['index'];
  typ := ASeries.Strings['type'];
  items := ASeries.Arrays['items'];
  lst := FChart.List;
  vertical := ASeries.Strings['baseDim'] = 'x';

  { EVERY ITEM'S POINT, through the coordinate system }
  for k := 0 to items.Count - 1 do
  begin
    item := items.Objects[k];
    arr := item.Arrays['values'];
    p := ACart.DataToPoint([NumOf(arr.Items[0]), NumOf(arr.Items[1])]);
    Same(Format('s%d[%d] x', [si, k]), p.X, item.Arrays['point'].Items[0]);
    Same(Format('s%d[%d] y', [si, k]), p.Y, item.Arrays['point'].Items[1]);
  end;

  { THE COLUMN the solve gave the series, off its band }
  if (typ = 'bar') and (ASeries.Find('offset') <> nil)
    and (ASeries.Find('offset').JSONType = jtString) then
  begin
    col := FChart.Column(si);
    Same(Format('s%d offset', [si]), col.Offset, ASeries.Find('offset'));
    Same(Format('s%d size', [si]), col.Width, ASeries.Find('size'));
  end;

  { A BAR'S BOX AS DRAWN, and a pictorial bar's floor }
  if (typ = 'bar') or (typ = 'pictorialBar') then
    for k := 0 to items.Count - 1 do
    begin
      item := items.Objects[k];
      cls := '';
      if item.Find('class') <> nil then cls := item.Strings['class'];
      marks := 0;
      mark := Default(TTyChartElement);
      if lst <> nil then
        for i := 0 to lst.Count - 1 do
        begin
          e := lst.Element(i);
          if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si)
            or (e.Datum.RawDataIndex <> k) then Continue;
          if e.Caption.FontSizeLogical > 0 then Continue;
          if (typ = 'pictorialBar')
            and (e.Style.HasFill or (e.Style.StrokeWidthLogical > 0)) then Continue;
          Inc(marks);
          mark := e;
        end;
      Inc(FCompared);
      if cls <> 'drawn' then
      begin
        if marks > 0 then
          Miss(Format('s%d[%d] is %s upstream, drawn here', [si, k, cls]));
        Continue;
      end;
      if marks <> 1 then
      begin
        Miss(Format('s%d[%d]: %d marks here', [si, k, marks]));
        Continue;
      end;
      b := TyShapeBounds(mark.Shape);
      Inc(FBoxes);
      if typ = 'pictorialBar' then
      begin
        floor := NumOf(item.Find('floor'));
        if vertical then
        begin
          if Abs(b.Top - floor) < Abs(b.Bottom - floor) then e0 := b.Top
          else e0 := b.Bottom;
        end
        else if Abs(b.Left - floor) < Abs(b.Right - floor) then e0 := b.Left
        else e0 := b.Right;
        Same(Format('s%d[%d] floor', [si, k]), e0, item.Find('floor'));
        Continue;
      end;
      arr := item.Arrays['box'];
      Same(Format('s%d[%d] box left', [si, k]), b.Left, arr.Items[0]);
      Same(Format('s%d[%d] box top', [si, k]), b.Top, arr.Items[1]);
      Same(Format('s%d[%d] box right', [si, k]), b.Right, arr.Items[2]);
      Same(Format('s%d[%d] box bottom', [si, k]), b.Bottom, arr.Items[3]);
    end;

  { A LINE'S VERTICES AS THE FLOAT32 ARRAY HOLDS THEM -- the ring drawn, and
    each symbol on its vertex. A ring with a gap in it is left alone: the
    fixture keeps the gap and the port splits the stroke there. }
  d := ASeries.Find('linePoints');
  if d is TJSONArray then
  begin
    pts := Solid(TJSONArray(d));
    ring := nil;
    if lst <> nil then
      for i := 0 to lst.Count - 1 do
      begin
        e := lst.Element(i);
        if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si)
          or (e.Datum.RawDataIndex <> -1) or e.Silent
          or (e.Shape.Kind <> cskPolyline) then Continue;
        { every stroke of the series, one after another }
        n := Length(ring);
        SetLength(ring, n + Length(e.Shape.Points));
        for k := 0 to High(e.Shape.Points) do ring[n + k] := e.Shape.Points[k];
      end;
    if Length(ring) = pts.Count then
      for k := 0 to pts.Count - 1 do
      begin
        Inc(FVertices);
        Same(Format('s%d vertex %d x', [si, k]), ring[k].X,
          TJSONArray(pts.Items[k]).Items[0]);
        Same(Format('s%d vertex %d y', [si, k]), ring[k].Y,
          TJSONArray(pts.Items[k]).Items[1]);
      end
    else
      Miss(Format('s%d: %d vertices upstream, %d drawn here',
        [si, pts.Count, Length(ring)]));
    pts.Free;
    { and the area's lower edge, the second half of its ring, backwards }
    d := ASeries.Find('areaLower');
    { A BELT WITH A GAP IN IT is two rings here, and upstream's lower edge
      runs on through the gap; compared where it is one }
    if (d is TJSONArray) and not HasGap(TJSONArray(d))
      and not HasGap(ASeries.Arrays['linePoints']) then
    begin
      pts := TJSONArray(d);
      ring := nil;
      if lst <> nil then
        for i := 0 to lst.Count - 1 do
        begin
          e := lst.Element(i);
          if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si)
            or (e.Datum.RawDataIndex <> -1) or (not e.Silent)
            or (e.Shape.Kind <> cskPolygon) then Continue;
          ring := e.Shape.Points;
        end;
      n := Length(ring) div 2;
      if (Length(ring) = 2 * pts.Count) then
        for k := 0 to pts.Count - 1 do
        begin
          Same(Format('s%d area %d x', [si, k]), ring[Length(ring) - 1 - k].X,
            TJSONArray(pts.Items[k]).Items[0]);
          Same(Format('s%d area %d y', [si, k]), ring[Length(ring) - 1 - k].Y,
            TJSONArray(pts.Items[k]).Items[1]);
        end
      else
        Miss(Format('s%d: an area of %d upstream, %d here', [si, pts.Count, n]));
    end;
  end;
end;

procedure TAdvChartCoordAffineOracleTest.CheckProbe(ACart: TTyCartesian2D;
  AProbe: TJSONObject);
var
  kind, tag: string;
  inp, outp: TJSONArray;
  p: TTyPointF;
  data: TTyDoubleArray;
  ax: TTyAxis;
begin
  kind := AProbe.Strings['kind'];
  FTol := 0;
  inp := AProbe.Arrays['input'];
  outp := AProbe.Arrays['output'];
  tag := kind + ' ' + AProbe.Arrays['inputText'].AsJSON;
  if (kind = 'dataToPoint') or (kind = 'dataToPointClamp') then
  begin
    p := ACart.DataToPointClamped([NumOf(inp.Items[0]), NumOf(inp.Items[1])],
      kind = 'dataToPointClamp');
    Same(tag + ' x', p.X, outp.Items[0]);
    Same(tag + ' y', p.Y, outp.Items[1]);
  end
  else if kind = 'pointToData' then
  begin
    ACart.PointToData(TyPointF(NumOf(inp.Items[0]), NumOf(inp.Items[1])), data);
    Same(tag + ' x', data[0], outp.Items[0]);
    Same(tag + ' y', data[1], outp.Items[1]);
  end
  else if (kind = 'axisPointToData') or (kind = 'axisPointerPixel') then
  begin
    ax := ACart.AxisByDim(AProbe.Strings['dim']);
    if ax = nil then
    begin
      Miss(tag + ': no ' + AProbe.Strings['dim'] + ' axis');
      Exit;
    end;
    { the pixel is the probe's point, on this axis' own dimension }
    if kind = 'axisPointToData' then
    begin
      if AProbe.Strings['dim'] = 'x' then
        Same(tag, ax.CoordToData(NumOf(inp.Items[0])), outp.Items[0])
      else
        Same(tag, ax.CoordToData(NumOf(inp.Items[1])), outp.Items[0]);
    end
    else
      Same(tag, ax.DataToCoord(NumOf(inp.Items[0]), True), outp.Items[0]);
  end
  else
    Miss('an unknown probe ' + kind);
end;

procedure TAdvChartCoordAffineOracleTest.CheckGrid(ACase, AGrid: TJSONObject;
  AGridIndex: Integer);
var
  gb: TTyGridBuild;
  cart: TTyCartesian2D;
  r, area: TTyXYWH;
  rect: TJSONObject;
  m: TTyMat2D;
  has: Boolean;
  arr: TJSONArray;
  i: Integer;
  doc: Boolean;
begin
  doc := (ACase.Find('documentary') <> nil) and ACase.Booleans['documentary'];
  if AGridIndex >= FChart.Build.GridCount then
  begin
    Miss('no grid ' + IntToStr(AGridIndex));
    Exit;
  end;
  gb := FChart.Build.Grid(AGridIndex);
  if gb.CartesianCount < 1 then
  begin
    Miss('no cartesian');
    Exit;
  end;
  cart := gb.CartesianByIndex(0);
  { A DOCUMENTARY CASE'S RECT comes of measured text, the grid-bounds
    oracle's question; everything below it is measured from that rect, so
    it is compared only where the rect is upstream's }
  rect := AGrid.Objects['rect'];
  r := gb.PlotXYWH;
  if doc and not ((r.X = NumOf(rect.Find('x'))) and (r.Y = NumOf(rect.Find('y')))
    and (r.W = NumOf(rect.Find('width'))) and (r.H = NumOf(rect.Find('height')))) then
    Exit;
  Same('rect x', r.X, rect.Find('x'));
  Same('rect y', r.Y, rect.Find('y'));
  Same('rect width', r.W, rect.Find('width'));
  Same('rect height', r.H, rect.Find('height'));

  { THE MATRIX, or none, and its inverse }
  has := cart.Transform(m);
  if AGrid.Find('transform') is TJSONArray then
  begin
    Inc(FAffine);
    if not has then Miss('a matrix upstream, none here')
    else
    begin
      arr := AGrid.Arrays['transform'];
      for i := 0 to 5 do Same(Format('matrix[%d]', [i]), m[i], arr.Items[i]);
    end;
  end
  else if has then Miss('no matrix upstream, one here');
  has := cart.InvTransform(m);
  if AGrid.Find('invTransform') is TJSONArray then
  begin
    if not has then Miss('an inverse upstream, none here')
    else
    begin
      arr := AGrid.Arrays['invTransform'];
      for i := 0 to 5 do Same(Format('inverse[%d]', [i]), m[i], arr.Items[i]);
    end;
  end
  else if has then Miss('no inverse upstream, one here');

  area := cart.GetArea;
  rect := AGrid.Objects['area'];
  Same('area x', area.X, rect.Find('x'));
  Same('area y', area.Y, rect.Find('y'));
  Same('area width', area.W, rect.Find('width'));
  Same('area height', area.H, rect.Find('height'));

  arr := AGrid.Arrays['axes'];
  for i := 0 to arr.Count - 1 do
    CheckAxis(gb, arr.Objects[i]);
  arr := AGrid.Arrays['series'];
  for i := 0 to arr.Count - 1 do
    CheckSeries(cart, arr.Objects[i]);
  arr := AGrid.Arrays['probes'];
  for i := 0 to arr.Count - 1 do
    CheckProbe(cart, arr.Objects[i]);
end;

procedure TAdvChartCoordAffineOracleTest.TestEveryCoordinateLandsWhereUpstreamPutsIt;
var
  cases, grids: TJSONArray;
  cs: TJSONObject;
  c, g, pass, w, h: Integer;
  bmp: TBGRABitmap;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if (cs.Find('deferred') <> nil) and cs.Booleans['deferred'] then Continue;
    w := cs.Integers['W'];
    h := cs.Integers['H'];
    FTol := 0;
    FLogCase := Pos('log', cs.Strings['name']) > 0;
    FChart.Option := cs.Objects['option'].AsJSON;
    AssertEquals(cs.Strings['name'] + ' parses', '', FChart.OptionError);
    FChart.SetBounds(0, 0, w, h);
    bmp := TBGRABitmap.Create(w, h, BGRA(255, 255, 255, 255));
    try
      for pass := 0 to 1 do
      begin
        FName := cs.Strings['name'];
        if pass = 1 then
        begin
          FName := FName + ' (again)';
          FChart.Invalidate;
        end;
        try
          FChart.Render(bmp.Canvas, Rect(0, 0, w, h), 96);
          if cs.Find('grids') is TJSONArray then
          begin
            grids := cs.Arrays['grids'];
            for g := 0 to grids.Count - 1 do
              CheckGrid(cs, grids.Objects[g], g);
          end
          else
            CheckGrid(cs, cs, 0);
        except
          on E: Exception do
            Miss(E.ClassName + ': ' + E.Message + ' at '
              + BackTraceStrFunc(ExceptAddr) + ' / '
              + BackTraceStrFunc(ExceptFrames[0]) + ' / '
              + BackTraceStrFunc(ExceptFrames[1]) + ' / '
              + BackTraceStrFunc(ExceptFrames[2]));
        end;
      end;
    finally
      bmp.Free;
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > 3000);
  AssertTrue(Format('enough matrices (%d)', [FAffine]), FAffine > 40);
  AssertTrue(Format('enough bars (%d)', [FBoxes]), FBoxes > 60);
  AssertTrue(Format('enough vertices (%d)', [FVertices]), FVertices > 60);
  AssertTrue(Format('enough labels (%d)', [FLabels]), FLabels > 1000);
end;

initialization
  RegisterTest(TAdvChartCoordAffineOracleTest);
end.
