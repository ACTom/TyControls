unit test.advchart.stattransforms;
{$mode objfpc}{$H+}
{ ECSTAT'S TRANSFORMS -- roadmap D3, batch 134 -- held to upstream.

  tools/advchart-oracle/stat-transforms.js runs the real ECharts 6.1 build
  with the built echarts-stat registered (ecStat.transform.regression,
  .histogram, .clustering) in node over 164 options, Math.random the
  port's xorshift32 reset before every chart, and records per dataset
  either the message upstream threw or every result: format, copy flag,
  header count, dimension names, detected count and the rows cell by cell
  (a root dataset's rows are its own source and left out); the number of
  Math.random draws the case made; and, for the options with series, the
  grid, the category axes, per series the items (bar rects, line and
  scatter points, a scatter's fill) and the non-empty labels.

  THE REPLAY: the tables are TTyDatasetCache's results read through
  TySourceFieldsOf, every number to the bit; a dataset upstream throws on
  has no table here and a reason; the cache's random state after the
  datasets is the seed stepped once per upstream draw. The charts are the
  control's own, text measured with zrender's width table, and the chart's
  random state after the first render is stepped the same.

  Hand-written beside it: the three are registered with no call; a
  clustering keeps its clusters over a resize and a merge without
  `dataset`, and draws again after one with it; a numeric string is not a
  number here (the one deviation the oracle carries); the diagnostic says
  what the transform refused. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StrConsts,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Builder,
     tyControls.AdvChart.Option, tyControls.AdvChart.Dataset,
     tyControls.AdvChart.DataTransform, tyControls.AdvChart.StatTransform,
     tyControls.AdvChart.Jitter, tyControls.AdvChart.Measure,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TStProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartStatTransformsTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TStProbe;
    FRoot, FTable: TJSONData;
    FBad, FCompared, FCells, FItems, FLabels, FDraws: Integer;
    FReport, FWhere: string;
    procedure Miss(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; const AHex: string);
    procedure SameInt(const AWhat: string; AGot, AWant: Int64);
    procedure SameStr(const AWhat, AGot, AWant: string);
    function Cases: TJSONArray;
    function CaseById(const AId: string): TJSONObject;
    procedure NewChart(AOption: TJSONObject);
    procedure RenderChart;
    procedure CheckCell(const AWhat: string; AGot: TJSONData; AWant: TJSONData);
    procedure CheckRows(const AWhat: string; ANode: TJSONObject; AWant: TJSONData);
    procedure CheckDatasets(ACase: TJSONObject);
    procedure CheckSeries(ASeries: TJSONObject);
    procedure CheckRender(ACase: TJSONObject);
    procedure Finish(const AWhat: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryTableIsUpstreamsTable;
    procedure TestEveryThrowLeavesNoTable;
    procedure TestChartsOverTheTransformsDrawAsUpstream;
    procedure TestTheThreeAreRegisteredWithNoCall;
    procedure TestAClusteringKeepsItsClustersUntilTheDatasetsChange;
    procedure TestANumericStringIsNotANumberHere;
    procedure TestARefusalIsADiagnostic;
  end;

implementation

{ ==================== the probe ==================== }

procedure TStProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TStProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

function TStProbe.List: TTyPaintList;
begin
  Result := SeriesList;
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

function Fmt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

{ to the bit -- a not-a-number is one whatever its payload }
function SameBits(A, B: Double): Boolean;
begin
  Result := (HexOf(A) = HexOf(B)) or (IsNan(A) and IsNan(B));
end;

function IsNull(AData: TJSONData): Boolean;
begin
  Result := (AData = nil) or (AData.JSONType = jtNull);
end;

function FormatName(AFormat: TTySourceFormat): string;
begin
  case AFormat of
    tsfArrayRows: Result := 'arrayRows';
    tsfObjectRows: Result := 'objectRows';
    tsfKeyedColumns: Result := 'keyedColumns';
    tsfOriginal: Result := 'original';
  else
    Result := 'unknown';
  end;
end;

{ the xorshift32 state after ADraws draws from the seed }
function StateAfter(ADraws: Integer): LongWord;
var i: Integer;
begin
  Result := TyJitterSeed;
  for i := 1 to ADraws do TyJitterRandom(Result);
end;

procedure TAdvChartStatTransformsTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-stat-transforms.json'));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-grid-bounds.json'));
    FTable := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartStatTransformsTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FTable);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartStatTransformsTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 16000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartStatTransformsTest.Same(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not SameBits(AGot, FromHex(AHex)) then
    Miss(Format('%s %s here, %s upstream', [AWhat, Fmt(AGot), Fmt(FromHex(AHex))]));
end;

procedure TAdvChartStatTransformsTest.SameInt(const AWhat: string; AGot, AWant: Int64);
begin
  Inc(FCompared);
  if AGot <> AWant then Miss(Format('%s %d here, %d upstream', [AWhat, AGot, AWant]));
end;

procedure TAdvChartStatTransformsTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then Miss(Format('%s "%s" here, "%s" upstream', [AWhat, AGot, AWant]));
end;

procedure TAdvChartStatTransformsTest.Finish(const AWhat: string);
begin
  if GetEnvironmentVariable('TY_STATTRANSFORMS_COUNTS') = '1' then
    WriteLn(Format('%s: %d compared, %d cells, %d items, %d labels, %d draws',
      [AWhat, FCompared, FCells, FItems, FLabels, FDraws]));
  AssertTrue(AWhat + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

function TAdvChartStatTransformsTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

function TAdvChartStatTransformsTest.CaseById(const AId: string): TJSONObject;
var i: Integer;
begin
  Result := nil;
  for i := 0 to Cases.Count - 1 do
    if Cases.Objects[i].Strings['id'] = AId then Exit(Cases.Objects[i]);
end;

procedure TAdvChartStatTransformsTest.NewChart(AOption: TJSONObject);
begin
  if FChart <> nil then
  begin
    FChart.Measurer := nil;
    FreeAndNil(FChart);
  end;
  FChart := TStProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FTable).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FTable).Objects['ratios'].Integers['firstCode']));
  FChart.Option := AOption.AsJSON;
  FChart.SetBounds(0, 0, TJSONObject(FRoot).Integers['W'], TJSONObject(FRoot).Integers['H']);
