unit test.advchart.categoryminmax;
{$mode objfpc}{$H+}
{ A category axis narrowed or widened by min and max -- held to upstream.

  tools/advchart-oracle/category-minmax.js runs the real ECharts 6.1 build and
  records, per category axis: whether it inverted and whether it went blank,
  its effective and mapping extents, its count and band, which values it
  contains and where seventeen of them land, its labels with their texts and
  whether they were drawn, its ticks and split lines; per bar series the
  column and every item's box after the clip; per line series every vertex as
  the Float32Array holds it, the clip rect and which items got a marker; per
  scatter the markers drawn and where; and for a set of pointer positions
  which category the axis pointer took, or that it took none.

  THE RULES IT HOLDS THE PORT TO: a number bound is rounded as Math.round
  rounds, a string one is a category's name and nothing else; an unwritten end
  is the first or last category; a bound past the list is allowed and its
  positions have empty labels; backwards inverts the axis; startValue widens
  an end nobody pinned; a bound naming nothing blanks the axis, which then
  draws nothing; a line is cut at the plot widened by half its pen, its
  markers only on labelled categories inside it; the pointer only on a
  category that exists.

  Everything is compared to the bit. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Builder,
     tyControls.AdvChart.BarLayout, tyControls.AdvChart.Layout,
     tyControls.AdvanceChart, test.advchart.gridbounds;
type
  TCatProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function Column(ASeriesIndex: Integer): TTyBarColumn;
    function Pointers(AX, AY: Integer): TTyAxisHitArray;
  end;

  { zrender's table in pixels, fed the chart's sizes in points: the theme
    writes a label as 9 pt, which is upstream's 12 px at 96 PPI }
  TPtToPxMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  private
    FInner: ITyTextMeasurer;
  public
    constructor Create(const AInner: ITyTextMeasurer);
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TAdvChartCategoryMinMaxOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCatProbe;
    FRoot, FTable: TJSONData;
    FBad, FCompared, FBlanks, FNarrowed, FProbes, FBars, FLines: Integer;
    FReport, FName: string;
    FProbeValues: TJSONArray;
    procedure Miss(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure CheckAxis(AAxis: TJSONObject);
    procedure CheckSeries(ASeries: TJSONObject);
    procedure CheckProbe(AProbe: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryCategoryWindowAsUpstreamDrawsIt;
    procedure TestAHugeWindowIsRefusedNotWalked;
    procedure TestABlankAxisTakesNoPointer;
    procedure TestAFractionalIndexLandsOnItsRoundedCategory;
  end;

implementation

procedure TCatProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

constructor TPtToPxMeasurer.Create(const AInner: ITyTextMeasurer);
begin
  inherited Create;
  FInner := AInner;
end;

procedure TPtToPxMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
begin
  FInner.MeasureLine(AText, AFontName, Round(AFontSizeLogical * 96 / 72),
    AWeight, AW, AH);
end;

function TPtToPxMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

{ zrender's width table, as the oracle measured with: the auto interval of a
  long category axis is decided by how wide its labels are }
function TCatProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

function TCatProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TCatProbe.Column(ASeriesIndex: Integer): TTyBarColumn;
begin
  Result := BarColumnOf(ASeriesIndex);
end;

function TCatProbe.Pointers(AX, AY: Integer): TTyAxisHitArray;
begin
  Result := ResolveAxisPointers(AX, AY);
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-category-minmax.json';
end;

{ 16 hex digits, or a name for a value that is not finite }
function NumOf(AData: TJSONData): Double;
var
  q: QWord;
  s: string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  if AData.JSONType = jtNumber then Exit(AData.AsFloat);
  s := AData.AsString;
  if s = 'NaN' then Exit(NaN);
  if s = 'Infinity' then Exit(Infinity);
  if s = '-Infinity' then Exit(NegInfinity);
  Result := 0;
  q := StrToQWord('$' + s);
  Move(q, Result, SizeOf(Result));
end;

{ 8 hex digits: a single's bits, widened }
function SingleOf(const AHex: string): Double;
var
  l: LongWord;
  s: Single;
begin
  l := LongWord(StrToQWord('$' + AHex));
  Move(l, s, SizeOf(s));
  Result := s;
end;

function Fmt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

procedure TAdvChartCategoryMinMaxOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TCatProbe.Create(FForm);
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
  FProbeValues := TJSONObject(FRoot).Arrays['probeValues'];
  { the text table from the grid-bounds fixture, which is the same zrender }
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-grid-bounds.json');
    FTable := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FTable).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FTable).Objects['ratios'].Integers['firstCode']));
  FBad := 0;
  FCompared := 0;
  FBlanks := 0;
  FNarrowed := 0;
  FProbes := 0;
  FBars := 0;
  FLines := 0;
  FReport := '';
end;

procedure TAdvChartCategoryMinMaxOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FTable);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartCategoryMinMaxOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 400 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

