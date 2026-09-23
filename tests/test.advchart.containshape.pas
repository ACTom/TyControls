unit test.advchart.containshape;
{$mode objfpc}{$H+}
{ Half a bar more at each end -- held to upstream's own extents.

  tools/advchart-oracle/contain-shape.js runs the real ECharts 6.1 build and
  records, per axis of grid 0, the effective extent (what the ticks are made
  from), the MAPPING extent (what values are placed over, wider by half the
  bars' data-space width) or none, the ticks and where they land, whether
  the axis asked to contain its shapes, whether its zero was discouraged,
  and which axes sit on its zero; per bar series, the band, offset and width
  the solve gave it; and per item, the rect as drawn.

  THE RULES IT HOLDS THE PORT TO: only a bar's or a pictorial bar's base axis
  widens, even when the bar is switched off or has no rows; a flat extent at
  zero opens to [-1, 1] on such an axis; the half width is the smallest gap
  between base values -- in decades on a log axis -- or four fifths of the
  axis for one value, measured against the pixel length the layout options
  gave; the band a bar is laid out in is measured over the mapping extent;
  an axis whose zero a bar moved is no zero for an `auto` onZero.

  Everything is compared to the bit -- extents, band, offset, width, ticks
  and every rect, the G9 cases that tell upstream's affine placement from a
  per-axis one included -- except on a log axis, held to eight units in the
  last place. A log mapping end is a power of ten to a fractional exponent,
  and FPC's Power is not V8's Math.pow: 10^2.5 comes back six units apart,
  50^(1/2)-ish ends seven.
  [Revised in batch 42: rects were held to eight units and the G9 rects not
  at all, until the affine path was ported.] }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Builder,
     tyControls.AdvChart.BarLayout, tyControls.AdvanceChart;
type
  TContainShapeProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function Column(ASeriesIndex: Integer): TTyBarColumn;
  end;

  TAdvChartContainShapeOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TContainShapeProbe;
    FRoot: TJSONData;
    FBad, FCompared, FMapped, FBoxes: Integer;
    FReport: string;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Miss(const ACase, AWhat: string);
    procedure CheckAxis(const AName: string; ACase, AAxis: TJSONObject);
    procedure CheckSeries(const AName: string; ACase, ASeries: TJSONObject);
    procedure CheckCase(ACase: TJSONObject; APass: Integer);
  published
    procedure TestEveryAxisMapsAsUpstreamWidensIt;
  end;

implementation

procedure TContainShapeProbe.Render(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TContainShapeProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TContainShapeProbe.Column(ASeriesIndex: Integer): TTyBarColumn;
begin
  Result := BarColumnOf(ASeriesIndex);
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-contain-shape.json';
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function HexAt(AArr: TJSONArray; AIndex: Integer): Double;
begin
  Result := FromHex(AArr.Strings[AIndex]);
end;

function Flag(AObj: TJSONObject; const AKey: string): Boolean;
var d: TJSONData;
begin
  d := AObj.Find(AKey);
  Result := (d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean;
end;

function ArrOrNil(AObj: TJSONObject; const AKey: string): TJSONArray;
var d: TJSONData;
begin
  d := AObj.Find(AKey);
  if d is TJSONArray then Result := TJSONArray(d) else Result := nil;
end;

var
  GWorstUlps: Double;

function Ulp(A: Double): Double;
var e: Integer;
begin
  A := Abs(A);
  if A < 1e-300 then Exit(4.9406564584124654e-324);
  e := Floor(Log2(A));
  Result := Power(2, e - 52);
end;

{ Within ATol units in the last place; 0 is exact. -0 is 0. }
function Near(A, B, ATol: Double): Boolean;
var d: Double;
begin
  if A = B then Exit(True);
  if IsNan(A) or IsNan(B) then Exit(False);
  d := Abs(A - B) / Ulp(Max(Abs(A), Abs(B)));
  if d > GWorstUlps then GWorstUlps := d;
  Result := d <= ATol;
end;

function Fmt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function Ulps(A, B: Double): string;
begin
  if A = B then Exit('0');
  Result := FloatToStrF(Abs(A - B) / Ulp(Max(Abs(A), Abs(B))), ffFixed, 15, 1);
end;

procedure TAdvChartContainShapeOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TContainShapeProbe.Create(FForm);
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
  FMapped := 0;
  FBoxes := 0;
  FReport := '';
end;

procedure TAdvChartContainShapeOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartContainShapeOracleTest.Miss(const ACase, AWhat: string);
begin
  Inc(FBad);
  if FBad <= 30 then
    FReport := FReport + LineEnding + '  ' + ACase + ': ' + AWhat;
end;

function AxisOf(AGrid: TTyGridBuild; const ADim: string;
  AIndex: Integer): TTyAxis;
begin
  Result := nil;
  if ADim = 'x' then
  begin
    if AIndex < AGrid.XAxisCount then Result := AGrid.XAxis(AIndex);
  end
  else if AIndex < AGrid.YAxisCount then Result := AGrid.YAxis(AIndex);
end;

function AxisName(AAxis: TTyAxis): string;
begin
  Result := '';
  if AAxis = nil then Exit;
  if AAxis.Horizontal then Result := 'x' else Result := 'y';
  Result := Result + IntToStr(AAxis.ComponentIndex);
end;

procedure TAdvChartContainShapeOracleTest.CheckAxis(const AName: string;
  ACase, AAxis: TJSONObject);
var
  grid: TTyGridBuild;
  ax, prov: TTyAxis;
  tag, want, got: string;
  tol, ctol, a, b: Double;
  isLog, isCat: Boolean;
  e, m: TTyRange;
  arr, lin, coords: TJSONArray;
  ticks: TTyScaleTickArray;
  i, n: Integer;
  mapper: ITyScaleMapper;
begin
  grid := FChart.Build.Grid(0);
  tag := AAxis.Strings['dim'] + IntToStr(AAxis.Integers['index']);
  ax := AxisOf(grid, AAxis.Strings['dim'], AAxis.Integers['index']);
  Inc(FCompared);
  if ax = nil then
  begin
    Miss(AName, tag + ': no such axis here');
    Exit;
  end;
  isLog := AAxis.Strings['type'] = 'log';
  isCat := AAxis.Strings['type'] = 'category';
  tol := 0;
  mapper := ax.Scale.Mapper;

  { WHETHER IT ASKED -- visible on an interval scale as the flag the flat
    rule reads; a category axis says so by its mapping alone }
  if (ax.Scale is TTyIntervalScale)
    and (TTyIntervalScale(ax.Scale).ContainShape <> AAxis.Booleans['ctnShp']) then
    Miss(AName, Format('%s: ctnShp %s upstream', [tag,
      BoolToStr(AAxis.Booleans['ctnShp'], True)]));
  if ax.ZeroDiscouraged <> AAxis.Booleans['discouraged'] then
    Miss(AName, Format('%s: zero discouraged %s upstream', [tag,
      BoolToStr(AAxis.Booleans['discouraged'], True)]));

  { THE EFFECTIVE EXTENT, which the ticks are made from }
  arr := AAxis.Arrays['effective'];
  e := ax.Scale.GetExtent;
  if not (Near(e.Start, HexAt(arr, 0), tol) and Near(e.Stop, HexAt(arr, 1), tol)) then
    Miss(AName, Format('%s: effective [%s, %s] upstream, [%s, %s] here',
      [tag, Fmt(HexAt(arr, 0)), Fmt(HexAt(arr, 1)), Fmt(e.Start), Fmt(e.Stop)]));

  { THE MAPPING EXTENT, or none }
  arr := ArrOrNil(AAxis, 'mapping');
  if arr = nil then
  begin
    if mapper.HasExtent(sekMapping) then
    begin
      m := ax.Scale.GetExtent2(sekMapping);
      Miss(AName, Format('%s: no mapping upstream, [%s, %s] here',
        [tag, Fmt(m.Start), Fmt(m.Stop)]));
    end;
  end
  else
  begin
    Inc(FMapped);
    m := ax.Scale.GetExtent2(sekMapping);
    if not mapper.HasExtent(sekMapping) then
      Miss(AName, Format('%s: mapping [%s, %s] upstream, none here',
        [tag, Fmt(HexAt(arr, 0)), Fmt(HexAt(arr, 1))]))
    else if not (Near(m.Start, HexAt(arr, 0), tol)
      and Near(m.Stop, HexAt(arr, 1), tol)) then
      Miss(AName, Format('%s: mapping [%s, %s] upstream, [%s, %s] here (%s, %s ulps)',
        [tag, Fmt(HexAt(arr, 0)), Fmt(HexAt(arr, 1)), Fmt(m.Start), Fmt(m.Stop),
         Ulps(m.Start, HexAt(arr, 0)), Ulps(m.Stop, HexAt(arr, 1))]));
    { and in decades, which is what the band is measured over }
    lin := ArrOrNil(AAxis, 'mappingLin');
    if isLog and (lin <> nil) and mapper.HasExtent(sekMapping) then
    begin
      a := mapper.TransformIn(m.Start);
      b := mapper.TransformIn(m.Stop);
      if not (Near(a, HexAt(lin, 0), tol) and Near(b, HexAt(lin, 1), tol)) then
        Miss(AName, Format('%s: linear mapping [%s, %s] upstream, [%s, %s] here',
          [tag, Fmt(HexAt(lin, 0)), Fmt(HexAt(lin, 1)), Fmt(a), Fmt(b)]));
    end;
  end;

  { THE TICKS STAY ON THE EFFECTIVE EXTENT and land where the mapping puts
    them. A banded category axis' ticks are band edges and are the axis
    label oracle's question; where they land in a documentary case is the
    grid-bounds oracle's, since the final plot decides it. Upstream's y is
    (r0 + r1) - map(n) + y: an end tick comes back as the plot edge to the
    bit, and this per-axis `a + n * (b - a)` two units off it. }
  arr := AAxis.Arrays['ticks'];
  coords := AAxis.Arrays['tickCoords'];
  if Flag(ACase, 'documentary') then coords := nil;
  ctol := tol;
  if not (isCat and ax.OnBand) then
  begin
    if not isCat then
    begin
      ticks := ax.Scale.GetTicks;
      n := 0;
      for i := 0 to High(ticks) do
        if ticks[i].Level = 0 then
        begin
          if (n < arr.Count) and not Near(ticks[i].Value, HexAt(arr, n), tol) then
          begin
            Miss(AName, Format('%s: tick %d is %s upstream, %s here',
              [tag, n, Fmt(HexAt(arr, n)), Fmt(ticks[i].Value)]));
            Break;
          end;
          Inc(n);
        end;
      if n <> arr.Count then
        Miss(AName, Format('%s: %d ticks upstream, %d here', [tag, arr.Count, n]));
    end;
    if coords <> nil then
    for i := 0 to arr.Count - 1 do
    begin
      a := ax.DataToCoord(HexAt(arr, i));
      if not Near(a, HexAt(coords, i), ctol) then
      begin
        Miss(AName, Format('%s: tick %s lands at %s upstream, %s here (%s ulps)',
          [tag, Fmt(HexAt(arr, i)), Fmt(HexAt(coords, i)), Fmt(a),
           Ulps(a, HexAt(coords, i))]));
        Break;
      end;
    end;
  end;

  { WHOSE ZERO THIS AXIS SITS ON -- upstream's getAxesOnZeroOf, one axis of
    the other family or none }
  want := '';
  arr := AAxis.Arrays['onZeroOf'];
  for i := 0 to arr.Count - 1 do want := want + arr.Strings[i];
  prov := grid.OnZeroProviderFor(ax);
  got := AxisName(prov);
  if want <> got then
    Miss(AName, Format('%s: on the zero of [%s] upstream, [%s] here',
      [tag, want, got]));
end;

procedure TAdvChartContainShapeOracleTest.CheckSeries(const AName: string;
  ACase, ASeries: TJSONObject);
var
  si, k, i, marks: Integer;
  typ: string;
  col: TTyBarColumn;
  items: TJSONArray;
  item: TJSONObject;
  box: TJSONArray;
  lst: TTyPaintList;
  e, mark: TTyChartElement;
  b: TTyRectF;
  pictorial, vertical, boxes: Boolean;
  floor, e0, tol: Double;
  d: TJSONData;
begin
  typ := ASeries.Strings['type'];
  if (typ <> 'bar') and (typ <> 'pictorialBar') then Exit;
  if ASeries.Booleans['filtered'] then Exit;
  si := ASeries.Integers['index'];
  pictorial := typ = 'pictorialBar';
  vertical := ASeries.Strings['baseDim'] = 'x';
  tol := 0;

  { THE SOLVE: band, offset, width, bit for bit }
  d := ASeries.Find('bandWidth');
  if (d <> nil) and (d.JSONType = jtString) and not pictorial then
  begin
    Inc(FCompared);
    col := FChart.Column(si);
    if not col.Solved then
      Miss(AName, Format('s%d: not solved here', [si]))
    else if not (Near(col.BandWidth, FromHex(ASeries.Strings['bandWidth']), tol)
      and Near(col.Offset, FromHex(ASeries.Strings['offset']), tol)
      and Near(col.Width, FromHex(ASeries.Strings['size']), tol)) then
      Miss(AName, Format('s%d: band/offset/size %s/%s/%s upstream, %s/%s/%s here',
        [si, ASeries.Strings['bandWidthText'], ASeries.Strings['offsetText'],
         ASeries.Strings['sizeText'], Fmt(col.BandWidth), Fmt(col.Offset),
         Fmt(col.Width)]));
  end;

  { THE RECTS -- except where the case exists to tell upstream's affine
    placement from this per-axis one, which is the next batch's }
  boxes := True;
  if not boxes then Exit;
  lst := FChart.List;
  items := ASeries.Arrays['items'];
  for k := 0 to items.Count - 1 do
  begin
    item := items.Objects[k];
    marks := 0;
    mark := Default(TTyChartElement);
    if lst <> nil then
      for i := 0 to lst.Count - 1 do
      begin
        e := lst.Element(i);
        if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si)
          or (e.Datum.RawDataIndex <> k) then Continue;
        if e.Caption.FontSizeLogical > 0 then Continue;
        { a pictorial bar's inkless rect is the bar; the glyphs its picture }
        if pictorial and (e.Style.HasFill or (e.Style.StrokeWidthLogical > 0)) then
          Continue;
        Inc(marks);
        mark := e;
      end;
    Inc(FCompared);
    if item.Strings['class'] <> 'drawn' then
    begin
      if marks > 0 then
        Miss(AName, Format('item %d/%d is %s upstream, drawn here',
          [si, k, item.Strings['class']]));
      Continue;
    end;
    if marks <> 1 then
    begin
      Miss(AName, Format('item %d/%d: %d marks here', [si, k, marks]));
      Continue;
    end;
    b := TyShapeBounds(mark.Shape);
    Inc(FBoxes);
    if pictorial then
    begin
      floor := FromHex(item.Strings['floor']);
      if vertical then
      begin
        if Abs(b.Top - floor) < Abs(b.Bottom - floor) then e0 := b.Top
        else e0 := b.Bottom;
      end
      else if Abs(b.Left - floor) < Abs(b.Right - floor) then e0 := b.Left
      else e0 := b.Right;
      if not Near(e0, floor, tol) then
        Miss(AName, Format('item %d/%d: floor %s upstream, %s here',
          [si, k, Fmt(floor), Fmt(e0)]));
      Continue;
    end;
    box := item.Arrays['box'];
    if not (Near(b.Left, HexAt(box, 0), tol) and Near(b.Top, HexAt(box, 1), tol)
      and Near(b.Right, HexAt(box, 2), tol) and Near(b.Bottom, HexAt(box, 3), tol)) then
      Miss(AName, Format('item %d/%d: box %s,%s,%s,%s upstream, %s,%s,%s,%s here',
        [si, k, Fmt(HexAt(box, 0)), Fmt(HexAt(box, 1)), Fmt(HexAt(box, 2)),
         Fmt(HexAt(box, 3)), Fmt(b.Left), Fmt(b.Top), Fmt(b.Right),
         Fmt(b.Bottom)]));
  end;
end;

procedure TAdvChartContainShapeOracleTest.CheckCase(ACase: TJSONObject;
  APass: Integer);
var
  name: string;
  axes, series: TJSONArray;
  rect: TJSONObject;
  plot: TTyRectF;
  xywh: TTyXYWH;
  i: Integer;
begin
  name := ACase.Strings['name'];
  if APass = 1 then name := name + ' (again)';
  axes := ACase.Arrays['axes'];
  series := ACase.Arrays['series'];

  { A DOCUMENTARY CASE is here for its extents: they depend on the pixel
    length the layout options gave, and not on the final plot, which is the
    grid-bounds oracle's question. }
  if not Flag(ACase, 'documentary') then
  begin
    rect := ACase.Objects['rect'];
    plot := FChart.Build.Grid(0).PlotRect;
    xywh := FChart.Build.Grid(0).PlotXYWH;
    Inc(FCompared);
    if not (Near(xywh.X, FromHex(rect.Strings['x']), 0)
      and Near(xywh.Y, FromHex(rect.Strings['y']), 0)
      and Near(xywh.W, FromHex(rect.Strings['width']), 0)
      and Near(xywh.H, FromHex(rect.Strings['height']), 0)) then
    begin
      rect := ACase.Objects['rectText'];
      Miss(name, Format('the plot is %s,%s %sx%s upstream, %s,%s %sx%s here',
        [rect.Strings['x'], rect.Strings['y'], rect.Strings['width'],
         rect.Strings['height'], Fmt(plot.Left), Fmt(plot.Top),
         Fmt(plot.Right - plot.Left), Fmt(plot.Bottom - plot.Top)]));
      Exit;
    end;
  end;

  for i := 0 to axes.Count - 1 do
    CheckAxis(name, ACase, axes.Objects[i]);
  if Flag(ACase, 'documentary') then Exit;
  for i := 0 to series.Count - 1 do
    CheckSeries(name, ACase, series.Objects[i]);
end;

procedure TAdvChartContainShapeOracleTest.TestEveryAxisMapsAsUpstreamWidensIt;
var
  cases: TJSONArray;
  cs: TJSONObject;
  c, pass, w, h: Integer;
  bmp: TBGRABitmap;
begin
  GWorstUlps := 0;
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if Flag(cs, 'deferred') then Continue;
    w := cs.Integers['W'];
    h := cs.Integers['H'];
    FChart.Option := cs.Objects['option'].AsJSON;
    AssertEquals(cs.Strings['name'] + ' parses', '', FChart.OptionError);
    FChart.SetBounds(0, 0, w, h);
    bmp := TBGRABitmap.Create(w, h, BGRA(255, 255, 255, 255));
    try
      for pass := 0 to 1 do
      begin
        if pass = 1 then FChart.Invalidate;
        try
          FChart.Render(bmp.Canvas, Rect(0, 0, w, h), 96);
          CheckCase(cs, pass);
        except
          on E: Exception do
            Miss(cs.Strings['name'], E.ClassName + ': ' + E.Message);
        end;
      end;
    finally
      bmp.Free;
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > 600);
  AssertTrue(Format('enough axes were widened (%d)', [FMapped]), FMapped > 100);
  AssertTrue(Format('enough bars were placed (%d)', [FBoxes]), FBoxes > 300);
end;

initialization
  RegisterTest(TAdvChartContainShapeOracleTest);
end.