end;

procedure TAdvChartStatTransformsTest.RenderChart;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

{ ==================== the tables ==================== }

{ A cell as the fixture writes it: a number its hex, 's:' a string, 'b:' a
  boolean, 'j:' anything else as JSON, null null (or a hole) }
procedure TAdvChartStatTransformsTest.CheckCell(const AWhat: string;
  AGot: TJSONData; AWant: TJSONData);
var
  w: string;
  jd: TJSONData;
begin
  Inc(FCompared);
  Inc(FCells);
  if IsNull(AWant) then
  begin
    if not IsNull(AGot) then Miss(AWhat + ': ' + AGot.AsJSON + ' here, null upstream');
    Exit;
  end;
  w := AWant.AsString;
  if AGot = nil then
  begin
    Miss(AWhat + ': nothing here, ' + w + ' upstream');
    Exit;
  end;
  if Copy(w, 1, 2) = 's:' then
  begin
    if (AGot.JSONType <> jtString) or (AGot.AsString <> Copy(w, 3, MaxInt)) then
      Miss(Format('%s: %s here, %s upstream', [AWhat, AGot.AsJSON, w]));
  end
  else if Copy(w, 1, 2) = 'b:' then
  begin
    if (AGot.JSONType <> jtBoolean) or (BoolToStr(AGot.AsBoolean, 'true', 'false') <> Copy(w, 3, MaxInt)) then
      Miss(Format('%s: %s here, %s upstream', [AWhat, AGot.AsJSON, w]));
  end
  else if Copy(w, 1, 2) = 'j:' then
  begin
    jd := GetJSON(Copy(w, 3, MaxInt));
    try
      if AGot.AsJSON <> jd.AsJSON then
        Miss(Format('%s: %s here, %s upstream', [AWhat, AGot.AsJSON, w]));
    finally
      jd.Free;
    end;
  end
  else if (AGot.JSONType <> jtNumber) or not SameBits(AGot.AsFloat, FromHex(w)) then
    Miss(Format('%s: %s here, %s upstream', [AWhat, AGot.AsJSON, Fmt(FromHex(w))]));