{ to the bit; a gap as a gap; -0 as 0 }
procedure TAdvChartCategoryMinMaxOracleTest.Same(const AWhat: string;
  AGot: Double; AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  want := NumOf(AWant);
  if IsNan(want) or IsNan(AGot) then
  begin
    if not (IsNan(want) and IsNan(AGot)) then
      Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(want), Fmt(AGot)]));
  end
  else if AGot <> want then
    Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(want), Fmt(AGot)]));
end;

function AxisOf(const ADim: string; AIndex: Integer; ABuild: TTyChartBuild): TTyAxis;
var
  g: TTyGridBuild;
  i: Integer;
begin
  Result := nil;
  if ABuild.GridCount = 0 then Exit;
  g := ABuild.Grid(0);
  if ADim = 'x' then
  begin
    for i := 0 to g.XAxisCount - 1 do
      if g.XAxis(i).ComponentIndex = AIndex then Exit(g.XAxis(i));
  end
  else
    for i := 0 to g.YAxisCount - 1 do
      if g.YAxis(i).ComponentIndex = AIndex then Exit(g.YAxis(i));
end;

procedure TAdvChartCategoryMinMaxOracleTest.CheckAxis(AAxis: TJSONObject);
var
  ax: TTyAxis;
  tag: string;
  arr, vals, coords, drawn: TJSONArray;
  e: TTyRange;
  i, k, p, built: Integer;
  blank: Boolean;
  spec: PTyAxisLayoutSpec;
  lab, markRec: TJSONObject;
  v: Double;
  d: TJSONData;

  procedure CheckMarks(const AWhat: string; const AMarks: TTyAxisMarkArray;
    ARec: TJSONObject);
  var q: Integer;
  begin
    vals := ARec.Arrays['values'];
    coords := ARec.Arrays['globalCoords'];
    Inc(FCompared);
    if Length(AMarks) <> vals.Count then
    begin
      Miss(Format('%s %s: %d upstream, %d here', [tag, AWhat, vals.Count,
        Length(AMarks)]));
      Exit;
    end;
    for q := 0 to vals.Count - 1 do
    begin
      Same(Format('%s %s %d value', [tag, AWhat, q]), AMarks[q].Value, vals.Items[q]);
      Same(Format('%s %s %d', [tag, AWhat, q]), AMarks[q].Coord, coords.Items[q]);
    end;
  end;