end;

procedure TAdvChartStatTransformsTest.CheckRows(const AWhat: string;
  ANode: TJSONObject; AWant: TJSONData);
var
  rows, want, wr, pairs: TJSONArray;
  r, c: Integer;
  got: TJSONData;
  obj: TJSONObject;
begin
  if IsNull(AWant) then Exit;   // a root dataset: its own source
  want := TJSONArray(AWant);
  rows := nil;
  if ANode.Find('source') is TJSONArray then rows := TJSONArray(ANode.Find('source'));
  if rows = nil then
  begin
    SameInt(AWhat + ' rows (no list here)', 0, want.Count);
    Exit;
  end;
  SameInt(AWhat + ' rows', rows.Count, want.Count);
  if rows.Count <> want.Count then Exit;
  for r := 0 to want.Count - 1 do
  begin
    got := rows.Items[r];
    if IsNull(want.Items[r]) then
    begin
      Inc(FCompared);
      if not IsNull(got) then Miss(Format('%s row %d: not null here', [AWhat, r]));
      Continue;
    end;
    if want.Items[r] is TJSONObject then
    begin
      pairs := TJSONObject(want.Items[r]).Arrays['o'];
      Inc(FCompared);
      if not (got is TJSONObject) or (TJSONObject(got).Count <> pairs.Count) then
      begin
        Miss(Format('%s row %d: %s here', [AWhat, r, got.AsJSON]));
        Continue;
      end;
      obj := TJSONObject(got);
      for c := 0 to pairs.Count - 1 do
      begin
        SameStr(Format('%s row %d key %d', [AWhat, r, c]), obj.Names[c],
          pairs.Arrays[c].Strings[0]);
        CheckCell(Format('%s row %d .%s', [AWhat, r, obj.Names[c]]), obj.Items[c],
          pairs.Arrays[c].Items[1]);
      end;
      Continue;
    end;
    wr := TJSONArray(want.Items[r]);
    Inc(FCompared);
    if not (got is TJSONArray) or (TJSONArray(got).Count <> wr.Count) then
    begin
      Miss(Format('%s row %d: %s here, %s upstream', [AWhat, r, got.AsJSON, wr.AsJSON]));
      Continue;
    end;
    for c := 0 to wr.Count - 1 do
      CheckCell(Format('%s row %d cell %d', [AWhat, r, c]), TJSONArray(got).Items[c], wr.Items[c]);
  end;
end;

procedure TAdvChartStatTransformsTest.CheckDatasets(ACase: TJSONObject);
var
  opt: TTyChartOption;
  cache: TTyDatasetCache;
  dss, res, dims: TJSONArray;
  ds, rec: TJSONObject;
  k, r, d, n: Integer;
  node: TJSONObject;
  fields: TTySourceFields;
  tag, nm: string;