begin
  tag := AAxis.Strings['dim'] + IntToStr(AAxis.Integers['index']);
  ax := AxisOf(AAxis.Strings['dim'], AAxis.Integers['index'], FChart.Build);
  if ax = nil then
  begin
    Miss(tag + ': no such axis here');
    Exit;
  end;
  Inc(FCompared);
  if ax.Inverse <> AAxis.Booleans['inverse'] then
    Miss(Format('%s: inverse %s upstream', [tag, BoolToStr(AAxis.Booleans['inverse'], True)]));
  if AAxis.Strings['type'] <> 'category' then
  begin
    { the other axis is compared for its extent only }
    e := ax.Scale.GetExtent;
    arr := AAxis.Arrays['effective'];
    Same(tag + ' effective start', e.Start, arr.Items[0]);
    Same(tag + ' effective stop', e.Stop, arr.Items[1]);
    Exit;
  end;

  { BLANK, OR THE WINDOW }
  blank := AAxis.Booleans['blank'];
  Inc(FCompared);
  if ax.Scale.Blank <> blank then
  begin
    Miss(Format('%s: blank %s upstream', [tag, BoolToStr(blank, True)]));
    Exit;
  end;
  if blank then
  begin
    Inc(FBlanks);
    { a blank axis draws no labels and no marks, and places nothing }
    spec := FChart.Build.Grid(0).SpecFor(ax);
    for i := 0 to High(spec^.Placements) do
      if spec^.Placements[i].Shown then
      begin
        Miss(tag + ': a label on a blank axis');
        Break;
      end;
    if Length(spec^.TickMarks) + Length(spec^.SplitLineMarks) > 0 then
      Miss(tag + ': marks on a blank axis');
    Exit;
  end;
  e := ax.Scale.GetExtent;
  arr := AAxis.Arrays['effective'];
  Same(tag + ' effective start', e.Start, arr.Items[0]);
  Same(tag + ' effective stop', e.Stop, arr.Items[1]);
  if (e.Start <> 0) or (e.Stop <> AAxis.Integers['nCat'] - 1) then Inc(FNarrowed);
  d := AAxis.Find('mapping');
  Inc(FCompared);
  if (d is TJSONArray) <> ax.Scale.Mapper.HasExtent(sekMapping) then
    Miss(Format('%s: a mapping %s upstream', [tag, BoolToStr(d is TJSONArray, 'yes', 'none')]))
  else if d is TJSONArray then
  begin
    e := ax.Scale.GetExtent2(sekMapping);
    Same(tag + ' mapping start', e.Start, TJSONArray(d).Items[0]);
    Same(tag + ' mapping stop', e.Stop, TJSONArray(d).Items[1]);
  end;
  Inc(FCompared);
  if IntToStr(TTyOrdinalScale(ax.Scale).Count) <> AAxis.Strings['count'] then
    Miss(Format('%s: %s categories in the window upstream, %d here', [tag,
      AAxis.Strings['count'], TTyOrdinalScale(ax.Scale).Count]));
  d := AAxis.Find('bandW');
  if (d <> nil) and (d.JSONType = jtString) then
    Same(tag + ' band', ax.BandWidth, d);

  { WHICH VALUES IT HOLDS, AND WHERE THEY LAND }
  arr := AAxis.Arrays['contain'];
  for i := 0 to FProbeValues.Count - 1 do
  begin
    v := FProbeValues.Items[i].AsFloat;
    Inc(FCompared);
    if ax.Scale.Contain(v) <> arr.Booleans[i] then
      Miss(Format('%s: contains %s is %s upstream', [tag, Fmt(v),
        BoolToStr(arr.Booleans[i], True)]));
    Same(Format('%s coord of %s', [tag, Fmt(v)]), ax.DataToCoord(v),
      AAxis.Arrays['coords'].Items[i]);
  end;

  { THE LABELS: the built ones, their text, and which were drawn -- at the
    interval upstream settled on }
  spec := FChart.Build.Grid(0).SpecFor(ax);
  d := AAxis.Objects['interval'].Find('used');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    Inc(FCompared);
    if spec^.LabelStep - 1 <> d.AsInteger then
      Miss(Format('%s: label interval %d upstream, %d here', [tag, d.AsInteger,
        spec^.LabelStep - 1]));
  end;
  arr := AAxis.Arrays['labels'];
  built := 0;
  for i := 0 to High(spec^.Placements) do
    if spec^.Placements[i].Built then Inc(built);
  Inc(FCompared);
  if built <> arr.Count then
    Miss(Format('%s: %d labels built upstream, %d here', [tag, arr.Count, built]));
  for k := 0 to arr.Count - 1 do
  begin
    lab := arr.Objects[k];
    v := lab.Floats['value'];
    p := -1;
    for i := 0 to High(spec^.TickValues) do
      if spec^.TickValues[i] = v then
      begin
        p := i;
        Break;
      end;
    Inc(FCompared);
    if (p < 0) or (p > High(spec^.Placements)) or not spec^.Placements[p].Built then
    begin
      Miss(Format('%s: no label built for %s here', [tag, Fmt(v)]));
      Continue;
    end;
    if spec^.Placements[p].Text <> lab.Strings['text'] then
      Miss(Format('%s label %s: "%s" upstream, "%s" here', [tag, Fmt(v),
        lab.Strings['text'], spec^.Placements[p].Text]));
    if spec^.Placements[p].OffInterval <> lab.Booleans['offInterval'] then
      Miss(Format('%s label %s: off the interval %s upstream', [tag, Fmt(v),
        BoolToStr(lab.Booleans['offInterval'], True)]));
    { upstream draws no empty text; here an empty one paints nothing }
    if (spec^.Placements[p].Shown and (spec^.Placements[p].Text <> ''))
      <> lab.Booleans['shown'] then
      Miss(Format('%s label %s: shown %s upstream', [tag, Fmt(v),
        BoolToStr(lab.Booleans['shown'], True)]));
  end;

  { THE TICKS AND THE SPLIT LINES }
  markRec := AAxis.Objects['ticks'];
  CheckMarks('tick', spec^.TickMarks, markRec);
  markRec := AAxis.Objects['splitLines'];
  CheckMarks('split line', spec^.SplitLineMarks, markRec);
end;

procedure TAdvChartCategoryMinMaxOracleTest.CheckSeries(ASeries: TJSONObject);
var
  si, k, i, marks, n: Integer;
  typ, cls: string;
  items, arr, pts: TJSONArray;
  item: TJSONObject;
  lst: TTyPaintList;
  e, mark: TTyChartElement;
  b: TTyRectF;
  col: TTyBarColumn;
  ring: TTyPointFArray;
  got, want: string;
  clip: TJSONObject;
  cx, cy, cw, ch: Double;
  d: TJSONData;
begin
  si := ASeries.Integers['index'];
  typ := ASeries.Strings['type'];
  if ASeries.Booleans['filtered'] then Exit;
  lst := FChart.List;
  if typ = 'bar' then
  begin
    Inc(FBars);
    col := FChart.Column(si);
    d := ASeries.Find('bandWidth');
    if (d <> nil) and (d.JSONType = jtString) then
    begin
      Same(Format('s%d band', [si]), col.BandWidth, d);
      Same(Format('s%d offset', [si]), col.Offset, ASeries.Find('offset'));
      Same(Format('s%d size', [si]), col.Width, ASeries.Find('size'));
    end;
    items := ASeries.Arrays['items'];
    for k := 0 to items.Count - 1 do
    begin
      item := items.Objects[k];
      cls := item.Strings['class'];
      marks := 0;
      mark := Default(TTyChartElement);
      if lst <> nil then
        for i := 0 to lst.Count - 1 do
        begin
          e := lst.Element(i);
          if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si)
            or (e.Datum.RawDataIndex <> k) or (e.Caption.FontSizeLogical > 0) then Continue;
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
      arr := item.Arrays['box'];
      Same(Format('s%d[%d] box left', [si, k]), b.Left, arr.Items[0]);
      Same(Format('s%d[%d] box top', [si, k]), b.Top, arr.Items[1]);
      Same(Format('s%d[%d] box right', [si, k]), b.Right, arr.Items[2]);
      Same(Format('s%d[%d] box bottom', [si, k]), b.Bottom, arr.Items[3]);
    end;
    Exit;
  end;

  { MARKERS: which items got one }
  want := '';
  arr := ASeries.Arrays['symbols'];
  for k := 0 to arr.Count - 1 do want := want + IntToStr(arr.Integers[k]) + ' ';
  got := '';
  if lst <> nil then
    for i := 0 to lst.Count - 1 do
    begin
      e := lst.Element(i);
      if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si) or (e.Datum.RawDataIndex < 0)
        or (e.Caption.FontSizeLogical > 0) then Continue;
      got := got + IntToStr(e.Datum.RawDataIndex) + ' ';
    end;
  Inc(FCompared);
  if want <> got then
    Miss(Format('s%d: markers on [%s] upstream, [%s] here', [si, Trim(want), Trim(got)]));

  if typ = 'scatter' then
  begin
    pts := ASeries.Arrays['symbolPoints'];
    n := 0;
    if lst <> nil then
      for i := 0 to lst.Count - 1 do
      begin
        e := lst.Element(i);
        if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si) or (e.Datum.RawDataIndex < 0)
          or (e.Caption.FontSizeLogical > 0) then Continue;
        if (n < pts.Count) and (e.Shape.Kind = cskCircle) then
        begin
          Same(Format('s%d marker %d x', [si, n]), e.Shape.CX,
            TJSONArray(pts.Items[n]).Items[0]);
          Same(Format('s%d marker %d y', [si, n]), e.Shape.CY,
            TJSONArray(pts.Items[n]).Items[1]);
        end;
        Inc(n);
      end;
    Exit;
  end;

  if typ <> 'line' then Exit;
  Inc(FLines);
  { THE STROKE: every vertex as a single, off the window included -- one
    run while nothing is missing }
  pts := ASeries.Arrays['points'];
  ring := nil;
  if lst <> nil then
    for i := 0 to lst.Count - 1 do
    begin
      e := lst.Element(i);
      if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si)
        or (e.Datum.RawDataIndex <> -1) or e.Silent
        or (e.Shape.Kind <> cskPolyline) then Continue;
      n := Length(ring);
      SetLength(ring, n + Length(e.Shape.Points));
      for k := 0 to High(e.Shape.Points) do ring[n + k] := e.Shape.Points[k];
      { and the cut it is drawn through }
      clip := ASeries.Objects['clip'];
      Inc(FCompared);
      if not e.HasClip then Miss(Format('s%d: no clip here', [si]))
      else
      begin
        cx := NumOf(clip.Find('x'));
        cy := NumOf(clip.Find('y'));
        cw := NumOf(clip.Find('width'));
        ch := NumOf(clip.Find('height'));
        if (e.ClipRect.Left <> cx) or (e.ClipRect.Top <> cy)
          or (e.ClipRect.Right <> cx + cw) or (e.ClipRect.Bottom <> cy + ch) then
          Miss(Format('s%d: clipped to %s,%s %sx%s upstream, %s,%s..%s,%s here',
            [si, Fmt(cx), Fmt(cy), Fmt(cw), Fmt(ch), Fmt(e.ClipRect.Left),
             Fmt(e.ClipRect.Top), Fmt(e.ClipRect.Right), Fmt(e.ClipRect.Bottom)]));
      end;
    end;
  { and the area under it, through the same cut }
  if lst <> nil then
    for i := 0 to lst.Count - 1 do
    begin
      e := lst.Element(i);
      if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si)
        or (e.Datum.RawDataIndex <> -1) or (not e.Silent)
        or (e.Shape.Kind <> cskPolygon) then Continue;
      clip := ASeries.Objects['clip'];
      Inc(FCompared);
      if not e.HasClip then Miss(Format('s%d: an area not clipped here', [si]))
      else if (e.ClipRect.Left <> NumOf(clip.Find('x')))
        or (e.ClipRect.Top <> NumOf(clip.Find('y'))) then
        Miss(Format('s%d: an area clipped elsewhere', [si]));
    end;
  Inc(FCompared);
  if Length(ring) <> pts.Count then
    Miss(Format('s%d: %d vertices upstream, %d here', [si, pts.Count, Length(ring)]))
  else
    for k := 0 to pts.Count - 1 do
    begin
      Inc(FCompared);
      if (ring[k].X <> SingleOf(TJSONArray(pts.Items[k]).Strings[0]))
        or (ring[k].Y <> SingleOf(TJSONArray(pts.Items[k]).Strings[1])) then
      begin
        Miss(Format('s%d vertex %d: %s,%s upstream, %s,%s here', [si, k,
          Fmt(SingleOf(TJSONArray(pts.Items[k]).Strings[0])),
          Fmt(SingleOf(TJSONArray(pts.Items[k]).Strings[1])),
          Fmt(ring[k].X), Fmt(ring[k].Y)]));
        Break;
      end;
    end;