begin
  opt := TTyChartOption.Create;
  cache := TTyDatasetCache.Create;
  try
    AssertTrue(FWhere + ': the option parses', opt.SetOptionText(ACase.Objects['option'].AsJSON));
    dss := ACase.Arrays['datasets'];
    for k := 0 to dss.Count - 1 do
    begin
      ds := dss.Objects[k];
      tag := Format('dataset %d', [k]);
      n := cache.ResultCount(opt, k);
      if not IsNull(ds.Find('error')) then
      begin
        { upstream threw: no table here, and a reason }
        Inc(FCompared);
        if (n <> 0) or (cache.ErrorOf(k) = '') then
          Miss(Format('%s: %d results and reason "%s" here, upstream threw "%s"',
            [tag, n, cache.ErrorOf(k), ds.Strings['error']]));
        Continue;
      end;
      SameStr(tag + ' reason', cache.ErrorOf(k), '');
      res := ds.Arrays['results'];
      SameInt(tag + ' results', n, res.Count);
      if n <> res.Count then Continue;
      for r := 0 to res.Count - 1 do
      begin
        rec := res.Objects[r];
        tag := Format('dataset %d result %d', [k, rec.Integers['r']]);
        node := cache.ResultNode(opt, k, rec.Integers['r']);
        if node = nil then
        begin
          Miss(tag + ': none here');
          Continue;
        end;
        Inc(FItems);
        fields := TySourceFieldsOf(node);
        SameStr(tag + ' format', FormatName(fields.Format), rec.Strings['format']);
        Inc(FCompared);
        if cache.ResultIsClone(opt, k, rec.Integers['r']) <> rec.Booleans['clone'] then
          Miss(tag + ': the copy flag');
        SameInt(tag + ' startIndex', fields.StartIndex, rec.Integers['startIndex']);
        if IsNull(rec.Find('detected')) then
          SameInt(tag + ' detected', fields.DetectedCount, -1)
        else
          SameInt(tag + ' detected', fields.DetectedCount, rec.Integers['detected']);
        Inc(FCompared);
        if IsNull(rec.Find('dims')) then
        begin
          if fields.DimsDefined then Miss(tag + ': dimensions here, none upstream');
        end
        else
        begin
          dims := rec.Arrays['dims'];
          if not fields.DimsDefined or (Length(fields.Dims) <> dims.Count) then
            Miss(Format('%s: %d dimensions here, %s upstream', [tag, Length(fields.Dims), dims.AsJSON]))
          else
            for d := 0 to dims.Count - 1 do
            begin
              if fields.Dims[d].HasName then nm := fields.Dims[d].Name else nm := '<none>';
              if IsNull(dims.Items[d]) then SameStr(Format('%s dim %d', [tag, d]), nm, '<none>')
              else SameStr(Format('%s dim %d', [tag, d]), nm, dims.Strings[d]);
            end;
        end;
        CheckRows(tag, node, rec.Find('rows'));
      end;
    end;
    { THE DRAWS: the cache's Math.random stepped once per upstream call }
    Inc(FCompared);
    Inc(FDraws, ACase.Integers['draws']);
    if cache.RandomState^ <> StateAfter(ACase.Integers['draws']) then
      Miss(Format('the random state is not %d draws on', [ACase.Integers['draws']]));
  finally
    cache.Free;
    opt.Free;
  end;
end;

procedure TAdvChartStatTransformsTest.TestEveryTableIsUpstreamsTable;
var
  i, n: Integer;
  c: TJSONObject;
begin
  n := 0;
  FCells := 0;
  FItems := 0;
  FDraws := 0;
  for i := 0 to Cases.Count - 1 do
  begin
    c := Cases.Objects[i];
    if (c.Strings['group'] = 'error') or (c.Find('deviation') <> nil) then Continue;
    FWhere := c.Strings['id'];
    CheckDatasets(c);
    Inc(n);
  end;
  Finish('tables');
  AssertTrue('the table cases', n >= 120);
  AssertTrue('the results', FItems >= 340);
  AssertTrue('the cells', FCells >= 11000);
  AssertTrue('the draws', FDraws >= 500);
end;

procedure TAdvChartStatTransformsTest.TestEveryThrowLeavesNoTable;
var
  i, n: Integer;
  c: TJSONObject;
begin
  n := 0;
  for i := 0 to Cases.Count - 1 do
  begin
    c := Cases.Objects[i];
    if c.Strings['group'] <> 'error' then Continue;
    FWhere := c.Strings['id'];
    Inc(n);
    CheckDatasets(c);
  end;
  AssertTrue('the error cases', n >= 20);
  Finish('throws');
end;

{ ==================== the charts ==================== }

function PackFill(AFill: TJSONArray): TTyChartColor;
begin
  Result := TTyChartColor((Cardinal(Floor(FromHex(AFill.Strings[3]) * 255 + 0.5)) shl 24)
    or (Cardinal(AFill.Integers[0]) shl 16) or (Cardinal(AFill.Integers[1]) shl 8)
    or Cardinal(AFill.Integers[2]));
end;

procedure TAdvChartStatTransformsTest.CheckSeries(ASeries: TJSONObject);
var
  si, k, i, n, d: Integer;
  typ, tag: string;
  items, labs, fills: TJSONArray;
  it: TJSONArray;
  lst: TTyPaintList;
  e: TTyChartElement;
  b: TTyRectF;
  x, y, w, h, cl, cr, ct, cb: Double;
  g: TTyXYWH;
  pts: TTyPointFArray;
  found: Boolean;
  want: array of Integer;
  gi: Integer;
begin
  si := ASeries.Integers['index'];
  typ := ASeries.Strings['type'];
  items := ASeries.Arrays['items'];
  lst := FChart.List;
  tag := Format('s%d %s', [si, typ]);
  if lst = nil then
  begin
    Miss(tag + ': no paint list');
    Exit;
  end;
  if typ = 'bar' then
  begin
    for k := 0 to items.Count - 1 do
    begin
      if IsNull(items.Items[k]) then Continue;
      it := TJSONArray(items.Items[k]);
      x := FromHex(it.Strings[0]);
      y := FromHex(it.Strings[1]);
      w := FromHex(it.Strings[2]);
      h := FromHex(it.Strings[3]);
      if IsNan(x) or IsNan(y) or IsNan(w) or IsNan(h) then Continue;
      found := False;
      for i := 0 to lst.Count - 1 do
      begin
        e := lst.Element(i);
        if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si) or (e.Datum.RawDataIndex <> k)
          or (e.Caption.FontSizeLogical > 0) or (e.Anim.Role = carLabel) then Continue;
        found := True;
        Inc(FItems);
        { the layout as its grid clips it }
        gi := 0;
        if FChart.Build.GridCount > 1 then
          for d := 0 to FChart.Build.GridCount - 1 do
          begin
            g := FChart.Build.Grid(d).PlotXYWH;
            if (Min(x, x + w) >= g.X - 1) and (Max(x, x + w) <= g.X + g.W + 1)
              and (Min(y, y + h) >= g.Y - 1) and (Max(y, y + h) <= g.Y + g.H + 1) then gi := d;
          end;
        g := FChart.Build.Grid(gi).PlotXYWH;
        cl := Max(Min(x, x + w), g.X);
        cr := Min(Max(x, x + w), g.X + g.W);
        ct := Max(Min(y, y + h), g.Y);
        cb := Min(Max(y, y + h), g.Y + g.H);
        b := TyShapeBounds(e.Shape);
        Inc(FCompared);
        if (b.Left <> cl) or (b.Right <> cr) or (b.Top <> ct) or (b.Bottom <> cb) then
          Miss(Format('%s[%d] bar %s,%s %sx%s upstream, %s,%s..%s,%s here',
            [tag, k, Fmt(x), Fmt(y), Fmt(w), Fmt(h), Fmt(b.Left), Fmt(b.Top),
             Fmt(b.Right), Fmt(b.Bottom)]));
        Break;
      end;
      if not found then Miss(Format('%s[%d]: no bar here', [tag, k]));
    end;
  end
  else if typ = 'scatter' then
  begin
    fills := nil;
    if ASeries.Find('fills') is TJSONArray then fills := ASeries.Arrays['fills'];
    n := 0;
    for i := 0 to lst.Count - 1 do
    begin
      e := lst.Element(i);
      if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si) or (e.Datum.RawDataIndex < 0)
        or (e.Caption.FontSizeLogical > 0) or (e.Anim.Role = carLabel)
        or (e.Shape.Kind <> cskCircle) then Continue;
      k := e.Datum.RawDataIndex;
      if k >= items.Count then Continue;
      Inc(FItems);
      Same(Format('%s[%d] x', [tag, k]), e.Shape.CX, TJSONArray(items.Items[k]).Strings[0]);
      Same(Format('%s[%d] y', [tag, k]), e.Shape.CY, TJSONArray(items.Items[k]).Strings[1]);
      if (fills <> nil) and (fills.Items[k] is TJSONArray) then
      begin
        Inc(FCompared);
        if e.Style.FillColor <> PackFill(TJSONArray(fills.Items[k])) then
          Miss(Format('%s[%d] fill $%.8x here, $%.8x upstream',
            [tag, k, e.Style.FillColor, PackFill(TJSONArray(fills.Items[k]))]));
      end;
      Inc(n);
    end;
    want := nil;
    for k := 0 to items.Count - 1 do
    begin
      it := TJSONArray(items.Items[k]);
      if IsNan(FromHex(it.Strings[0])) or IsNan(FromHex(it.Strings[1])) then Continue;
      SetLength(want, Length(want) + 1);
    end;
    SameInt(tag + ' points', n, Length(want));
  end
  else if typ = 'line' then
  begin
    { the polyline, vertex by vertex, as singles: every run of two numbers
      or more is a segment }
    pts := nil;
    for i := 0 to lst.Count - 1 do
    begin
      e := lst.Element(i);
      if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si) or (e.Datum.RawDataIndex <> -1)
        or e.Silent or (e.Shape.Kind <> cskPolyline) then Continue;
      n := Length(pts);
      SetLength(pts, n + Length(e.Shape.Points));
      for k := 0 to High(e.Shape.Points) do pts[n + k] := e.Shape.Points[k];
    end;
    want := nil;
    k := 0;
    while k < items.Count do
    begin
      i := k;
      while (i < items.Count) and not IsNan(FromHex(TJSONArray(items.Items[i]).Strings[0]))
        and not IsNan(FromHex(TJSONArray(items.Items[i]).Strings[1])) do Inc(i);
      if i - k >= 2 then
        for d := k to i - 1 do
        begin
          SetLength(want, Length(want) + 1);
          want[High(want)] := d;
        end;
      k := i + 1;
    end;
    SameInt(tag + ' vertices', Length(pts), Length(want));
    if Length(pts) = Length(want) then
      for k := 0 to High(want) do
      begin
        Inc(FItems);
        Inc(FCompared);
        it := TJSONArray(items.Items[want[k]]);
        if (pts[k].X <> Single(FromHex(it.Strings[0]))) or (pts[k].Y <> Single(FromHex(it.Strings[1]))) then
          Miss(Format('%s vertex %d is %s,%s here', [tag, want[k], Fmt(pts[k].X), Fmt(pts[k].Y)]));
      end;
  end;
  { the labels: each upstream (non-empty) text on its item, and no more here }
  labs := ASeries.Arrays['labels'];
  n := 0;
  for i := 0 to lst.Count - 1 do
    if (lst.Element(i).Anim.Role = carLabel) and (lst.Element(i).Datum.SeriesIndex = si)
      and (lst.Element(i).Caption.Text <> '') then Inc(n);
  SameInt(tag + ' labels', n, labs.Count);
  for k := 0 to labs.Count - 1 do
  begin
    d := labs.Objects[k].Integers['d'];
    found := False;
    for i := 0 to lst.Count - 1 do
    begin
      e := lst.Element(i);
      if (e.Anim.Role <> carLabel) or (e.Datum.SeriesIndex <> si) or (e.Datum.DataIndex <> d) then Continue;
      found := True;
      Inc(FLabels);
      SameStr(Format('%s[%d] label', [tag, d]), e.Caption.Text, labs.Objects[k].Strings['text']);
      Break;
    end;
    if not found then Miss(Format('%s[%d]: no label "%s" here', [tag, d, labs.Objects[k].Strings['text']]));
  end;
end;

procedure TAdvChartStatTransformsTest.CheckRender(ACase: TJSONObject);
var
  rend: TJSONObject;
  arr, cats: TJSONArray;
  g: TTyXYWH;
  i, k: Integer;
  ax: TTyAxis;
begin
  rend := ACase.Objects['render'];
  NewChart(ACase.Objects['option']);
  RenderChart;
  { the chart's stream after the first render: the transforms' draws }
  Inc(FCompared);
  if FChart.AxisMemory.RandomState^ <> StateAfter(ACase.Integers['draws']) then
    Miss(Format('the chart''s random state is not %d draws on', [ACase.Integers['draws']]));
  if not IsNull(rend.Find('rect')) then
  begin
    arr := rend.Arrays['rect'];
    g := FChart.Build.Grid(0).PlotXYWH;
    Same('grid x', g.X, arr.Strings[0]);
    Same('grid y', g.Y, arr.Strings[1]);
    Same('grid w', g.W, arr.Strings[2]);
    Same('grid h', g.H, arr.Strings[3]);
  end;
  arr := rend.Arrays['axes'];
  for i := 0 to arr.Count - 1 do
  begin
    if IsNull(arr.Objects[i].Find('categories')) then Continue;
    cats := arr.Objects[i].Arrays['categories'];
    ax := FChart.Build.Axis(arr.Objects[i].Strings['dim'] + 'Axis', arr.Objects[i].Integers['index']);
    Inc(FCompared);
    if (ax = nil) or (ax.Categories = nil) then
    begin
      Miss(arr.Objects[i].Strings['dim'] + ': no category axis here');
      Continue;
    end;
    SameInt(arr.Objects[i].Strings['dim'] + ' categories', ax.Categories.Count, cats.Count);
    if ax.Categories.Count = cats.Count then
      for k := 0 to cats.Count - 1 do
        SameStr(Format('%s category %d', [arr.Objects[i].Strings['dim'], k]),
          ax.Categories.CategoryAt(k), cats.Strings[k]);
  end;
  arr := rend.Arrays['series'];
  for i := 0 to arr.Count - 1 do CheckSeries(arr.Objects[i]);