end;

procedure TAdvChartCategoryMinMaxOracleTest.CheckProbe(AProbe: TJSONObject);
var
  hits: TTyAxisHitArray;
  i, found: Integer;
  dim: string;
  wantV: TJSONData;
begin
  Inc(FProbes);
  hits := FChart.Pointers(AProbe.Integers['x'], AProbe.Integers['y']);
  dim := AProbe.Strings['axisDim'];
  found := -1;
  for i := 0 to High(hits) do
    if (not hits[i].Cross) and (hits[i].Axis <> nil)
      and (hits[i].Axis.Horizontal = (dim = 'x')) then
    begin
      found := i;
      Break;
    end;
  wantV := AProbe.Find('axisValue');
  Inc(FCompared);
  if (wantV = nil) or (wantV.JSONType = jtNull) then
  begin
    if found >= 0 then
      Miss(Format('at %d,%d: no pointer upstream, one on %s here',
        [AProbe.Integers['x'], AProbe.Integers['y'], Fmt(hits[found].Value)]));
    Exit;
  end;
  if found < 0 then
  begin
    Miss(Format('at %d,%d: a pointer on %s upstream, none here',
      [AProbe.Integers['x'], AProbe.Integers['y'], Fmt(wantV.AsFloat)]));
    Exit;
  end;
  if hits[found].Value <> wantV.AsFloat then
    Miss(Format('at %d,%d: the pointer on %s upstream, %s here',
      [AProbe.Integers['x'], AProbe.Integers['y'], Fmt(wantV.AsFloat),
       Fmt(hits[found].Value)]));
  { and the datum it names }
  if (AProbe.Find('dataIndex') <> nil) and (AProbe.Find('dataIndex').JSONType = jtNumber) then
  begin
    Inc(FCompared);
    if (Length(hits[found].Rows) = 0)
      or (hits[found].Rows[0] <> AProbe.Integers['dataIndex']) then
      Miss(Format('at %d,%d: datum %d upstream', [AProbe.Integers['x'],
        AProbe.Integers['y'], AProbe.Integers['dataIndex']]));
  end
  else if Length(hits[found].Rows) > 0 then
    Miss(Format('at %d,%d: no datum upstream, row %d here',
      [AProbe.Integers['x'], AProbe.Integers['y'], hits[found].Rows[0]]));
end;

procedure TAdvChartCategoryMinMaxOracleTest.TestEveryCategoryWindowAsUpstreamDrawsIt;
var
  cases, arr: TJSONArray;
  cs: TJSONObject;
  c, i, w, h, deferred: Integer;
  bmp: TBGRABitmap;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  deferred := 0;
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    FName := cs.Strings['name'];
    if (cs.Find('deferred') <> nil) and cs.Booleans['deferred'] then
    begin
      AssertTrue(FName + ' says why it is deferred', cs.Strings['why'] <> '');
      Inc(deferred);
      Continue;
    end;
    w := cs.Integers['W'];
    h := cs.Integers['H'];
    FChart.Option := cs.Objects['option'].AsJSON;
    AssertEquals(FName + ' parses', '', FChart.OptionError);
    FChart.SetBounds(0, 0, w, h);
    bmp := TBGRABitmap.Create(w, h, BGRA(255, 255, 255, 255));
    try
      try
        FChart.Render(bmp.Canvas, Rect(0, 0, w, h), 96);
        arr := cs.Arrays['axes'];
        for i := 0 to arr.Count - 1 do CheckAxis(arr.Objects[i]);
        arr := cs.Arrays['series'];
        for i := 0 to arr.Count - 1 do CheckSeries(arr.Objects[i]);
        if cs.Find('probes') is TJSONArray then
        begin
          arr := cs.Arrays['probes'];
          for i := 0 to arr.Count - 1 do CheckProbe(arr.Objects[i]);
        end;
      except
        on E: Exception do
          Miss(E.ClassName + ': ' + E.Message + ' at ' + BackTraceStrFunc(ExceptAddr)
            + ' / ' + BackTraceStrFunc(ExceptFrames[0]) + ' / '
            + BackTraceStrFunc(ExceptFrames[1]) + ' / ' + BackTraceStrFunc(ExceptFrames[2]));
      end;
    finally
      bmp.Free;
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertEquals('the deferred cases', 3, deferred);
  AssertTrue(Format('enough compared (%d)', [FCompared]), FCompared > 3000);
  AssertTrue(Format('enough windows narrowed (%d)', [FNarrowed]), FNarrowed > 40);
  AssertTrue(Format('enough blank axes (%d)', [FBlanks]), FBlanks >= 8);
  AssertTrue(Format('enough bar series (%d)', [FBars]), FBars >= 20);
  AssertTrue(Format('enough lines (%d)', [FLines]), FLines >= 8);
  AssertTrue(Format('enough pointer probes (%d)', [FProbes]), FProbes >= 30);