end;

procedure TAdvChartStatTransformsTest.TestChartsOverTheTransformsDrawAsUpstream;
var
  i, n: Integer;
  c: TJSONObject;
begin
  n := 0;
  FItems := 0;
  FLabels := 0;
  for i := 0 to Cases.Count - 1 do
  begin
    c := Cases.Objects[i];
    if (c.Find('render') = nil) or (c.Objects['render'].Find('error') <> nil) then Continue;
    FWhere := c.Strings['id'];
    CheckRender(c);
    Inc(n);
  end;
  AssertTrue('the render cases', n >= 8);
  AssertTrue('the items', FItems >= 300);
  AssertTrue('the labels', FLabels >= 20);
  Finish('render');
end;

{ ==================== hand-written ==================== }

procedure TAdvChartStatTransformsTest.TestTheThreeAreRegisteredWithNoCall;
var
  f, g: TTyDataTransformFunc;
  b: Boolean;
begin
  AssertTrue('regression', TyFindDataTransform('ecStat:regression', f, b) and not b);
  AssertTrue('histogram', TyFindDataTransform('ecStat:histogram', f, b) and not b);
  AssertTrue('clustering', TyFindDataTransform('ecStat:clustering', f, b) and not b);
  AssertFalse('not without the namespace', TyFindDataTransform('regression', f, b));
  { a program's own under the name replaces it; the call puts it back }
  AssertTrue(TyFindDataTransform('ecStat:histogram', g, b));
  AssertTrue(TyFindDataTransform('ecStat:regression', f, b));
  TyRegisterDataTransform('ecStat:histogram', f);
  AssertTrue(TyFindDataTransform('ecStat:histogram', f, b));
  AssertFalse('replaced', f = g);
  TyRegisterEcStatTransforms;
  AssertTrue(TyFindDataTransform('ecStat:histogram', f, b));
  AssertTrue('back', f = g);
end;

{ the scatter's symbols, as "x,y,fill;" in paint order }
function ScatterPrint(AList: TTyPaintList; ASeries: Integer): string;
var
  i: Integer;
  e: TTyChartElement;
begin
  Result := '';
  for i := 0 to AList.Count - 1 do
  begin
    e := AList.Element(i);
    if e.Datum.IsEdge or (e.Datum.SeriesIndex <> ASeries) or (e.Datum.RawDataIndex < 0)
      or (e.Shape.Kind <> cskCircle) or (e.Anim.Role = carLabel) then Continue;
    Result := Result + Format('%d:%s,%s,%.8x;', [e.Datum.RawDataIndex, HexOf(e.Shape.CX),
      HexOf(e.Shape.CY), e.Style.FillColor]);
  end;
end;

procedure TAdvChartStatTransformsTest.TestAClusteringKeepsItsClustersUntilTheDatasetsChange;
var
  c: TJSONObject;
  first, again, fills: string;
  st: LongWord;
  draws: Integer;
begin
  c := CaseById('rr-cluster');
  AssertNotNull('the case', c);
  draws := c.Integers['draws'];
  AssertTrue('the clustering drew', draws > 0);
  NewChart(c.Objects['option']);
  RenderChart;
  first := ScatterPrint(FChart.List, 0);
  st := FChart.AxisMemory.RandomState^;
  AssertEquals('the first render moved the stream on', StateAfter(draws), st);
  { a resize rebuilds the tables: the same clusters, the stream untouched }
  FChart.SetBounds(0, 0, 600, 400);
  RenderChart;
  again := ScatterPrint(FChart.List, 0);
  AssertEquals('the same symbols after a rebuild', first, again);
  AssertEquals('the stream stays', st, FChart.AxisMemory.RandomState^);
  { a merge without `dataset` keeps them too }
  AssertTrue(FChart.MergeOption('{"title":{"text":"t"}}'));
  RenderChart;
  AssertEquals('the same symbols after a merge without datasets', first, ScatterPrint(FChart.List, 0));
  AssertEquals('the stream stays after it', st, FChart.AxisMemory.RandomState^);
  { a merge carrying `dataset` runs the transform again, from where the
    stream stands: new centroids, the stream moved on by as many draws }
  AssertTrue(FChart.MergeOption('{"dataset":[{},{}]}'));
  RenderChart;
  AssertEquals('drawn again', StateAfter(2 * draws), FChart.AxisMemory.RandomState^);
  fills := ScatterPrint(FChart.List, 0);
  AssertTrue('every point still drawn', Length(fills) > 0);
end;

procedure TAdvChartStatTransformsTest.TestANumericStringIsNotANumberHere;
var
  c: TJSONObject;
  opt: TTyChartOption;
  cache: TTyDatasetCache;
  node: TJSONObject;
  rows: TJSONArray;
  i: Integer;
begin
  c := CaseById('r-numstr');
  AssertNotNull('the case', c);
  AssertEquals('the deviation it carries', 'numeric-string', c.Strings['deviation']);
  { upstream kept the row with '7' and added it as text: NaN everywhere }
  rows := c.Arrays['datasets'].Objects[1].Arrays['results'].Objects[0].Arrays['rows'];
  AssertEquals('upstream kept four', 4, rows.Count);
  opt := TTyChartOption.Create;
  cache := TTyDatasetCache.Create;
  try
    AssertTrue(opt.SetOptionText(c.Objects['option'].AsJSON));
    node := cache.ResultNode(opt, 1, 0);
    AssertNotNull('a table here', node);
    rows := node.Arrays['source'];
    AssertEquals('the port drops the row', 3, rows.Count);
    for i := 0 to rows.Count - 1 do
      AssertFalse('a number for every y', IsNan(TJSONArray(rows.Items[i]).Floats[1]));
    AssertTrue('a formula with numbers', Pos('NaN', TJSONArray(rows.Items[2]).Strings[2]) = 0);
  finally
    cache.Free;
    opt.Free;
  end;
end;

procedure TAdvChartStatTransformsTest.TestARefusalIsADiagnostic;
var
  c: TJSONObject;
  i: Integer;
  all, want: string;
begin
  c := CaseById('rr-error');
  AssertNotNull('the case', c);
  AssertTrue('upstream refuses the option', c.Objects['render'].Find('error') <> nil);
  NewChart(c.Objects['option']);
  RenderChart;
  all := '';
  for i := 0 to FChart.DiagnosticCount - 1 do all := all + FChart.Diagnostic(i) + '|';
  want := Format(rsTyChartDatasetNoTable, [1, Format(rsTyStatRegMethod, ['nope'])]);
  AssertTrue('the diagnostic: ' + all, Pos(want, all) > 0);
  for i := 0 to FChart.List.Count - 1 do
    AssertFalse('the series draws nothing',
      (FChart.List.Element(i).Datum.SeriesIndex = 0) and (FChart.List.Element(i).Datum.RawDataIndex >= 0));
end;

initialization
  RegisterTest(TAdvChartStatTransformsTest);
end.