end;

procedure TAdvChartCategoryMinMaxOracleTest.TestAHugeWindowIsRefusedNotWalked;
var
  bmp: TBGRABitmap;
  ax: TTyAxis;
begin
  { MORE CATEGORIES THAN ANYTHING CAN DRAW. Upstream walks min 0 max 3e6 and
    draws the two labels it has; walking it here would build three million
    label strings, so the window is refused and the axis goes blank -- a
    recorded divergence, and the oracle keeps its case deferred. }
  FChart.Option := '{ xAxis: { type: ''category'', data: [''a'', ''b''], max: 3000000 },'
    + ' yAxis: { type: ''value'' }, series: [{ type: ''bar'', data: [1, 2] }] }';
  FChart.SetBounds(0, 0, 600, 400);
  bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
  finally
    bmp.Free;
  end;
  ax := FChart.Build.Grid(0).XAxis(0);
  AssertTrue('the window is refused', ax.Scale.Blank);
  AssertEquals('and has no categories in it', 0, TTyOrdinalScale(ax.Scale).Count);
  { a window of a million still is one }
  FChart.Option := '{ xAxis: { type: ''category'', data: [''a'', ''b''], max: 1048575 },'
    + ' yAxis: { type: ''value'' }, series: [] }';
  bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
  finally
    bmp.Free;
  end;
  AssertFalse('a million is still a window',
    FChart.Build.Grid(0).XAxis(0).Scale.Blank);
end;

procedure TAdvChartCategoryMinMaxOracleTest.TestABlankAxisTakesNoPointer;
var
  bmp: TBGRABitmap;
begin
  { A VALUE AXIS WITH NOTHING ON IT is blank: [0, 1] with ticks upstream does
    not draw, and no pointer either -- the blank test comes before any
    containment }
  FChart.Option := '{ tooltip: { trigger: ''axis'' }, xAxis: { type: ''value'' },'
    + ' yAxis: { type: ''value'' }, series: [{ type: ''line'', data: [] }] }';
  FChart.SetBounds(0, 0, 600, 400);
  bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
  finally
    bmp.Free;
  end;
  AssertTrue('the axis is blank', FChart.Build.Grid(0).XAxis(0).Scale.Blank);
  AssertEquals('and takes no pointer', 0, Length(FChart.Pointers(300, 200)));
end;

procedure TAdvChartCategoryMinMaxOracleTest.TestAFractionalIndexLandsOnItsRoundedCategory;
var
  bmp: TBGRABitmap;
  ax: TTyAxis;
begin
  { AN INDEX IS KEPT AS WRITTEN AND ROUNDED WHERE IT IS PLACED, as upstream's
    Ordinal.parse rounds a number -- half up, the way Math.round does: 1.5
    is the third category, -0.5 the first }
  FChart.Option := '{ xAxis: { type: ''category'', data: [''a'', ''b'', ''c'', ''d''] },'
    + ' yAxis: { type: ''value'' }, series: [{ type: ''line'', data: [[1.5, 3]] }] }';
  FChart.SetBounds(0, 0, 600, 400);
  bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
  finally
    bmp.Free;
  end;
  ax := FChart.Build.Grid(0).XAxis(0);
  AssertEquals('1.5 on the third category', ax.DataToCoord(2), ax.DataToCoord(1.5), 0);
  AssertEquals('2.4 on the third', ax.DataToCoord(2), ax.DataToCoord(2.4), 0);
  AssertEquals('-0.5 on the first', ax.DataToCoord(0), ax.DataToCoord(-0.5), 0);
  AssertTrue('and 1.5 is not between the second and the third',
    ax.DataToCoord(1.5) <> (ax.DataToCoord(1) + ax.DataToCoord(2)) / 2);
end;

initialization
  RegisterTest(TAdvChartCategoryMinMaxOracleTest);
end.
